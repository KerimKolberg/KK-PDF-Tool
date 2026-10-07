import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'app_paths.dart';

/// Saved signatures (transparent PNGs) in `<app documents>/signatures/`,
/// plus stamping one onto a page image.
class SignatureService {
  Future<Directory> get _dir async {
    final base = await appDataDirectory();
    final dir = Directory(p.join(base.path, 'signatures'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Newest first.
  Future<List<File>> list() async {
    final dir = await _dir;
    final files = <File>[
      await for (final e in dir.list())
        if (e is File && e.path.toLowerCase().endsWith('.png')) e,
    ];
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<File> save(Uint8List png) async {
    final dir = await _dir;
    final file = File(p.join(dir.path, 'sig_${DateTime.now().millisecondsSinceEpoch}.png'));
    await file.writeAsBytes(png, flush: true);
    return file;
  }

  Future<void> delete(File file) async {
    if (await file.exists()) await file.delete();
  }

  /// The folder holding saved signatures (for backups).
  Future<Directory> get directory => _dir;

  /// Copies signature PNGs from a backup folder, skipping ones already
  /// present (same file name). Returns how many were added.
  Future<int> importFrom(Directory source) async {
    if (!await source.exists()) return 0;
    final dir = await _dir;
    var added = 0;
    await for (final entity in source.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.png')) continue;
      final target = File(p.join(dir.path, p.basename(entity.path)));
      if (await target.exists()) continue;
      await entity.copy(target.path);
      added++;
    }
    return added;
  }

  /// Draws [signaturePng] onto [pageBytes]. Position and width are fractions
  /// of the page (0..1); the height follows the signature's aspect ratio.
  static Future<Uint8List> stamp({
    required Uint8List pageBytes,
    required Uint8List signaturePng,
    required double leftFrac,
    required double topFrac,
    required double widthFrac,
  }) {
    return compute(_stampIsolate, {
      'page': pageBytes,
      'signature': signaturePng,
      'left': leftFrac,
      'top': topFrac,
      'width': widthFrac,
    });
  }
}

Uint8List _stampIsolate(Map<String, dynamic> args) {
  final decodedPage = img.decodeImage(args['page'] as Uint8List);
  final decodedSig = img.decodeImage(args['signature'] as Uint8List);
  if (decodedPage == null || decodedSig == null) {
    throw const FormatException('Bild konnte nicht gelesen werden');
  }
  // JPEG pages decode to 3 channels; blending a transparent PNG needs the
  // destination to be a regular RGB image, which this guarantees.
  final page = img.bakeOrientation(decodedPage).convert(numChannels: 3);
  final targetWidth = ((args['width'] as double) * page.width).round().clamp(8, page.width);
  final sig = img.copyResize(
    decodedSig.convert(numChannels: 4),
    width: targetWidth,
    interpolation: img.Interpolation.average,
  );
  img.compositeImage(
    page,
    sig,
    dstX: ((args['left'] as double) * page.width).round(),
    dstY: ((args['top'] as double) * page.height).round(),
  );
  return img.encodeJpg(page, quality: 92);
}
