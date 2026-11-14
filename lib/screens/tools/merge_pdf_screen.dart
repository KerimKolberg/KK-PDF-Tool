import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../widgets/delete_originals_switch.dart';
import '../../widgets/tool_drop_zone.dart';
import '../../widgets/tool_layout.dart';
import '../../widgets/tool_result.dart';
import '../../l10n.dart';
import '../../widgets/busy_icon.dart';

class _PickedPdf {
  final String name;
  final String? path;
  final Uint8List bytes;
  _PickedPdf(this.name, this.path, this.bytes);
}

/// Merges several picked PDFs, in a user-chosen order, into one PDF.
class MergePdfScreen extends StatefulWidget {
  const MergePdfScreen({super.key});

  @override
  State<MergePdfScreen> createState() => _MergePdfScreenState();
}

class _MergePdfScreenState extends State<MergePdfScreen> {
  final _downloadsExport = DownloadsExportService();
  final List<_PickedPdf> _pdfs = [];
  bool _deleteOriginals = false;
  bool _busy = false;

  Future<void> _addPdfs() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final files = await FilePickers.openMany('merge_pdf', [typeGroup]);
    if (files.isEmpty) return;
    final picked = await Future.wait(files.map((f) async {
      final bytes = await f.readAsBytes();
      return _PickedPdf(p.basenameWithoutExtension(f.name), f.path, bytes);
    }));
    setState(() => _pdfs.addAll(picked));
  }

  void _remove(int index) => setState(() => _pdfs.removeAt(index));

  Future<void> _merge() async {
    if (_pdfs.length < 2 || _busy) return;
    final title = await _askTitle();
    if (title == null) return;

    setState(() => _busy = true);
    try {
      final merged = await PdfToolsService.merge(
        [for (final pdf in _pdfs) pdf.bytes],
      );
      final location = await _downloadsExport.export(merged, '$title.pdf');
      var message = tr('Zusammengeführt und gespeichert unter $location', 'Merged and saved to $location');
      if (_deleteOriginals) {
        message += await OriginalFilesCleanupService.deleteAndDescribe([for (final pdf in _pdfs) pdf.path]);
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Zusammenführen fehlgeschlagen: $e', 'Merging failed: $e'))),
      );
    }
  }

  Future<String?> _askTitle() async {
    final controller = TextEditingController(text: tr('Zusammengeführt', 'Merged'));
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
              Navigator.pop(context, text.isEmpty ? tr('Zusammengeführt', 'Merged') : text);
            },
            child: Text(tr('Zusammenführen', 'Merge')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ToolDropZone(
      onDrop: _addPdfs,
      child: ToolScaffold(
        appBar: AppBar(title: Text(tr('PDFs zusammenführen', 'Merge PDFs'))),
        body: _pdfs.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: FilePickPanel(
                  multiple: true,
                  hint: tr('Füge mindestens zwei PDFs hinzu. Sie werden in dieser Reihenfolge zusammengeführt.', 'Add at least two PDFs. They are merged in this order.'),
                  onPressed: _addPdfs,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(tr('PDFs hinzufügen', 'Add PDFs')),
                ),
              )
            : ReorderableListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _pdfs.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final item = _pdfs.removeAt(oldIndex);
                    _pdfs.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, i) => Card(
                  key: ValueKey('${_pdfs[i].name}_$i'),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(_pdfs[i].name),
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
                if (_pdfs.isNotEmpty)
                  DeleteOriginalsSwitch(
                    value: _deleteOriginals,
                    onChanged: (v) => setState(() => _deleteOriginals = v),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _addPdfs,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(tr('PDFs hinzufügen', 'Add PDFs')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _pdfs.length < 2 || _busy ? null : _merge,
                        icon: BusyIcon(busy: _busy, child: const Icon(Icons.merge_type)),
                        label: Text(_busy ? tr('Führe zusammen…', 'Merging…') : tr('Zusammenführen', 'Merge')),
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
