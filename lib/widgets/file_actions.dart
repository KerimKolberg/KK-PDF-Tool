import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n.dart';
import '../screens/tools_screen.dart';
import '../utils/layout.dart';

/// What the user picked in [chooseFileAction]: add the files to the
/// library ([tool] is null), or open [tool] with them.
class FileAction {
  final ToolEntry? tool;
  const FileAction.import() : tool = null;
  const FileAction.tool(ToolEntry this.tool);
}

const _importable = {'pdf', 'jpg', 'jpeg', 'png'};

/// Lower-case extension without the dot, e.g. "pdf".
String fileKind(String name) => p.extension(name).replaceFirst('.', '').toLowerCase();

/// Whether the main window accepts a dropped file of this name at all.
bool isSupportedFile(String name) {
  final kind = fileKind(name);
  return _importable.contains(kind) || ToolsScreen.toolsFor([kind]).isNotEmpty;
}

/// Asks what to do with files that were dropped on the main window or
/// opened with the app: add them to the library, or open one of the tools
/// that take this kind of file. A dialog on wide screens, a bottom sheet on
/// phones.
Future<FileAction?> chooseFileAction(BuildContext context, List<String> names) {
  final kinds = [for (final n in names) fileKind(n)];
  final tools = ToolsScreen.toolsFor(kinds);
  final canImport = kinds.every(_importable.contains);
  final content = _FileActionList(names: names, tools: tools, canImport: canImport);
  if (isWideLayout(context)) {
    return showDialog<FileAction>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: content,
        ),
      ),
    );
  }
  return showModalBottomSheet<FileAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: content,
    ),
  );
}

class _FileActionList extends StatelessWidget {
  final List<String> names;
  final List<ToolEntry> tools;
  final bool canImport;

  const _FileActionList({required this.names, required this.tools, required this.canImport});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final single = names.length == 1;
    final isPdf = names.every((n) => fileKind(n) == 'pdf');
    final isImage = names.every((n) => const {'jpg', 'jpeg', 'png', 'webp'}.contains(fileKind(n)));

    Widget tile(
      IconData icon,
      String title,
      String subtitle,
      FileAction action, {
      bool primary = false,
    }) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: primary ? scheme.primary : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 22,
            color: primary ? scheme.onPrimary : scheme.onPrimaryContainer,
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: () => Navigator.of(context).pop(action),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              Icon(
                isPdf
                    ? Icons.picture_as_pdf_outlined
                    : isImage
                    ? Icons.image_outlined
                    : Icons.insert_drive_file_outlined,
                size: 32,
                color: scheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      single ? names.first : tr('${names.length} Dateien', '${names.length} files'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      tr('Was möchtest du damit machen?', 'What do you want to do with it?'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (canImport)
                tile(
                  Icons.library_add_outlined,
                  tr('Zur Bibliothek hinzufügen', 'Add to library'),
                  single
                      ? tr(
                          'Als Dokument in "Meine Scans" speichern',
                          'Save as a document in "My scans"',
                        )
                      : tr(
                          'Jede Datei als eigenes Dokument speichern',
                          'Save each file as its own document',
                        ),
                  const FileAction.import(),
                  primary: true,
                ),
              if (tools.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(
                    tr('Werkzeuge', 'Tools'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              for (final tool in tools)
                tile(tool.icon, tool.title, tool.subtitle, FileAction.tool(tool)),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('Abbrechen', 'Cancel')),
            ),
          ),
        ),
      ],
    );
  }
}
