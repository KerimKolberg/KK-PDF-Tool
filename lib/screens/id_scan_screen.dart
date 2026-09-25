import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/scan_document.dart';
import '../services/document_store.dart';
import '../services/downloads_export_service.dart';
import '../services/pdf_service.dart';
import '../services/pdf_tools_service.dart';
import '../services/settings_service.dart';
import 'capture_screen.dart';
import 'crop_screen.dart';

/// Captures the front and back of an ID card/document and combines both
/// into a single one-page PDF, matching the "copy of both sides on one
/// sheet" layout most offices/authorities ask for.
class IdScanScreen extends StatefulWidget {
  final DocumentStore store;

  const IdScanScreen({super.key, required this.store});

  @override
  State<IdScanScreen> createState() => _IdScanScreenState();
}

class _IdScanScreenState extends State<IdScanScreen> {
  final _settings = SettingsService();
  final _downloadsExport = DownloadsExportService();
  Uint8List? _front;
  Uint8List? _back;
  bool _cropEnabled = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _settings.getCropEnabledDefault().then((value) {
      if (mounted) setState(() => _cropEnabled = value);
    });
  }

  Future<void> _capture({required bool front}) async {
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
    setState(() {
      if (front) {
        _front = processed;
      } else {
        _back = processed;
      }
    });
  }

  Future<void> _save() async {
    final front = _front;
    final back = _back;
    if (front == null || back == null || _saving) return;
    final title = await _askTitle();
    if (title == null) return;

    setState(() => _saving = true);
    try {
      final pdfBytes = await PdfService.buildIdCardPdf(front, back);
      final thumbnail = await PdfToolsService.rasterPages(pdfBytes, pages: [0], dpi: 120);
      final doc = await widget.store.createDocument(
        title: title,
        pageJpegBytes: thumbnail,
        pdfBytes: pdfBytes,
      );
      String? location;
      try {
        location = await _downloadsExport.export(pdfBytes, '$title.pdf');
      } catch (_) {
        // Document is already safely stored in the library; the Downloads
        // export is a convenience copy, so a failure here shouldn't block.
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
    final controller = TextEditingController(text: 'Ausweis');
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
              Navigator.pop(context, text.isEmpty ? 'Ausweis' : text);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  Widget _side({required String label, required bool front}) {
    final bytes = front ? _front : _back;
    return Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 1.586, // ISO/IEC 7810 ID-1 card ratio
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes == null
                  ? InkWell(
                      onTap: () => _capture(front: front),
                      child: const Center(child: Icon(Icons.add_a_photo_outlined, size: 32)),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(bytes, fit: BoxFit.cover),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: IconButton.filledTonal(
                            iconSize: 18,
                            icon: const Icon(Icons.refresh),
                            onPressed: () => _capture(front: front),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _front != null && _back != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Ausweis scannen')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vorder- und Rückseite werden zusammen auf eine PDF-Seite gesetzt.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _side(label: 'Vorderseite', front: true),
                const SizedBox(width: 16),
                _side(label: 'Rückseite', front: false),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: !ready || _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save),
            label: Text(_saving ? 'Speichere…' : 'Speichern'),
          ),
        ),
      ),
    );
  }
}
