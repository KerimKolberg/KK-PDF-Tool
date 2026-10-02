import 'package:flutter/material.dart';

import '../services/document_store.dart';

/// Asks for a folder name; returns the trimmed name or null if cancelled.
Future<String?> promptFolderName(
  BuildContext context, {
  String title = 'Neuer Ordner',
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty) return null;
  return name;
}

/// Lets the user pick a target folder for a document. Returns null when
/// cancelled, otherwise a record whose `folder` is null for "no folder".
Future<({String? folder})?> pickFolder(
  BuildContext context,
  DocumentStore store, {
  String? current,
}) async {
  final folders = await store.loadFolders();
  if (!context.mounted) return null;
  return showModalBottomSheet<({String? folder})>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('In Ordner verschieben', style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Kein Ordner'),
              trailing: current == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(sheetContext, (folder: null)),
            ),
            for (final f in folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f),
                trailing: current == f ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, (folder: f)),
              ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Neuer Ordner…'),
              onTap: () async {
                final name = await promptFolderName(sheetContext);
                if (name == null) return;
                await store.addFolder(name);
                if (sheetContext.mounted) Navigator.pop(sheetContext, (folder: name));
              },
            ),
          ],
        ),
      ),
    ),
  );
}
