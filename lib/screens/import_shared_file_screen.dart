import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/document_store.dart';
import '../services/incoming_file_service.dart';
import '../services/pdf_service.dart';
import '../services/pdf_tools_service.dart';
import 'document_viewer_screen.dart';

/// Shown when the OS hands DocScanner a PDF or image via "Open with" / the
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

      if (widget.file.isPdf) {
        pdfBytes = sourceBytes;
        final pages = await PdfToolsService.rasterPages(sourceBytes, dpi: 120);
        pageJpegs = pages;
      } else {
        pageJpegs = [sourceBytes];
        pdfBytes = await PdfService.buildPdf([sourceBytes]);
      }

      final doc = await widget.store.createDocument(
        title: title,
        pageJpegBytes: pageJpegs,
        pdfBytes: pdfBytes,
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
        _error = 'Import fehlgeschlagen: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Datei importieren')),
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
              subtitle: const Text('Wird zur Bibliothek hinzugefügt'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Titel',
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
                    child: const Text('Abbrechen'),
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
                    label: Text(_busy ? 'Importiere…' : 'Importieren'),
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
