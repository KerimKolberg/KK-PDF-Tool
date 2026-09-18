import 'dart:io';

import 'package:flutter/material.dart';

import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final _clientIdController = TextEditingController();
  bool _cropEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cropEnabled = await _settings.getCropEnabledDefault();
    final clientId = await _settings.getGoogleWebClientId();
    if (!mounted) return;
    setState(() {
      _cropEnabled = cropEnabled;
      _clientIdController.text = clientId ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Google-Verbindung (für PowerPoint → PDF und PDF → Word)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Diese beiden Werkzeuge laufen über dein eigenes Google-Konto '
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
