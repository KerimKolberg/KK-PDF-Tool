import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../widgets/delete_originals_switch.dart';

class _PickedPdf {
  final String name;
  final String? path;
  final Uint8List bytes;
  _PickedPdf(this.name, this.path, this.bytes);
}

/// Parses a page spec like "1-3,5,8-9" (1-based, as typed by a user) into
/// 0-based page indices. Returns null (meaning "all pages") for blank input.
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

/// Rotates one or more PDFs, either entirely or just a chosen set of pages
/// (e.g. "1-3,5").
class RotatePdfScreen extends StatefulWidget {
  const RotatePdfScreen({super.key});

  @override
  State<RotatePdfScreen> createState() => _RotatePdfScreenState();
}

class _RotatePdfScreenState extends State<RotatePdfScreen> {
  final _downloadsExport = DownloadsExportService();
  final _pageSpecController = TextEditingController();
  final List<_PickedPdf> _pdfs = [];
  int _degrees = 90;
  bool _deleteOriginals = false;
  bool _busy = false;

  Future<void> _addPdfs() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return;
    final picked = await Future.wait(files.map((f) async {
      final bytes = await f.readAsBytes();
      return _PickedPdf(p.basenameWithoutExtension(f.name), f.path, bytes);
    }));
    setState(() => _pdfs.addAll(picked));
  }

  void _remove(int index) => setState(() => _pdfs.removeAt(index));

  Future<void> _rotate() async {
    if (_pdfs.isEmpty || _busy) return;
    final pageIndices = _parsePageSpec(_pageSpecController.text);
    setState(() => _busy = true);
    try {
      String? lastLocation;
      for (final pdf in _pdfs) {
        final rotated = await PdfToolsService.rotatePages(
          pdf.bytes,
          pageIndices: pageIndices?.toList(),
          degrees: _degrees,
        );
        lastLocation = await _downloadsExport.export(
          rotated,
          '${pdf.name}_gedreht.pdf',
        );
      }
      var message =
          '${_pdfs.length} Datei(en) gedreht${lastLocation != null ? ' → ${_folderOf(lastLocation)}' : ''}';
      if (_deleteOriginals) {
        final notDeleted = await OriginalFilesCleanupService.deleteAll(
          [for (final pdf in _pdfs) pdf.path],
        );
        if (notDeleted.isNotEmpty) {
          message += ' · ${notDeleted.length} Original(e) konnten nicht gelöscht werden';
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Drehen fehlgeschlagen: $e')),
      );
    }
  }

  String _folderOf(String location) {
    final idx = location.lastIndexOf(RegExp(r'[\\/]'));
    return idx == -1 ? location : location.substring(0, idx);
  }

  @override
  void dispose() {
    _pageSpecController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF drehen')),
      body: _pdfs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Füge eine oder mehrere PDF-Dateien hinzu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (var i = 0; i < _pdfs.length; i++)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(_pdfs[i].name),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(i),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text('Winkel', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 90, label: Text('90°')),
                    ButtonSegment(value: 180, label: Text('180°')),
                    ButtonSegment(value: 270, label: Text('270°')),
                  ],
                  selected: {_degrees},
                  onSelectionChanged: _busy
                      ? null
                      : (v) => setState(() => _degrees = v.first),
                ),
                const SizedBox(height: 16),
                Text('Seiten (optional)', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                TextField(
                  controller: _pageSpecController,
                  decoration: const InputDecoration(
                    hintText: 'z. B. 1-3,5 · leer lassen für alle Seiten',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
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
                      label: const Text('PDFs hinzufügen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _pdfs.isEmpty || _busy ? null : _rotate,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.rotate_right),
                      label: Text(_busy ? 'Drehe…' : 'Drehen & speichern'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
