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
///   scans/`<id>`/page_0.jpg ...        - processed page images
///   scans/`<id>`/document.pdf          - generated multi-page PDF
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
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final dir = await documentDir(id);

    for (var i = 0; i < pageJpegBytes.length; i++) {
      final f = File(p.join(dir.path, 'page_$i.jpg'));
      await f.writeAsBytes(pageJpegBytes[i], flush: true);
    }
    final pdfFile = File(p.join(dir.path, 'document.pdf'));
    await pdfFile.writeAsBytes(pdfBytes, flush: true);

    final doc = ScanDocument(
      id: id,
      title: title,
      createdAt: DateTime.now(),
      pageCount: pageJpegBytes.length,
    );

    final all = await loadAll();
    all.add(doc);
    await _writeIndex(all);
    return doc;
  }

  Future<void> rename(String id, String newTitle) async {
    final all = await loadAll();
    final idx = all.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    all[idx] = all[idx].copyWith(title: newTitle);
    await _writeIndex(all);
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
