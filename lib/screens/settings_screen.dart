import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../services/backup_service.dart';
import '../services/document_store.dart';
import '../services/downloads_export_service.dart';
import '../services/file_picker_service.dart';
import '../services/google_desktop_auth.dart';
import '../services/settings_service.dart';
import '../services/windows_desktop_service.dart';
import '../utils/formatting.dart';
import '../utils/layout.dart';
import '../widgets/settings_widgets.dart';

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
    if (AppPlatform.isWindows) await GoogleDesktopAuth.load();
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
    unawaited(showDialog<void>(
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
    ));
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
      extensions: const ['zip'],
      mimeTypes: const ['application/zip', 'application/x-zip-compressed'],
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

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openExportFolder() async {
    final dir = await DownloadsExportService().desktopTargetDir();
    await launchUrl(Uri.directory(dir.path));
  }

  Future<void> _saveGoogleSettings() async {
    if (AppPlatform.isWindows) {
      AppPrefs.setString(
        SettingsService.googleDesktopClientIdKey,
        _desktopClientIdController.text.trim(),
      );
      AppPrefs.setString(
        SettingsService.googleDesktopClientSecretKey,
        _desktopSecretController.text.trim(),
      );
      setState(() {});
    } else {
      await _settings.setGoogleWebClientId(_clientIdController.text);
    }
    if (mounted) _snack(tr('Gespeichert', 'Saved'));
  }

  Future<void> _googleSignOut() async {
    await GoogleDesktopAuth.signOut();
    if (!mounted) return;
    setState(() {});
    _snack(tr('Von Google abgemeldet', 'Signed out of Google'));
  }

  Widget _appearanceSection() {
    return SettingsSection(
      title: tr('Darstellung', 'Appearance'),
      children: [
        SettingsTile(
          icon: Icons.palette_outlined,
          title: tr('Farbschema', 'Theme'),
          subtitle: tr('Hell, dunkel oder wie im System eingestellt', 'Light, dark or as set in the system'),
          trailing: ValueListenableBuilder<ThemeMode>(
            valueListenable: SettingsService.themeMode,
            builder: (context, mode, _) => SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(tr('System', 'System'))),
                ButtonSegment(value: ThemeMode.light, label: Text(tr('Hell', 'Light'))),
                ButtonSegment(value: ThemeMode.dark, label: Text(tr('Dunkel', 'Dark'))),
              ],
              selected: {mode},
              onSelectionChanged: (v) => _settings.setThemeMode(v.first),
            ),
          ),
        ),
        SettingsTile(
          icon: Icons.translate,
          // Always bilingual, so it can be found in either language.
          title: 'Sprache / Language',
          subtitle: AppPlatform.isWindows
              ? tr('Automatisch: wie bei der Installation gewählt', 'Automatic: as chosen during installation')
              : tr('Automatisch: wie die Gerätesprache', 'Automatic: same as the device language'),
          trailing: SegmentedButton<AppLanguage>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: AppLanguage.automatic, label: Text(tr('Automatisch', 'Automatic'))),
              const ButtonSegment(value: AppLanguage.de, label: Text('Deutsch')),
              const ButtonSegment(value: AppLanguage.en, label: Text('English')),
            ],
            selected: {L10n.choice},
            onSelectionChanged: (v) => L10n.setChoice(v.first),
          ),
        ),
      ],
    );
  }

  Widget _windowsSection() {
    return SettingsSection(
      title: 'Windows',
      children: [
        SettingsTile(
          icon: Icons.power_settings_new,
          title: tr('Mit Windows starten', 'Start with Windows'),
          subtitle: tr('KK-PDF-Tool startet automatisch beim Anmelden', 'KK-PDF-Tool starts automatically when you sign in'),
          trailing: Switch(
            value: _autostart,
            onChanged: (value) async {
              setState(() => _autostart = value);
              await WindowsDesktopService.instance.setAutostart(value, minimized: _startMinimized);
            },
          ),
        ),
        SettingsTile(
          icon: Icons.notifications_none,
          title: tr('Dabei nur im Infobereich starten', 'Start only in the notification area'),
          subtitle: tr(
            'Startet unsichtbar mit Symbol unten rechts neben der Uhr - Klick darauf öffnet die App',
            'Starts hidden with an icon at the bottom right next to the clock - click it to open the app',
          ),
          trailing: Switch(
            value: _startMinimized,
            onChanged: !_autostart
                ? null
                : (value) async {
                    setState(() => _startMinimized = value);
                    await WindowsDesktopService.instance.setAutostart(true, minimized: value);
                  },
          ),
        ),
      ],
    );
  }

  Widget _scanningSection() {
    return SettingsSection(
      title: tr('Scannen', 'Scanning'),
      children: [
        SettingsTile(
          icon: Icons.crop,
          title: tr('Zuschnitt standardmäßig aktiv', 'Crop on by default'),
          subtitle: tr(
            'Bei jedem neuen Scan lässt sich das trotzdem einzeln umschalten.',
            'You can still switch it for each new scan.',
          ),
          trailing: Switch(
            value: _cropEnabled,
            onChanged: (value) async {
              setState(() => _cropEnabled = value);
              await _settings.setCropEnabledDefault(value);
            },
          ),
        ),
        if (AppPlatform.isAndroid)
          SettingsTile(
            icon: Icons.manage_search,
            title: tr('Durchsuchbare PDFs', 'Searchable PDFs'),
            subtitle: tr(
              'Text wird beim Speichern offline erkannt und unsichtbar in die '
                  'PDF gelegt - so kannst du darin suchen und Text kopieren.',
              'Text is recognized offline when saving and laid invisibly into the '
                  'PDF - so you can search it and copy text.',
            ),
            trailing: Switch(
              value: _searchablePdf,
              onChanged: (value) async {
                setState(() => _searchablePdf = value);
                await _settings.setSearchablePdfEnabled(value);
              },
            ),
          ),
      ],
    );
  }

  Widget _storageSection() {
    return SettingsSection(
      title: tr('Speicher & Sicherung', 'Storage & backup'),
      children: [
        SettingsTile(
          icon: Icons.folder_outlined,
          title: tr('Speicherort', 'Storage location'),
          subtitle: AppPlatform.isAndroid
              ? tr('Fertige PDFs landen zusätzlich in Downloads/KK-PDF-Tool',
                  'Finished PDFs are also saved to Downloads/KK-PDF-Tool')
              : tr('Fertige Dateien landen zusätzlich in Downloads\\KK-PDF-Tool',
                  'Finished files are also saved to Downloads\\KK-PDF-Tool'),
          trailing: AppPlatform.isWindows
              ? OutlinedButton.icon(
                  onPressed: _openExportFolder,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(tr('Ordner öffnen', 'Open folder')),
                )
              : null,
        ),
        SettingsTile(
          icon: Icons.backup_outlined,
          title: tr('Sicherung erstellen', 'Create backup'),
          subtitle: tr(
            'Alle Scans, Ordner und Unterschriften als eine ZIP-Datei in Downloads/KK-PDF-Tool',
            'All scans, folders and signatures as one ZIP file in Downloads/KK-PDF-Tool',
          ),
          trailing: OutlinedButton(
            onPressed: _createBackup,
            child: Text(tr('Erstellen', 'Create')),
          ),
        ),
        SettingsTile(
          icon: Icons.settings_backup_restore,
          title: tr('Sicherung wiederherstellen', 'Restore backup'),
          subtitle: tr(
            'Fügt die Dokumente einer Sicherung hinzu - vorhandene bleiben unverändert',
            'Adds the documents of a backup - existing ones stay unchanged',
          ),
          trailing: OutlinedButton(
            onPressed: _restoreBackup,
            child: Text(tr('Wiederherstellen…', 'Restore…')),
          ),
        ),
      ],
    );
  }

  Widget _googleSection() {
    final windows = AppPlatform.isWindows;
    final configured = (AppPrefs.getString(SettingsService.googleDesktopClientIdKey) ?? '').isNotEmpty &&
        (AppPrefs.getString(SettingsService.googleDesktopClientSecretKey) ?? '').isNotEmpty;
    final saveButton = Align(
      alignment: Alignment.centerRight,
      child: FilledButton(
        onPressed: _saveGoogleSettings,
        child: Text(tr('Speichern', 'Save')),
      ),
    );
    return SettingsSection(
      title: tr('Google-Verbindung', 'Google connection'),
      children: [
        SettingsTile(
          icon: Icons.cloud_outlined,
          title: tr('Online-Werkzeuge', 'Online tools'),
          subtitle: windows
              ? tr(
                  'Die Werkzeuge mit Wolken-Symbol laufen über dein eigenes Google-Konto '
                      '(kostenlos, braucht Internet). Unter Windows braucht die App dafür einmalig '
                      'eine Client-ID vom Typ "Desktop-App" aus deinem Google-Cloud-Projekt '
                      '(siehe README). Beim ersten Umwandeln öffnet sich der Browser zum Anmelden.',
                  'The tools with a cloud icon run through your own Google account '
                      '(free, needs internet). On Windows the app needs a client ID of type '
                      '"Desktop app" from your Google Cloud project once (see README). '
                      'The first conversion opens the browser to sign in.',
                )
              : tr(
                  'Die Werkzeuge mit Wolken-Symbol laufen über dein eigenes Google-Konto '
                      '(kostenlos, braucht Internet). Beim ersten Mal wirst du zum Anmelden aufgefordert.',
                  'The tools with a cloud icon run through your own Google account '
                      '(free, needs internet). The first time you will be asked to sign in.',
                ),
          trailing: windows
              ? StatusChip(
                  positive: GoogleDesktopAuth.isSignedIn,
                  label: !configured
                      ? tr('Nicht eingerichtet', 'Not set up')
                      : GoogleDesktopAuth.isSignedIn
                          ? tr('Angemeldet', 'Signed in')
                          : tr('Nicht angemeldet', 'Not signed in'),
                )
              : null,
        ),
        if (windows)
          SettingsTile(
            icon: Icons.key_outlined,
            title: tr('Desktop-App-Zugang', 'Desktop app credentials'),
            subtitle: tr(
              'Aus Google Cloud: APIs & Dienste → Anmeldedaten → OAuth-Client "Desktop-App"',
              'From Google Cloud: APIs & Services → Credentials → OAuth client "Desktop app"',
            ),
            below: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _desktopClientIdController,
                  decoration: InputDecoration(
                    labelText: tr('Client-ID', 'Client ID'),
                    hintText: 'xxxxxxxxxxxx.apps.googleusercontent.com',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _desktopSecretController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: tr('Client-Secret', 'Client secret')),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (GoogleDesktopAuth.isSignedIn) ...[
                      TextButton(onPressed: _googleSignOut, child: Text(tr('Abmelden', 'Sign out'))),
                      const SizedBox(width: 8),
                    ],
                    FilledButton(
                      onPressed: _saveGoogleSettings,
                      child: Text(tr('Speichern', 'Save')),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          Theme(
            // No divider lines from the expansion tile inside the card.
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const Icon(Icons.tune),
              title: Text(tr('Eigene Client-ID (erweitert)', 'Custom client ID (advanced)')),
              subtitle: Text(tr(
                'Nur nötig für ein eigenes Google-Cloud-Projekt (siehe README)',
                'Only needed for your own Google Cloud project (see README)',
              )),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                TextField(
                  controller: _clientIdController,
                  decoration: InputDecoration(
                    labelText: tr('Google Web-Client-ID', 'Google web client ID'),
                    hintText: 'xxxxxxxxxxxx.apps.googleusercontent.com',
                  ),
                ),
                const SizedBox(height: 12),
                saveButton,
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Einstellungen', 'Settings'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: centeredPadding(constraints.maxWidth, maxWidth: 760, vertical: 8)
                    .copyWith(bottom: 32),
                children: [
                  _appearanceSection(),
                  if (AppPlatform.isWindows) _windowsSection(),
                  _scanningSection(),
                  _storageSection(),
                  _googleSection(),
                ],
              ),
            ),
    );
  }
}
