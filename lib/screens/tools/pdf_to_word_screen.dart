import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/google_drive_convert_service.dart';

/// Converts a PDF to an editable .docx by round-tripping it through the
/// user's own Google Drive (Docs), which OCRs scanned/image-based pages.
/// Needs internet and a one-time Google sign-in.
class PdfToWordScreen extends StatefulWidget {
  const PdfToWordScreen({super.key});

  @override
  State<PdfToWordScreen> createState() => _PdfToWordScreenState();
}

class _PdfToWordScreenState extends State<PdfToWordScreen> {
  final _drive = GoogleDriveConvertService();
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
      final docx = await _drive.pdfToWord(bytes, '$name.pdf');
      final location = await _downloadsExport.export(docx, '$name.docx');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gespeichert unter $location')),
      );
      Navigator.of(context).pop();
    } on GoogleDriveNotConfiguredException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
      appBar: AppBar(title: const Text('PDF → Word')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.cloud_outlined),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Läuft über dein Google-Konto (kostenlos, mit Texterkennung '
                        'für gescannte Seiten) und braucht Internet. Einmalige '
                        'Einrichtung in den Einstellungen nötig.',
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
                    : const Icon(Icons.description_outlined),
                label: Text(_busy ? 'Wandle um…' : 'In Word umwandeln'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
