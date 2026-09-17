import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'settings_service.dart';

/// Converts documents by round-tripping them through the user's own Google
/// Drive: Drive auto-converts recognised uploads into a native Google
/// format (Slides/Docs), which can then be exported as PDF/.docx. This is
/// the only free, no-server way to get real PPTX->PDF and OCR'd PDF->Word
/// conversion - it does need the internet and the user's own Google account.
class GoogleDriveConvertService {
  static const _scopes = ['https://www.googleapis.com/auth/drive.file'];
  static const _uploadUrl =
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart';
  static const _filesUrl = 'https://www.googleapis.com/drive/v3/files';

  final SettingsService _settings = SettingsService();
  GoogleSignIn? _signIn;
  bool _initialized = false;

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

  Future<GoogleSignInAccount> _signInAndAuthorize() async {
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
    return account;
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
    final boundary = 'docscanner_${DateTime.now().microsecondsSinceEpoch}';
    final metadata = jsonEncode({'name': fileName, 'mimeType': targetGoogleMimeType});

    final body = BytesBuilder();
    void writeString(String s) => body.add(utf8.encode(s));

    writeString('--$boundary\r\n');
    writeString('Content-Type: application/json; charset=UTF-8\r\n\r\n');
    writeString(metadata);
    writeString('\r\n--$boundary\r\n');
    writeString('Content-Type: $sourceMimeType\r\n\r\n');
    body.add(bytes);
    writeString('\r\n--$boundary--');

    final response = await http.post(
      Uri.parse(_uploadUrl),
      headers: {
        ..._authHeader,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body.toBytes(),
    );
    if (response.statusCode != 200) {
      throw GoogleDriveApiException(
        'Hochladen fehlgeschlagen (${response.statusCode}): ${response.body}',
      );
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<Uint8List> _exportAndDelete(String fileId, String exportMimeType) async {
    try {
      final response = await http.get(
        Uri.parse('$_filesUrl/$fileId/export?mimeType=${Uri.encodeComponent(exportMimeType)}'),
        headers: _authHeader,
      );
      if (response.statusCode != 200) {
        throw GoogleDriveApiException(
          'Export fehlgeschlagen (${response.statusCode}): ${response.body}',
        );
      }
      return response.bodyBytes;
    } finally {
      await http.delete(Uri.parse('$_filesUrl/$fileId'), headers: _authHeader);
    }
  }

  /// Converts a .pptx file to PDF via Google Slides.
  Future<Uint8List> pptxToPdf(Uint8List pptxBytes, String fileName) async {
    await _signInAndAuthorize();
    final fileId = await _uploadAndConvert(
      bytes: pptxBytes,
      fileName: fileName,
      sourceMimeType:
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
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

  Future<void> signOut() async {
    await _signIn?.signOut();
  }
}

class GoogleDriveNotConfiguredException implements Exception {
  const GoogleDriveNotConfiguredException();
  @override
  String toString() =>
      'Google-Verbindung ist nicht eingerichtet. Bitte in den Einstellungen die '
      'Google-Client-ID hinterlegen.';
}

class GoogleDriveApiException implements Exception {
  final String message;
  const GoogleDriveApiException(this.message);
  @override
  String toString() => message;
}
