import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Exports finished files (PDFs, images) into a public, user-visible
/// "DocScanner" folder inside the platform's normal Downloads location, so
/// files show up in the system Files app / Explorer, not just inside the
/// app's own library.
///
///  - Android: `Download/DocScanner/`, via a small native MethodChannel
///    (`android/.../MainActivity.kt`) that writes through MediaStore on
///    API 29+, which needs no runtime permission at all.
///  - Windows: `<Downloads>/DocScanner/`.
///  - Other desktop platforms: falls back to the app documents directory.
class DownloadsExportService {
  static const _folderName = 'DocScanner';
  static const _channel = MethodChannel('docscanner/downloads');

  Future<String> export(Uint8List bytes, String fileName) async {
    if (Platform.isAndroid) {
      final location = await _channel.invokeMethod<String>('saveToDownloads', {
        'fileName': fileName,
        'bytes': bytes,
      });
      return location ?? 'Downloads/$_folderName/$fileName';
    }

    final downloads = await getDownloadsDirectory();
    final baseDir = downloads ?? await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(baseDir.path, _folderName));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final file = File(p.join(targetDir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
