import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/markdown_pdf_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../widgets/delete_originals_switch.dart';

/// Converts Markdown (.md) source into a styled PDF - fully offline, no
/// Google account needed.
class MarkdownToPdfScreen extends StatefulWidget {
  const MarkdownToPdfScreen({super.key});

  @override
  State<MarkdownToPdfScreen> createState() => _MarkdownToPdfScreenState();
}

class _MarkdownToPdfScreenState extends State<MarkdownToPdfScreen> {
  final _downloadsExport = DownloadsExportService();
  String? _fileName;
  String? _sourcePath;
  String? _source;
  bool _deleteOriginal = false;
  bool _busy = false;

  Future<void> _pickFile() async {
    const typeGroup = XTypeGroup(label: 'Markdown', extensions: ['md', 'markdown', 'txt']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _sourcePath = file.path;
      _source = text;
    });
  }

  Future<void> _convert() async {
    final source = _source;
    final name = _fileName;
    if (source == null || name == null || _busy) return;
    setState(() => _busy = true);
    try {
      final pdfBytes = await MarkdownPdfService.convert(source);
      final location = await _downloadsExport.export(pdfBytes, '$name.pdf');
      var message = 'PDF gespeichert unter $location';
      if (_deleteOriginal) {
        final notDeleted = await OriginalFilesCleanupService.deleteAll([_sourcePath]);
        if (notDeleted.isNotEmpty) {
          message += ' · Original konnte nicht gelöscht werden';
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      appBar: AppBar(title: const Text('Markdown → PDF')),
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
                    Icon(Icons.offline_bolt_outlined),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Läuft komplett offline, ohne Internet oder Google-Konto.',
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
                onPressed: _pickFile,
                icon: const Icon(Icons.article_outlined),
                label: const Text('Markdown-Datei wählen'),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(_fileName!),
                trailing: TextButton(
                  onPressed: _busy ? null : _pickFile,
                  child: const Text('Ändern'),
                ),
              ),
              DeleteOriginalsSwitch(
                label: 'Originaldatei danach löschen',
                value: _deleteOriginal,
                onChanged: (v) => setState(() => _deleteOriginal = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _convert,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
