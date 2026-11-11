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
import '../../widgets/tool_layout.dart';
import '../../widgets/tool_result.dart';
import '../../l10n.dart';

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
    setState(() => _busyLabel = tr('Seiten werden geladen…', 'Loading pages…'));
    try {
      final rendered = await PdfToolsService.rasterPages(bytes, dpi: 200);
      final formats = await PdfToolsService.pageFormats(bytes);
      final pages = await PdfToolsService.toJpegs(rendered, quality: 88);
      final built = await DocumentBuilder.build(
        pages,
        searchable: true,
        pageFormats: formats,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _busyLabel = tr('Texterkennung ${done < total ? done + 1 : total}/$total…', 'Text recognition ${done < total ? done + 1 : total}/$total…'));
          }
        },
      );
      final location = await _downloadsExport.export(built.pdfBytes, '${name}_durchsuchbar.pdf');
      var message = built.text == null
          ? tr('Kein Text erkannt · gespeichert unter $location', 'No text recognized · saved to $location')
          : tr('Gespeichert unter $location', 'Saved to $location');
      if (_deleteOriginal) {
        final notDeleted = await OriginalFilesCleanupService.deleteAll([_sourcePath]);
        if (notDeleted.isNotEmpty) message += tr(' · Original konnte nicht gelöscht werden', ' · Original could not be deleted');
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyLabel = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Fehlgeschlagen: $e', 'Failed: $e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busyLabel != null;
    return ToolDropZone(
      onDrop: _pickPdf,
      child: ToolScaffold(
        appBar: AppBar(title: Text(tr('PDF durchsuchbar machen', 'Make PDF searchable'))),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Erkennt den Text jeder Seite offline und legt ihn unsichtbar hinter '
                'das Bild. Die PDF sieht gleich aus, lässt sich aber durchsuchen '
                '(Strg+F) und Text kopieren.',
                'Recognizes the text of every page offline and lays it invisibly behind '
                'the image. The PDF looks the same, but can be searched '
                '(Ctrl+F) and text can be copied.'),
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 24),
              if (_fileName == null)
                FilePickPanel(
                  onPressed: _pickPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(tr('PDF wählen', 'Choose PDF')),
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(_fileName!),
                  trailing: TextButton(
                    onPressed: busy ? null : _pickPdf,
                    child: Text(tr('Ändern', 'Change')),
                  ),
                ),
                DeleteOriginalsSwitch(
                  label: tr('Originaldatei danach löschen', 'Delete original file afterwards'),
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
                  label: Text(_busyLabel ?? tr('Durchsuchbar machen', 'Make searchable')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
