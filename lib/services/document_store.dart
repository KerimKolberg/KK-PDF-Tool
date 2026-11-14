import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/ocr_result.dart';
import '../models/scan_document.dart';
import 'app_paths.dart';

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
    final base = await appDataDirectory();
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

  /// All changes to the index run one after another through this queue, so
  /// two of them (e.g. a batch save and a rename) can never overwrite each
  /// other's result. Shared by all [DocumentStore] instances.
  static Future<void> _queue = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// All documents, newest first.
  ///
  /// The index is written atomically with the previous version kept as
  /// `index.json.bak`. Should the index still be unreadable (e.g. the disk
  /// was full), the backup copy is used; as a last resort the list is
  /// rebuilt from the document folders, so scans are never "lost" just
  /// because the list of them is damaged.
  Future<List<ScanDocument>> loadAll() async {
    final file = await _indexFile;
    final backup = File('${file.path}.bak');
    if (!await file.exists() && !await backup.exists()) return [];
    final docs = await _readIndex(file) ?? await _readIndex(backup) ?? await _rebuildIndex();
    docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return docs;
  }

  /// Null when [file] is missing, empty or not a valid index.
  static Future<List<ScanDocument>?> _readIndex(File file) async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return [
        for (final e in jsonDecode(raw) as List) ScanDocument.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Recreates the document list from the folders on disk.
  Future<List<ScanDocument>> _rebuildIndex() async {
    final root = await _root;
    final docs = <ScanDocument>[];
    await for (final entity in root.list()) {
      final id = p.basename(entity.path);
      if (entity is! Directory || !_validId.hasMatch(id)) continue;
      if (!await File(p.join(entity.path, 'document.pdf')).exists()) continue;
      var pages = 0;
      while (await File(p.join(entity.path, 'page_$pages.jpg')).exists()) {
        pages++;
      }
      final micros = int.tryParse(id);
      final created = micros != null
          ? DateTime.fromMicrosecondsSinceEpoch(micros)
          : (await entity.stat()).modified;
      docs.add(ScanDocument(
        id: id,
        title: 'Scan ${created.year}-${_two(created.month)}-${_two(created.day)} '
            '${_two(created.hour)}:${_two(created.minute)}',
        createdAt: created,
        pageCount: pages,
      ));
    }
    return docs;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _writeIndex(List<ScanDocument> docs) async {
    await _writeAtomically(await _indexFile, jsonEncode([for (final d in docs) d.toJson()]));
    changes.value++;
  }

  /// Writes to a temporary file first and then swaps it in, keeping the
  /// previous version as `.bak` - a crash or full disk in the middle of
  /// writing can't leave a half-written file behind.
  static Future<void> _writeAtomically(File file, String content) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(content, flush: true);
    if (await file.exists()) await file.rename('${file.path}.bak');
    await temp.rename(file.path);
  }

  /// The library's own folder (for backups).
  Future<Directory> get rootDirectory => _root;

  /// Moves documents from an extracted backup ([sourceScans] is its "scans"
  /// folder) into the library. Documents already in the library (same id)
  /// are skipped, so restoring the same backup twice is harmless.
  Future<({int added, int skipped})> importDocuments(
    Directory sourceScans,
    List<ScanDocument> docs,
  ) =>
      _serialized(() => _importDocuments(sourceScans, docs));

  Future<({int added, int skipped})> _importDocuments(
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

  /// The folder of document [id]. Not created here: reading something of
  /// a document that no longer exists must not bring its folder back.
  Future<Directory> documentDir(String id) async {
    final root = await _root;
    return Directory(p.join(root.path, id));
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

    await _updateIndex((all) => all..add(doc));
    return doc;
  }

  /// Loads the index, applies [change] and saves it - as one step that
  /// can't interleave with another change.
  Future<void> _updateIndex(List<ScanDocument> Function(List<ScanDocument> all) change) =>
      _serialized(() async => _writeIndex(change(await loadAll())));

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
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && p.basename(entity.path).startsWith('page_')) {
          await entity.delete();
        }
      }
    }
    await _writeContent(id, pageJpegBytes, pdfBytes, text, ocr);

    late ScanDocument updated;
    await _updateIndex((all) {
      final idx = all.indexWhere((d) => d.id == id);
      if (idx == -1) throw StateError('Document $id no longer exists');
      updated = all[idx].copyWith(pageCount: pageJpegBytes.length);
      return all..[idx] = updated;
    });
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
    await dir.create(recursive: true);
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

  Future<void> rename(String id, String newTitle) => _updateIndex((all) => [
        for (final d in all) d.id == id ? d.copyWith(title: newTitle) : d,
      ]);

  Future<void> moveToFolder(String id, String? folder) => _updateIndex((all) => [
        for (final d in all) d.id == id ? d.copyWith(folder: folder) : d,
      ]);

  Future<File> get _foldersFile async =>
      File(p.join((await _root).path, 'folders.json'));

  /// All folder names: explicitly created ones plus any referenced by a
  /// document, sorted alphabetically.
  /// Pass [docs] when already loaded to avoid reading the index twice.
  Future<List<String>> loadFolders({List<ScanDocument>? docs}) async {
    final names = <String>{};
    final file = await _foldersFile;
    if (await file.exists()) {
      final raw = await file.readAsString();
      if (raw.trim().isNotEmpty) {
        names.addAll((jsonDecode(raw) as List).cast<String>());
      }
    }
    for (final doc in docs ?? await loadAll()) {
      if (doc.folder != null) names.add(doc.folder!);
    }
    return names.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<void> _writeFolders(List<String> names) async =>
      _writeAtomically(await _foldersFile, jsonEncode(names));

  Future<void> addFolder(String name) => _serialized(() async {
        final folders = await loadFolders();
        if (!folders.contains(name)) folders.add(name);
        await _writeFolders(folders);
      });

  Future<void> renameFolder(String oldName, String newName) => _serialized(() async {
        final all = await loadAll();
        final folders = await loadFolders(docs: all)
          ..remove(oldName);
        if (!folders.contains(newName)) folders.add(newName);
        await _writeFolders(folders);
        await _writeIndex([
          for (final d in all) d.folder == oldName ? d.copyWith(folder: newName) : d,
        ]);
      });

  /// Deletes the folder only; its documents stay, just without a folder.
  Future<void> deleteFolder(String name) => _serialized(() async {
        final all = await loadAll();
        final folders = await loadFolders(docs: all)
          ..remove(name);
        await _writeFolders(folders);
        await _writeIndex([
          for (final d in all) d.folder == name ? d.copyWith(folder: null) : d,
        ]);
      });

  Future<void> delete(String id) async {
    await _updateIndex((all) => all..removeWhere((d) => d.id == id));
    final dir = await documentDir(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
