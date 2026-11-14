import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small secrets (sign-in tokens) kept in the operating system's protected
/// storage - on Windows encrypted for the current user account - instead of
/// the plain-text preferences file.
///
/// Never throws: if the protected storage is unavailable, reads return null
/// and writes are dropped, which only means signing in again next time.
class SecretStore {
  static const _storage = FlutterSecureStorage();

  static Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  /// null deletes the value.
  static Future<void> write(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (_) {
      // See class comment.
    }
  }
}
