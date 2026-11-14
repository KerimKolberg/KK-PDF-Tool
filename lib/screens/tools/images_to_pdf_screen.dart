import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_service.dart';
import '../../widgets/delete_originals_switch.dart';
import '../../widgets/tool_drop_zone.dart';
import '../../widgets/tool_layout.dart';
import '../../widgets/tool_result.dart';
import '../../l10n.dart';
import '../../widgets/busy_icon.dart';

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
    final typeGroup = XTypeGroup(
      label: tr('Bilder', 'Images'),
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    final files = await FilePickers.openMany('images_to_pdf', [typeGroup]);
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
      var message = tr('PDF gespeichert unter $location', 'PDF saved to $location');
      if (_deleteOriginals) {
        message += await OriginalFilesCleanupService.deleteAndDescribe([for (final image in _images) image.path]);
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Fehlgeschlagen: $e', 'Failed: $e'))),
      );
    }
  }

  Future<String?> _askTitle() async {
    final controller = TextEditingController(text: tr('Bilder', 'Images'));
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('PDF-Name', 'PDF name')),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Abbrechen', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(context, text.isEmpty ? tr('Bilder', 'Images') : text);
            },
            child: Text(tr('Erstellen', 'Create')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ToolDropZone(
      onDrop: _addImages,
      child: ToolScaffold(
        appBar: AppBar(title: Text(tr('Bilder → PDF', 'Images → PDF'))),
        body: _images.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: FilePickPanel(
                  multiple: true,
                  hint: tr('Füge Bilder hinzu, die zu einer PDF zusammengefasst werden sollen.', 'Add images to combine into one PDF.'),
                  onPressed: _addImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(tr('Bilder hinzufügen', 'Add images')),
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
                    title: Text(tr('Seite ${i + 1}', 'Page ${i + 1}')),
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
                        label: Text(tr('Bilder hinzufügen', 'Add images')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _images.isEmpty || _busy ? null : _createPdf,
                        icon: BusyIcon(busy: _busy, child: const Icon(Icons.picture_as_pdf_outlined)),
                        label: Text(_busy ? tr('Erstelle…', 'Creating…') : tr('PDF erstellen', 'Create PDF')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
