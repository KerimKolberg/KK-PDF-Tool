import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../l10n.dart';
import 'google_desktop_auth.dart';
import 'settings_service.dart';

/// Converts documents by round-tripping them through the user's own Google
/// Drive: Drive auto-converts recognised uploads into a native Google
/// format (Slides/Docs), which can then be exported as PDF/.docx. This is
/// the only free, no-server way to get real PPTX->PDF and OCR'd PDF->Word
/// conversion - it does need the internet and the user's own Google account.
class GoogleDriveConvertService {
  static const _scopes = ['https://www.googleapis.com/auth/drive.file'];
  static const _uploadUrl = 'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable';
  static const _filesUrl = 'https://www.googleapis.com/drive/v3/files';
  static const _timeout = Duration(seconds: 60);
  static const _uploadTimeout = Duration(minutes: 5);

  final SettingsService _settings = SettingsService();
  GoogleSignIn? _signIn;
  bool _initialized = false;

  GoogleDriveConvertService();

  /// Skips the sign-in and uses [accessToken] (for tests).
  @visibleForTesting
  GoogleDriveConvertService.withToken(String accessToken) : _fixedToken = accessToken;

  String? _fixedToken;

  Future<GoogleSignIn> _ensureSignIn() async {
    if (_initialized && _signIn != null) return _signIn!;
    final clientId = await _settings.getGoogleWebClientId();
    if (clientId == null || clientId.isEmpty) {
      throw const GoogleDriveNotConfiguredException();
    }
    final instance = GoogleSignIn.instance;
    await instance.initialize(serverClientId: clientId);
    _signIn = instance;
    _initialized = true;
    return instance;
  }

  Future<void> _signInAndAuthorize() async {
    if (_fixedToken != null) {
      _accessToken = _fixedToken;
      return;
    }
    if (Platform.isWindows) {
      final clientId = AppPrefs.getString(SettingsService.googleDesktopClientIdKey);
      final secret = AppPrefs.getString(SettingsService.googleDesktopClientSecretKey);
      if (clientId == null || clientId.isEmpty || secret == null || secret.isEmpty) {
        throw const GoogleDriveNotConfiguredException(windows: true);
      }
      _accessToken = await GoogleDesktopAuth.accessToken(
        clientId: clientId,
        clientSecret: secret,
        scopes: _scopes,
      );
      return;
    }
    final signIn = await _ensureSignIn();
    GoogleSignInAccount? account;
    try {
      final lightweight = signIn.attemptLightweightAuthentication();
      account = lightweight != null ? await lightweight : null;
    } catch (_) {
      // Fall through to an explicit interactive sign-in below.
    }
    account ??= await signIn.authenticate();

    final authorization =
        await account.authorizationClient.authorizationForScopes(_scopes) ??
        await account.authorizationClient.authorizeScopes(_scopes);
    _accessToken = authorization.accessToken;
  }

  String? _accessToken;

  Map<String, String> get _authHeader => {'Authorization': 'Bearer $_accessToken'};

