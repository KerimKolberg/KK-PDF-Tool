import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const _seedColor = Color(0xFF2C5F6F);

/// The app's look. On desktop (Windows) controls are more compact and
/// pointer-sized; on phones and tablets they keep touch-friendly sizes.
ThemeData buildAppTheme(Brightness brightness) {
  final desktop = defaultTargetPlatform == TargetPlatform.windows;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  );
  final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);
  // ThemeData.textTheme carries no font sizes until Theme.of() localizes
  // it, so take the sizes from the typography here.
  final textTheme = base.typography.englishLike.merge(base.textTheme);
  final radius = BorderRadius.circular(10);
  final buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: desktop ? 12 : 14);
  final buttonMinSize = Size(64, desktop ? 40 : 48);
  final buttonShape = RoundedRectangleBorder(borderRadius: radius);

  return base.copyWith(
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: buttonPadding,
        minimumSize: buttonMinSize,
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: buttonPadding,
        minimumSize: buttonMinSize,
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: Size(48, desktop ? 36 : 40), shape: buttonShape),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: radius),
      isDense: desktop,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: desktop ? 480 : null,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surfaceContainer,
      elevation: 0,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      indicatorColor: colorScheme.secondaryContainer,
      selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
  );
}
