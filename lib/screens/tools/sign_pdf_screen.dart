import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../widgets/delete_originals_switch.dart';
import '../sign_pages_screen.dart';

/// Picks a PDF, lets the user place signatures on its pages and saves the
/// signed copy to Downloads.
class SignPdfScreen extends StatefulWidget {
  const SignPdfScreen({super.key});

  @override
  State<SignPdfScreen> createState() => _SignPdfScreenState();
}

class _SignPdfScreenState extends State<SignPdfScreen> {
  final _downloadsExport = DownloadsExportService();
  String? _fileName;
  String? _sourcePath;
  Uint8List? _pdfBytes;
  bool _deleteOriginal = false;
  String? _busyLabel;

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

  Future<void> _sign() async {
    final bytes = _pdfBytes;
    final name = _fileName;
    if (bytes == null || name == null || _busyLabel != null) return;
    setState(() => _busyLabel = 'Seiten werden geladen…');
    try {
      final rendered = await PdfToolsService.rasterPages(bytes, dpi: 170);
      final pages = await PdfToolsService.toJpegs(rendered, quality: 90);
      if (!mounted) return;
      setState(() => _busyLabel = null);

      final signed = await Navigator.of(context).push<List<Uint8List>>(
        MaterialPageRoute(builder: (_) => SignPagesScreen(pages: pages)),
      );
      if (signed == null || !mounted) return;

      setState(() => _busyLabel = 'Speichere…');
      final pdf = await PdfService.buildPdf(signed);
      final location = await _downloadsExport.export(pdf, '${name}_unterschrieben.pdf');
      var message = 'Gespeichert unter $location';
      if (_deleteOriginal) {
        final notDeleted = await OriginalFilesCleanupService.deleteAll([_sourcePath]);
        if (notDeleted.isNotEmpty) message += ' · Original konnte nicht gelöscht werden';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyLabel = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unterschreiben fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busyLabel != null;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF unterschreiben')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Unterschrift einmal zeichnen und speichern, danach auf beliebigen '
              'Seiten platzieren. Läuft komplett offline.',
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
                onPressed: busy ? null : _sign,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.draw_outlined),
                label: Text(_busyLabel ?? 'Unterschreiben'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
