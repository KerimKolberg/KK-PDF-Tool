import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';
import '../services/document_store.dart';
import '../services/downloads_export_service.dart';
import '../services/file_picker_service.dart';
import '../services/google_desktop_auth.dart';
import '../services/settings_service.dart';
import '../services/windows_desktop_service.dart';
import '../utils/formatting.dart';
import '../l10n.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final _clientIdController = TextEditingController();
  final _desktopClientIdController = TextEditingController(
    text: AppPrefs.getString(SettingsService.googleDesktopClientIdKey),
  );
  final _desktopSecretController = TextEditingController(
    text: AppPrefs.getString(SettingsService.googleDesktopClientSecretKey),
  );
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
    _desktopClientIdController.dispose();
    _desktopSecretController.dispose();
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
    await _withProgress(tr('Sicherung wird erstellt…', 'Creating backup…'), (onProgress) async {
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
        SnackBar(content: Text(tr('Sicherung fehlgeschlagen: $error', 'Backup failed: $error'))),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Sicherung erstellt', 'Backup created')),
        content: Text(
          tr('${done.documents} ${done.documents == 1 ? 'Dokument' : 'Dokumente'} '
          '(${formatFileSize(done.bytes)})\n\nGespeichert unter:\n$location\n\n'
          'Tipp: Lege die Datei zusätzlich woanders ab (z. B. Google Drive), '
          'damit sie auch bei Verlust des Geräts erhalten bleibt.',
          '${done.documents} ${done.documents == 1 ? 'document' : 'documents'} '
          '(${formatFileSize(done.bytes)})\n\nSaved to:\n$location\n\n'
          'Tip: also keep a copy somewhere else (e.g. Google Drive), '
          'so it survives losing the device.'),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => SharePlus.instance.share(
              ShareParams(files: [XFile(done.file.path, mimeType: 'application/zip')]),
            ),
            icon: const Icon(Icons.ios_share),
            label: Text(tr('Teilen…', 'Share…')),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _restoreBackup() async {
    final typeGroup = XTypeGroup(
      label: tr('Sicherung (ZIP)', 'Backup (ZIP)'),
      extensions: ['zip'],
      mimeTypes: ['application/zip', 'application/x-zip-compressed'],
    );
    final file = await FilePickers.openOne('backup', [typeGroup]);
    if (file == null || !mounted) return;
    RestoreSummary? summary;
    Object? error;
    await _withProgress(tr('Sicherung wird wiederhergestellt…', 'Restoring backup…'), (_) async {
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
          : tr('Wiederherstellen fehlgeschlagen: $error', 'Restore failed: $error');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Wiederhergestellt', 'Restored')),
        content: Text([
          tr('${done.added} ${done.added == 1 ? 'Dokument' : 'Dokumente'} hinzugefügt', '${done.added} ${done.added == 1 ? 'document' : 'documents'} added'),
          if (done.skipped > 0) tr('${done.skipped} waren schon vorhanden (unverändert)', '${done.skipped} already existed (unchanged)'),
          if (done.folders > 0) tr('${done.folders} Ordner hinzugefügt', '${done.folders} folder(s) added'),
          if (done.signatures > 0)
            tr('${done.signatures} ${done.signatures == 1 ? 'Unterschrift' : 'Unterschriften'} hinzugefügt', '${done.signatures} ${done.signatures == 1 ? 'signature' : 'signatures'} added'),
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
      appBar: AppBar(title: Text(tr('Einstellungen', 'Settings'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Darstellung', 'Appearance'), style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: SettingsService.themeMode,
                        builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                          segments: [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_outlined),
                              label: Text('System'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text(tr('Hell', 'Light')),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text(tr('Dunkel', 'Dark')),
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
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Always bilingual, so it can be found in either language.
                      Text('Sprache / Language', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<AppLanguage>(
                        segments: [
                          ButtonSegment(
                            value: AppLanguage.automatic,
                            icon: const Icon(Icons.language),
                            label: Text(tr('Automatisch', 'Automatic')),
                          ),
                          const ButtonSegment(value: AppLanguage.de, label: Text('Deutsch')),
                          const ButtonSegment(value: AppLanguage.en, label: Text('English')),
                        ],
                        selected: {L10n.choice},
                        onSelectionChanged: (v) => L10n.setChoice(v.first),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Platform.isWindows
                            ? tr('Automatisch: wie bei der Installation gewählt',
                                'Automatic: as chosen during installation')
                            : tr('Automatisch: wie die Gerätesprache',
                                'Automatic: same as the device language'),
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (WindowsDesktopService.supported) ...[
                  SwitchListTile(
                    secondary: const Icon(Icons.power_settings_new),
                    title: Text(tr('Mit Windows starten', 'Start with Windows')),
                    subtitle: Text(tr('KK-PDF-Tool startet automatisch beim Anmelden', 'KK-PDF-Tool starts automatically when you sign in')),
                    value: _autostart,
                    onChanged: (value) async {
                      setState(() => _autostart = value);
                      await WindowsDesktopService.instance.setAutostart(value, minimized: _startMinimized);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.minimize),
                    title: Text(tr('Dabei nur im Infobereich starten', 'Start only in the notification area')),
                    subtitle: Text(
                      tr('Startet unsichtbar mit Symbol unten rechts neben der Uhr - Klick darauf öffnet die App', 'Starts hidden with an icon at the bottom right next to the clock - click it to open the app'),
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
                    title: Text(tr('Durchsuchbare PDFs', 'Searchable PDFs')),
                    subtitle: Text(
                      tr('Text wird beim Speichern offline erkannt und unsichtbar in die '
                      'PDF gelegt - so kannst du darin suchen und Text kopieren.',
                      'Text is recognized offline when saving and laid invisibly into the '
                      'PDF - so you can search it and copy text.'),
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
                  title: Text(tr('Zuschnitt standardmäßig aktiv', 'Crop on by default')),
                  subtitle: Text(
                    tr('Bei jedem neuen Scan lässt sich das trotzdem einzeln umschalten.', 'You can still switch it for each new scan.'),
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
                  title: Text(tr('Speicherort', 'Storage location')),
                  subtitle: Text(
                    Platform.isAndroid
                        ? tr('Fertige PDFs landen zusätzlich in Downloads/KK-PDF-Tool', 'Finished PDFs are also saved to Downloads/KK-PDF-Tool')
                        : tr('Fertige PDFs landen zusätzlich im Downloads-Ordner, Unterordner "KK-PDF-Tool"', 'Finished PDFs are also saved to the Downloads folder, subfolder "KK-PDF-Tool"'),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(tr('Datensicherung', 'Backup'), style: Theme.of(context).textTheme.titleSmall),
                ),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: Text(tr('Sicherung erstellen', 'Create backup')),
                  subtitle: Text(
                    tr('Alle Scans, Ordner und Unterschriften als eine ZIP-Datei in Downloads/KK-PDF-Tool', 'All scans, folders and signatures as one ZIP file in Downloads/KK-PDF-Tool'),
                  ),
                  onTap: _createBackup,
                ),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore),
                  title: Text(tr('Sicherung wiederherstellen', 'Restore backup')),
                  subtitle: Text(
                    tr('Fügt die Dokumente einer Sicherung hinzu - vorhandene bleiben unverändert', 'Adds the documents of a backup - existing ones stay unchanged'),
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
                        tr('Google-Verbindung (für Online-Umwandlungen und Texterkennung unter Windows)', 'Google connection (for online conversions and text recognition on Windows)'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Platform.isWindows
                            ? tr('Die Werkzeuge mit Wolken-Symbol laufen über dein eigenes Google-Konto '
                                '(kostenlos, braucht Internet). Unter Windows braucht die App dafür '
                                'einmalig eine eigene Client-ID vom Typ "Desktop-App" aus deinem '
                                'Google-Cloud-Projekt (siehe README). Beim ersten Umwandeln öffnet '
                                'sich dann der Browser zum Anmelden.',
                                'The tools with a cloud icon run through your own Google account '
                                '(free, needs internet). On Windows the app needs its own '
                                'client ID of type "Desktop app" from your Google Cloud '
                                'project once (see README). The first conversion then opens '
                                'the browser to sign in.')
                            : tr('Die Werkzeuge mit Wolken-Symbol laufen über dein eigenes Google-Konto '
                                '(kostenlos, braucht Internet). Die Client-ID ist bereits fest '
                                'in der App hinterlegt — nur ändern, falls du ein eigenes '
                                'Google-Cloud-Projekt verwenden möchtest (siehe README).',
                                'The tools with a cloud icon run through your own Google account '
                                '(free, needs internet). The client ID is already built '
                                'into the app - only change it if you want to use your own '
                                'Google Cloud project (see README).'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (Platform.isWindows) ...[
                        TextField(
                          controller: _desktopClientIdController,
                          decoration: InputDecoration(
                            labelText: tr('Client-ID (Desktop-App)', 'Client ID (desktop app)'),
                            hintText: 'xxxxxxxxxxxx.apps.googleusercontent.com',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _desktopSecretController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: tr('Client-Secret (Desktop-App)', 'Client secret (desktop app)'),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ] else
                        TextField(
                          controller: _clientIdController,
                          decoration: InputDecoration(
                            labelText: tr('Google Web-Client-ID', 'Google web client ID'),
                            hintText: 'xxxxxxxxxxxx.apps.googleusercontent.com',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (Platform.isWindows && GoogleDesktopAuth.isSignedIn)
                            TextButton(
                              onPressed: () async {
                                await GoogleDesktopAuth.signOut();
                                if (!context.mounted) return;
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(tr('Von Google abgemeldet', 'Signed out of Google'))),
                                );
                              },
                              child: Text(tr('Abmelden', 'Sign out')),
                            ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              if (Platform.isWindows) {
                                AppPrefs.setString(
                                  SettingsService.googleDesktopClientIdKey,
                                  _desktopClientIdController.text.trim(),
                                );
                                AppPrefs.setString(
                                  SettingsService.googleDesktopClientSecretKey,
                                  _desktopSecretController.text.trim(),
                                );
                              } else {
                                await _settings.setGoogleWebClientId(_clientIdController.text);
                              }
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(tr('Gespeichert', 'Saved'))),
                              );
                            },
                            child: Text(tr('Speichern', 'Save')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
