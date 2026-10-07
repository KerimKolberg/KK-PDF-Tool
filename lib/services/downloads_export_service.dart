import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  /// Replaces characters that aren't allowed in Windows/Android file names
  /// (titles like "Scan 3.10.2026 14:05" contain a colon).
  static String safeFileName(String name) {
    var safe = name
        .replaceAll(':', '-')
        .replaceAll(RegExp(r'[<>"/\\|?*\x00-\x1F]'), '_')
        .trim();
    while (safe.endsWith('.') || safe.endsWith(' ')) {
      safe = safe.substring(0, safe.length - 1);
    }
    return safe.isEmpty ? 'Dokument' : safe;
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
    final targetDir = await _desktopTargetDir();
    final copy = await source.copy(p.join(targetDir.path, fileName));
    return copy.path;
  }

  Future<Directory> _desktopTargetDir() async {
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

    final targetDir = await _desktopTargetDir();
    final file = File(p.join(targetDir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
