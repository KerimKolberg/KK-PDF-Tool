import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n.dart';
import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/markdown_pdf_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../widgets/busy_icon.dart';
import '../../widgets/delete_originals_switch.dart';
import '../../widgets/tool_drop_zone.dart';
import '../../widgets/tool_layout.dart';
import '../../widgets/tool_result.dart';

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
    final file = await FilePickers.openOne('markdown_to_pdf', [typeGroup]);
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
      var message = tr('PDF gespeichert unter $location', 'PDF saved to $location');
      if (_deleteOriginal) {
        message += await OriginalFilesCleanupService.deleteAndDescribe([_sourcePath]);
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Umwandlung fehlgeschlagen: $e', 'Conversion failed: $e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolDropZone(
      onDrop: _pickFile,
      child: ToolScaffold(
        appBar: AppBar(title: const Text('Markdown → PDF')),
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
                      const Icon(Icons.offline_bolt_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tr('Läuft komplett offline, ohne Internet oder Google-Konto.', 'Runs completely offline, without internet or a Google account.'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_fileName == null)
                FilePickPanel(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.article_outlined),
                  label: Text(tr('Markdown-Datei wählen', 'Choose Markdown file')),
                )
              else ...[
                SelectedFileTile(
                  name: _fileName!,
                  onChange: _busy ? null : _pickFile,
                ),
                DeleteOriginalsSwitch(
                  label: tr('Originaldatei danach löschen', 'Delete original file afterwards'),
                  value: _deleteOriginal,
                  onChanged: (v) => setState(() => _deleteOriginal = v),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _convert,
                  icon: BusyIcon(busy: _busy, child: const Icon(Icons.picture_as_pdf_outlined)),
                  label: Text(_busy ? tr('Wandle um…', 'Converting…') : tr('In PDF umwandeln', 'Convert to PDF')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
