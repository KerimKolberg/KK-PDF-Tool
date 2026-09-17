import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/google_drive_convert_service.dart';

/// Converts a .pptx to a real, text-preserving PDF by round-tripping it
/// through the user's own Google Drive (Slides). Needs internet and a
/// one-time Google sign-in.
class PptxToPdfScreen extends StatefulWidget {
  const PptxToPdfScreen({super.key});

  @override
  State<PptxToPdfScreen> createState() => _PptxToPdfScreenState();
}

class _PptxToPdfScreenState extends State<PptxToPdfScreen> {
  final _drive = GoogleDriveConvertService();
  final _downloadsExport = DownloadsExportService();
  String? _fileName;
  Uint8List? _pptxBytes;
  bool _busy = false;

  Future<void> _pickPptx() async {
    const typeGroup = XTypeGroup(label: 'PowerPoint', extensions: ['pptx']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _pptxBytes = bytes;
    });
  }

  Future<void> _convert() async {
    final bytes = _pptxBytes;
    final name = _fileName;
    if (bytes == null || name == null || _busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await _drive.pptxToPdf(bytes, '$name.pptx');
      final location = await _downloadsExport.export(pdf, '$name.pdf');
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
      appBar: AppBar(title: const Text('PowerPoint → PDF')),
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
                        'Läuft über dein Google-Konto (kostenlos) und braucht '
                        'Internet. Einmalige Einrichtung in den Einstellungen nötig.',
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
                onPressed: _pickPptx,
                icon: const Icon(Icons.slideshow_outlined),
                label: const Text('PowerPoint-Datei wählen'),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(_fileName!),
                trailing: TextButton(
                  onPressed: _busy ? null : _pickPptx,
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
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(_busy ? 'Wandle um…' : 'In PDF umwandeln'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
