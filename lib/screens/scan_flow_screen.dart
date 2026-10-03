import 'dart:io';
import 'dart:typed_data';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';

import '../models/scan_document.dart';
import '../services/document_builder.dart';
import '../services/document_store.dart';
import '../services/downloads_export_service.dart';
import '../services/settings_service.dart';
import 'capture_screen.dart';
import 'crop_screen.dart';

/// Orchestrates a scanning session: capture/crop one or more pages, then
/// save them as a new [ScanDocument] with a generated PDF.
class ScanFlowScreen extends StatefulWidget {
  final DocumentStore store;

  /// Library folder the new document is saved into (null = none).
  final String? folder;

  /// Pages to start with (e.g. already captured elsewhere).
  final List<Uint8List> initialPages;

  const ScanFlowScreen({
    super.key,
    required this.store,
    this.folder,
    this.initialPages = const [],
  });

  @override
  State<ScanFlowScreen> createState() => _ScanFlowScreenState();
}

class _ScanFlowScreenState extends State<ScanFlowScreen> {
  late final List<Uint8List> _pages = List.of(widget.initialPages);
  final _settings = SettingsService();
  final _downloadsExport = DownloadsExportService();
  bool _saving = false;
  String? _savingLabel;
  bool _autoScanning = false;
  bool _cropEnabled = true;

  /// Batch mode: every page becomes its own document (e.g. a stack of
  /// receipts) instead of one multi-page document.
  bool _batch = AppPrefs.getBool('scan.batch', false);

