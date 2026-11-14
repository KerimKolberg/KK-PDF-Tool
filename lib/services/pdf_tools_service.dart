import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as rx;

import '../l10n.dart';
import 'pdf_service.dart';
import 'pptx_writer_service.dart';

enum PageNumberFormat {
  plain,
  seite,
  seiteVon,
  slash;

  String get example => format(1, 5);

  String format(int number, int total) => switch (this) {
        PageNumberFormat.plain => '$number',
        PageNumberFormat.seite => tr('Seite $number', 'Page $number'),
        PageNumberFormat.seiteVon => tr('Seite $number von $total', 'Page $number of $total'),
        PageNumberFormat.slash => '$number / $total',
      };
}

enum PageNumberPosition {
  bottomCenter('Unten Mitte', 'Bottom center'),
  bottomRight('Unten rechts', 'Bottom right'),
  topRight('Oben rechts', 'Top right');

  final String _de;
  final String _en;
  const PageNumberPosition(this._de, this._en);

  String get label => tr(_de, _en);
}

/// How rendered pages are encoded.
enum PageImageFormat {
  /// Lossless; best for text, large for photos.
  png,

  /// Small, slightly lossy; best for scans and photos.
  jpeg,

  /// PNG for pages that compress well as PNG (text, line art), JPEG for
  /// photo-like pages (scans) - keeps both sharp text and small files.
  compact,
}

/// Rendered page images of a PDF together with each page's size.
class RenderedPdf {
  final List<Uint8List> images;
  final List<PdfPageFormat> formats;
  const RenderedPdf(this.images, this.formats);
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
  /// to images at [dpi].
  static Future<List<Uint8List>> rasterPages(
    Uint8List pdfBytes, {
    List<int>? pages,
    double dpi = 150,
    PageImageFormat format = PageImageFormat.png,
    int jpegQuality = 90,
  }) async {
    final rendered = await renderPdf(
      pdfBytes,
      pages: pages,
      dpi: dpi,
      format: format,
      jpegQuality: jpegQuality,
    );
    return rendered.images;
  }

  /// Like [rasterPages], but also returns each rendered page's size, and
  /// can cut the pages in [cropPages] (all when omitted) down to [crop]
  /// (fractions of the page, 0..1) while rendering. The PDF is opened once.
  static Future<RenderedPdf> renderPdf(
    Uint8List pdfBytes, {
    List<int>? pages,
    double dpi = 150,
    PageImageFormat format = PageImageFormat.png,
    int jpegQuality = 90,
    ui.Rect? crop,
    List<int>? cropPages,
  }) {
    return _withDocument(pdfBytes, (doc) async {
      final all = doc.pages;
      final images = <Uint8List>[];
      final formats = <PdfPageFormat>[];
      for (final index in pages ?? [for (var i = 0; i < all.length; i++) i]) {
        if (index < 0 || index >= all.length) continue;
        final page = all[index];
        final area = crop != null && _isSelected(cropPages, index) ? crop : null;
        images.add(await _renderPage(page, dpi, format, jpegQuality, area));
        formats.add(PdfPageFormat(
          page.width * (area?.width ?? 1),
          page.height * (area?.height ?? 1),
        ));
      }
      return RenderedPdf(images, formats);
    });
  }

  /// Renders one page - or just the part [crop] of it - and encodes it.
  static Future<Uint8List> _renderPage(
    rx.PdfPage page,
    double dpi,
    PageImageFormat format,
    int jpegQuality,
    ui.Rect? crop,
  ) async {
    final fullWidth = page.width * dpi / 72;
    final fullHeight = page.height * dpi / 72;
    final raw = await page.render(
      x: crop == null ? 0 : (crop.left * fullWidth).round(),
      y: crop == null ? 0 : (crop.top * fullHeight).round(),
      width: crop == null ? null : (crop.width * fullWidth).round().clamp(1, fullWidth.ceil()),
      height: crop == null ? null : (crop.height * fullHeight).round().clamp(1, fullHeight.ceil()),
      fullWidth: fullWidth,
      fullHeight: fullHeight,
      backgroundColor: 0xffffffff,
    );
    if (raw == null) {
      throw StateError(tr('Seite ${page.pageNumber} konnte nicht gelesen werden', 'Could not read page ${page.pageNumber}'));
    }
    try {
      if (format == PageImageFormat.jpeg) return await _encodeJpeg(raw, jpegQuality);
      final png = await _encodePng(raw);
      // PNG is ideal for text and line art, but several times larger than
      // JPEG for photos and scans (more than ~2 bits per pixel).
      if (format == PageImageFormat.compact && png.length > raw.width * raw.height / 4) {
        final jpeg = await _encodeJpeg(raw, jpegQuality);
        if (jpeg.length < png.length) return jpeg;
      }
      return png;
    } finally {
      raw.dispose();
    }
  }

  static Future<Uint8List> _encodePng(rx.PdfImage raw) async {
    final image = await raw.createImage();
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  static Future<Uint8List> _encodeJpeg(rx.PdfImage raw, int quality) => compute(
        _bgraToJpegIsolate,
        (pixels: raw.pixels, width: raw.width, height: raw.height, quality: quality),
      );

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
    final pages = await renderPdf(
      pdfBytes,
      dpi: dpi,
      format: PageImageFormat.jpeg,
      jpegQuality: quality,
    );
    return PdfService.buildPdf(pages.images, pageFormats: pages.formats);
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
    final pages = await renderPdf(pdfBytes, format: PageImageFormat.compact);
    return compute(_buildWatermarkedPdfIsolate, {
      'images': pages.images,
      'formats': _formatsArg(pages.formats),
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
    // Only the wanted part of each page is rendered, so nothing has to be
    // decoded and encoded a second time.
    final pages = await renderPdf(
      pdfBytes,
      format: PageImageFormat.compact,
      crop: ui.Rect.fromLTRB(leftFrac, topFrac, rightFrac, bottomFrac),
      cropPages: pageIndices,
    );
    return PdfService.buildPdf(pages.images, pageFormats: pages.formats);
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
    final pages = await renderPdf(pdfBytes, format: PageImageFormat.compact);
    return compute(_buildPageNumberedPdfIsolate, {
      'images': pages.images,
      'formats': _formatsArg(pages.formats),
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
  if (decoded == null) throw FormatException(tr('Bild konnte nicht gelesen werden', 'Could not read image'));
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

/// Encodes raw BGRA pixels (as PDFium renders them) as a JPEG.
Uint8List _bgraToJpegIsolate(({Uint8List pixels, int width, int height, int quality}) args) {
  final image = img.Image.fromBytes(
    width: args.width,
    height: args.height,
    bytes: args.pixels.buffer,
    bytesOffset: args.pixels.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.bgra,
  );
  return img.encodeJpg(image, quality: args.quality);
}

bool _isSelected(List<dynamic>? pageIndices, int index) {
  if (pageIndices == null || pageIndices.isEmpty) return true;
  return pageIndices.contains(index);
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
