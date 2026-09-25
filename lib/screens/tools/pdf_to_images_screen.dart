import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../widgets/delete_originals_switch.dart';

/// Rasterizes every page of a picked PDF into a JPEG image and exports
/// them all into a per-document subfolder under Downloads/DocScanner.
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
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
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
        SnackBar(content: Text('Konnte PDF nicht lesen: $e')),
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
          '${name}_seite_${(i + 1).toString().padLeft(2, '0')}.png',
        );
      }
      var message =
          '${images.length} Bild(er) gespeichert${lastLocation != null ? ' in ${_folderOf(lastLocation)}' : ''}';
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
        SnackBar(content: Text('Export fehlgeschlagen: $e')),
      );
    }
  }

  String _folderOf(String location) {
    final idx = location.lastIndexOf(RegExp(r'[\\/]'));
    return idx == -1 ? location : location.substring(0, idx);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF → Bilder')),
      body: _pdfBytes == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Wähle eine PDF-Datei, deren Seiten als Bilder exportiert werden sollen.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.outline),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _pickPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF wählen'),
                    ),
                  ],
                ),
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
                      label: 'Originaldatei danach löschen',
                      value: _deleteOriginal,
                      onChanged: (v) => setState(() => _deleteOriginal = v),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _exportAll,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download_outlined),
                      label: Text(
                        _busy
                            ? 'Exportiere…'
                            : '${_previewImages!.length} Bild(er) speichern',
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
