import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n.dart';

/// Deletes picked source files after a successful conversion, when the user
/// opted in via [DeleteOriginalsSwitch].
///
/// Skips any path inside the app's own cache/temp directory without error:
/// on Android, `file_selector` sometimes hands back a *copy* of a picked
/// file there instead of its real path (e.g. for files from cloud-backed
/// pickers like Google Photos), and deleting that copy wouldn't touch the
/// actual original - silently "succeeding" while leaving it untouched would
/// be worse than just not deleting it.
class OriginalFilesCleanupService {
  /// Returns the paths that were skipped or failed to delete, so the caller
  /// can tell the user their originals weren't all removed.
  static Future<List<String>> deleteAll(Iterable<String?> paths) async {
    final cacheDir = (await getTemporaryDirectory()).path;
    final notDeleted = <String>[];
    for (final path in {...paths}) {
      if (path == null || path.isEmpty || p.isWithin(cacheDir, path)) {
        if (path != null && path.isNotEmpty) notDeleted.add(path);
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        notDeleted.add(path);
      }
    }
    return notDeleted;
  }

  /// Deletes [paths] and returns the note to append to the "saved" message
  /// when some of them could not be removed (empty if all are gone).
  static Future<String> deleteAndDescribe(List<String?> paths) async {
    final notDeleted = await deleteAll(paths);
    if (notDeleted.isEmpty) return '';
    return paths.length == 1
        ? tr(' · Original konnte nicht gelöscht werden', ' · Original could not be deleted')
        : tr(
            ' · ${notDeleted.length} Original(e) konnten nicht gelöscht werden',
            ' · ${notDeleted.length} original(s) could not be deleted',
          );
  }
}
