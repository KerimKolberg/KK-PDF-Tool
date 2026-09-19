import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/pdf_tools_service.dart';

/// Stamps a diagonal text watermark across every page of a PDF.
class WatermarkPdfScreen extends StatefulWidget {
  const WatermarkPdfScreen({super.key});

  @override
  State<WatermarkPdfScreen> createState() => _WatermarkPdfScreenState();
}

class _WatermarkPdfScreenState extends State<WatermarkPdfScreen> {
  final _downloadsExport = DownloadsExportService();
  final _textController = TextEditingController(text: 'ENTWURF');
  String? _fileName;
  Uint8List? _pdfBytes;
  double _opacity = 0.35;
  bool _busy = false;

  Future<void> _pickPdf() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _pdfBytes = bytes;
    });
  }

  Future<void> _apply() async {
    final bytes = _pdfBytes;
    final name = _fileName;
    final text = _textController.text.trim();
    if (bytes == null || name == null || text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await PdfToolsService.addWatermark(
        bytes,
        text: text,
        opacity: _opacity,
      );
      final location =
          await _downloadsExport.export(result, '${name}_wasserzeichen.pdf');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gespeichert unter $location')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehlgeschlagen: $e')),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wasserzeichen')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                  onPressed: _busy ? null : _pickPdf,
                  child: const Text('Ändern'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text('Deckkraft: ${(_opacity * 100).round()}%'),
              Slider(
                value: _opacity,
                min: 0.1,
                max: 0.7,
                onChanged: _busy ? null : (v) => setState(() => _opacity = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _apply,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.water_drop_outlined),
                label: Text(_busy ? 'Wende an…' : 'Wasserzeichen einfügen'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
