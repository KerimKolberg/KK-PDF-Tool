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
import '../../widgets/tool_drop_zone.dart';
import '../../widgets/tool_layout.dart';
import '../../widgets/tool_result.dart';
import '../../l10n.dart';
import '../../widgets/busy_icon.dart';

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
    setState(() => _busyLabel = tr('Seiten werden geladen…', 'Loading pages…'));
    try {
      final rendered = await PdfToolsService.renderPdf(bytes, dpi: 170, format: PageImageFormat.jpeg);
      final formats = rendered.formats;
      final pages = rendered.images;
      if (!mounted) return;
      setState(() => _busyLabel = null);

      final edited = await Navigator.of(context).push<List<Uint8List>>(
        MaterialPageRoute(
          builder: (_) => AnnotatePagesScreen(pages: pages, initialMode: widget.mode),
        ),
      );
      if (edited == null || !mounted) return;

      setState(() => _busyLabel = tr('Speichere…', 'Saving…'));
      final pdf = await PdfService.buildPdf(edited, pageFormats: formats);
      final suffix = _fill ? '_ausgefuellt' : '_markiert';
      final location = await _downloadsExport.export(pdf, '$name$suffix.pdf');
      var message = tr('Gespeichert unter $location', 'Saved to $location');
      if (_deleteOriginal) {
        message += await OriginalFilesCleanupService.deleteAndDescribe([_sourcePath]);
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyLabel = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Bearbeiten fehlgeschlagen: $e', 'Editing failed: $e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busyLabel != null;
    return ToolDropZone(
      onDrop: _pickPdf,
      child: ToolScaffold(
        appBar: AppBar(title: Text(_fill ? tr('PDF ausfüllen & unterschreiben', 'Fill in & sign PDF') : tr('PDF markieren & zeichnen', 'Highlight & draw on PDF'))),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _fill
                    ? tr('Text, Datum, Haken/Kreuze und Unterschriften auf beliebigen Seiten '
                        'platzieren - z. B. um Formulare auszufüllen. Läuft komplett offline.',
                        'Place text, date, check marks/crosses and signatures on any pages '
                        '- e.g. to fill in forms. Runs completely offline.')
                    : tr('Mit Stift und Textmarker direkt auf die Seiten zeichnen. Läuft '
                        'komplett offline.',
                        'Draw directly on the pages with pen and highlighter. Runs '
                        'completely offline.'),
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 24),
              if (_fileName == null)
                FilePickPanel(
                  onPressed: _pickPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(tr('PDF wählen', 'Choose PDF')),
                )
              else ...[
                SelectedFileTile(
                  name: _fileName!,
                  onChange: busy ? null : _pickPdf,
                ),
                DeleteOriginalsSwitch(
                  label: tr('Originaldatei danach löschen', 'Delete original file afterwards'),
                  value: _deleteOriginal,
                  onChanged: (v) => setState(() => _deleteOriginal = v),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy ? null : _edit,
                  icon: BusyIcon(busy: busy, child: Icon(_fill ? Icons.edit_note : Icons.brush_outlined)),
                  label: Text(_busyLabel ?? (_fill ? tr('Ausfüllen', 'Fill in') : tr('Zeichnen', 'Draw'))),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
