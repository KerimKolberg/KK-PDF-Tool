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
  static final _reservedName = RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
    caseSensitive: false,
  );

  /// Turns [name] into a file name that works on Windows and Android:
  /// no path separators or forbidden characters (titles like
  /// "Scan 3.10.2026 14:05" contain a colon), no reserved device names, and
  /// not longer than file systems allow.
  static String safeFileName(String name) {
    var safe = name.replaceAll(':', '-').replaceAll(RegExp(r'[<>"/\\|?*\x00-\x1F]'), '_').trim();
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
    final target = await _freeFile(await desktopTargetDir(), fileName);
    final copy = await source.copy(target.path);
    return copy.path;
  }

  /// A file in [dir] named [fileName] that doesn't exist yet: an existing
  /// file of the same name (an earlier result, or the very file a tool was
  /// working on) is never overwritten - the new one becomes "name (2).pdf".
  static Future<File> _freeFile(Directory dir, String fileName) async {
    final base = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    var candidate = File(p.join(dir.path, fileName));
    for (var n = 2; await candidate.exists(); n++) {
      candidate = File(p.join(dir.path, '$base ($n)$extension'));
    }
    return candidate;
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

    final file = await _freeFile(await desktopTargetDir(), fileName);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
