import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/google_drive_convert_service.dart';
import '../../services/ocr_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/delete_originals_switch.dart';

const _mimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};

/// Extracts text from a photo - offline via ML Kit on Android, or via Google
/// Drive's OCR (the same engine used for PDF -> Word) - as a plain string
/// the user can copy or save as .txt.
class TextFromImageScreen extends StatefulWidget {
  const TextFromImageScreen({super.key});

  @override
  State<TextFromImageScreen> createState() => _TextFromImageScreenState();
}

class _TextFromImageScreenState extends State<TextFromImageScreen> {
  final _drive = GoogleDriveConvertService();
  final _downloadsExport = DownloadsExportService();
  String? _fileName;
  String? _sourcePath;
  Uint8List? _sourceBytes;
  String? _extractedText;
  bool _deleteOriginal = false;

  /// Android can recognise text offline on the device; Windows always uses
  /// the Google (online) engine.
  bool _offline =
      OcrService.isOfflineAvailable && AppPrefs.getBool('ocr.offline', true);
  bool _busy = false;

  Future<void> _pickFile() async {
    const typeGroup = XTypeGroup(label: 'Bilder', extensions: ['jpg', 'jpeg', 'png', 'webp']);
    final file = await FilePickers.openOne('text_from_image', [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _sourcePath = file.path;
      _sourceBytes = bytes;
      _extractedText = null;
    });
  }

  Future<void> _extract() async {
    final bytes = _sourceBytes;
    final name = _fileName;
    if (bytes == null || name == null || _busy) return;
    final ext = p.extension(_sourcePath ?? '').replaceFirst('.', '').toLowerCase();
    setState(() => _busy = true);
    try {
      final String text;
      if (_offline) {
        final upright = await OcrService.normalizeOrientation(bytes);
        text = (await OcrService.recognize(upright)).text;
      } else {
        text = await _drive.imageToText(
          bytes,
          '$name.${ext.isEmpty ? 'jpg' : ext}',
          mimeType: _mimeByExtension[ext] ?? 'image/jpeg',
        );
      }
      if (_deleteOriginal) {
        await OriginalFilesCleanupService.deleteAll([_sourcePath]);
      }
      if (!mounted) return;
      setState(() {
        _extractedText = text;
        _busy = false;
      });
    } on GoogleDriveNotConfiguredException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Texterkennung fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _copy() async {
    final text = _extractedText;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('In die Zwischenablage kopiert')),
    );
  }

  Future<void> _saveAsTxt() async {
    final text = _extractedText;
    final name = _fileName;
    if (text == null || name == null) return;
    try {
      final location = await _downloadsExport.export(
        Uint8List.fromList(utf8.encode(text)),
        '$name.txt',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gespeichert unter $location')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Text aus Bild (OCR)')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (OcrService.isOfflineAvailable) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.phone_android),
                    label: Text('Offline'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.cloud_outlined),
                    label: Text('Google'),
                  ),
                ],
                selected: {_offline},
                onSelectionChanged: _busy
                    ? null
                    : (v) {
                        setState(() => _offline = v.first);
                        AppPrefs.setBool('ocr.offline', v.first);
                      },
              ),
              const SizedBox(height: 12),
            ],
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(_offline ? Icons.phone_android : Icons.cloud_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _offline
                            ? 'Läuft direkt auf dem Gerät - ohne Internet und ohne '
                                'Google-Konto. Für Handschrift ist "Google" oft genauer.'
                            : 'Läuft über dein Google-Konto (kostenlos) und braucht '
                                'Internet - gleiche Texterkennung wie bei PDF → Word.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_fileName == null)
              FilledButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Bild wählen'),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(_fileName!),
                trailing: TextButton(
                  onPressed: _busy ? null : _pickFile,
                  child: const Text('Ändern'),
                ),
              ),
              DeleteOriginalsSwitch(
                label: 'Originalbild danach löschen',
                value: _deleteOriginal,
                onChanged: (v) => setState(() => _deleteOriginal = v),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _extract,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.text_snippet_outlined),
                label: Text(_busy ? 'Erkenne Text…' : 'Text erkennen'),
              ),
              if (_extractedText != null) ...[
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _extractedText!.isEmpty ? '(kein Text erkannt)' : _extractedText!,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copy,
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Kopieren'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saveAsTxt,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Als .txt speichern'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
