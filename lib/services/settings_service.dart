import 'package:shared_preferences/shared_preferences.dart';

/// Small persisted app preferences, backed by [SharedPreferences].
class SettingsService {
  static const _cropEnabledKey = 'crop_enabled_default';

  Future<bool> getCropEnabledDefault() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cropEnabledKey) ?? true;
  }

  Future<void> setCropEnabledDefault(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cropEnabledKey, value);
  }
}
