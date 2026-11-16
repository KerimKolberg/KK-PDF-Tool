import 'dart:async';
import 'dart:io';

import 'package:doc_scanner/l10n.dart';
import 'package:doc_scanner/services/downloads_export_service.dart';
import 'package:doc_scanner/utils/errors.dart';
import 'package:doc_scanner/utils/formatting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const safe = DownloadsExportService.safeFileName;

  group('safeFileName', () {
    test('removes path separators and forbidden characters', () {
      expect(safe('Scan 3.10.2026 14:05.pdf'), 'Scan 3.10.2026 14-05.pdf');
      expect(safe('../../etc/passwd'), '.._.._etc_passwd');
      expect(safe(r'a\b/c?.pdf'), 'a_b_c_.pdf');
      expect(safe('name. . '), 'name');
    });

    test('never returns an empty or reserved name', () {
      expect(safe('   '), isNotEmpty);
      expect(safe('...'), isNotEmpty);
      expect(safe('CON.pdf'), '_CON.pdf');
      expect(safe('nul'), '_nul');
      expect(safe('console.pdf'), 'console.pdf');
    });

    test('shortens very long names but keeps the extension', () {
      final result = safe('${'x' * 400}.pdf');
      expect(result.length, lessThanOrEqualTo(150));
      expect(result, endsWith('.pdf'));
    });
  });

  group('parsePageSpec', () {
    test('blank means all pages', () => expect(parsePageSpec('  '), isNull));
    test('single pages and ranges, 1-based in, 0-based out', () {
      expect(parsePageSpec('1-3, 5,8-9'), {0, 1, 2, 4, 7, 8});
    });
    test('ignores nonsense instead of failing', () {
      expect(parsePageSpec('0, -2, x, 4-2, 3'), {2});
    });
  });

  test('formatFileSize and folderOf', () {
    expect(formatFileSize(512 * 1024), '512 KB');
    L10n.language.value = 'en';
    expect(formatFileSize(3 * 1024 * 1024 ~/ 2), '1.5 MB');
    L10n.language.value = 'de';
    expect(formatFileSize(3 * 1024 * 1024 ~/ 2), '1,5 MB');
    expect(
      folderOf(r'C:\Users\me\Downloads\KK-PDF-Tool\a.pdf'),
      r'C:\Users\me\Downloads\KK-PDF-Tool',
    );
    expect(folderOf('Downloads/KK-PDF-Tool/a.pdf'), 'Downloads/KK-PDF-Tool');
  });

  group('describeError', () {
    setUp(() => L10n.language.value = 'en');
    tearDown(() => L10n.language.value = 'de');

    test('explains common problems in plain words', () {
      expect(describeError(const SocketException('Failed host lookup')), contains('internet'));
      expect(describeError(TimeoutException('x')), contains('No response'));
      expect(
        describeError(const FileSystemException('write', 'a.pdf', OSError('No space', 28))),
        'The storage is full.',
      );
      expect(
        describeError(PlatformException(code: 'save_failed', message: 'Disk busy')),
        'Disk busy',
      );
      expect(describeError(const FormatException('Not a backup')), 'Not a backup');
      expect(describeError(Exception('Something odd')), 'Something odd');
    });
  });
}
