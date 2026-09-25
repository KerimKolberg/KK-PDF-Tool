import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../widgets/delete_originals_switch.dart';

enum _CompressLevel { low, medium, high }

extension on _CompressLevel {
  String get label => switch (this) {
        _CompressLevel.low => 'Wenig (beste Qualität)',
        _CompressLevel.medium => 'Mittel',
        _CompressLevel.high => 'Stark (kleinste Datei)',
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
  _CompressLevel _level = _CompressLevel.medium;
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
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
      final before = _formatSize(bytes.length);
      final after = _formatSize(compressed.length);
      var message = '$before → $after · gespeichert unter $location';
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
        SnackBar(content: Text('Komprimierung fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF komprimieren')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                subtitle: Text(_formatSize(_pdfBytes!.length)),
                trailing: TextButton(
                  onPressed: _busy ? null : _pickPdf,
                  child: const Text('Ändern'),
                ),
              ),
              const SizedBox(height: 12),
              Text('Kompressionsgrad', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              RadioGroup<_CompressLevel>(
                groupValue: _level,
                onChanged: _busy ? (_) {} : (v) => setState(() => _level = v!),
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
                label: 'Originaldatei danach löschen',
                value: _deleteOriginal,
                onChanged: (v) => setState(() => _deleteOriginal = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _compress,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.compress),
                label: Text(_busy ? 'Komprimiere…' : 'Komprimieren'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
