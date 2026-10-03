import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../models/ocr_result.dart';
import '../models/scan_document.dart';
import 'document_store.dart';
import 'ocr_service.dart';
import 'pdf_service.dart';
import 'pdf_tools_service.dart';
import 'searchable_pdf_service.dart';
import 'settings_service.dart';

class BuiltDocument {
  /// The page images actually used (orientation-normalised when OCR ran).
  final List<Uint8List> pages;
  final Uint8List pdfBytes;
  final String? text;

  /// Per-page OCR results when text recognition ran (for [DocumentStore]).
  final List<OcrResult?>? ocr;

  const BuiltDocument({required this.pages, required this.pdfBytes, this.text, this.ocr});
}

/// Turns page images into the stored PDF. On Android (unless turned off in
/// Settings) every page is OCR'd offline and the PDF gets an invisible text
/// layer, making it searchable. Any OCR problem falls back to a plain
/// image PDF, so saving never fails because of text recognition.
class DocumentBuilder {
  static Future<BuiltDocument> build(
    List<Uint8List> pages, {
    bool? searchable,
    void Function(int done, int total)? onProgress,
  }) async {
    final useOcr = OcrService.isOfflineAvailable &&
        (searchable ?? await SettingsService().getSearchablePdfEnabled());
    if (!useOcr) {
      return BuiltDocument(pages: pages, pdfBytes: await PdfService.buildPdf(pages));
    }

    final normalized = <Uint8List>[];
    final results = <OcrResult?>[];
    for (var i = 0; i < pages.length; i++) {
      onProgress?.call(i, pages.length);
      final page = await OcrService.normalizeOrientation(pages[i]);
      normalized.add(page);
      try {
        results.add(await OcrService.recognize(page));
      } catch (_) {
        results.add(null);
      }
    }
    onProgress?.call(pages.length, pages.length);

    final text = _joinText(results);
    if (results.every((r) => r == null)) {
      return BuiltDocument(pages: normalized, pdfBytes: await PdfService.buildPdf(normalized));
    }
    Uint8List pdf;
    try {
      pdf = await SearchablePdfService.build(normalized, results);
    } catch (_) {
      pdf = await PdfService.buildPdf(normalized);
    }
    return BuiltDocument(pages: normalized, pdfBytes: pdf, text: text, ocr: results);
  }

  /// Offline OCR of [pages] without building a PDF (Android only).
  static Future<String?> recognizeText(
    List<Uint8List> pages, {
    void Function(int done, int total)? onProgress,
  }) async {
    final results = <OcrResult?>[];
    for (var i = 0; i < pages.length; i++) {
      onProgress?.call(i, pages.length);
      try {
        final page = await OcrService.normalizeOrientation(pages[i]);
        results.add(await OcrService.recognize(page));
      } catch (_) {
        results.add(null);
      }
    }
    return _joinText(results);
  }

  static String? _joinText(List<OcrResult?> results) {
    final text = results
        .map((r) => r?.text.trim() ?? '')
        .where((t) => t.isNotEmpty)
        .join('\n\n');
    return text.isEmpty ? null : text;
  }

  /// Loads a library document's pages in a quality good enough to rebuild
  /// the PDF from. Camera scans already store full-resolution pages; for
  /// imported PDFs and ID scans the stored page images are only preview
  /// renders, so those pages are re-rendered from the PDF at 200 dpi.
  static Future<List<Uint8List>> loadEditablePages(
    DocumentStore store,
    ScanDocument doc,
  ) async {
    final files = await store.pageFiles(doc.id, doc.pageCount);
    Uint8List? pdfBytes;
    final pages = <Uint8List>[];
    for (var i = 0; i < files.length; i++) {
      final bytes = await files[i].readAsBytes();
      final width = await _pixelWidth(bytes);
      if (width != null && width >= 1200) {
        pages.add(bytes);
        continue;
      }
      try {
        pdfBytes ??= await File(await store.pdfPath(doc.id)).readAsBytes();
        final raster = await PdfToolsService.rasterPages(pdfBytes, pages: [i], dpi: 200);
        if (raster.isNotEmpty) {
          pages.add((await PdfToolsService.toJpegs(raster, quality: 90)).first);
          continue;
        }
      } catch (_) {
        // Fall back to the stored preview image below.
      }
      pages.add(bytes);
    }
    return pages;
  }

  static Future<int?> _pixelWidth(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      descriptor.dispose();
      buffer.dispose();
      return width;
    } catch (_) {
      return null;
    }
  }
}
