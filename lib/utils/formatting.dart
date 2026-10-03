/// Small helpers shared by several screens.
library;

/// "512 KB" / "1,4 MB" (German decimal comma).
String formatFileSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// The folder part of a saved file's location (for "saved in …" messages).
String folderOf(String location) {
  final idx = location.lastIndexOf(RegExp(r'[\\/]'));
  return idx == -1 ? location : location.substring(0, idx);
}

/// Parses a page spec like "1-3,5,8-9" (1-based, as typed by a user) into
/// 0-based page indices. Returns null (meaning "all pages") for blank input.
Set<int>? parsePageSpec(String spec) {
  final trimmed = spec.trim();
  if (trimmed.isEmpty) return null;
  final indices = <int>{};
  for (final part in trimmed.split(',')) {
    final range = part.trim().split('-');
    if (range.length == 1) {
      final n = int.tryParse(range[0].trim());
      if (n != null && n >= 1) indices.add(n - 1);
    } else if (range.length == 2) {
      final start = int.tryParse(range[0].trim());
      final end = int.tryParse(range[1].trim());
      if (start != null && end != null && start >= 1 && end >= start) {
        for (var i = start; i <= end; i++) {
          indices.add(i - 1);
        }
      }
    }
  }
  return indices;
}
