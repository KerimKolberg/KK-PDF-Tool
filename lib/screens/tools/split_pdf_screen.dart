import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../widgets/delete_originals_switch.dart';

class _PageRange {
  final TextEditingController from;
  final TextEditingController to;
  _PageRange(int start, int end)
      : from = TextEditingController(text: '$start'),
        to = TextEditingController(text: '$end');
}

/// Splits a picked PDF into several new PDFs, one per user-defined
/// (1-based, inclusive) page range.
class SplitPdfScreen extends StatefulWidget {
  const SplitPdfScreen({super.key});

  @override
  State<SplitPdfScreen> createState() => _SplitPdfScreenState();
}

class _SplitPdfScreenState extends State<SplitPdfScreen> {
  final _downloadsExport = DownloadsExportService();
  String? _fileName;
  String? _sourcePath;
  Uint8List? _pdfBytes;
  int? _pageCount;
  final List<_PageRange> _ranges = [];
  bool _deleteOriginal = false;
  bool _busy = false;
  bool _counting = false;

  Future<void> _pickPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _sourcePath = file.path;
      _pdfBytes = bytes;
      _pageCount = null;
      _ranges
        ..clear()
        ..add(_PageRange(1, 1));
      _counting = true;
    });
    try {
      final count = await PdfToolsService.countPages(bytes);
      if (!mounted) return;
      setState(() {
        _pageCount = count;
        _ranges[0] = _PageRange(1, count);
        _counting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _counting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte PDF nicht lesen: $e')),
      );
    }
  }

  void _addRange() {
    final last = _ranges.isEmpty ? 0 : int.tryParse(_ranges.last.to.text) ?? 0;
    final next = (last + 1).clamp(1, _pageCount ?? 1);
    setState(() => _ranges.add(_PageRange(next, _pageCount ?? next)));
  }

  void _removeRange(int index) => setState(() => _ranges.removeAt(index));

  Future<void> _split() async {
    final bytes = _pdfBytes;
    final pageCount = _pageCount;
    final name = _fileName;
    if (bytes == null || pageCount == null || name == null || _busy) return;
    if (_ranges.isEmpty) return;

    final parsedRanges = <(int, int)>[];
    for (final r in _ranges) {
      final start = int.tryParse(r.from.text.trim());
      final end = int.tryParse(r.to.text.trim());
      if (start == null || end == null || start < 1 || end > pageCount || start > end) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ungültiger Seitenbereich (gültig: 1–$pageCount).',
            ),
          ),
        );
        return;
      }
      parsedRanges.add((start, end));
    }

    setState(() => _busy = true);
    try {
      String? lastLocation;
      for (var i = 0; i < parsedRanges.length; i++) {
        final (start, end) = parsedRanges[i];
        final part = await PdfToolsService.extractRange(
          bytes,
          startPage: start,
          endPage: end,
        );
        final suffix = parsedRanges.length > 1 ? '_teil_${i + 1}' : '_teil';
        lastLocation = await _downloadsExport.export(
          part,
          '$name${suffix}_s$start-$end.pdf',
        );
      }
      var message =
          '${parsedRanges.length} Datei(en) gespeichert${lastLocation != null ? ' in ${_folderOf(lastLocation)}' : ''}';
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
        SnackBar(content: Text('Aufteilen fehlgeschlagen: $e')),
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
      appBar: AppBar(title: const Text('PDF aufteilen')),
      body: _pdfBytes == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Wähle eine PDF-Datei, die in mehrere Dateien aufgeteilt werden soll.',
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
          : _counting
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '$_fileName · $_pageCount Seiten',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < _ranges.length; i++)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Text('Teil ${i + 1}:'),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _ranges[i].from,
                                  keyboardType: TextInputType.number,
                                  decoration:
                                      const InputDecoration(labelText: 'von Seite'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _ranges[i].to,
                                  keyboardType: TextInputType.number,
                                  decoration:
                                      const InputDecoration(labelText: 'bis Seite'),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _ranges.length > 1
                                    ? () => _removeRange(i)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _addRange,
                      icon: const Icon(Icons.add),
                      label: const Text('Weiteren Bereich hinzufügen'),
                    ),
                  ],
                ),
      bottomNavigationBar: _pdfBytes == null || _counting
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
                      onPressed: _busy ? null : _split,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.content_cut),
                      label: Text(_busy ? 'Teile auf…' : 'Aufteilen & speichern'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
