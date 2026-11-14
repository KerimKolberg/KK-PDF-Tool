import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/delete_originals_switch.dart';
import '../../widgets/tool_drop_zone.dart';
import '../../widgets/tool_layout.dart';
import '../../widgets/tool_result.dart';
import '../../l10n.dart';
import '../../widgets/busy_icon.dart';

/// Stamps a diagonal text watermark across every page of a PDF.
class WatermarkPdfScreen extends StatefulWidget {
  const WatermarkPdfScreen({super.key});

  @override
  State<WatermarkPdfScreen> createState() => _WatermarkPdfScreenState();
}

class _WatermarkPdfScreenState extends State<WatermarkPdfScreen> {
  final _downloadsExport = DownloadsExportService();
  final _textController =
      TextEditingController(text: AppPrefs.getString('watermark.text') ?? tr('ENTWURF', 'DRAFT'));
  String? _fileName;
  String? _sourcePath;
  Uint8List? _pdfBytes;
  double _opacity = AppPrefs.getDouble('watermark.opacity', 0.35);
  bool _deleteOriginal = false;
  bool _busy = false;

  Future<void> _pickPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await FilePickers.openOne('watermark_pdf', [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _sourcePath = file.path;
      _pdfBytes = bytes;
    });
  }

  Future<void> _apply() async {
    final bytes = _pdfBytes;
    final name = _fileName;
    final text = _textController.text.trim();
    AppPrefs.setString('watermark.text', text);
    AppPrefs.setDouble('watermark.opacity', _opacity);
    if (bytes == null || name == null || text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await PdfToolsService.addWatermark(
        bytes,
        text: text,
        opacity: _opacity,
      );
      final location =
          await _downloadsExport.export(result, '${name}_wasserzeichen.pdf');
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
        SnackBar(content: Text(tr('Fehlgeschlagen: $e', 'Failed: $e'))),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ToolDropZone(
      onDrop: _pickPdf,
      child: ToolScaffold(
        appBar: AppBar(title: Text(tr('Wasserzeichen', 'Watermark'))),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_fileName == null)
                FilePickPanel(
                  onPressed: _pickPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(tr('PDF wählen', 'Choose PDF')),
                )
              else ...[
                SelectedFileTile(
                  name: _fileName!,
                  onChange: _busy ? null : _pickPdf,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    labelText: 'Text',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(tr('Deckkraft: ${(_opacity * 100).round()}%', 'Opacity: ${(_opacity * 100).round()}%')),
                Slider(
                  value: _opacity,
                  min: 0.1,
                  max: 0.7,
                  onChanged: _busy ? null : (v) => setState(() => _opacity = v),
                ),
                DeleteOriginalsSwitch(
                  label: tr('Originaldatei danach löschen', 'Delete original file afterwards'),
                  value: _deleteOriginal,
                  onChanged: (v) => setState(() => _deleteOriginal = v),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _apply,
                  icon: BusyIcon(busy: _busy, child: const Icon(Icons.water_drop_outlined)),
                  label: Text(_busy ? tr('Wende an…', 'Applying…') : tr('Wasserzeichen einfügen', 'Add watermark')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
