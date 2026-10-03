import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'settings_service.dart';

/// File pickers that reopen in the folder last used by the same tool.
/// Only matters on desktop: Android's system picker manages its own
/// "recent" location and ignores a starting folder.
class FilePickers {
  static Future<XFile?> openOne(String toolKey, List<XTypeGroup> groups) async {
    final file = await openFile(
      acceptedTypeGroups: groups,
      initialDirectory: _initialDirectory(toolKey),
    );
    if (file != null) _remember(toolKey, file.path);
    return file;
  }

  static Future<List<XFile>> openMany(String toolKey, List<XTypeGroup> groups) async {
    final files = await openFiles(
      acceptedTypeGroups: groups,
      initialDirectory: _initialDirectory(toolKey),
    );
    if (files.isNotEmpty) _remember(toolKey, files.first.path);
    return files;
  }

  static bool get _desktop => !(Platform.isAndroid || Platform.isIOS);

  static String? _initialDirectory(String toolKey) {
    if (!_desktop) return null;
    final dir = AppPrefs.getString('lastDir.$toolKey');
    if (dir == null || !Directory(dir).existsSync()) return null;
    return dir;
  }

  static void _remember(String toolKey, String path) {
    if (!_desktop || path.isEmpty) return;
    AppPrefs.setString('lastDir.$toolKey', p.dirname(path));
  }
}
