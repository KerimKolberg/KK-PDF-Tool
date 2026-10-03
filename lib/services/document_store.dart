import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/ocr_result.dart';
import '../models/scan_document.dart';

/// Manages persistence of scanned documents on disk.
///
/// Layout inside the app documents directory:
///   scans/index.json                   - list of document metadata
///   scans/folders.json                 - folder names (incl. empty ones)
///   scans/`<id>`/page_0.jpg ...        - processed page images
///   scans/`<id>`/document.pdf          - generated multi-page PDF
///   scans/`<id>`/text.txt              - recognised text (OCR), if any
///   scans/`<id>`/ocr.json              - OCR line positions per page, if any
class DocumentStore {
  /// Bumped on every change to the library index, so screens that stay
  /// open (the library tab) can refresh, e.g. after a restore in Settings.
  static final changes = ValueNotifier<int>(0);

  /// Only ids like the ones this app creates are accepted from a backup
  /// (they become folder names).
  static final _validId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  Directory? _scansDir;

  Future<Directory> get _root async {
    if (_scansDir != null) return _scansDir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'scans'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _scansDir = dir;
    return dir;
  }

  Future<File> get _indexFile async {
    final root = await _root;
    return File(p.join(root.path, 'index.json'));
  }

  Future<List<ScanDocument>> loadAll() async {
    final file = await _indexFile;
    if (!await file.exists()) return [];
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    final docs = list
        .map((e) => ScanDocument.fromJson(e as Map<String, dynamic>))
        .toList();
    docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return docs;
  }

  Future<void> _writeIndex(List<ScanDocument> docs) async {
    final file = await _indexFile;
    final raw = jsonEncode(docs.map((d) => d.toJson()).toList());
    await file.writeAsString(raw);
    changes.value++;
  }

  /// The library's own folder (for backups).
  Future<Directory> get rootDirectory => _root;

  /// Moves documents from an extracted backup ([sourceScans] is its "scans"
  /// folder) into the library. Documents already in the library (same id)
  /// are skipped, so restoring the same backup twice is harmless.
  Future<({int added, int skipped})> importDocuments(
    Directory sourceScans,
    List<ScanDocument> docs,
  ) async {
    final root = await _root;
    final all = await loadAll();
    final existing = {for (final d in all) d.id};
    var added = 0;
    var skipped = 0;
    for (final doc in docs) {
      final src = Directory(p.join(sourceScans.path, doc.id));
      if (!_validId.hasMatch(doc.id) || existing.contains(doc.id) || !await src.exists()) {
        skipped++;
        continue;
      }
      final dst = Directory(p.join(root.path, doc.id));
      try {
        await src.rename(dst.path);
      } on FileSystemException {
        // Different drive/volume: copy instead of move.
        await _copyDirectory(src, dst);
      }
      all.add(doc);
      existing.add(doc.id);
      added++;
    }
    if (added > 0) await _writeIndex(all);
    return (added: added, skipped: skipped);
  }

