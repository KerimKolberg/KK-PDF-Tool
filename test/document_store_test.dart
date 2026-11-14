import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:doc_scanner/services/backup_service.dart';
import 'package:doc_scanner/services/document_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/fake_paths.dart';

final _page = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]);
final _pdf = Uint8List.fromList(utf8.encode('%PDF-test'));

void main() {
  late DocumentStore store;
  late Directory scans;

  setUpAll(() async {
    FakePaths.install();
    store = DocumentStore();
    scans = await store.rootDirectory;
  });

  setUp(() async {
    // Start every test with an empty library.
    await for (final e in scans.list()) {
      await e.delete(recursive: true);
    }
  });

  File index() => File(p.join(scans.path, 'index.json'));

  test('create, rename, move and delete keep the index in step', () async {
    final doc = await store.createDocument(title: 'A', pageJpegBytes: [_page, _page], pdfBytes: _pdf, text: 'hello');
    expect((await store.loadAll()).single.pageCount, 2);
    expect(await store.readText(doc.id), 'hello');

    await store.rename(doc.id, 'B');
    await store.moveToFolder(doc.id, 'Work');
    final loaded = (await store.loadAll()).single;
    expect((loaded.title, loaded.folder), ('B', 'Work'));
    expect(await store.loadFolders(), ['Work']);

    await store.delete(doc.id);
    expect(await store.loadAll(), isEmpty);
    expect(await Directory(p.join(scans.path, doc.id)).exists(), isFalse);
  });

  test('reading from a deleted document does not recreate its folder', () async {
    final doc = await store.createDocument(title: 'A', pageJpegBytes: [_page], pdfBytes: _pdf);
    await store.delete(doc.id);
    await store.readText(doc.id);
    await store.pageFiles(doc.id, 1);
    expect(await Directory(p.join(scans.path, doc.id)).exists(), isFalse);
  });

  test('changes made at the same time do not overwrite each other', () async {
    final docs = await Future.wait([
      for (var i = 0; i < 8; i++) store.createDocument(title: 'Doc $i', pageJpegBytes: [_page], pdfBytes: _pdf),
    ]);
    await Future.wait([
      for (final (i, d) in docs.indexed) i.isEven ? store.rename(d.id, 'Renamed $i') : store.moveToFolder(d.id, 'F$i'),
    ]);
    final all = await store.loadAll();
    expect(all, hasLength(8));
    expect(all.where((d) => d.title.startsWith('Renamed')), hasLength(4));
    expect(all.where((d) => d.folder != null), hasLength(4));
  });

  test('a damaged index falls back to the previous version', () async {
    await store.createDocument(title: 'First', pageJpegBytes: [_page], pdfBytes: _pdf);
    await store.createDocument(title: 'Second', pageJpegBytes: [_page], pdfBytes: _pdf);
    await index().writeAsString('{ not json');
    // The .bak copy is the index before the last change.
    expect((await store.loadAll()).map((d) => d.title), ['First']);
  });

  test('without any readable index the list is rebuilt from the folders', () async {
    final doc = await store.createDocument(title: 'Lost', pageJpegBytes: [_page, _page, _page], pdfBytes: _pdf);
    await index().writeAsString('');
    await File('${index().path}.bak').writeAsString('garbage');
    final rebuilt = (await store.loadAll()).single;
    expect((rebuilt.id, rebuilt.pageCount), (doc.id, 3));
  });

  group('backup', () {
    test('round trip restores documents, folders and text; twice is harmless', () async {
      final doc = await store.createDocument(
        title: 'Vertrag', pageJpegBytes: [_page], pdfBytes: _pdf, text: 'Miete', folder: 'Wohnung');
      await store.addFolder('Leer');
      final backup = await BackupService(store).create();
      expect(backup.documents, 1);

      await store.delete(doc.id);
      await store.deleteFolder('Wohnung');
      await store.deleteFolder('Leer');

      final first = await BackupService(store).restore(backup.file);
      expect((first.added, first.skipped), (1, 0));
      final restored = (await store.loadAll()).single;
      expect((restored.title, restored.folder), ('Vertrag', 'Wohnung'));
      expect(await store.readText(restored.id), 'Miete');
      expect(await store.loadFolders(), containsAll(['Leer', 'Wohnung']));

      final second = await BackupService(store).restore(backup.file);
      expect((second.added, second.skipped), (0, 1));
    });

    test('rejects foreign zips and document ids that are not plain names', () async {
      final temp = Directory.systemTemp.createTempSync('zips');
      File zipOf(Map<String, String> files) {
        final archive = Archive();
        files.forEach((name, content) => archive.addFile(ArchiveFile.string(name, content)));
        return File(p.join(temp.path, '${files.length}-${files.keys.first.hashCode}.zip'))
          ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      }

      await expectLater(
        BackupService(store).restore(zipOf({'readme.txt': 'hi'})),
        throwsA(isA<FormatException>()),
      );

      final evil = zipOf({
        'manifest.json': jsonEncode({'app': 'KK-PDF-Tool', 'format': 1}),
        'scans/index.json': jsonEncode([
          {'id': '../../escape', 'title': 'x', 'createdAt': DateTime(2026).toIso8601String(), 'pageCount': 1},
        ]),
        'scans/../../escape/document.pdf': 'x',
      });
      final summary = await BackupService(store).restore(evil);
      expect((summary.added, summary.skipped), (0, 1));
      expect(await store.loadAll(), isEmpty);
      expect(await Directory(p.join(scans.parent.parent.path, 'escape')).exists(), isFalse);
    });
  });
}
