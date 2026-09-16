import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/pdf_tools_service.dart';

class _PickedPdf {
  final String name;
  final Uint8List bytes;
  _PickedPdf(this.name, this.bytes);
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
  bool _busy = false;

  Future<void> _addPdfs() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return;
    final picked = await Future.wait(files.map((f) async {
      final bytes = await f.readAsBytes();
      return _PickedPdf(p.basenameWithoutExtension(f.name), bytes);
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zusammengeführt und gespeichert unter $location')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zusammenführen fehlgeschlagen: $e')),
      );
    }
  }

  Future<String?> _askTitle() async {
    final controller = TextEditingController(text: 'Zusammengeführt');
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
              Navigator.pop(context, text.isEmpty ? 'Zusammengeführt' : text);
            },
            child: const Text('Zusammenführen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDFs zusammenführen')),
      body: _pdfs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Füge mindestens zwei PDFs hinzu. Sie werden in dieser Reihenfolge zusammengeführt.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
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
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _addPdfs,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDFs hinzufügen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _pdfs.length < 2 || _busy ? null : _merge,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.merge_type),
                  label: Text(_busy ? 'Führe zusammen…' : 'Zusammenführen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
