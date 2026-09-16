import 'dart:io';
import 'dart:typed_data';

import 'package:media_store_plus/media_store_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Exports finished files (PDFs, images) into a public, user-visible
/// "DocScanner" folder inside the platform's normal Downloads location, so
/// files show up in the system Files app / Explorer, not just inside the
/// app's own library.
///
///  - Android: `Download/DocScanner/` via the MediaStore API (no broad
///    storage permission needed on modern Android).
///  - Windows: `<Downloads>/DocScanner/`.
///  - Other desktop platforms: falls back to the app documents directory.
class DownloadsExportService {
  static const _folderName = 'DocScanner';
  bool _mediaStoreReady = false;

  Future<void> _ensureMediaStore() async {
    if (_mediaStoreReady) return;
    await MediaStore.ensureInitialized();
    MediaStore.appFolder = _folderName;
    _mediaStoreReady = true;
  }

  /// Writes [bytes] under a file named [fileName] inside the DocScanner
  /// Downloads folder and returns a human-readable location string to show
  /// the user.
  Future<String> export(Uint8List bytes, String fileName) async {
    if (Platform.isAndroid) {
      await _ensureMediaStore();
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, fileName));
      await tempFile.writeAsBytes(bytes, flush: true);
      final info = await MediaStore().saveFile(
        tempFilePath: tempFile.path,
        dirType: DirType.download,
        dirName: DirName.download,
      );
      await tempFile.delete();
      return 'Downloads/$_folderName/${info?.name ?? fileName}';
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
