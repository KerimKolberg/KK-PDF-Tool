import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../l10n.dart';

/// Exports finished files (PDFs, images) into a public, user-visible
/// "KK-PDF-Tool" folder inside the platform's normal Downloads location, so
/// files show up in the system Files app / Explorer, not just inside the
/// app's own library.
///
///  - Android: `Download/KK-PDF-Tool/`, via a small native MethodChannel
///    (`android/.../MainActivity.kt`) that writes through MediaStore on
///    API 29+, which needs no runtime permission at all.
///  - Windows: `<Downloads>/KK-PDF-Tool/`.
///  - Other desktop platforms: falls back to the app documents directory.
class DownloadsExportService {
  static const _folderName = 'KK-PDF-Tool';
  static const _channel = MethodChannel('docscanner/downloads');

  /// Names Windows reserves for devices; a file can't be called that.
  static final _reservedName = RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$', caseSensitive: false);

  /// Turns [name] into a file name that works on Windows and Android:
  /// no path separators or forbidden characters (titles like
  /// "Scan 3.10.2026 14:05" contain a colon), no reserved device names, and
  /// not longer than file systems allow.
  static String safeFileName(String name) {
    var safe = name
        .replaceAll(':', '-')
        .replaceAll(RegExp(r'[<>"/\\|?*\x00-\x1F]'), '_')
        .trim();
    while (safe.endsWith('.') || safe.endsWith(' ')) {
      safe = safe.substring(0, safe.length - 1);
    }
    if (safe.isEmpty) return tr('Dokument', 'Document');
    if (_reservedName.hasMatch(p.basenameWithoutExtension(safe))) safe = '_$safe';
    const maxLength = 150;
    if (safe.length > maxLength) {
      final extension = p.extension(safe);
      final keep = extension.length <= 10 ? extension : '';
      safe = safe.substring(0, maxLength - keep.length).trimRight() + keep;
    }
    return safe;
  }

  /// Like [export], but copies an existing (possibly very large) file without
  /// loading it into memory.
  Future<String> exportFile(File source, String fileName, {String? mimeType}) async {
    fileName = safeFileName(fileName);
    if (Platform.isAndroid) {
      final location = await _channel.invokeMethod<String>('saveFileToDownloads', {
        'fileName': fileName,
        'sourcePath': source.path,
        'mimeType': mimeType,
      });
      return location ?? 'Downloads/$_folderName/$fileName';
    }
    final targetDir = await desktopTargetDir();
    final copy = await source.copy(p.join(targetDir.path, fileName));
    return copy.path;
  }

  /// Desktop: the Downloads\KK-PDF-Tool folder (created if missing).
  Future<Directory> desktopTargetDir() async {
    final downloads = await getDownloadsDirectory();
    final baseDir = downloads ?? await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(baseDir.path, _folderName));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    return targetDir;
  }

  Future<String> export(Uint8List bytes, String fileName) async {
    fileName = safeFileName(fileName);
    if (Platform.isAndroid) {
      final location = await _channel.invokeMethod<String>('saveToDownloads', {
        'fileName': fileName,
        'bytes': bytes,
      });
      return location ?? 'Downloads/$_folderName/$fileName';
    }

    final targetDir = await desktopTargetDir();
    final file = File(p.join(targetDir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
