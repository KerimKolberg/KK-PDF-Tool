import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as rx;

import 'pdf_service.dart';
import 'pptx_writer_service.dart';

enum PageNumberFormat {
  plain('1'),
  seite('Seite 1'),
  seiteVon('Seite 1 von 5'),
  slash('1 / 5');

  final String example;
  const PageNumberFormat(this.example);

  String format(int number, int total) => switch (this) {
        PageNumberFormat.plain => '$number',
        PageNumberFormat.seite => 'Seite $number',
        PageNumberFormat.seiteVon => 'Seite $number von $total',
        PageNumberFormat.slash => '$number / $total',
      };
}

enum PageNumberPosition {
  bottomCenter('Unten Mitte'),
  bottomRight('Unten rechts'),
  topRight('Oben rechts');

  final String label;
  const PageNumberPosition(this.label);
}

/// PDF manipulation on top of PDFium (via pdfrx).
///
/// Merging, splitting and rotating copy the original pages unchanged: text
/// stays text, nothing gets re-rendered, and the files stay small. The
/// tools that draw onto pages (watermark, page numbers, crop, compress)
/// work on page renders, but every page keeps its original size - slides
/// stay slides instead of being put onto A4.
class PdfToolsService {
  static Future<void>? _engine;
  static int _docCounter = 0;

  static Future<void> _ensureEngine() => _engine ??= rx.pdfrxFlutterInitialize();

  static String _newName(String prefix) => '$prefix-${_docCounter++}';

  /// Opens [pdfBytes], runs [action] on it and disposes the document again.
  static Future<T> _withDocument<T>(
    Uint8List pdfBytes,
    Future<T> Function(rx.PdfDocument doc) action,
  ) async {
    await _ensureEngine();
    final doc = await rx.PdfDocument.openData(pdfBytes, sourceName: _newName('in'));
    try {
      return await action(doc);
    } finally {
      await doc.dispose();
    }
  }

  /// Writes [pages] (from documents that are still open) into a new PDF.
  static Future<Uint8List> _encodePages(List<rx.PdfPage> pages) async {
    final out = await rx.PdfDocument.createNew(sourceName: _newName('out'));
    try {
      out.pages = pages;
      return await out.encodePdf();
    } finally {
      await out.dispose();
    }
  }

  /// Renders [pages] (0-based indices; all pages when omitted) of [pdfBytes]
  /// to PNG images at [dpi].
  static Future<List<Uint8List>> rasterPages(
    Uint8List pdfBytes, {
    List<int>? pages,
    double dpi = 150,
  }) {
    return _withDocument(pdfBytes, (doc) async {
      final all = doc.pages;
      final images = <Uint8List>[];
      for (final index in pages ?? [for (var i = 0; i < all.length; i++) i]) {
        if (index < 0 || index >= all.length) continue;
        images.add(await _renderPng(all[index], dpi));
      }
      return images;
    });
  }

  static Future<Uint8List> _renderPng(rx.PdfPage page, double dpi) async {
    final raw = await page.render(
      fullWidth: page.width * dpi / 72,
      fullHeight: page.height * dpi / 72,
      backgroundColor: 0xffffffff,
    );
    if (raw == null) {
      throw StateError('Seite ${page.pageNumber} konnte nicht gelesen werden');
    }
    try {
      final image = await raw.createImage();
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        return png!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      raw.dispose();
    }
  }

  /// The size of every page of [pdfBytes], as displayed (rotation applied).
  static Future<List<PdfPageFormat>> pageFormats(Uint8List pdfBytes) {
    return _withDocument(pdfBytes, (doc) async => [
          for (final page in doc.pages) PdfPageFormat(page.width, page.height),
        ]);
  }

  /// Total page count of [pdfBytes].
  static Future<int> countPages(Uint8List pdfBytes) {
    return _withDocument(pdfBytes, (doc) async => doc.pages.length);
  }

