import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'settings_service.dart';

/// File pickers that reopen in the folder last used by the same tool.
/// Only matters on desktop: Android's system picker manages its own
/// "recent" location and ignores a starting folder.
class FilePickers {
  /// Files dragged onto a tool (Windows); consumed by the next open call
  /// instead of showing the dialog.
  static List<XFile>? _dropped;
  static bool _droppedMatched = false;

  static void setDropped(List<XFile> files) {
    _dropped = files;
    _droppedMatched = false;
  }

  /// Clears pending dropped files; true if none of them fit the tool.
  static bool clearDropped() {
    final unmatched = _dropped != null && !_droppedMatched;
    _dropped = null;
    return unmatched;
  }

  static List<XFile>? _takeDropped(List<XTypeGroup> groups) {
    final dropped = _dropped;
    if (dropped == null) return null;
    _dropped = null;
    final exts = {
      for (final g in groups)
        for (final e in g.extensions ?? const <String>[]) '.${e.toLowerCase()}',
    };
    final matching = [
      for (final f in dropped)
        if (exts.isEmpty || exts.contains(p.extension(f.path).toLowerCase())) f,
    ];
    _droppedMatched = matching.isNotEmpty;
    return matching;
  }

  static Future<XFile?> openOne(String toolKey, List<XTypeGroup> groups) async {
    final dropped = _takeDropped(groups);
    if (dropped != null) return dropped.isEmpty ? null : dropped.first;
    final file = await openFile(
      acceptedTypeGroups: groups,
      initialDirectory: _initialDirectory(toolKey),
    );
    if (file != null) _remember(toolKey, file.path);
    return file;
  }

  static Future<List<XFile>> openMany(String toolKey, List<XTypeGroup> groups) async {
    final dropped = _takeDropped(groups);
    if (dropped != null) return dropped;
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