  bool get _hasAutoScan => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _settings.getCropEnabledDefault().then((value) {
      if (mounted) setState(() => _cropEnabled = value);
    });
    // On platforms without the automatic ML Kit scanner, go straight into
    // manual capture since there's no choice to offer.
    if (!_hasAutoScan && _pages.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addPage());
    }
  }

  Future<void> _addPage() async {
    final raw = await Navigator.of(
      context,
    ).push<Uint8List>(MaterialPageRoute(builder: (_) => const CaptureScreen()));
    if (raw == null || !mounted) return;
    final processed = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) =>
            CropScreen(initialBytes: raw, initialCropEnabled: _cropEnabled),
      ),
    );
    if (processed == null || !mounted) return;
    setState(() => _pages.add(processed));
  }

  /// Uses Google ML Kit's on-device document scanner (Android only): the
  /// user gets a native camera UI with automatic edge detection and
  /// perspective correction, just like CamScanner's auto-capture. Works
  /// fully offline once the ML Kit module is installed (it self-installs
  /// via Play Services the first time it's used).
  Future<void> _autoScan() async {
    if (_autoScanning || _saving) return;
    setState(() => _autoScanning = true);
    try {
      final paths = await CunningDocumentScanner.getPictures(noOfPages: 20);
      if (paths == null || paths.isEmpty) {
        if (mounted) setState(() => _autoScanning = false);
        return;
      }
      final newPages = await Future.wait(
        paths.map((path) => File(path).readAsBytes()),
      );
      if (!mounted) return;
      setState(() {
        _pages.addAll(newPages);
        _autoScanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _autoScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Automatischer Scan fehlgeschlagen: $e')),
      );
    }
  }

  /// Re-opens a captured page to change its filter or rotation - also the
  /// way to apply the app's filters to pages from "Automatisch scannen".
  Future<void> _editPage(int index) async {
    if (_saving) return;
    final edited = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) =>
            CropScreen(initialBytes: _pages[index], initialCropEnabled: false),
      ),
    );
    if (edited == null || !mounted) return;
    setState(() => _pages[index] = edited);
  }

  void _removePage(int index) {
    setState(() => _pages.removeAt(index));
  }

  Future<bool> _confirmDiscard() async {
    if (_pages.isEmpty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan verwerfen?'),
        content: Text('${_pages.length} erfasste Seite(n) gehen verloren.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _save() async {
    if (_pages.isEmpty || _saving) return;
    final title = await _askTitle(batch: _batch);
    if (title == null) return;
    if (_batch) return _saveBatch(title);

    setState(() => _saving = true);
    try {
      final built = await DocumentBuilder.build(
        _pages,
        onProgress: (done, total) {
          if (mounted) {
            setState(
              () => _savingLabel =
                  'Text ${done < total ? done + 1 : total}/$total…',
            );
          }
        },
      );
      final pdfBytes = built.pdfBytes;
      final doc = await widget.store.createDocument(
        title: title,
        pageJpegBytes: built.pages,
        pdfBytes: pdfBytes,
        text: built.text,
        ocr: built.ocr,
        folder: widget.folder,
      );
      String? location;
      try {
        location = await _downloadsExport.export(pdfBytes, '$title.pdf');
      } catch (_) {
        // Document is already safely stored in the app library; the
        // Downloads export is a convenience copy, so a failure here
        // shouldn't block the save.
      }
      if (!mounted) return;
      if (location != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gespeichert unter $location')));
      }
      Navigator.of(context).pop<ScanDocument>(doc);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    }
  }

  /// Saves every page as its own document, numbered "<title> 1", "<title> 2"…
  /// If something fails midway, the documents already saved stay in the
  /// library and are removed from this session so a retry won't duplicate
  /// them.
  Future<void> _saveBatch(String baseTitle) async {
    setState(() => _saving = true);
    final total = _pages.length;
    final digits = '$total'.length;
    var saved = 0;
    ScanDocument? last;
    try {
      for (var i = 0; i < total; i++) {
        if (mounted) setState(() => _savingLabel = '${i + 1}/$total…');
        final built = await DocumentBuilder.build([_pages[i]]);
        final title = '$baseTitle ${(i + 1).toString().padLeft(digits, '0')}';
        last = await widget.store.createDocument(
          title: title,
          pageJpegBytes: built.pages,
          pdfBytes: built.pdfBytes,
          text: built.text,
          ocr: built.ocr,
          folder: widget.folder,
        );
        saved++;
        try {
          await _downloadsExport.export(built.pdfBytes, '$title.pdf');
        } catch (_) {
          // Convenience copy only; the document itself is saved.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$total Dokumente gespeichert'
            '${widget.folder != null ? ' in "${widget.folder}"' : ''}',
          ),
        ),
      );
      Navigator.of(context).pop<ScanDocument>(last);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pages.removeRange(0, saved);
        _saving = false;
        _savingLabel = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler nach $saved von $total Dokumenten: $e')),
      );
    }
  }

  Future<String?> _askTitle({bool batch = false}) async {
    final now = DateTime.now();
    final defaultTitle =
        'Scan ${now.day}.${now.month}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final controller = TextEditingController(text: defaultTitle);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          batch ? '${_pages.length} Dokumente speichern' : 'Dokument speichern',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Titel',
            helperText: batch
                ? 'Wird nummeriert: "Titel 1", "Titel 2", …'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(context, text.isEmpty ? defaultTitle : text);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscard();
        if (!context.mounted) return;
        if (shouldPop) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Neuer Scan (${_pages.length} Seite(n))'),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  const Text('Zuschnitt', style: TextStyle(fontSize: 13)),
                  Switch(
                    value: _cropEnabled,
                    onChanged: (v) => setState(() => _cropEnabled = v),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: SwitchListTile(
                dense: true,
                secondary: const Icon(Icons.burst_mode_outlined),
                title: const Text('Stapel-Modus'),
                subtitle: const Text(
                  'Jede Seite als eigenes Dokument speichern (z. B. Belege)',
                ),
                value: _batch,
                onChanged: _saving
                    ? null
                    : (v) {
                        setState(() => _batch = v);
                        AppPrefs.setBool('scan.batch', v);
                      },
              ),
            ),
            Expanded(child: _buildPages()),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (_hasAutoScan && _pages.isNotEmpty) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving || _autoScanning ? null : _autoScan,
                      icon: const Icon(Icons.document_scanner),
                      label: const Text('Scan'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _addPage,
                    icon: const Icon(Icons.add_a_photo),
                    label: Text(_hasAutoScan ? 'Manuell' : 'Seite hinzufügen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pages.isEmpty || _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _saving ? (_savingLabel ?? 'Speichere…') : 'Speichern',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPages() {
    return _pages.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hasAutoScan
                        ? 'Automatisch scannen erkennt das Dokument\nund den Zuschnitt direkt beim Fotografieren.'
                        : 'Noch keine Seite erfasst.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  if (_hasAutoScan) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _autoScanning ? null : _autoScan,
                      icon: _autoScanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.document_scanner),
                      label: Text(
                        _autoScanning ? 'Scanne…' : 'Automatisch scannen',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _addPage,
                      icon: const Icon(Icons.add_a_photo),
                      label: const Text('Manuell aufnehmen'),
                    ),
                  ],
                ],
              ),
            ),
          )
        : GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.72,
            ),
            itemCount: _pages.length,
            itemBuilder: (context, i) => Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: () => _editPage(i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _pages[i],
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: InkWell(
                    onTap: () => _editPage(i),
                    child: const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.tune, size: 14, color: Colors.white),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: InkWell(
                    onTap: () => _removePage(i),
                    child: const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          );
  }
}
