import 'package:shared_preferences/shared_preferences.dart';

/// Small persisted app preferences, backed by [SharedPreferences].
class SettingsService {
  static const _cropEnabledKey = 'crop_enabled_default';
  static const _googleWebClientIdKey = 'google_web_client_id';

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
