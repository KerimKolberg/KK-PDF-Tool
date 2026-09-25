import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfService {
  /// Builds a single PDF where every entry in [pageJpegBytes] becomes one
  /// page, scaled to fit an A4 sheet.
  static Future<Uint8List> buildPdf(List<Uint8List> pageJpegBytes) async {
    final doc = pw.Document();
    for (final bytes in pageJpegBytes) {
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }
    return doc.save();
  }

  /// Builds a single-page PDF with the front and back of an ID card/document
  /// stacked on one A4 sheet - the layout most offices/authorities expect
  /// for a "copy of both sides" instead of two separate pages.
  static Future<Uint8List> buildIdCardPdf(
    Uint8List frontJpeg,
    Uint8List backJpeg,
  ) async {
    const margin = 28.0;
    const headerHeight = 20.0;
    const gap = 24.0;
    final contentHeight = PdfPageFormat.a4.height - margin * 2;
    final imageHeight = (contentHeight - headerHeight * 2 - gap) / 2;

    pw.Widget side(String label, Uint8List jpeg) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            height: headerHeight,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Container(
            height: imageHeight,
            width: double.infinity,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            padding: const pw.EdgeInsets.all(6),
            child: pw.Center(
              child: pw.Image(pw.MemoryImage(jpeg), fit: pw.BoxFit.contain),
            ),
          ),
        ],
      );
    }

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(margin),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            side('Vorderseite', frontJpeg),
            pw.SizedBox(height: gap),
            side('Rückseite', backJpeg),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