  /// Concatenates all pages of [pdfs], in order, into a single new PDF.
  /// The pages are copied as they are, not re-rendered.
  static Future<Uint8List> merge(List<Uint8List> pdfs) async {
    await _ensureEngine();
    final sources = <rx.PdfDocument>[];
    try {
      for (final pdf in pdfs) {
        sources.add(await rx.PdfDocument.openData(pdf, sourceName: _newName('in')));
      }
      return await _encodePages([for (final source in sources) ...source.pages]);
    } finally {
      for (final source in sources) {
        await source.dispose();
      }
    }
  }

  /// Copies the inclusive 1-based page range [startPage]..[endPage] of
  /// [pdfBytes] into a new PDF, unchanged.
  static Future<Uint8List> extractRange(
    Uint8List pdfBytes, {
    required int startPage,
    required int endPage,
  }) {
    return _withDocument(
      pdfBytes,
      (doc) => _encodePages(doc.pages.sublist(startPage - 1, endPage)),
    );
  }

  /// Renders every page of [pdfBytes] and packs each one as a full-slide
  /// picture into a .pptx file (see [PptxWriterService] for why this is a
  /// mechanical image-per-slide export, not an editable reconstruction).
  static Future<Uint8List> toPptx(Uint8List pdfBytes) async {
    final images = await rasterPages(pdfBytes, dpi: 150);
    return compute(_buildPptxIsolate, images);
  }

  /// Re-renders the whole PDF at a lower resolution/JPEG quality to shrink
  /// its file size. Lossy, like every "PDF compressor" that doesn't have
  /// access to the original vector content.
  static Future<Uint8List> compress(
    Uint8List pdfBytes, {
    required double dpi,
    required int quality,
  }) async {
    final images = await rasterPages(pdfBytes, dpi: dpi);
    final formats = await pageFormats(pdfBytes);
    final jpegs = await compute(_reencodeJpegBatchIsolate, {
      'images': images,
      'quality': quality,
    });
    return PdfService.buildPdf(jpegs, pageFormats: formats);
  }

  /// Stamps [text] diagonally across every page (or just [pageIndices], if
  /// given; 0-based).
  static Future<Uint8List> addWatermark(
    Uint8List pdfBytes, {
    required String text,
    List<int>? pageIndices,
    double opacity = 0.35,
    double fontSize = 56,
  }) async {
    final images = await rasterPages(pdfBytes, dpi: 150);
    return compute(_buildWatermarkedPdfIsolate, {
      'images': images,
      'formats': _formatsArg(await pageFormats(pdfBytes)),
      'text': text,
      'pageIndices': pageIndices,
      'opacity': opacity,
      'fontSize': fontSize,
    });
  }

  /// Rotates [pageIndices] (0-based; all pages when omitted) of [pdfBytes]
  /// by [degrees] (90/180/270) clockwise; other pages are left untouched.
  /// Only the pages' rotation setting changes - the content is not
  /// re-rendered.
  static Future<Uint8List> rotatePages(
    Uint8List pdfBytes, {
    List<int>? pageIndices,
    required int degrees,
  }) {
    return _withDocument(pdfBytes, (doc) {
      final pages = doc.pages;
      return _encodePages([
        for (var i = 0; i < pages.length; i++)
          _isSelected(pageIndices, i) ? _rotated(pages[i], degrees) : pages[i],
      ]);
    });
  }

  static rx.PdfPage _rotated(rx.PdfPage page, int degrees) => switch (degrees % 360) {
        90 => page.rotatedCW90(),
        180 => page.rotated180(),
        270 => page.rotatedCCW90(),
        _ => page,
      };

