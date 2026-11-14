import 'package:flutter/material.dart';

/// A titled group of settings, shown as one card with divided rows.
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsSection({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One settings row: icon, title and description on the left, the control
/// on the right - or below the text when there is not enough width.
/// [below] adds full-width content under the row (e.g. text fields).
class SettingsTile extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;

  const SettingsTile({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.below,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null || trailing != null || below != null;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Wide controls (segmented buttons, buttons) move under the text
            // on narrow screens; switches and status labels stay on the right.
            final narrow =
                constraints.maxWidth < 560 && trailing is! Switch && trailing is! StatusChip;
            final leading = icon == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Icon(icon, color: enabled ? scheme.onSurfaceVariant : scheme.outline),
                  );
            final indent = icon == null ? 0.0 : 40.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ?leading,
                    Expanded(child: text),
                    if (trailing != null && !narrow) ...[const SizedBox(width: 16), trailing!],
                  ],
                ),
                if (trailing != null && narrow)
                  Padding(
                    padding: EdgeInsets.only(left: indent, top: 12),
                    child: trailing!,
                  ),
                if (below != null)
                  Padding(
                    padding: EdgeInsets.only(left: indent, top: 14),
                    child: below!,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A small colored status label, e.g. "Signed in".
class StatusChip extends StatelessWidget {
  final String label;
  final bool positive;

  const StatusChip({super.key, required this.label, required this.positive});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = positive ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = positive ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(positive ? Icons.check_circle : Icons.circle_outlined, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}