  static Future<void> _copyDirectory(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list()) {
      final target = p.join(dst.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(target);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      }
    }
  }

  Future<Directory> documentDir(String id) async {
    final root = await _root;
    final dir = Directory(p.join(root.path, id));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> pdfPath(String id) async {
    final dir = await documentDir(id);
    return p.join(dir.path, 'document.pdf');
  }

  Future<List<File>> pageFiles(String id, int pageCount) async {
    final dir = await documentDir(id);
    return List.generate(
      pageCount,
      (i) => File(p.join(dir.path, 'page_$i.jpg')),
    );
  }

  /// Creates a new document from processed page JPEG bytes and a
  /// pre-rendered PDF, writing everything to disk and updating the index.
  Future<ScanDocument> createDocument({
    required String title,
    required List<Uint8List> pageJpegBytes,
    required Uint8List pdfBytes,
    String? text,
    List<OcrResult?>? ocr,
    String? folder,
  }) async {
    // Batch scans create documents in quick succession; make sure two never
    // share an id (= folder).
    var id = DateTime.now().microsecondsSinceEpoch.toString();
    while (await Directory(p.join((await _root).path, id)).exists()) {
      id = '${int.parse(id) + 1}';
    }
    await _writeContent(id, pageJpegBytes, pdfBytes, text, ocr);

    final doc = ScanDocument(
      id: id,
      title: title,
      createdAt: DateTime.now(),
      pageCount: pageJpegBytes.length,
      folder: folder,
    );

    final all = await loadAll();
    all.add(doc);
    await _writeIndex(all);
    return doc;
  }

  /// Replaces all pages, the PDF and the recognised text of an existing
  /// document (after reordering/deleting/adding pages or signing).
  Future<ScanDocument> replaceContent(
    String id, {
    required List<Uint8List> pageJpegBytes,
    required Uint8List pdfBytes,
    String? text,
    List<OcrResult?>? ocr,
  }) async {
    final dir = await documentDir(id);
    await for (final entity in dir.list()) {
      if (entity is File && p.basename(entity.path).startsWith('page_')) {
        await entity.delete();
      }
    }
    await _writeContent(id, pageJpegBytes, pdfBytes, text, ocr);

    final all = await loadAll();
    final idx = all.indexWhere((d) => d.id == id);
    final updated = all[idx].copyWith(pageCount: pageJpegBytes.length);
    all[idx] = updated;
    await _writeIndex(all);
    return updated;
  }

  Future<void> _writeContent(
    String id,
    List<Uint8List> pageJpegBytes,
    Uint8List pdfBytes,
    String? text,
    List<OcrResult?>? ocr,
  ) async {
    final dir = await documentDir(id);
    for (var i = 0; i < pageJpegBytes.length; i++) {
      final f = File(p.join(dir.path, 'page_$i.jpg'));
      await f.writeAsBytes(pageJpegBytes[i], flush: true);
    }
    final pdfFile = File(p.join(dir.path, 'document.pdf'));
    await pdfFile.writeAsBytes(pdfBytes, flush: true);
    await writeText(id, text);
    await _writeOcr(id, ocr);
  }

  /// Per-page OCR line positions (same order as the pages), used to rebuild
  /// a searchable PDF (e.g. a smaller copy for sharing) without running text
  /// recognition again. Null when the document has none or it's unreadable.
  Future<List<OcrResult?>?> readOcr(String id) async {
    final file = File(p.join((await documentDir(id)).path, 'ocr.json'));
    if (!await file.exists()) return null;
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      return [
        for (final e in list) e == null ? null : OcrResult.fromMap(e as Map),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeOcr(String id, List<OcrResult?>? ocr) async {
    final file = File(p.join((await documentDir(id)).path, 'ocr.json'));
    if (ocr == null || ocr.every((r) => r == null)) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(jsonEncode([for (final r in ocr) r?.toMap()]), flush: true);
  }

  Future<String?> readText(String id) async {
    final file = File(p.join((await documentDir(id)).path, 'text.txt'));
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// Stores the recognised text (used for library search); null/blank
  /// removes it.
  Future<void> writeText(String id, String? text) async {
    final file = File(p.join((await documentDir(id)).path, 'text.txt'));
    if (text == null || text.trim().isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(text, flush: true);
  }

  Future<void> rename(String id, String newTitle) async {
    final all = await loadAll();
    final idx = all.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    all[idx] = all[idx].copyWith(title: newTitle);
    await _writeIndex(all);
  }

  Future<void> moveToFolder(String id, String? folder) async {
    final all = await loadAll();
    final idx = all.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    all[idx] = all[idx].copyWith(folder: folder);
    await _writeIndex(all);
  }

  Future<File> get _foldersFile async =>
      File(p.join((await _root).path, 'folders.json'));

  /// All folder names: explicitly created ones plus any referenced by a
  /// document, sorted alphabetically.
  Future<List<String>> loadFolders() async {
    final names = <String>{};
    final file = await _foldersFile;
    if (await file.exists()) {
      final raw = await file.readAsString();
      if (raw.trim().isNotEmpty) {
        names.addAll((jsonDecode(raw) as List).cast<String>());
      }
    }
    for (final doc in await loadAll()) {
      if (doc.folder != null) names.add(doc.folder!);
    }
    return names.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<void> _writeFolders(List<String> names) async {
    final file = await _foldersFile;
    await file.writeAsString(jsonEncode(names));
  }

  Future<void> addFolder(String name) async {
    final folders = await loadFolders();
    if (!folders.contains(name)) folders.add(name);
    await _writeFolders(folders);
  }

  Future<void> renameFolder(String oldName, String newName) async {
    final folders = await loadFolders()
      ..remove(oldName);
    if (!folders.contains(newName)) folders.add(newName);
    await _writeFolders(folders);
    final all = await loadAll();
    await _writeIndex([
      for (final d in all) d.folder == oldName ? d.copyWith(folder: newName) : d,
    ]);
  }

  /// Deletes the folder only; its documents stay, just without a folder.
  Future<void> deleteFolder(String name) async {
    final folders = await loadFolders()
      ..remove(name);
    await _writeFolders(folders);
    final all = await loadAll();
    await _writeIndex([
      for (final d in all) d.folder == name ? d.copyWith(folder: null) : d,
    ]);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((d) => d.id == id);
    await _writeIndex(all);
    final dir = await documentDir(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
