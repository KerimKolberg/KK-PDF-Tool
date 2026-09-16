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
  bool _cropEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _settings.getCropEnabledDefault().then((value) {
      if (!mounted) return;
      setState(() {
        _cropEnabled = value;
        _loading = false;
      });
    });
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
              ],
            ),
    );
  }
}
