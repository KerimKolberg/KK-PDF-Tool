import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../widgets/delete_originals_switch.dart';
import '../annotate_pages_screen.dart';
import '../../widgets/tool_result.dart';

/// Picks a PDF, opens it in the fill-in/drawing editor and saves the edited
/// copy to Downloads.
class AnnotatePdfScreen extends StatefulWidget {
  final AnnotateMode mode;

  const AnnotatePdfScreen({super.key, required this.mode});

  @override
  State<AnnotatePdfScreen> createState() => _AnnotatePdfScreenState();
}

class _AnnotatePdfScreenState extends State<AnnotatePdfScreen> {
  final _downloadsExport = DownloadsExportService();
  String? _fileName;
  String? _sourcePath;
  Uint8List? _pdfBytes;
  bool _deleteOriginal = false;
  String? _busyLabel;

  bool get _fill => widget.mode == AnnotateMode.fill;

  Future<void> _pickPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await FilePickers.openOne('annotate_pdf', [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _sourcePath = file.path;
      _pdfBytes = bytes;
    });
  }

  Future<void> _edit() async {
    final bytes = _pdfBytes;
    final name = _fileName;
    if (bytes == null || name == null || _busyLabel != null) return;
    setState(() => _busyLabel = 'Seiten werden geladen…');
    try {
      final rendered = await PdfToolsService.rasterPages(bytes, dpi: 170);
      final pages = await PdfToolsService.toJpegs(rendered, quality: 90);
      if (!mounted) return;
      setState(() => _busyLabel = null);

      final edited = await Navigator.of(context).push<List<Uint8List>>(
        MaterialPageRoute(
          builder: (_) => AnnotatePagesScreen(pages: pages, initialMode: widget.mode),
        ),
      );
      if (edited == null || !mounted) return;

      setState(() => _busyLabel = 'Speichere…');
      final pdf = await PdfService.buildPdf(edited);
      final suffix = _fill ? '_ausgefuellt' : '_markiert';
      final location = await _downloadsExport.export(pdf, '$name$suffix.pdf');
      var message = 'Gespeichert unter $location';
      if (_deleteOriginal) {
        final notDeleted = await OriginalFilesCleanupService.deleteAll([_sourcePath]);
        if (notDeleted.isNotEmpty) message += ' · Original konnte nicht gelöscht werden';
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyLabel = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bearbeiten fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busyLabel != null;
    return Scaffold(
      appBar: AppBar(title: Text(_fill ? 'PDF ausfüllen & unterschreiben' : 'PDF markieren & zeichnen')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _fill
                  ? 'Text, Datum, Haken/Kreuze und Unterschriften auf beliebigen Seiten '
                      'platzieren - z. B. um Formulare auszufüllen. Läuft komplett offline.'
                  : 'Mit Stift und Textmarker direkt auf die Seiten zeichnen. Läuft '
                      'komplett offline.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 24),
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
                trailing: TextButton(
                  onPressed: busy ? null : _pickPdf,
                  child: const Text('Ändern'),
                ),
              ),
              DeleteOriginalsSwitch(
                label: 'Originaldatei danach löschen',
                value: _deleteOriginal,
                onChanged: (v) => setState(() => _deleteOriginal = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy ? null : _edit,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(_fill ? Icons.edit_note : Icons.brush_outlined),
                label: Text(_busyLabel ?? (_fill ? 'Ausfüllen' : 'Zeichnen')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