  /// Crops [pageIndices] (0-based; all pages when omitted) of [pdfBytes] to
  /// the rectangle described by [leftFrac]/[topFrac]/[rightFrac]/[bottomFrac]
  /// (each 0..1, fraction of that page's width/height); other pages are
  /// left untouched.
  static Future<Uint8List> cropPages(
    Uint8List pdfBytes, {
    List<int>? pageIndices,
    required double leftFrac,
    required double topFrac,
    required double rightFrac,
    required double bottomFrac,
  }) async {
    final images = await rasterPages(pdfBytes, dpi: 150);
    final formats = [
      for (final (i, f) in (await pageFormats(pdfBytes)).indexed)
        _isSelected(pageIndices, i)
            ? PdfPageFormat(f.width * (rightFrac - leftFrac), f.height * (bottomFrac - topFrac))
            : f,
    ];
    final cropped = await compute(_cropBatchIsolate, {
      'images': images,
      'pageIndices': pageIndices,
      'left': leftFrac,
      'top': topFrac,
      'right': rightFrac,
      'bottom': bottomFrac,
    });
    return PdfService.buildPdf(cropped, pageFormats: formats);
  }

  /// Downscales each image so its longer side is at most [maxSide] and
  /// re-encodes it as JPEG at [quality]. One image at a time, to keep
  /// memory low for long documents.
  static Future<List<Uint8List>> shrinkImages(
    List<Uint8List> images, {
    required int maxSide,
    required int quality,
  }) async {
    return [
      for (final image in images)
        await compute(_shrinkIsolate, {'bytes': image, 'maxSide': maxSide, 'quality': quality}),
    ];
  }

  /// Re-encodes images (e.g. PNG page renders) as JPEGs, which are much
  /// smaller to store and embed.
  static Future<List<Uint8List>> toJpegs(
    List<Uint8List> images, {
    int quality = 90,
  }) {
    return compute(_reencodeJpegBatchIsolate, {
      'images': images,
      'quality': quality,
    });
  }

  /// Adds page numbers (when [numberFormat] is set) and an optional header
  /// (top centre) and footer (bottom left) text to every page.
  static Future<Uint8List> addPageNumbers(
    Uint8List pdfBytes, {
    PageNumberFormat? numberFormat,
    PageNumberPosition position = PageNumberPosition.bottomCenter,
    int startAt = 1,
    String header = '',
    String footer = '',
  }) async {
    final images = await rasterPages(pdfBytes, dpi: 150);
    return compute(_buildPageNumberedPdfIsolate, {
      'images': images,
      'formats': _formatsArg(await pageFormats(pdfBytes)),
      'format': numberFormat?.index,
      'position': position.index,
      'startAt': startAt,
      'header': header,
      'footer': footer,
    });
  }
}

/// Page sizes as plain numbers, to pass them into an isolate.
List<List<double>> _formatsArg(List<PdfPageFormat> formats) =>
    [for (final f in formats) [f.width, f.height]];

PdfPageFormat _formatFromArg(Map<String, dynamic> args, int index) {
  final formats = args['formats'] as List;
  if (index >= formats.length) return PdfPageFormat.a4;
  final size = formats[index] as List;
  return PdfPageFormat(size[0] as double, size[1] as double);
}

