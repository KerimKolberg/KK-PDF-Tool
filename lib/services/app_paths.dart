import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const appFolderName = 'KK-PDF-Tool';

Future<Directory>? _appData;

/// Where the library and signatures live. On Android that's the app's
/// private folder; on Windows "Documents" is the user's real Documents
/// folder, so everything goes into Documents\KK-PDF-Tool instead.
Future<Directory> appDataDirectory() => _appData ??= _resolve();

Future<Directory> _resolve() async {
  final docs = await getApplicationDocumentsDirectory();
  if (!Platform.isWindows) return docs;
  final dir = Directory(p.join(docs.path, appFolderName));
  await dir.create(recursive: true);
  // One-time move of data that older versions saved directly in Documents.
  // Only folders recognisably created by this app are moved.
  final oldScans = Directory(p.join(docs.path, 'scans'));
  final newScans = Directory(p.join(dir.path, 'scans'));
  if (!await newScans.exists() && await File(p.join(oldScans.path, 'index.json')).exists()) {
    await oldScans.rename(newScans.path);
  }
  final oldSigs = Directory(p.join(docs.path, 'signatures'));
  final newSigs = Directory(p.join(dir.path, 'signatures'));
  if (!await newSigs.exists() &&
      await oldSigs.exists() &&
      await oldSigs.list().every((e) => p.basename(e.path).startsWith('sig_'))) {
    await oldSigs.rename(newSigs.path);
  }
  return dir;
}
