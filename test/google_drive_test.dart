import 'dart:convert';
import 'dart:typed_data';

import 'package:doc_scanner/services/google_drive_convert_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // 6 MB: more than a single-request upload may carry.
  final bigPdf = Uint8List(6 * 1024 * 1024);

  test('large files go through a resumable upload, then export and cleanup', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      expect(request.headers['Authorization'] ?? 'Bearer token', 'Bearer token');
      if (request.url.queryParameters['uploadType'] == 'resumable') {
        expect(request.headers['X-Upload-Content-Length'], '${bigPdf.length}');
        expect(jsonDecode(request.body)['mimeType'], 'application/vnd.google-apps.document');
        return http.Response('', 200, headers: {'location': 'https://upload.example/session1'});
      }
      if (request.url.host == 'upload.example') {
        expect(request.bodyBytes.length, bigPdf.length);
        return http.Response(jsonEncode({'id': 'file1'}), 200);
      }
      if (request.url.path.endsWith('/export')) return http.Response('DOCX', 200);
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response('unexpected', 500);
    });

    final docx = await http.runWithClient(
      () => GoogleDriveConvertService.withToken('token').pdfToWord(bigPdf, 'big.pdf'),
      () => client,
    );
    expect(utf8.decode(docx), 'DOCX');
    expect(calls, [
      'POST /upload/drive/v3/files',
      'PUT /session1',
      'GET /drive/v3/files/file1/export',
      'DELETE /drive/v3/files/file1',
    ]);
  });

  test('Google errors become readable messages', () async {
    final client = MockClient((request) async {
      if (request.url.queryParameters['uploadType'] == 'resumable') {
        return http.Response('', 200, headers: {'location': 'https://upload.example/s'});
      }
      if (request.method == 'PUT') return http.Response(jsonEncode({'id': 'f'}), 200);
      if (request.url.path.endsWith('/export')) {
        return http.Response('{"error":{"errors":[{"reason":"exportSizeLimitExceeded"}]}}', 403);
      }
      return http.Response('', 204);
    });
    await expectLater(
      http.runWithClient(
        () => GoogleDriveConvertService.withToken('token').pdfToWord(Uint8List(10), 'a.pdf'),
        () => client,
      ),
      throwsA(predicate((e) => e.toString().contains('10 MB'))),
    );
  });
}
