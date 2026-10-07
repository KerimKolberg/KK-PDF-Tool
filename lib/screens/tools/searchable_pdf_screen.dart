import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/document_builder.dart';
import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../widgets/delete_originals_switch.dart';
import '../../widgets/tool_drop_zone.dart';
import '../../widgets/tool_result.dart';

/// Android only: OCRs every page of a scanned PDF offline and saves a copy
/// with an invisible text layer, so it can be searched and text copied.
class SearchablePdfScreen extends StatefulWidget {
  const SearchablePdfScreen({super.key});

  @override
  State<SearchablePdfScreen> createState() => _SearchablePdfScreenState();
}

class _SearchablePdfScreenState extends State<SearchablePdfScreen> {
  final _downloadsExport = DownloadsExportService();
  String? _fileName;
  String? _sourcePath;
  Uint8List? _pdfBytes;
  bool _deleteOriginal = false;
  String? _busyLabel;

  Future<void> _pickPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await FilePickers.openOne('searchable_pdf', [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _sourcePath = file.path;
      _pdfBytes = bytes;
    });
  }

  Future<void> _convert() async {
    final bytes = _pdfBytes;
    final name = _fileName;
    if (bytes == null || name == null || _busyLabel != null) return;
    setState(() => _busyLabel = 'Seiten werden geladen…');
    try {
      final rendered = await PdfToolsService.rasterPages(bytes, dpi: 200);
      final pages = await PdfToolsService.toJpegs(rendered, quality: 88);
      final built = await DocumentBuilder.build(
        pages,
        searchable: true,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _busyLabel = 'Texterkennung ${done < total ? done + 1 : total}/$total…');
          }
        },
      );
      final location = await _downloadsExport.export(built.pdfBytes, '${name}_durchsuchbar.pdf');
      var message = built.text == null
          ? 'Kein Text erkannt · gespeichert unter $location'
          : 'Gespeichert unter $location';
      if (_deleteOriginal) {
        final notDeleted = await OriginalFilesCleanupService.deleteAll([_sourcePath]);
        if (notDeleted.isNotEmpty) message += ' · Original konnte nicht gelöscht werden';
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyLabel = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busyLabel != null;
    return ToolDropZone(
      onDrop: _pickPdf,
      child: Scaffold(
        appBar: AppBar(title: const Text('PDF durchsuchbar machen')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Erkennt den Text jeder Seite offline und legt ihn unsichtbar hinter '
                'das Bild. Die PDF sieht gleich aus, lässt sich aber durchsuchen '
                '(Strg+F) und Text kopieren.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
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
                    onPressed: busy ? null : _pickPdf,
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
                  onPressed: busy ? null : _convert,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.manage_search),
                  label: Text(_busyLabel ?? 'Durchsuchbar machen'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
