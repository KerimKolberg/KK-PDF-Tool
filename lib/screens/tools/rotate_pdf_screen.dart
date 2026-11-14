import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n.dart';
import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../services/settings_service.dart';
import '../../utils/formatting.dart';
import '../../widgets/busy_icon.dart';
import '../../widgets/delete_originals_switch.dart';
import '../../widgets/tool_drop_zone.dart';
import '../../widgets/tool_layout.dart';
import '../../widgets/tool_result.dart';

class _PickedPdf {
  final String name;
  final String? path;
  final Uint8List bytes;
  _PickedPdf(this.name, this.path, this.bytes);
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
  int _degrees = AppPrefs.getInt('rotate.degrees', 90);
  bool _deleteOriginals = false;
  bool _busy = false;

  Future<void> _addPdfs() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final files = await FilePickers.openMany('rotate_pdf', [typeGroup]);
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
    final pageIndices = parsePageSpec(_pageSpecController.text);
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
          tr('${_pdfs.length} Datei(en) gedreht${lastLocation != null ? ' → ${folderOf(lastLocation)}' : ''}', '${_pdfs.length} file(s) rotated${lastLocation != null ? ' → ${folderOf(lastLocation)}' : ''}');
      if (_deleteOriginals) {
        message += await OriginalFilesCleanupService.deleteAndDescribe([for (final pdf in _pdfs) pdf.path]);
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Drehen fehlgeschlagen: $e', 'Rotating failed: $e'))),
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
      onDrop: _addPdfs,
      child: ToolScaffold(
        appBar: AppBar(title: Text(tr('PDF drehen', 'Rotate PDF'))),
        body: _pdfs.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: FilePickPanel(
                  multiple: true,
                  hint: tr('Füge eine oder mehrere PDF-Dateien hinzu.', 'Add one or more PDF files.'),
                  onPressed: _addPdfs,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(tr('PDFs hinzufügen', 'Add PDFs')),
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
                  Text(tr('Winkel', 'Angle'), style: Theme.of(context).textTheme.titleSmall),
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
                        : (v) {
                            setState(() => _degrees = v.first);
                            AppPrefs.setInt('rotate.degrees', v.first);
                          },
                  ),
                  const SizedBox(height: 16),
                  Text(tr('Seiten (optional)', 'Pages (optional)'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _pageSpecController,
                    decoration: InputDecoration(
                      hintText: tr('z. B. 1-3,5 · leer lassen für alle Seiten', 'e.g. 1-3,5 · leave empty for all pages'),
                      border: const OutlineInputBorder(),
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
                        label: Text(tr('PDFs hinzufügen', 'Add PDFs')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _pdfs.isEmpty || _busy ? null : _rotate,
                        icon: BusyIcon(busy: _busy, child: const Icon(Icons.rotate_right)),
                        label: Text(_busy ? tr('Drehe…', 'Rotating…') : tr('Drehen & speichern', 'Rotate & save')),
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
