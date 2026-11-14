import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../l10n.dart';
import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/pdf_tools_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/busy_icon.dart';
import '../../widgets/delete_originals_switch.dart';
import '../../widgets/tool_drop_zone.dart';
import '../../widgets/tool_layout.dart';
import '../../widgets/tool_result.dart';

/// Adds page numbers and/or a header/footer text to every page of a PDF.
class PageNumbersScreen extends StatefulWidget {
  const PageNumbersScreen({super.key});

  @override
  State<PageNumbersScreen> createState() => _PageNumbersScreenState();
}

class _PageNumbersScreenState extends State<PageNumbersScreen> {
  final _downloadsExport = DownloadsExportService();
  final _headerController = TextEditingController(
    text: AppPrefs.getString('pageNumbers.header') ?? '',
  );
  final _footerController = TextEditingController(
    text: AppPrefs.getString('pageNumbers.footer') ?? '',
  );
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
      var message = tr('Gespeichert unter $location', 'Saved to $location');
      if (_deleteOriginal) {
        message += await OriginalFilesCleanupService.deleteAndDescribe([_sourcePath]);
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Fehlgeschlagen: $e', 'Failed: $e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolDropZone(
      onDrop: _pickPdf,
      child: ToolScaffold(
        appBar: AppBar(title: Text(tr('Seitenzahlen & Kopfzeile', 'Page numbers & header'))),
        body: _fileName == null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: FilePickPanel(
                  onPressed: _pickPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(tr('PDF wählen', 'Choose PDF')),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SelectedFileTile(name: _fileName!, onChange: _busy ? null : _pickPdf),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Seitenzahlen', 'Page numbers')),
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
                      decoration: InputDecoration(
                        labelText: tr('Beginnen bei', 'Start at'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextField(
                    controller: _headerController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: tr(
                        'Kopfzeile (optional, oben Mitte)',
                        'Header (optional, top center)',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _footerController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: tr(
                        'Fußzeile (optional, unten links)',
                        'Footer (optional, bottom left)',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DeleteOriginalsSwitch(
                    label: tr('Originaldatei danach löschen', 'Delete original file afterwards'),
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
                    icon: BusyIcon(busy: _busy, child: const Icon(Icons.format_list_numbered)),
                    label: Text(
                      _busy
                          ? tr('Wird erstellt…', 'Creating…')
                          : tr('Anwenden & speichern', 'Apply & save'),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
