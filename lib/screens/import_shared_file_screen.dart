import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/ocr_result.dart';
import '../services/document_builder.dart';
import '../services/document_store.dart';
import '../services/incoming_file_service.dart';
import '../services/pdf_tools_service.dart';
import 'document_viewer_screen.dart';
import '../l10n.dart';

/// Shown when the OS hands KK-PDF-Tool a PDF or image via "Open with" / the
/// share sheet. Imports it into the local library so it shows up like any
/// scanned document.
class ImportSharedFileScreen extends StatefulWidget {
  final IncomingFile file;
  final DocumentStore store;

  const ImportSharedFileScreen({
    super.key,
    required this.file,
    required this.store,
  });

  @override
  State<ImportSharedFileScreen> createState() => _ImportSharedFileScreenState();
}

class _ImportSharedFileScreenState extends State<ImportSharedFileScreen> {
  late final TextEditingController _titleController;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final base = widget.file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
    _titleController = TextEditingController(text: base.isEmpty ? 'Import' : base);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_busy) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sourceBytes = await File(widget.file.path).readAsBytes();
      final Uint8List pdfBytes;
      final List<Uint8List> pageJpegs;
      String? text;
      List<OcrResult?>? ocr;

      if (widget.file.isPdf) {
        pdfBytes = sourceBytes;
        // Preview images for the library; the PDF itself is kept as it is.
        pageJpegs = await PdfToolsService.rasterPages(
          sourceBytes,
          dpi: 120,
          format: PageImageFormat.jpeg,
          jpegQuality: 85,
        );
      } else {
        final built = await DocumentBuilder.build([sourceBytes]);
        pageJpegs = built.pages;
        pdfBytes = built.pdfBytes;
        text = built.text;
        ocr = built.ocr;
      }

      final doc = await widget.store.createDocument(
        title: title,
        pageJpegBytes: pageJpegs,
        pdfBytes: pdfBytes,
        text: text,
        ocr: ocr,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DocumentViewerScreen(store: widget.store, document: doc),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = tr('Import fehlgeschlagen: $e', 'Import failed: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Datei importieren', 'Import file'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(
                widget.file.isPdf
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined,
              ),
              title: Text(widget.file.name),
              subtitle: Text(tr('Wird zur Bibliothek hinzugefügt', 'Will be added to the library')),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('Titel', 'Title'),
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(tr('Abbrechen', 'Cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(_busy ? tr('Importiere…', 'Importing…') : tr('Importieren', 'Import')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