  /// Uploads [bytes] (named [fileName], with [sourceMimeType]) and asks
  /// Drive to convert it into [targetGoogleMimeType] (a native Google
  /// Workspace format), returning the new file's Drive id.
  Future<String> _uploadAndConvert({
    required Uint8List bytes,
    required String fileName,
    required String sourceMimeType,
    required String targetGoogleMimeType,
  }) async {
    // A resumable upload: unlike a single multipart request (which Google
    // limits to 5 MB) it works for files of any size, e.g. long scans.
    final start = await http
        .post(
          Uri.parse(_uploadUrl),
          headers: {
            ..._authHeader,
            'Content-Type': 'application/json; charset=UTF-8',
            'X-Upload-Content-Type': sourceMimeType,
            'X-Upload-Content-Length': '${bytes.length}',
          },
          body: jsonEncode({'name': fileName, 'mimeType': targetGoogleMimeType}),
        )
        .timeout(_timeout);
    final uploadUrl = start.headers['location'];
    if (start.statusCode != 200 || uploadUrl == null) {
      throw _apiError(start, tr('Hochladen fehlgeschlagen', 'Upload failed'));
    }
    final response = await http
        .put(Uri.parse(uploadUrl), headers: {'Content-Type': sourceMimeType}, body: bytes)
        .timeout(_uploadTimeout);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _apiError(response, tr('Hochladen fehlgeschlagen', 'Upload failed'));
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  /// A readable error for a failed Google request. Google's own reason is
  /// kept short; common cases get a plain explanation.
  GoogleDriveApiException _apiError(http.Response response, String what) {
    if (response.statusCode == 401) GoogleDesktopAuth.invalidate();
    final body = response.body;
    final String reason;
    if (body.contains('exportSizeLimitExceeded')) {
      reason = tr(
        'Das Ergebnis ist größer als Google erlaubt (10 MB). Teile die PDF vorher auf.',
        'The result is larger than Google allows (10 MB). Split the PDF first.',
      );
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      reason = tr(
        'Google hat den Zugriff abgelehnt. Bitte in den Einstellungen abmelden und neu anmelden.',
        'Google refused access. Please sign out in Settings and sign in again.',
      );
    } else if (response.statusCode == 429 || response.statusCode >= 500) {
      reason = tr(
        'Google ist gerade nicht erreichbar. Bitte später erneut versuchen.',
        'Google is not available right now. Please try again later.',
      );
    } else {
      reason =
          'HTTP ${response.statusCode}: ${body.length > 200 ? '${body.substring(0, 200)}…' : body}';
    }
    return GoogleDriveApiException('$what - $reason');
  }

  Future<Uint8List> _exportAndDelete(String fileId, String exportMimeType) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_filesUrl/$fileId/export?mimeType=${Uri.encodeComponent(exportMimeType)}'),
            headers: _authHeader,
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw _apiError(response, tr('Umwandlung fehlgeschlagen', 'Conversion failed'));
      }
      return response.bodyBytes;
    } finally {
      // Best effort: the conversion result matters more than the cleanup.
      try {
        await http.delete(Uri.parse('$_filesUrl/$fileId'), headers: _authHeader).timeout(_timeout);
      } catch (_) {}
    }
  }

  /// Converts a .pptx file to PDF via Google Slides.
  Future<Uint8List> pptxToPdf(Uint8List pptxBytes, String fileName) async {
    await _signInAndAuthorize();
    final fileId = await _uploadAndConvert(
      bytes: pptxBytes,
      fileName: fileName,
      sourceMimeType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      targetGoogleMimeType: 'application/vnd.google-apps.presentation',
    );
    return _exportAndDelete(fileId, 'application/pdf');
  }

  /// Converts a PDF to an editable .docx via Google Docs (with OCR for
  /// scanned/image-based pages).
  Future<Uint8List> pdfToWord(Uint8List pdfBytes, String fileName) async {
    await _signInAndAuthorize();
    final fileId = await _uploadAndConvert(
      bytes: pdfBytes,
      fileName: fileName,
      sourceMimeType: 'application/pdf',
      targetGoogleMimeType: 'application/vnd.google-apps.document',
    );
    return _exportAndDelete(
      fileId,
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
  }

  /// Converts a .docx file to PDF via Google Docs.
  Future<Uint8List> docxToPdf(Uint8List docxBytes, String fileName) async {
    await _signInAndAuthorize();
    final fileId = await _uploadAndConvert(
      bytes: docxBytes,
      fileName: fileName,
      sourceMimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      targetGoogleMimeType: 'application/vnd.google-apps.document',
    );
    return _exportAndDelete(fileId, 'application/pdf');
  }

  /// Converts an HTML file to PDF via Google Docs (which imports basic HTML
  /// formatting into a document).
  Future<Uint8List> htmlToPdf(Uint8List htmlBytes, String fileName) async {
    await _signInAndAuthorize();
    final fileId = await _uploadAndConvert(
      bytes: htmlBytes,
      fileName: fileName,
      sourceMimeType: 'text/html',
      targetGoogleMimeType: 'application/vnd.google-apps.document',
    );
    return _exportAndDelete(fileId, 'application/pdf');
  }

  /// Extracts text from a photo (jpg/png/webp) using Google Drive's
  /// built-in OCR: uploads it while asking Drive to convert it straight
  /// into a Google Doc (which OCRs any recognised text), then exports that
  /// doc as plain text.
  Future<String> imageToText(
    Uint8List imageBytes,
    String fileName, {
    String mimeType = 'image/jpeg',
  }) async {
    await _signInAndAuthorize();
    final fileId = await _uploadAndConvert(
      bytes: imageBytes,
      fileName: fileName,
      sourceMimeType: mimeType,
      targetGoogleMimeType: 'application/vnd.google-apps.document',
    );
    final bytes = await _exportAndDelete(fileId, 'text/plain');
    return utf8.decode(bytes);
  }

  /// Extracts all text from a (scanned) PDF via Google Docs' OCR.
  Future<String> pdfToText(Uint8List pdfBytes, String fileName) async {
    await _signInAndAuthorize();
    final fileId = await _uploadAndConvert(
      bytes: pdfBytes,
      fileName: fileName,
      sourceMimeType: 'application/pdf',
      targetGoogleMimeType: 'application/vnd.google-apps.document',
    );
    final bytes = await _exportAndDelete(fileId, 'text/plain');
    return utf8.decode(bytes);
  }

  Future<void> signOut() async {
    if (Platform.isWindows) return GoogleDesktopAuth.signOut();
    await _signIn?.signOut();
  }
}

class GoogleDriveNotConfiguredException implements Exception {
  final bool windows;
  const GoogleDriveNotConfiguredException({this.windows = false});
  @override
  String toString() => windows
      ? tr(
          'Google-Verbindung für Windows ist noch nicht eingerichtet. Bitte in den '
              'Einstellungen Client-ID und Client-Secret der Desktop-App hinterlegen '
              '(siehe README).',
          'The Google connection for Windows is not set up yet. Please enter the '
              'client ID and client secret of the desktop app in Settings '
              '(see README).',
        )
      : tr(
          'Google-Verbindung ist nicht eingerichtet. Bitte in den Einstellungen die '
              'Google-Client-ID hinterlegen.',
          'The Google connection is not set up. Please enter the '
              'Google client ID in Settings.',
        );
}

class GoogleDriveApiException implements Exception {
  final String message;
  const GoogleDriveApiException(this.message);
  @override
  String toString() => message;
}
