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
}
