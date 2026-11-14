import 'package:flutter/material.dart';

import '../l10n.dart';
import '../utils/layout.dart';
import 'drop_visuals.dart';

/// Scaffold for the tool pages. In wide windows the content and the bottom
/// action bar form a centered column of limited width instead of
/// stretching across the whole window.
class ToolScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? bottomNavigationBar;

  static const double contentWidth = 760;

  const ToolScaffold({super.key, this.appBar, this.body, this.bottomNavigationBar});

  @override
  Widget build(BuildContext context) {
    final bottom = bottomNavigationBar;
    return Scaffold(
      appBar: appBar,
      body: body == null ? null : ContentWidth(maxWidth: contentWidth, child: body!),
      bottomNavigationBar: bottom == null
          ? null
          : Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: contentWidth),
                child: bottom,
              ),
            ),
    );
  }
}

/// A tool's empty state: a large area to choose (or, on Windows, drop) the
/// input file. Clicking anywhere on it opens the file picker; the drop
/// itself is handled by the ToolDropZone around the whole tool.
class FilePickPanel extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final Widget label;
  final String? hint;

  /// Whether the tool takes several files at once (changes the drag hint).
  final bool multiple;

  const FilePickPanel({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.hint,
    this.multiple = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(16);
    final panel = DashedBorder(
      color: scheme.outlineVariant,
      radius: 16,
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                  child: IconTheme(
                    data: IconThemeData(color: scheme.onPrimaryContainer, size: 30),
                    child: icon,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    hint!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(onPressed: onPressed, child: label),
                if (AppPlatform.isWindows) ...[
                  const SizedBox(height: 10),
                  Text(
                    multiple
                        ? tr('oder Dateien hierher ziehen', 'or drag files here')
                        : tr('oder Datei hierher ziehen', 'or drag a file here'),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return SizedBox(width: double.infinity, child: panel);
  }
}

/// The file a tool is working on, with a button to pick a different one.
class SelectedFileTile extends StatelessWidget {
  final String name;
  final IconData icon;
  final Widget? subtitle;

  /// Null while the tool is busy.
  final VoidCallback? onChange;

  const SelectedFileTile({
    super.key,
    required this.name,
    required this.onChange,
    this.icon = Icons.description_outlined,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon),
        title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle,
        trailing: TextButton(onPressed: onChange, child: Text(tr('Ändern', 'Change'))),
      ),
    );
  }
}
