import 'dart:io';

import 'package:flutter/material.dart';

/// Platform checks for UI code. Overridable so the Windows layout can be
/// rendered in tests on other machines.
class AppPlatform {
  @visibleForTesting
  static bool? debugIsWindows;

  static bool get isWindows => debugIsWindows ?? Platform.isWindows;
  static bool get isAndroid => !isWindows && Platform.isAndroid;
}

/// From this width on the app uses the desktop layout: side navigation
/// instead of the bottom bar. Windows uses it at every usable window size.
double get wideLayoutBreakpoint => AppPlatform.isWindows ? 600 : 840;

bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideLayoutBreakpoint;

/// Centers [child] at the top and limits it to [maxWidth], so forms and
/// lists stay readable in large windows instead of stretching edge to edge.
class ContentWidth extends StatelessWidget {
  final double maxWidth;
  final Widget child;

  const ContentWidth({super.key, this.maxWidth = 760, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Horizontal padding that centers a [maxWidth] column inside [width] -
/// for scroll views, so the scrollbar stays at the window edge.
EdgeInsets centeredPadding(double width, {double maxWidth = 760, double min = 16, double vertical = 16}) {
  final side = width > maxWidth + 2 * min ? (width - maxWidth) / 2 : min;
  return EdgeInsets.symmetric(horizontal: side, vertical: vertical);
}
