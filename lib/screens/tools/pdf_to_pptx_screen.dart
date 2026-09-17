import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/pdf_tools_service.dart';

/// Packs every page of a picked PDF as a full-slide picture into a new
/// .pptx file. This is a mechanical "one page per slide" export, not a real
/// PDF-to-editable-PowerPoint reconstruction: no free service turns a PDF
/// page back into editable text boxes, so the pages stay pictures — movable
/// and resizable in PowerPoint, but not text-editable.
class PdfToPptxScreen extends StatefulWidget {
  const PdfToPptxScreen({super.key});

  @override
  State<PdfToPptxScreen> createState() => _PdfToPptxScreenState();
}

class _PdfToPptxScreenState extends State<PdfToPptxScreen> {
  final _downloadsExport = DownloadsExportService();
  String? _fileName;
  Uint8List? _pdfBytes;
  bool _busy = false;

  Future<void> _pickPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _pdfBytes = bytes;
    });
  }

  Future<void> _convert() async {
    final bytes = _pdfBytes;
    final name = _fileName;
    if (bytes == null || name == null || _busy) return;
    setState(() => _busy = true);
    try {
      final pptx = await PdfToolsService.toPptx(bytes);
      final location = await _downloadsExport.export(pptx, '$name.pptx');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gespeichert unter $location')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Umwandlung fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF → PowerPoint')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Jede PDF-Seite wird als Bild auf eine eigene Folie '
                        'gesetzt. Der Text ist danach nicht mehr bearbeitbar, '
                        'nur das Bild verschieb- und skalierbar.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_fileName == null)
              FilledButton.icon(
                onPressed: _pickPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF wählen'),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(_fileName!),
                trailing: TextButton(
                  onPressed: _busy ? null : _pickPdf,
                  child: const Text('Ändern'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _convert,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.slideshow_outlined),
                label: Text(_busy ? 'Wandle um…' : 'Als PPTX speichern'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
