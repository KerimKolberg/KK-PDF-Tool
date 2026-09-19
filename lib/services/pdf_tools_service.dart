import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'pdf_service.dart';
import 'pptx_writer_service.dart';

/// PDF manipulation built on rasterizing pages, since there is no
/// pure-Dart/Flutter library that can copy vector pages between existing
/// PDFs on both Android and Windows. Output files are image-based PDFs:
/// they look identical to the source but are not text-searchable.
class PdfToolsService {
  /// Renders [pages] (0-based indices; all pages when omitted) of [pdfBytes]
  /// to PNG images at [dpi].
  static Future<List<Uint8List>> rasterPages(
    Uint8List pdfBytes, {
    List<int>? pages,
    double dpi = 150,
  }) async {
    final images = <Uint8List>[];
    await for (final page in Printing.raster(pdfBytes, pages: pages, dpi: dpi)) {
      images.add(await page.toPng());
    }
    return images;
  }

  /// Total page count of [pdfBytes], found by rasterizing at a very low
  /// resolution (cheap) since the `printing` package exposes no direct
  /// page-count API.
  static Future<int> countPages(Uint8List pdfBytes) async {
    var count = 0;
    await for (final _ in Printing.raster(pdfBytes, dpi: 36)) {
      count++;
    }
    return count;
  }

  /// Concatenates all pages of [pdfs], in order, into a single new PDF.
  static Future<Uint8List> merge(List<Uint8List> pdfs) async {
    final allImages = <Uint8List>[];
    for (final pdf in pdfs) {
      allImages.addAll(await rasterPages(pdf));
    }
    return PdfService.buildPdf(allImages);
  }

  /// Extracts the inclusive 1-based page range [startPage]..[endPage] from
  /// [pdfBytes] into a new PDF.
  static Future<Uint8List> extractRange(
    Uint8List pdfBytes, {
    required int startPage,
    required int endPage,
  }) async {
    final indices = [
      for (var i = startPage - 1; i <= endPage - 1; i++) i,
    ];
    final images = await rasterPages(pdfBytes, pages: indices);
    return PdfService.buildPdf(images);
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
    final jpegs = await compute(_reencodeJpegBatchIsolate, {
      'images': images,
      'quality': quality,
    });
    return PdfService.buildPdf(jpegs);
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
      'text': text,
      'pageIndices': pageIndices,
      'opacity': opacity,
      'fontSize': fontSize,
    });
  }

  /// Rotates [pageIndices] (0-based; all pages when omitted) of [pdfBytes]
  /// by [degrees] (90/180/270) clockwise; other pages are left untouched.
  static Future<Uint8List> rotatePages(
    Uint8List pdfBytes, {
    List<int>? pageIndices,
    required int degrees,
  }) async {
    final images = await rasterPages(pdfBytes, dpi: 150);
    final rotated = await compute(_rotateBatchIsolate, {
      'images': images,
      'pageIndices': pageIndices,
      'degrees': degrees,
    });
    return PdfService.buildPdf(rotated);
  }

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
    final cropped = await compute(_cropBatchIsolate, {
      'images': images,
      'pageIndices': pageIndices,
      'left': leftFrac,
      'top': topFrac,
      'right': rightFrac,
      'bottom': bottomFrac,
    });
    return PdfService.buildPdf(cropped);
  }
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

List<Uint8List> _rotateBatchIsolate(Map<String, dynamic> args) {
  final images = (args['images'] as List).cast<Uint8List>();
  final pageIndices = args['pageIndices'] as List?;
  final degrees = args['degrees'] as int;
  return [
    for (var i = 0; i < images.length; i++)
      if (_isSelected(pageIndices, i))
        img.encodePng(
          img.copyRotate(img.decodeImage(images[i])!, angle: degrees),
        )
      else
        images[i],
  ];
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
        pageFormat: PdfPageFormat.a4,
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
