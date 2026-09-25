import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../services/downloads_export_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_service.dart';
import '../../widgets/delete_originals_switch.dart';

class _PickedImage {
  final String? path;
  final Uint8List bytes;
  _PickedImage(this.path, this.bytes);
}

/// Combines one or more picked images into a single PDF, one image per page.
class ImagesToPdfScreen extends StatefulWidget {
  const ImagesToPdfScreen({super.key});

  @override
  State<ImagesToPdfScreen> createState() => _ImagesToPdfScreenState();
}

class _ImagesToPdfScreenState extends State<ImagesToPdfScreen> {
  final _downloadsExport = DownloadsExportService();
  final List<_PickedImage> _images = [];
  bool _deleteOriginals = false;
  bool _busy = false;

  Future<void> _addImages() async {
    const typeGroup = XTypeGroup(
      label: 'Bilder',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return;
    final picked = await Future.wait(
      files.map((f) async => _PickedImage(f.path, await f.readAsBytes())),
    );
    setState(() => _images.addAll(picked));
  }

  void _remove(int index) => setState(() => _images.removeAt(index));

  Future<void> _createPdf() async {
    if (_images.isEmpty || _busy) return;
    final title = await _askTitle();
    if (title == null) return;

    setState(() => _busy = true);
    try {
      final pdfBytes = await PdfService.buildPdf(
        [for (final image in _images) image.bytes],
      );
      final location = await _downloadsExport.export(pdfBytes, '$title.pdf');
      var message = 'PDF gespeichert unter $location';
      if (_deleteOriginals) {
        final notDeleted = await OriginalFilesCleanupService.deleteAll(
          [for (final image in _images) image.path],
        );
        if (notDeleted.isNotEmpty) {
          message += ' · ${notDeleted.length} Original(e) konnten nicht gelöscht werden';
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehlgeschlagen: $e')),
      );
    }
  }

  Future<String?> _askTitle() async {
    final controller = TextEditingController(text: 'Bilder');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDF-Name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(context, text.isEmpty ? 'Bilder' : text);
            },
            child: const Text('Erstellen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bilder → PDF')),
      body: _images.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Füge Bilder hinzu, die zu einer PDF zusammengefasst werden sollen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _images.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final item = _images.removeAt(oldIndex);
                  _images.insert(newIndex, item);
                });
              },
              itemBuilder: (context, i) => Card(
                key: ValueKey('img_$i${_images[i].bytes.length}'),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(_images[i].bytes,
                        width: 48, height: 48, fit: BoxFit.cover),
                  ),
                  title: Text('Seite ${i + 1}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(i),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_images.isNotEmpty)
                DeleteOriginalsSwitch(
                  value: _deleteOriginals,
                  onChanged: (v) => setState(() => _deleteOriginals = v),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _addImages,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Bilder hinzufügen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _images.isEmpty || _busy ? null : _createPdf,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(_busy ? 'Erstelle…' : 'PDF erstellen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
