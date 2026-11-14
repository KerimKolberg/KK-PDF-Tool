import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../services/settings_service.dart';
import '../../utils/formatting.dart';
import '../../widgets/delete_originals_switch.dart';
import '../../widgets/rect_crop_overlay.dart';
import '../../widgets/tool_drop_zone.dart';
import '../../widgets/tool_layout.dart';
import '../../widgets/tool_result.dart';
import '../../l10n.dart';
import '../../widgets/busy_icon.dart';

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
  String? _sourcePath;
  Uint8List? _pdfBytes;
  Uint8List? _previewImage;
  double _previewW = 0;
  double _previewH = 0;
  bool _loadingPreview = false;
  bool _deleteOriginal = false;
  bool _busy = false;

  Future<void> _pickPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await FilePickers.openOne('crop_pdf', [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _sourcePath = file.path;
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
        SnackBar(content: Text(tr('Vorschau fehlgeschlagen: $e', 'Preview failed: $e'))),
      );
    }
  }

  /// The crop area used last time, so similar documents can be trimmed
  /// the same way without redrawing the rectangle.
  ({double left, double top, double right, double bottom})? get _rememberedRect {
    final left = AppPrefs.getDouble('cropPdf.left', -1);
    final top = AppPrefs.getDouble('cropPdf.top', -1);
    final right = AppPrefs.getDouble('cropPdf.right', -1);
    final bottom = AppPrefs.getDouble('cropPdf.bottom', -1);
    final valid = left >= 0 && top >= 0 && right <= 1 && bottom <= 1 &&
        right - left > 0.05 && bottom - top > 0.05;
    return valid ? (left: left, top: top, right: right, bottom: bottom) : null;
  }

  Future<void> _apply() async {
    final bytes = _pdfBytes;
    final name = _fileName;
    final overlay = _overlayKey.currentState;
    if (bytes == null || name == null || overlay == null || _busy) return;
    final rect = overlay.fractionalRect;
    final pageIndices = parsePageSpec(_pageSpecController.text);
    AppPrefs.setDouble('cropPdf.left', rect.left);
    AppPrefs.setDouble('cropPdf.top', rect.top);
    AppPrefs.setDouble('cropPdf.right', rect.right);
    AppPrefs.setDouble('cropPdf.bottom', rect.bottom);

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
      var message = tr('Gespeichert unter $location', 'Saved to $location');
      if (_deleteOriginal) {
        message += await OriginalFilesCleanupService.deleteAndDescribe([_sourcePath]);
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Zuschneiden fehlgeschlagen: $e', 'Cropping failed: $e'))),
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
    return ToolDropZone(
      onDrop: _pickPdf,
      child: ToolScaffold(
        appBar: AppBar(title: Text(tr('PDF zuschneiden', 'Crop PDF'))),
        body: _fileName == null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: FilePickPanel(
                  hint: tr('Wähle eine PDF. Der Zuschnitt wird an der ersten Seite '
                        'festgelegt und auf alle (oder gewählte) Seiten angewendet.',
                        'Choose a PDF. The crop is set on the first page '
                        'and applied to all (or the chosen) pages.'),
                  onPressed: _pickPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(tr('PDF wählen', 'Choose PDF')),
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
                      initialRect: _rememberedRect,
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
                        decoration: InputDecoration(
                          hintText: tr('z. B. 1-3,5 · leer lassen für alle Seiten', 'e.g. 1-3,5 · leave empty for all pages'),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      DeleteOriginalsSwitch(
                        label: tr('Originaldatei danach löschen', 'Delete original file afterwards'),
                        value: _deleteOriginal,
                        onChanged: (v) => setState(() => _deleteOriginal = v),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _busy ? null : _apply,
                        icon: BusyIcon(busy: _busy, child: const Icon(Icons.crop)),
                        label: Text(_busy ? tr('Schneide zu…', 'Cropping…') : tr('Zuschneiden & speichern', 'Crop & save')),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
