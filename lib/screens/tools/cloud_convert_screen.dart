import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/downloads_export_service.dart';
import '../../services/google_drive_convert_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../widgets/delete_originals_switch.dart';

/// Generic "pick a file -> convert via Google Drive -> save" screen, shared
/// by every cloud-based conversion tool so the flow and error handling stay
/// consistent.
class CloudConvertScreen extends StatefulWidget {
  final String title;
  final String pickButtonLabel;
  final IconData pickIcon;
  final String convertButtonLabel;
  final IconData convertIcon;
  final XTypeGroup typeGroup;
  final String sourceExtension;
  final String outputExtension;
  final Future<Uint8List> Function(
    GoogleDriveConvertService drive,
    Uint8List bytes,
    String fileName,
  ) convert;

  const CloudConvertScreen({
    super.key,
    required this.title,
    required this.pickButtonLabel,
    required this.pickIcon,
    required this.convertButtonLabel,
    required this.convertIcon,
    required this.typeGroup,
    required this.sourceExtension,
    required this.outputExtension,
    required this.convert,
  });

  @override
  State<CloudConvertScreen> createState() => _CloudConvertScreenState();
}

class _CloudConvertScreenState extends State<CloudConvertScreen> {
  final _drive = GoogleDriveConvertService();
  final _downloadsExport = DownloadsExportService();
  String? _fileName;
  String? _sourcePath;
  Uint8List? _sourceBytes;
  bool _deleteOriginal = false;
  bool _busy = false;

  Future<void> _pickFile() async {
    final file = await openFile(acceptedTypeGroups: [widget.typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = p.basenameWithoutExtension(file.name);
      _sourcePath = file.path;
      _sourceBytes = bytes;
    });
  }

  Future<void> _convert() async {
    final bytes = _sourceBytes;
    final name = _fileName;
    if (bytes == null || name == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.convert(
        _drive,
        bytes,
        '$name.${widget.sourceExtension}',
      );
      final location = await _downloadsExport.export(
        result,
        '$name.${widget.outputExtension}',
      );
      var message = 'Gespeichert unter $location';
      if (_deleteOriginal) {
        final notDeleted = await OriginalFilesCleanupService.deleteAll([_sourcePath]);
        if (notDeleted.isNotEmpty) {
          message += ' · Original konnte nicht gelöscht werden';
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop();
    } on GoogleDriveNotConfiguredException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Umwandlung fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.cloud_outlined),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Läuft über dein Google-Konto (kostenlos) und braucht '
                        'Internet. Beim ersten Mal wirst du zum Anmelden aufgefordert.',
                        style: TextStyle(fontSize: 13),
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
                icon: Icon(widget.pickIcon),
                label: Text(widget.pickButtonLabel),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(_fileName!),
                trailing: TextButton(
                  onPressed: _busy ? null : _pickFile,
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
                onPressed: _busy ? null : _convert,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(widget.convertIcon),
                label: Text(_busy ? 'Wandle um…' : widget.convertButtonLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
