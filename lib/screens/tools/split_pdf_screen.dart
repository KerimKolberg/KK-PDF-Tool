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
    final file = await FilePickers.openOne('split_pdf', [typeGroup]);
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
        SnackBar(content: Text(tr('Konnte PDF nicht lesen: $e', 'Could not read PDF: $e'))),
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
              tr(
                'Ungültiger Seitenbereich (gültig: 1–$pageCount).',
                'Invalid page range (valid: 1–$pageCount).',
              ),
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
        final part = await PdfToolsService.extractRange(bytes, startPage: start, endPage: end);
        final suffix = parsedRanges.length > 1 ? tr('_teil_${i + 1}', '_part_${i + 1}') : '_teil';
        lastLocation = await _downloadsExport.export(part, '$name${suffix}_s$start-$end.pdf');
      }
      var message = tr(
        '${parsedRanges.length} Datei(en) gespeichert${lastLocation != null ? ' in ${folderOf(lastLocation)}' : ''}',
        '${parsedRanges.length} file(s) saved${lastLocation != null ? ' in ${folderOf(lastLocation)}' : ''}',
      );
      if (_deleteOriginal) {
        message += await OriginalFilesCleanupService.deleteAndDescribe([_sourcePath]);
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Aufteilen fehlgeschlagen: $e', 'Splitting failed: $e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolDropZone(
      onDrop: _pickPdf,
      child: ToolScaffold(
        appBar: AppBar(title: Text(tr('PDF aufteilen', 'Split PDF'))),
        body: _pdfBytes == null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: FilePickPanel(
                  hint: tr(
                    'Wähle eine PDF-Datei, die in mehrere Dateien aufgeteilt werden soll.',
                    'Choose a PDF file to split into several files.',
                  ),
                  onPressed: _pickPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(tr('PDF wählen', 'Choose PDF')),
                ),
              )
            : _counting
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    tr('$_fileName · $_pageCount Seiten', '$_fileName · $_pageCount pages'),
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
                            Text(tr('Teil ${i + 1}:', 'Part ${i + 1}:')),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _ranges[i].from,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: tr('von Seite', 'from page'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _ranges[i].to,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(labelText: tr('bis Seite', 'to page')),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _ranges.length > 1 ? () => _removeRange(i) : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addRange,
                    icon: const Icon(Icons.add),
                    label: Text(tr('Weiteren Bereich hinzufügen', 'Add another range')),
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
                        label: tr(
                          'Originaldatei danach löschen',
                          'Delete original file afterwards',
                        ),
                        value: _deleteOriginal,
                        onChanged: (v) => setState(() => _deleteOriginal = v),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _split,
                        icon: BusyIcon(busy: _busy, child: const Icon(Icons.content_cut)),
                        label: Text(
                          _busy
                              ? tr('Teile auf…', 'Splitting…')
                              : tr('Aufteilen & speichern', 'Split & save'),
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