Future<Uint8List> _buildPageNumberedPdfIsolate(Map<String, dynamic> args) async {
  final images = (args['images'] as List).cast<Uint8List>();
  final formatIndex = args['format'] as int?;
  final position = PageNumberPosition.values[args['position'] as int];
  final startAt = args['startAt'] as int;
  final header = args['header'] as String;
  final footer = args['footer'] as String;
  final format = formatIndex == null ? null : PageNumberFormat.values[formatIndex];

  const style = pw.TextStyle(fontSize: 10, color: PdfColors.grey800);
  final numberAlignment = switch (position) {
    PageNumberPosition.bottomCenter => pw.Alignment.bottomCenter,
    PageNumberPosition.bottomRight => pw.Alignment.bottomRight,
    PageNumberPosition.topRight => pw.Alignment.topRight,
  };
  final total = images.length + startAt - 1;

  pw.Widget overlay(pw.Alignment alignment, String text) => pw.Positioned.fill(
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: pw.Align(alignment: alignment, child: pw.Text(text, style: style)),
        ),
      );

  final doc = pw.Document();
  for (var i = 0; i < images.length; i++) {
    final image = pw.MemoryImage(images[i]);
    doc.addPage(
      pw.Page(
        pageFormat: _formatFromArg(args, i),
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
            ),
            if (header.trim().isNotEmpty) overlay(pw.Alignment.topCenter, header.trim()),
            if (footer.trim().isNotEmpty) overlay(pw.Alignment.bottomLeft, footer.trim()),
            if (format != null) overlay(numberAlignment, format.format(startAt + i, total)),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

Uint8List _shrinkIsolate(Map<String, dynamic> args) {
  final decoded = img.decodeImage(args['bytes'] as Uint8List);
  if (decoded == null) throw const FormatException('Bild konnte nicht gelesen werden');
  final image = img.bakeOrientation(decoded);
  final maxSide = args['maxSide'] as int;
  final longer = image.width > image.height ? image.width : image.height;
  final resized = longer <= maxSide
      ? image
      : img.copyResize(
          image,
          width: image.width >= image.height ? maxSide : null,
          height: image.width < image.height ? maxSide : null,
          interpolation: img.Interpolation.average,
        );
  return img.encodeJpg(resized, quality: args['quality'] as int);
}

Uint8List _buildPptxIsolate(List<Uint8List> images) {
  return PptxWriterService.buildPptx(images);
}

List<Uint8List> _reencodeJpegBatchIsolate(Map<String, dynamic> args) {
  final images = (args['images'] as List).cast<Uint8List>();
  final quality = args['quality'] as int;
  return [
    for (final bytes in images)
      img.encodeJpg(img.decodeImage(bytes)!, quality: quality),
  ];
}

bool _isSelected(List<dynamic>? pageIndices, int index) {
  if (pageIndices == null || pageIndices.isEmpty) return true;
  return pageIndices.contains(index);
}

List<Uint8List> _cropBatchIsolate(Map<String, dynamic> args) {
  final images = (args['images'] as List).cast<Uint8List>();
  final pageIndices = args['pageIndices'] as List?;
  final left = args['left'] as double;
  final top = args['top'] as double;
  final right = args['right'] as double;
  final bottom = args['bottom'] as double;
  return [
    for (var i = 0; i < images.length; i++)
      if (_isSelected(pageIndices, i))
        _cropOne(images[i], left, top, right, bottom)
      else
        images[i],
  ];
}

Uint8List _cropOne(
  Uint8List bytes,
  double left,
  double top,
  double right,
  double bottom,
) {
  final image = img.decodeImage(bytes)!;
  final x = (left * image.width).round().clamp(0, image.width - 1);
  final y = (top * image.height).round().clamp(0, image.height - 1);
  final w = ((right - left) * image.width).round().clamp(1, image.width - x);
  final h = ((bottom - top) * image.height).round().clamp(1, image.height - y);
  return img.encodePng(img.copyCrop(image, x: x, y: y, width: w, height: h));
}

Future<Uint8List> _buildWatermarkedPdfIsolate(Map<String, dynamic> args) async {
  final images = (args['images'] as List).cast<Uint8List>();
  final text = args['text'] as String;
  final pageIndices = args['pageIndices'] as List?;
  final opacity = args['opacity'] as double;
  final fontSize = args['fontSize'] as double;

  final doc = pw.Document();
  for (var i = 0; i < images.length; i++) {
    final image = pw.MemoryImage(images[i]);
    final watermark = _isSelected(pageIndices, i)
        ? pw.Center(
            child: pw.Opacity(
              opacity: opacity,
              child: pw.Transform.rotate(
                angle: -0.6,
                child: pw.Text(
                  text,
                  style: pw.TextStyle(
                    fontSize: fontSize,
                    color: PdfColors.red700,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
          )
        : pw.SizedBox();

    doc.addPage(
      pw.Page(
        pageFormat: _formatFromArg(args, i),
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
            ),
            pw.Positioned.fill(child: watermark),
          ],
        ),
      ),
    );
  }
  return doc.save();
}
