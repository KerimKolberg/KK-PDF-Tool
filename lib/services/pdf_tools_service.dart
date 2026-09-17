import 'package:flutter/foundation.dart';
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
}

Uint8List _buildPptxIsolate(List<Uint8List> images) {
  return PptxWriterService.buildPptx(images);
}
