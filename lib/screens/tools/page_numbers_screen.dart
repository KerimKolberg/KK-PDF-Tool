import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/delete_originals_switch.dart';

/// Adds page numbers and/or a header/footer text to every page of a PDF.
class PageNumbersScreen extends StatefulWidget {
  const PageNumbersScreen({super.key});

  @override
  State<PageNumbersScreen> createState() => _PageNumbersScreenState();
}

class _PageNumbersScreenState extends State<PageNumbersScreen> {
  final _downloadsExport = DownloadsExportService();
  final _headerController =
      TextEditingController(text: AppPrefs.getString('pageNumbers.header') ?? '');
  final _footerController =
      TextEditingController(text: AppPrefs.getString('pageNumbers.footer') ?? '');
  final _startController = TextEditingController(text: '1');
  String? _fileName;
  String? _sourcePath;
  Uint8List? _pdfBytes;
  bool _numbersEnabled = AppPrefs.getBool('pageNumbers.enabled', true);
  PageNumberFormat _format = AppPrefs.getEnum(
    'pageNumbers.format',
    PageNumberFormat.values,
    PageNumberFormat.seiteVon,
  );
  PageNumberPosition _position = AppPrefs.getEnum(
    'pageNumbers.position',
    PageNumberPosition.values,
    PageNumberPosition.bottomCenter,
  );
  bool _deleteOriginal = false;
  bool _busy = false;

  @override
  void dispose() {
    _headerController.dispose();
    _footerController.dispose();
    _startController.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await FilePickers.openOne('page_numbers', [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _sourcePath = file.path;
      _pdfBytes = bytes;
    });
  }

  bool get _hasSomethingToAdd =>
      _numbersEnabled ||
      _headerController.text.trim().isNotEmpty ||
      _footerController.text.trim().isNotEmpty;

  Future<void> _apply() async {
    final bytes = _pdfBytes;
    final name = _fileName;
    if (bytes == null || name == null || _busy || !_hasSomethingToAdd) return;
    setState(() => _busy = true);
    try {
      AppPrefs.setBool('pageNumbers.enabled', _numbersEnabled);
      AppPrefs.setEnum('pageNumbers.format', _format);
      AppPrefs.setEnum('pageNumbers.position', _position);
      AppPrefs.setString('pageNumbers.header', _headerController.text);
      AppPrefs.setString('pageNumbers.footer', _footerController.text);
      final result = await PdfToolsService.addPageNumbers(
        bytes,
        numberFormat: _numbersEnabled ? _format : null,
        position: _position,
        startAt: int.tryParse(_startController.text.trim()) ?? 1,
        header: _headerController.text,
        footer: _footerController.text,
      );
      final location = await _downloadsExport.export(result, '${name}_nummeriert.pdf');
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
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seitenzahlen & Kopfzeile')),
      body: _fileName == null
          ? Center(
              child: FilledButton.icon(
                onPressed: _pickPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF wählen'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(_fileName!),
                  trailing: TextButton(
                    onPressed: _busy ? null : _pickPdf,
                    child: const Text('Ändern'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Seitenzahlen'),
                  value: _numbersEnabled,
                  onChanged: (v) => setState(() => _numbersEnabled = v),
                ),
                if (_numbersEnabled) ...[
                  DropdownButtonFormField<PageNumberFormat>(
                    initialValue: _format,
                    decoration: const InputDecoration(
                      labelText: 'Format',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final f in PageNumberFormat.values)
                        DropdownMenuItem(value: f, child: Text(f.example)),
                    ],
                    onChanged: (v) => setState(() => _format = v ?? _format),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PageNumberPosition>(
                    initialValue: _position,
                    decoration: const InputDecoration(
                      labelText: 'Position',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final pos in PageNumberPosition.values)
                        DropdownMenuItem(value: pos, child: Text(pos.label)),
                    ],
                    onChanged: (v) => setState(() => _position = v ?? _position),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _startController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Beginnen bei',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: _headerController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Kopfzeile (optional, oben Mitte)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _footerController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Fußzeile (optional, unten links)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DeleteOriginalsSwitch(
                  label: 'Originaldatei danach löschen',
                  value: _deleteOriginal,
                  onChanged: (v) => setState(() => _deleteOriginal = v),
                ),
              ],
            ),
      bottomNavigationBar: _fileName == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _busy || !_hasSomethingToAdd ? null : _apply,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.format_list_numbered),
                  label: Text(_busy ? 'Wird erstellt…' : 'Anwenden & speichern'),
                ),
              ),
            ),
    );
  }
}
