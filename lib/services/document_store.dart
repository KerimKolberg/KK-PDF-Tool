import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/scan_document.dart';

/// Manages persistence of scanned documents on disk.
///
/// Layout inside the app documents directory:
///   scans/index.json                   - list of document metadata
///   scans/folders.json                 - folder names (incl. empty ones)
///   scans/`<id>`/page_0.jpg ...        - processed page images
///   scans/`<id>`/document.pdf          - generated multi-page PDF
///   scans/`<id>`/text.txt              - recognised text (OCR), if any
class DocumentStore {
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
    String? folder,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await _writeContent(id, pageJpegBytes, pdfBytes, text);

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
  }) async {
    final dir = await documentDir(id);
    await for (final entity in dir.list()) {
      if (entity is File && p.basename(entity.path).startsWith('page_')) {
        await entity.delete();
      }
    }
    await _writeContent(id, pageJpegBytes, pdfBytes, text);

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
  ) async {
    final dir = await documentDir(id);
    for (var i = 0; i < pageJpegBytes.length; i++) {
      final f = File(p.join(dir.path, 'page_$i.jpg'));
      await f.writeAsBytes(pageJpegBytes[i], flush: true);
    }
    final pdfFile = File(p.join(dir.path, 'document.pdf'));
    await pdfFile.writeAsBytes(pdfBytes, flush: true);
    await writeText(id, text);
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
