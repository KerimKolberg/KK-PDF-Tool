import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/scan_document.dart';
import 'document_store.dart';
import 'signature_service.dart';

class BackupSummary {
  final File file;
  final int documents;
  final int bytes;
  const BackupSummary(this.file, this.documents, this.bytes);
}

class RestoreSummary {
  final int added;
  final int skipped;
  final int folders;
  final int signatures;
  const RestoreSummary({
    required this.added,
    required this.skipped,
    required this.folders,
    required this.signatures,
  });
}

/// Backs up the whole library (scans incl. folders and recognised text, plus
/// saved signatures) into one ZIP file, and restores such a file by merging
/// it into the library. Files are streamed one at a time and stored
/// uncompressed (scans are already compressed JPEG/PDF), so even a large
/// library doesn't need much memory.
///
/// ZIP layout: manifest.json, scans/... (the library folder), signatures/...
class BackupService {
  static const _app = 'KK-PDF-Tool';
  static const _format = 1;

  final DocumentStore store;
  final SignatureService signatures;

  BackupService(this.store, [SignatureService? signatures])
      : signatures = signatures ?? SignatureService();

  Future<BackupSummary> create({void Function(double progress)? onProgress}) async {
    final scans = await store.rootDirectory;
    final signatureDir = await signatures.directory;
    final docs = await store.loadAll();

    final outDir = Directory(p.join((await getTemporaryDirectory()).path, 'backup'));
    if (await outDir.exists()) await outDir.delete(recursive: true);
    await outDir.create(recursive: true);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final zipPath = p.join(
      outDir.path,
      'KK-PDF-Tool-Sicherung_${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}-${two(now.minute)}.zip',
    );

    final entries = <(File, String)>[];
    for (final dir in [scans, signatureDir]) {
      if (!await dir.exists()) continue;
      final top = p.basename(dir.path);
      await for (final e in dir.list(recursive: true)) {
        if (e is! File) continue;
        final relative = p.split(p.relative(e.path, from: dir.path));
        entries.add((e, p.posix.joinAll([top, ...relative])));
      }
    }

    final encoder = ZipFileEncoder()..create(zipPath);
    try {
      encoder.addArchiveFile(ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'app': _app,
          'format': _format,
          'createdAt': now.toIso8601String(),
          'documents': docs.length,
        }),
      ));
      for (var i = 0; i < entries.length; i++) {
        final (file, name) = entries[i];
        final input = InputFileStream(file.path);
        try {
          encoder.addArchiveFile(
            ArchiveFile.stream(name, input)
              ..compression = CompressionType.none
              ..lastModTime = (await file.lastModified()).millisecondsSinceEpoch ~/ 1000,
          );
        } finally {
          await input.close();
        }
        onProgress?.call((i + 1) / entries.length);
        await Future<void>.delayed(Duration.zero); // keep the UI responsive
      }
    } finally {
      await encoder.close();
    }
    final zip = File(zipPath);
    return BackupSummary(zip, docs.length, await zip.length());
  }

  /// Merges a backup into the library; documents that already exist (same
  /// id) are kept as they are, so nothing in the library is overwritten.
  Future<RestoreSummary> restore(File zip) async {
    final work = Directory(p.join((await getTemporaryDirectory()).path, 'restore'));
    if (await work.exists()) await work.delete(recursive: true);
    await work.create(recursive: true);

    try {
      final input = InputFileStream(zip.path);
      try {
        final Archive archive;
        try {
          archive = ZipDecoder().decodeStream(input);
        } catch (_) {
          throw const FormatException('Die Datei ist keine gültige ZIP-Sicherung.');
        }
        final manifestEntry = archive.find('manifest.json');
        final manifestBytes = manifestEntry?.readBytes();
        if (manifestBytes == null) {
          throw const FormatException('Diese Datei ist keine KK-PDF-Tool-Sicherung.');
        }
        final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
        if (manifest['app'] != _app) {
          throw const FormatException('Diese Datei ist keine KK-PDF-Tool-Sicherung.');
        }
        if ((manifest['format'] as int? ?? 0) > _format) {
          throw const FormatException(
            'Diese Sicherung stammt aus einer neueren App-Version - bitte zuerst die App aktualisieren.',
          );
        }
        // Path traversal ("../") entries are skipped by extractArchiveToDisk.
        await extractArchiveToDisk(archive, work.path);
      } finally {
        await input.close();
      }

      final scans = Directory(p.join(work.path, 'scans'));
      final indexFile = File(p.join(scans.path, 'index.json'));
      final docs = await indexFile.exists()
          ? [
              for (final e in jsonDecode(await indexFile.readAsString()) as List)
                ScanDocument.fromJson(e as Map<String, dynamic>),
            ]
          : <ScanDocument>[];
      final imported = await store.importDocuments(scans, docs);

      var folders = 0;
      final foldersFile = File(p.join(scans.path, 'folders.json'));
      if (await foldersFile.exists()) {
        final existing = (await store.loadFolders()).toSet();
        for (final name in (jsonDecode(await foldersFile.readAsString()) as List).cast<String>()) {
          if (existing.add(name)) {
            await store.addFolder(name);
            folders++;
          }
        }
      }
      final sigs = await signatures.importFrom(Directory(p.join(work.path, 'signatures')));
      DocumentStore.changes.value++;
      return RestoreSummary(
        added: imported.added,
        skipped: imported.skipped,
        folders: folders,
        signatures: sigs,
      );
    } finally {
      if (await work.exists()) await work.delete(recursive: true);
    }
  }
}
