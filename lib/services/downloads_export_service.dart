import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Exports finished files (PDFs, images) into a public, user-visible
/// "DocScanner" folder inside the platform's normal Downloads location, so
/// files show up in the system Files app / Explorer, not just inside the
/// app's own library.
///
///  - Android: `/storage/emulated/0/Download/DocScanner/`, using the "All
///    files access" permission (fine for a personal, side-loaded app; it is
///    requested once and only for this purpose).
///  - Windows: `<Downloads>/DocScanner/`.
///  - Other desktop platforms: falls back to the app documents directory.
class DownloadsExportService {
  static const _folderName = 'DocScanner';

  Future<String> export(Uint8List bytes, String fileName) async {
    if (Platform.isAndroid) {
      return _exportAndroid(bytes, fileName);
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

  Future<String> _exportAndroid(Uint8List bytes, String fileName) async {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
    if (!status.isGranted) {
      throw StateError(
        'Kein Zugriff auf den Speicher erlaubt (Berechtigung "Alle Dateien verwalten" fehlt).',
      );
    }

    final targetDir = Directory('/storage/emulated/0/Download/$_folderName');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final file = File(p.join(targetDir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return 'Downloads/$_folderName/$fileName';
  }
}
