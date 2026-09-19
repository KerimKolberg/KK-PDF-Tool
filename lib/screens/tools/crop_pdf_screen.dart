import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../widgets/rect_crop_overlay.dart';

/// Lets the user draw a crop rectangle on the first page's preview, then
/// applies that same rectangle (as a fraction of the page) to every page,
/// or just a chosen page range.
class CropPdfScreen extends StatefulWidget {
  const CropPdfScreen({super.key});

  @override
  State<CropPdfScreen> createState() => _CropPdfScreenState();
}

class _CropPdfScreenState extends State<CropPdfScreen> {
  final _downloadsExport = DownloadsExportService();
  final _overlayKey = GlobalKey<RectCropOverlayState>();
  final _pageSpecController = TextEditingController();

  String? _fileName;
  Uint8List? _pdfBytes;
  Uint8List? _previewImage;
  double _previewW = 0;
  double _previewH = 0;
  bool _loadingPreview = false;
  bool _busy = false;

  Future<void> _pickPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _pdfBytes = bytes;
      _previewImage = null;
      _loadingPreview = true;
    });
    try {
      final pages = await PdfToolsService.rasterPages(bytes, pages: [0], dpi: 120);
      final preview = pages.first;
      final codec = await ui.instantiateImageCodec(preview);
      final frame = await codec.getNextFrame();
      final w = frame.image.width.toDouble();
      final h = frame.image.height.toDouble();
      frame.image.dispose();
      codec.dispose();
      if (!mounted) return;
      setState(() {
        _previewImage = preview;
        _previewW = w;
        _previewH = h;
        _loadingPreview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingPreview = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vorschau fehlgeschlagen: $e')),
      );
    }
  }

  Set<int>? _parsePageSpec(String spec) {
    final trimmed = spec.trim();
    if (trimmed.isEmpty) return null;
    final indices = <int>{};
    for (final part in trimmed.split(',')) {
      final token = part.trim();
      if (token.isEmpty) continue;
      final range = token.split('-');
      if (range.length == 1) {
        final n = int.tryParse(range[0].trim());
        if (n != null && n >= 1) indices.add(n - 1);
      } else if (range.length == 2) {
        final start = int.tryParse(range[0].trim());
        final end = int.tryParse(range[1].trim());
        if (start != null && end != null && start >= 1 && end >= start) {
          for (var i = start; i <= end; i++) {
            indices.add(i - 1);
          }
        }
      }
    }
    return indices;
  }

  Future<void> _apply() async {
    final bytes = _pdfBytes;
    final name = _fileName;
    final overlay = _overlayKey.currentState;
    if (bytes == null || name == null || overlay == null || _busy) return;
    final rect = overlay.fractionalRect;
    final pageIndices = _parsePageSpec(_pageSpecController.text);

    setState(() => _busy = true);
    try {
      final result = await PdfToolsService.cropPages(
        bytes,
        pageIndices: pageIndices?.toList(),
        leftFrac: rect.left,
        topFrac: rect.top,
        rightFrac: rect.right,
        bottomFrac: rect.bottom,
      );
      final location =
          await _downloadsExport.export(result, '${name}_zugeschnitten.pdf');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gespeichert unter $location')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zuschneiden fehlgeschlagen: $e')),
      );
    }
  }

  @override
  void dispose() {
    _pageSpecController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF zuschneiden')),
      body: _fileName == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Wähle eine PDF. Der Zuschnitt wird an der ersten Seite '
                      'festgelegt und auf alle (oder gewählte) Seiten angewendet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
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
          : _loadingPreview || _previewImage == null
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: RectCropOverlay(
                    key: _overlayKey,
                    imageBytes: _previewImage!,
                    imageWidth: _previewW,
                    imageHeight: _previewH,
                  ),
                ),
      bottomNavigationBar: _fileName == null || _loadingPreview
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _pageSpecController,
                      decoration: const InputDecoration(
                        hintText: 'z. B. 1-3,5 · leer lassen für alle Seiten',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _busy ? null : _apply,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.crop),
                      label: Text(_busy ? 'Schneide zu…' : 'Zuschneiden & speichern'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
