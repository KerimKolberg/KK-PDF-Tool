import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n.dart';
import '../../services/downloads_export_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/google_drive_convert_service.dart';
import '../../services/original_files_cleanup_service.dart';
import '../../widgets/busy_icon.dart';
import '../../widgets/delete_originals_switch.dart';
import '../../widgets/tool_drop_zone.dart';
import '../../widgets/tool_layout.dart';
import '../../widgets/tool_result.dart';

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
    final file = await FilePickers.openOne('cloud_${widget.sourceExtension}', [widget.typeGroup]);
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
      var message = tr('Gespeichert unter $location', 'Saved to $location');
      if (_deleteOriginal) {
        message += await OriginalFilesCleanupService.deleteAndDescribe([_sourcePath]);
      }
      if (!mounted) return;
      finishTool(context, widget, message);
    } on GoogleDriveNotConfiguredException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Umwandlung fehlgeschlagen: $e', 'Conversion failed: $e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolDropZone(
      onDrop: _pickFile,
      child: ToolScaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tr('Läuft über dein Google-Konto (kostenlos) und braucht '
                          'Internet. Beim ersten Mal wirst du zum Anmelden aufgefordert.',
                          'Runs through your Google account (free) and needs '
                          'internet. The first time you will be asked to sign in.'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_fileName == null)
                FilePickPanel(
                  onPressed: _pickFile,
                  icon: Icon(widget.pickIcon),
                  label: Text(widget.pickButtonLabel),
                )
              else ...[
                SelectedFileTile(
                  name: _fileName!,
                  onChange: _busy ? null : _pickFile,
                ),
                DeleteOriginalsSwitch(
                  label: tr('Originaldatei danach löschen', 'Delete original file afterwards'),
                  value: _deleteOriginal,
                  onChanged: (v) => setState(() => _deleteOriginal = v),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _convert,
                  icon: BusyIcon(busy: _busy, child: Icon(widget.convertIcon)),
                  label: Text(_busy ? tr('Wandle um…', 'Converting…') : widget.convertButtonLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
