import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n.dart';
import 'secret_store.dart';
import 'settings_service.dart';

/// Google sign-in for Windows, where google_sign_in has no implementation.
///
/// Uses Google's OAuth flow for desktop apps: the browser opens Google's
/// sign-in page, and Google sends the result back to a short-lived web
/// server on this PC (`http://127.0.0.1:<port>`). PKCE ties the returned code
/// to this sign-in. The refresh token is kept, so later conversions don't
/// open the browser again.
class GoogleDesktopAuth {
  static const _authUrl = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const _revokeUrl = 'https://oauth2.googleapis.com/revoke';
  static const _refreshTokenKey = 'google.desktop.refreshToken';

  static const _timeout = Duration(seconds: 30);

  static String? _accessToken;
  static DateTime _expiry = DateTime.fromMillisecondsSinceEpoch(0);

  static String? _refreshToken;
  static Future<void>? _loaded;

  /// Reads the saved sign-in from the protected storage (once). Call before
  /// using [isSignedIn].
  static Future<void> load() => _loaded ??= _load();

  static Future<void> _load() async {
    // Older versions kept the token in the plain preferences file.
    final legacy = AppPrefs.getString(_refreshTokenKey);
    if (legacy != null) {
      await SecretStore.write(_refreshTokenKey, legacy);
      AppPrefs.setString(_refreshTokenKey, null);
    }
    _refreshToken = legacy ?? await SecretStore.read(_refreshTokenKey);
  }

  static Future<void> _setRefreshToken(String? token) {
    _refreshToken = token;
    return SecretStore.write(_refreshTokenKey, token);
  }

  /// A valid access token for [scopes]; signs in through the browser only
  /// when there is no usable refresh token yet.
  static Future<String> accessToken({
    required String clientId,
    required String clientSecret,
    required List<String> scopes,
  }) async {
    final cached = _accessToken;
    if (cached != null && DateTime.now().isBefore(_expiry)) return cached;

    await load();
    final refreshToken = _refreshToken;
    if (refreshToken != null) {
      final response = await http.post(Uri.parse(_tokenUrl), body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      }).timeout(_timeout);
      if (response.statusCode == 200) return _store(response.body);
      if (response.statusCode != 400 && response.statusCode != 401) {
        // A server or network problem - keep the sign-in for the next try.
        throw GoogleDesktopAuthException(
          tr('Google-Anmeldung fehlgeschlagen (${response.statusCode}): ${response.body}', 'Google sign-in failed (${response.statusCode}): ${response.body}'),
        );
      }
      // Revoked or expired (Google expires them after 7 days while the
      // Cloud project is in "Testing" mode): sign in again below.
      await _setRefreshToken(null);
    }
    return _signIn(clientId: clientId, clientSecret: clientSecret, scopes: scopes);
  }

  /// Forgets the cached token, e.g. after Google rejected it.
  static void invalidate() => _accessToken = null;

  static Future<void> signOut() async {
    await load();
    final token = _refreshToken ?? _accessToken;
    _accessToken = null;
    await _setRefreshToken(null);
    if (token != null) {
      try {
        await http.post(Uri.parse(_revokeUrl), body: {'token': token}).timeout(_timeout);
      } catch (_) {
        // Offline: the token is forgotten locally either way.
      }
    }
  }

  /// Whether a sign-in is saved. Only meaningful after [load].
  static bool get isSignedIn => _refreshToken != null;

  static Future<String> _signIn({
    required String clientId,
    required String clientSecret,
    required List<String> scopes,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirectUri = 'http://127.0.0.1:${server.port}';
      final verifier = _randomString(64);
      final challenge =
          base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
      final state = _randomString(24);

      final url = Uri.parse(_authUrl).replace(queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': scopes.join(' '),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
      });
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw GoogleDesktopAuthException(tr('Browser konnte nicht geöffnet werden.', 'Could not open the browser.'));
      }

      final code = await _waitForCode(server, state).timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw GoogleDesktopAuthException(
          tr('Anmeldung abgebrochen (keine Antwort von Google innerhalb von 5 Minuten).', 'Sign-in cancelled (no answer from Google within 5 minutes).'),
        ),
      );
      _focusApp();

      final response = await http.post(Uri.parse(_tokenUrl), body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
      }).timeout(_timeout);
      if (response.statusCode != 200) {
        throw GoogleDesktopAuthException(
          tr('Google-Anmeldung fehlgeschlagen (${response.statusCode}): ${response.body}', 'Google sign-in failed (${response.statusCode}): ${response.body}'),
        );
      }
      return await _store(response.body);
    } finally {
      await server.close(force: true);
    }
  }

  /// Waits for Google's redirect to the local server and returns the code.
  static Future<String> _waitForCode(HttpServer server, String state) async {
    await for (final request in server) {
      if (request.uri.path != '/') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      final params = request.uri.queryParameters;
      final ok = params['state'] == state && params['code'] != null;
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        tr('<!doctype html><meta charset="utf-8"><title>KK-PDF-Tool</title>'
        '<body style="font-family:sans-serif;text-align:center;padding-top:15vh">'
        '<h2>${ok ? 'Anmeldung abgeschlossen' : 'Anmeldung fehlgeschlagen'}</h2>'
        '<p>Du kannst dieses Fenster schließen und zu KK-PDF-Tool zurückkehren.</p>',
        '<!doctype html><meta charset="utf-8"><title>KK-PDF-Tool</title>'
        '<body style="font-family:sans-serif;text-align:center;padding-top:15vh">'
        '<h2>${ok ? 'Signed in' : 'Sign-in failed'}</h2>'
        '<p>You can close this window and return to KK-PDF-Tool.</p>'),
      );
      await request.response.close();
      if (ok) return params['code']!;
      throw GoogleDesktopAuthException(
        params['error'] == 'access_denied'
            ? tr('Anmeldung bei Google abgebrochen.', 'Google sign-in cancelled.')
            : tr('Google-Anmeldung fehlgeschlagen: ${params['error'] ?? 'ungültige Antwort'}', 'Google sign-in failed: ${params['error'] ?? 'invalid response'}'),
      );
    }
    throw GoogleDesktopAuthException(tr('Anmeldung abgebrochen.', 'Sign-in cancelled.'));
  }

  static Future<String> _store(String body) async {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final token = json['access_token'] as String;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    _accessToken = token;
    _expiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
    final refreshToken = json['refresh_token'] as String?;
    if (refreshToken != null) await _setRefreshToken(refreshToken);
    return token;
  }

  /// Brings the app back in front of the browser after signing in.
  static void _focusApp() {
    windowManager.focus().catchError((_) {});
  }

  static String _randomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return String.fromCharCodes(
      List.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }
}

class GoogleDesktopAuthException implements Exception {
  final String message;
  const GoogleDesktopAuthException(this.message);
  @override
  String toString() => message;
}
