import 'dart:typed_data';

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
import '../../widgets/tool_drop_zone.dart';
import '../../widgets/tool_layout.dart';
import '../../widgets/tool_result.dart';
import '../../l10n.dart';
import '../../widgets/busy_icon.dart';

enum _CompressLevel { low, medium, high }

extension on _CompressLevel {
  String get label => switch (this) {
        _CompressLevel.low => tr('Wenig (beste Qualität)', 'Low (best quality)'),
        _CompressLevel.medium => tr('Mittel', 'Medium'),
        _CompressLevel.high => tr('Stark (kleinste Datei)', 'Strong (smallest file)'),
      };
  double get dpi => switch (this) {
        _CompressLevel.low => 150,
        _CompressLevel.medium => 110,
        _CompressLevel.high => 80,
      };
  int get quality => switch (this) {
        _CompressLevel.low => 85,
        _CompressLevel.medium => 65,
        _CompressLevel.high => 45,
      };
}

/// Shrinks a PDF's file size by re-rendering every page at a lower
/// resolution/JPEG quality - the same lossy trade-off every "PDF
/// compressor" makes once the original vector/text content isn't kept.
class CompressPdfScreen extends StatefulWidget {
  const CompressPdfScreen({super.key});

  @override
  State<CompressPdfScreen> createState() => _CompressPdfScreenState();
}

class _CompressPdfScreenState extends State<CompressPdfScreen> {
  final _downloadsExport = DownloadsExportService();
  String? _fileName;
  String? _sourcePath;
  Uint8List? _pdfBytes;
  _CompressLevel _level =
      AppPrefs.getEnum('compress.level', _CompressLevel.values, _CompressLevel.medium);
  bool _deleteOriginal = false;
  bool _busy = false;

  Future<void> _pickPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await FilePickers.openOne('compress_pdf', [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _sourcePath = file.path;
      _pdfBytes = bytes;
    });
  }

  Future<void> _compress() async {
    final bytes = _pdfBytes;
    final name = _fileName;
    if (bytes == null || name == null || _busy) return;
    setState(() => _busy = true);
    try {
      final compressed = await PdfToolsService.compress(
        bytes,
        dpi: _level.dpi,
        quality: _level.quality,
      );
      final location =
          await _downloadsExport.export(compressed, '${name}_komprimiert.pdf');
      final before = formatFileSize(bytes.length);
      final after = formatFileSize(compressed.length);
      var message = tr('$before → $after · gespeichert unter $location', '$before → $after · saved to $location');
      if (_deleteOriginal) {
        message += await OriginalFilesCleanupService.deleteAndDescribe([_sourcePath]);
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Komprimierung fehlgeschlagen: $e', 'Compression failed: $e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolDropZone(
      onDrop: _pickPdf,
      child: ToolScaffold(
        appBar: AppBar(title: Text(tr('PDF komprimieren', 'Compress PDF'))),
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
                  subtitle: Text(formatFileSize(_pdfBytes!.length)),
                  onChange: _busy ? null : _pickPdf,
                ),
                const SizedBox(height: 12),
                Text(tr('Kompressionsgrad', 'Compression level'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                RadioGroup<_CompressLevel>(
                  groupValue: _level,
                  onChanged: _busy
                      ? (_) {}
                      : (v) {
                          setState(() => _level = v!);
                          AppPrefs.setEnum('compress.level', v!);
                        },
                  child: Column(
                    children: [
                      for (final level in _CompressLevel.values)
                        RadioListTile<_CompressLevel>(
                          value: level,
                          title: Text(level.label),
                          dense: true,
                        ),
                    ],
                  ),
                ),
                DeleteOriginalsSwitch(
                  label: tr('Originaldatei danach löschen', 'Delete original file afterwards'),
                  value: _deleteOriginal,
                  onChanged: (v) => setState(() => _deleteOriginal = v),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _compress,
                  icon: BusyIcon(busy: _busy, child: const Icon(Icons.compress)),
                  label: Text(_busy ? tr('Komprimiere…', 'Compressing…') : tr('Komprimieren', 'Compress')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
