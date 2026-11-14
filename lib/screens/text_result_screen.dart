import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../services/downloads_export_service.dart';

/// Shows recognised text with copy and "save as .txt" actions.
class TextResultScreen extends StatelessWidget {
  final String title;
  final String text;

  const TextResultScreen({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Text: $title', 'Text: $title'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(text.isEmpty ? tr('(kein Text erkannt)', '(no text recognized)') : text),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(tr('In die Zwischenablage kopiert', 'Copied to clipboard'))),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(tr('Kopieren', 'Copy')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    try {
                      final location = await DownloadsExportService().export(
                        Uint8List.fromList(utf8.encode(text)),
                        '$title.txt',
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('Gespeichert unter $location', 'Saved to $location'))),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('Speichern fehlgeschlagen: $e', 'Saving failed: $e'))),
                      );
                    }
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: Text(tr('Als .txt speichern', 'Save as .txt')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
