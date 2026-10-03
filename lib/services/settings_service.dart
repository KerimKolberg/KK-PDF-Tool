import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembered choices (last options per tool, library view, scan filter).
/// Loaded once at startup via [init] so screens can read them
/// synchronously when they open; writes are fire-and-forget.
class AppPrefs {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String _k(String key) => 'pref.$key';

  static bool getBool(String key, bool fallback) => _prefs?.getBool(_k(key)) ?? fallback;
  static int getInt(String key, int fallback) => _prefs?.getInt(_k(key)) ?? fallback;
  static double getDouble(String key, double fallback) =>
      _prefs?.getDouble(_k(key)) ?? fallback;
  static String? getString(String key) => _prefs?.getString(_k(key));

  static T getEnum<T extends Enum>(String key, List<T> values, T fallback) =>
      values.asNameMap()[getString(key)] ?? fallback;

  static void setBool(String key, bool value) => _write(_prefs?.setBool(_k(key), value));
  static void setInt(String key, int value) => _write(_prefs?.setInt(_k(key), value));
  static void setDouble(String key, double value) => _write(_prefs?.setDouble(_k(key), value));
  static void setEnum(String key, Enum value) => setString(key, value.name);

  /// null removes the value.
  static void setString(String key, String? value) => _write(
        value == null ? _prefs?.remove(_k(key)) : _prefs?.setString(_k(key), value),
      );

  static void _write(Future<bool>? write) {
    if (write != null) unawaited(write);
  }
}

/// Small persisted app preferences, backed by [SharedPreferences].
class SettingsService {
  static const _cropEnabledKey = 'crop_enabled_default';
  static const _googleWebClientIdKey = 'google_web_client_id';
  static const _searchablePdfKey = 'searchable_pdf_enabled';
  static const _themeModeKey = 'theme_mode';

  /// App-wide theme choice; [DocScannerApp] rebuilds when this changes.
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_themeModeKey) ?? ThemeMode.system.index;
    themeMode.value = ThemeMode.values[index.clamp(0, ThemeMode.values.length - 1)];
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  /// Whether new scans get an invisible OCR text layer (Android only).
  Future<bool> getSearchablePdfEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_searchablePdfKey) ?? true;
  }

  Future<void> setSearchablePdfEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_searchablePdfKey, value);
  }

  /// Built into the app so it doesn't need to be re-entered after every
  /// fresh install. Google's own docs note that OAuth client IDs for
  /// installed/native apps are not secrets and are safe to ship in the app
  /// itself. The in-app Settings field still overrides this, in case the
  /// Google Cloud project ever changes.
  static const _defaultGoogleWebClientId =
      '591408303886-90d7fsngk4oa7kj0u0ll21pundjgvmh4.apps.googleusercontent.com';

  Future<bool> getCropEnabledDefault() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cropEnabledKey) ?? true;
  }

  Future<void> setCropEnabledDefault(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cropEnabledKey, value);
  }

  /// The "Web application" OAuth Client ID from the user's own Google Cloud
  /// project, required by google_sign_in on Android as `serverClientId`.
  /// Not a secret - Google's own docs note these client IDs are safe to
  /// embed in a distributed app - so it's fine to store as a plain setting.
  Future<String?> getGoogleWebClientId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_googleWebClientIdKey);
    if (stored != null && stored.isNotEmpty) return stored;
    return _defaultGoogleWebClientId;
  }

  Future<void> setGoogleWebClientId(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_googleWebClientIdKey, value.trim());
  }
}
