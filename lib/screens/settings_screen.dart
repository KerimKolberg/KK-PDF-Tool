import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';
import '../services/document_store.dart';
import '../services/downloads_export_service.dart';
import '../services/file_picker_service.dart';
import '../services/settings_service.dart';
import '../services/windows_desktop_service.dart';
import '../utils/formatting.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final _clientIdController = TextEditingController();
  bool _cropEnabled = true;
  bool _searchablePdf = true;
  bool _autostart = false;
  bool _startMinimized = WindowsDesktopService.instance.startMinimized;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cropEnabled = await _settings.getCropEnabledDefault();
    final searchablePdf = await _settings.getSearchablePdfEnabled();
    final clientId = await _settings.getGoogleWebClientId();
    final autostart = WindowsDesktopService.supported
        ? await WindowsDesktopService.instance.isAutostartEnabled()
        : false;
    if (!mounted) return;
    setState(() {
      _cropEnabled = cropEnabled;
      _searchablePdf = searchablePdf;
      _autostart = autostart;
      _clientIdController.text = clientId ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    super.dispose();
  }

  /// Runs [task] behind a modal progress dialog (it reports 0..1 progress).
  Future<void> _withProgress(
    String title,
    Future<void> Function(void Function(double) onProgress) task,
  ) async {
    final progress = ValueNotifier<double?>(null);
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, value, _) => LinearProgressIndicator(value: value),
          ),
        ),
      ),
    );
    try {
      await task((v) => progress.value = v);
    } finally {
      navigator.pop();
      progress.dispose();
    }
  }

  Future<void> _createBackup() async {
    BackupSummary? summary;
    String? location;
    Object? error;
    await _withProgress('Sicherung wird erstellt…', (onProgress) async {
      try {
        summary = await BackupService(DocumentStore()).create(onProgress: onProgress);
        location = await DownloadsExportService().exportFile(
          summary!.file,
          p.basename(summary!.file.path),
          mimeType: 'application/zip',
        );
      } catch (e) {
        error = e;
      }
    });
    if (!mounted) return;
    final done = summary;
    if (done == null || error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sicherung fehlgeschlagen: $error')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sicherung erstellt'),
        content: Text(
          '${done.documents} ${done.documents == 1 ? 'Dokument' : 'Dokumente'} '
          '(${formatFileSize(done.bytes)})\n\nGespeichert unter:\n$location\n\n'
          'Tipp: Lege die Datei zusätzlich woanders ab (z. B. Google Drive), '
          'damit sie auch bei Verlust des Geräts erhalten bleibt.',
        ),
        actions: [
          TextButton.icon(
            onPressed: () => SharePlus.instance.share(
              ShareParams(files: [XFile(done.file.path, mimeType: 'application/zip')]),
            ),
            icon: const Icon(Icons.ios_share),
            label: const Text('Teilen…'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _restoreBackup() async {
    const typeGroup = XTypeGroup(
      label: 'Sicherung (ZIP)',
      extensions: ['zip'],
      mimeTypes: ['application/zip', 'application/x-zip-compressed'],
    );
    final file = await FilePickers.openOne('backup', [typeGroup]);
    if (file == null || !mounted) return;
    RestoreSummary? summary;
    Object? error;
    await _withProgress('Sicherung wird wiederhergestellt…', (_) async {
      try {
        summary = await BackupService(DocumentStore()).restore(File(file.path));
      } catch (e) {
        error = e;
      }
    });
    if (!mounted) return;
    final done = summary;
    if (done == null) {
      final message = error is FormatException
          ? (error as FormatException).message
          : 'Wiederherstellen fehlgeschlagen: $error';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wiederhergestellt'),
        content: Text([
          '${done.added} ${done.added == 1 ? 'Dokument' : 'Dokumente'} hinzugefügt',
          if (done.skipped > 0) '${done.skipped} waren schon vorhanden (unverändert)',
          if (done.folders > 0) '${done.folders} Ordner hinzugefügt',
          if (done.signatures > 0)
            '${done.signatures} ${done.signatures == 1 ? 'Unterschrift' : 'Unterschriften'} hinzugefügt',
        ].join('\n')),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Darstellung', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: SettingsService.themeMode,
                        builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_outlined),
                              label: Text('System'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('Hell'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('Dunkel'),
                            ),
                          ],
                          selected: {mode},
                          onSelectionChanged: (v) => _settings.setThemeMode(v.first),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (WindowsDesktopService.supported) ...[
                  SwitchListTile(
                    secondary: const Icon(Icons.power_settings_new),
                    title: const Text('Mit Windows starten'),
                    subtitle: const Text('KK-PDF-Tool startet automatisch beim Anmelden'),
                    value: _autostart,
                    onChanged: (value) async {
                      setState(() => _autostart = value);
                      await WindowsDesktopService.instance.setAutostart(value, minimized: _startMinimized);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.minimize),
                    title: const Text('Dabei nur im Infobereich starten'),
                    subtitle: const Text(
                      'Startet unsichtbar mit Symbol unten rechts neben der Uhr - Klick darauf öffnet die App',
                    ),
                    value: _startMinimized,
                    onChanged: !_autostart
                        ? null
                        : (value) async {
                            setState(() => _startMinimized = value);
                            await WindowsDesktopService.instance.setAutostart(true, minimized: value);
                          },
                  ),
                  const Divider(height: 1),
                ],
                if (Platform.isAndroid) ...[
                  SwitchListTile(
                    title: const Text('Durchsuchbare PDFs'),
                    subtitle: const Text(
                      'Text wird beim Speichern offline erkannt und unsichtbar in die '
                      'PDF gelegt - so kannst du darin suchen und Text kopieren.',
                    ),
                    value: _searchablePdf,
                    onChanged: (value) async {
                      setState(() => _searchablePdf = value);
                      await _settings.setSearchablePdfEnabled(value);
                    },
                  ),
                  const Divider(height: 1),
                ],
                SwitchListTile(
                  title: const Text('Zuschnitt standardmäßig aktiv'),
                  subtitle: const Text(
                    'Bei jedem neuen Scan lässt sich das trotzdem einzeln umschalten.',
                  ),
                  value: _cropEnabled,
                  onChanged: (value) async {
                    setState(() => _cropEnabled = value);
                    await _settings.setCropEnabledDefault(value);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Speicherort'),
                  subtitle: Text(
                    Platform.isAndroid
                        ? 'Fertige PDFs landen zusätzlich in Downloads/DocScanner'
                        : 'Fertige PDFs landen zusätzlich im Downloads-Ordner, Unterordner "DocScanner"',
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text('Datensicherung', style: Theme.of(context).textTheme.titleSmall),
                ),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Sicherung erstellen'),
                  subtitle: const Text(
                    'Alle Scans, Ordner und Unterschriften als eine ZIP-Datei in Downloads/DocScanner',
                  ),
                  onTap: _createBackup,
                ),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore),
                  title: const Text('Sicherung wiederherstellen'),
                  subtitle: const Text(
                    'Fügt die Dokumente einer Sicherung hinzu - vorhandene bleiben unverändert',
                  ),
                  onTap: _restoreBackup,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Google-Verbindung (für Online-Umwandlungen und Texterkennung unter Windows)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Die Werkzeuge mit Wolken-Symbol laufen über dein eigenes Google-Konto '
                        '(kostenlos, braucht Internet). Die Client-ID ist bereits fest '
                        'in der App hinterlegt — nur ändern, falls du ein eigenes '
                        'Google-Cloud-Projekt verwenden möchtest (siehe README).',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _clientIdController,
                        decoration: const InputDecoration(
                          labelText: 'Google Web-Client-ID',
                          hintText: 'xxxxxxxxxxxx.apps.googleusercontent.com',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () async {
                            await _settings.setGoogleWebClientId(
                              _clientIdController.text,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Gespeichert')),
                            );
                          },
                          child: const Text('Speichern'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
