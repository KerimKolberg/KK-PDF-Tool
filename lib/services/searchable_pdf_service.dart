import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/ocr_result.dart';

/// Builds an A4 PDF where each page shows the scanned image, with the OCR'd
/// text laid invisibly on top at the same positions - so the PDF looks
/// exactly like the scan but can be searched (Ctrl+F) and text can be
/// selected/copied, the way CamScanner's "searchable PDF" works.
class SearchablePdfService {
  /// The built-in PDF font only covers Latin-1 (incl. äöüß); map common
  /// typographic characters ML Kit returns to plain equivalents so they
  /// stay searchable instead of being dropped.
  static const _replacements = {
    '„': '"', '“': '"', '”': '"', '‚': "'", '‘': "'", '’': "'",
    '–': '-', '—': '-', '…': '...', '€': 'EUR', '•': '*',
    'ﬁ': 'fi', 'ﬂ': 'fl', ' ': ' ',
  };

  static String _pdfSafe(String text) {
    final out = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (rune <= 0xFF) {
        out.write(ch);
      } else {
        final replacement = _replacements[ch];
        if (replacement != null) out.write(replacement);
      }
    }
    return out.toString();
  }

  static Future<Uint8List> build(
    List<Uint8List> pageImages,
    List<OcrResult?> ocrResults,
  ) async {
    final pageW = PdfPageFormat.a4.width;
    final pageH = PdfPageFormat.a4.height;
    final doc = pw.Document();

    for (var i = 0; i < pageImages.length; i++) {
      final image = pw.MemoryImage(pageImages[i]);
      final imgW = (image.width ?? 1).toDouble();
      final imgH = (image.height ?? 1).toDouble();
      final scale = math.min(pageW / imgW, pageH / imgH);
      final drawW = imgW * scale;
      final drawH = imgH * scale;
      final dx = (pageW - drawW) / 2;
      final dy = (pageH - drawH) / 2;

      final ocr = i < ocrResults.length ? ocrResults[i] : null;
      final textLayer = <pw.Widget>[];
      if (ocr != null && ocr.width > 0 && ocr.height > 0) {
        final sx = drawW / ocr.width;
        final sy = drawH / ocr.height;
        for (final line in ocr.lines) {
          final w = (line.right - line.left) * sx;
          final h = (line.bottom - line.top) * sy;
          final text = _pdfSafe(line.text);
          if (text.trim().isEmpty || w <= 1 || h <= 1) continue;
          textLayer.add(
            pw.Positioned(
              left: dx + line.left * sx,
              top: dy + line.top * sy,
              child: pw.SizedBox(
                width: w,
                height: h,
                child: pw.FittedBox(
                  fit: pw.BoxFit.fill,
                  child: pw.Text(
                    text,
                    style: const pw.TextStyle(
                      fontSize: 10,
                      renderingMode: PdfTextRenderingMode.invisible,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.SizedBox(
            width: pageW,
            height: pageH,
            child: pw.Stack(
              children: [
                pw.Positioned(
                  left: dx,
                  top: dy,
                  child: pw.Image(image, width: drawW, height: drawH),
                ),
                ...textLayer,
              ],
            ),
          ),
        ),
      );
    }
    return doc.save();
  }
}
