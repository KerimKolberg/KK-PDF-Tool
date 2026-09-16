import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/scan_document.dart';
import '../services/document_store.dart';
import '../services/downloads_export_service.dart';
import '../services/pdf_service.dart';
import '../services/settings_service.dart';
import 'capture_screen.dart';
import 'crop_screen.dart';

/// Orchestrates a scanning session: capture/crop one or more pages, then
/// save them as a new [ScanDocument] with a generated PDF.
class ScanFlowScreen extends StatefulWidget {
  final DocumentStore store;

  const ScanFlowScreen({super.key, required this.store});

  @override
  State<ScanFlowScreen> createState() => _ScanFlowScreenState();
}

class _ScanFlowScreenState extends State<ScanFlowScreen> {
  final List<Uint8List> _pages = [];
  final _settings = SettingsService();
  final _downloadsExport = DownloadsExportService();
  bool _saving = false;
  bool _cropEnabled = true;

  @override
  void initState() {
    super.initState();
    _settings.getCropEnabledDefault().then((value) {
      if (mounted) setState(() => _cropEnabled = value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _addPage());
  }

  Future<void> _addPage() async {
    final raw = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const CaptureScreen()),
    );
    if (raw == null || !mounted) return;
    final processed = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => CropScreen(
          initialBytes: raw,
          initialCropEnabled: _cropEnabled,
        ),
      ),
    );
    if (processed == null || !mounted) return;
    setState(() => _pages.add(processed));
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
        content: Text(
          '${_pages.length} erfasste Seite(n) gehen verloren.',
        ),
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
    final title = await _askTitle();
    if (title == null) return;

    setState(() => _saving = true);
    try {
      final pdfBytes = await PdfService.buildPdf(_pages);
      final doc = await widget.store.createDocument(
        title: title,
        pageJpegBytes: _pages,
        pdfBytes: pdfBytes,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gespeichert unter $location')),
        );
      }
      Navigator.of(context).pop<ScanDocument>(doc);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
    }
  }

  Future<String?> _askTitle() async {
    final now = DateTime.now();
    final defaultTitle =
        'Scan ${now.day}.${now.month}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final controller = TextEditingController(text: defaultTitle);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dokument speichern'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Titel'),
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
        body: _pages.isEmpty
            ? const Center(child: Text('Noch keine Seite erfasst.'))
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_pages[i], fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: () => _removePage(i),
                        child: const CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _addPage,
                    icon: const Icon(Icons.add_a_photo),
                    label: const Text('Seite hinzufügen'),
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
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Speichere…' : 'Speichern'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
