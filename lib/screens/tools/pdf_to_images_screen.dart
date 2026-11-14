import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n.dart';
import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../utils/formatting.dart';
import '../../widgets/busy_icon.dart';
import '../../widgets/delete_originals_switch.dart';
import '../../widgets/tool_drop_zone.dart';
import '../../widgets/tool_layout.dart';
import '../../widgets/tool_result.dart';

/// Rasterizes every page of a picked PDF into a JPEG image and exports
/// them all into a per-document subfolder under Downloads/KK-PDF-Tool.
class PdfToImagesScreen extends StatefulWidget {
  const PdfToImagesScreen({super.key});

  @override
  State<PdfToImagesScreen> createState() => _PdfToImagesScreenState();
}

class _PdfToImagesScreenState extends State<PdfToImagesScreen> {
  final _downloadsExport = DownloadsExportService();
  String? _fileName;
  String? _sourcePath;
  Uint8List? _pdfBytes;
  List<Uint8List>? _previewImages;
  bool _deleteOriginal = false;
  bool _busy = false;

  Future<void> _pickPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await FilePickers.openOne('pdf_to_images', [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _sourcePath = file.path;
      _pdfBytes = bytes;
      _previewImages = null;
    });
    await _render();
  }

  Future<void> _render() async {
    final bytes = _pdfBytes;
    if (bytes == null) return;
    setState(() => _busy = true);
    try {
      final images = await PdfToolsService.rasterPages(bytes, dpi: 120);
      if (!mounted) return;
      setState(() {
        _previewImages = images;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Konnte PDF nicht lesen: $e', 'Could not read PDF: $e'))),
      );
    }
  }

  Future<void> _exportAll() async {
    final images = _previewImages;
    final name = _fileName;
    if (images == null || name == null || _busy) return;
    setState(() => _busy = true);
    try {
      String? lastLocation;
      for (var i = 0; i < images.length; i++) {
        lastLocation = await _downloadsExport.export(
          images[i],
          tr(
            '${name}_seite_${(i + 1).toString().padLeft(2, '0')}.png',
            '${name}_page_${(i + 1).toString().padLeft(2, '0')}.png',
          ),
        );
      }
      var message = tr(
        '${images.length} Bild(er) gespeichert${lastLocation != null ? ' in ${folderOf(lastLocation)}' : ''}',
        '${images.length} image(s) saved${lastLocation != null ? ' in ${folderOf(lastLocation)}' : ''}',
      );
      if (_deleteOriginal) {
        message += await OriginalFilesCleanupService.deleteAndDescribe([_sourcePath]);
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('Export fehlgeschlagen: $e', 'Export failed: $e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolDropZone(
      onDrop: _pickPdf,
      child: ToolScaffold(
        appBar: AppBar(title: Text(tr('PDF → Bilder', 'PDF → images'))),
        body: _pdfBytes == null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: FilePickPanel(
                  hint: tr(
                    'Wähle eine PDF-Datei, deren Seiten als Bilder exportiert werden sollen.',
                    'Choose a PDF file whose pages should be exported as images.',
                  ),
                  onPressed: _pickPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(tr('PDF wählen', 'Choose PDF')),
                ),
              )
            : _busy && _previewImages == null
            ? const Center(child: CircularProgressIndicator())
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.72,
                ),
                itemCount: _previewImages?.length ?? 0,
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_previewImages![i], fit: BoxFit.cover),
                ),
              ),
        bottomNavigationBar: _previewImages == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DeleteOriginalsSwitch(
                        label: tr(
                          'Originaldatei danach löschen',
                          'Delete original file afterwards',
                        ),
                        value: _deleteOriginal,
                        onChanged: (v) => setState(() => _deleteOriginal = v),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _exportAll,
                        icon: BusyIcon(busy: _busy, child: const Icon(Icons.download_outlined)),
                        label: Text(
                          _busy
                              ? tr('Exportiere…', 'Exporting…')
                              : tr(
                                  '${_previewImages!.length} Bild(er) speichern',
                                  'Save ${_previewImages!.length} image(s)',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
