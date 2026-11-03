import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'services/settings_service.dart';

/// The user's language choice in Settings.
enum AppLanguage { automatic, de, en }

/// German/English UI texts. Texts are written inline as `tr(german,
/// english)`; this class decides which one is shown.
///
/// "Automatic" follows the language picked in the Windows installer, or the
/// device language on Android (German for German devices, English
/// otherwise).
class L10n {
  static const _prefKey = 'app.language';

  /// 'de' or 'en'; [DocScannerApp] rebuilds everything when it changes.
  static final language = ValueNotifier<String>('de');

  static String? _installerLanguage;

  /// Call after [AppPrefs.init].
  static Future<void> init() async {
    if (Platform.isWindows) _installerLanguage = await _readInstallerLanguage();
    language.value = _resolve();
  }

  static AppLanguage get choice =>
      AppPrefs.getEnum(_prefKey, AppLanguage.values, AppLanguage.automatic);

  static void setChoice(AppLanguage value) {
    AppPrefs.setEnum(_prefKey, value);
    language.value = _resolve();
  }

  static bool get isEnglish => language.value == 'en';

  static String _resolve() => switch (choice) {
        AppLanguage.de => 'de',
        AppLanguage.en => 'en',
        AppLanguage.automatic => _installerLanguage ??
            (ui.PlatformDispatcher.instance.locale.languageCode == 'de' ? 'de' : 'en'),
      };

  /// The installer writes the chosen setup language into `language.ini`
  /// next to the exe.
  static Future<String?> _readInstallerLanguage() async {
    try {
      final file = File(p.join(p.dirname(Platform.resolvedExecutable), 'language.ini'));
      if (!await file.exists()) return null;
      final match = RegExp(r'^\s*Language\s*=\s*(de|en)\s*$', multiLine: true)
          .firstMatch(await file.readAsString());
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }
}

/// [de] or [en], depending on the current UI language.
String tr(String de, String en) => L10n.isEnglish ? en : de;
