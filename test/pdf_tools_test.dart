import 'dart:io';
import 'dart:typed_data';

import 'package:doc_scanner/services/pdf_tools_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as rx;

import 'support/fake_paths.dart';

/// A PDF with [count] slide-sized (960x540) pages of real text.
Future<Uint8List> _slides(int count, {String label = 'Slide'}) async {
  final doc = pw.Document();
  for (var i = 0; i < count; i++) {
    doc.addPage(pw.Page(
      pageFormat: const PdfPageFormat(960, 540),
      build: (_) => pw.Column(children: [
        pw.Text('$label ${i + 1}', style: const pw.TextStyle(fontSize: 40)),
        pw.Container(width: 200, height: 100, color: PdfColors.red),
      ]),
    ));
  }
  return doc.save();
}

List<String> _sizes(List<PdfPageFormat> formats) =>
    [for (final f in formats) '${f.width.round()}x${f.height.round()}'];

/// These tests drive the real PDF engine. `flutter test` builds PDFium for
/// the host machine into build/native_assets; without it they are skipped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pdfium = File('build/native_assets/linux/libpdfium.so');
  final skip = pdfium.existsSync() ? null : 'PDFium for this machine is not built';

  setUpAll(() {
    FakePaths.install();
    if (skip == null) rx.Pdfrx.pdfiumModulePath = pdfium.absolute.path;
  });

  testWidgets('split, merge and rotate copy pages without changing them', (tester) async {
    await tester.runAsync(() async {
      final a = await _slides(5);
      final b = await _slides(3, label: 'Other');
      expect(await PdfToolsService.countPages(a), 5);

      final part = await PdfToolsService.extractRange(a, startPage: 2, endPage: 3);
      expect(_sizes(await PdfToolsService.pageFormats(part)), ['960x540', '960x540']);
      // Copied, not turned into pictures: about as small as the source.
      expect(part.length, lessThan(a.length * 2));

      final merged = await PdfToolsService.merge([a, b]);
      expect(await PdfToolsService.countPages(merged), 8);

      final rotated = await PdfToolsService.rotatePages(a, pageIndices: [0], degrees: 90);
      expect(_sizes(await PdfToolsService.pageFormats(rotated)).take(2), ['540x960', '960x540']);
    });
  }, skip: skip != null);

  testWidgets('tools that redraw pages keep each page size', (tester) async {
    await tester.runAsync(() async {
      final a = await _slides(2);
      const slide = ['960x540', '960x540'];

      final watermarked = await PdfToolsService.addWatermark(a, text: 'DRAFT');
      expect(_sizes(await PdfToolsService.pageFormats(watermarked)), slide);

      final numbered = await PdfToolsService.addPageNumbers(a, numberFormat: PageNumberFormat.slash);
      expect(_sizes(await PdfToolsService.pageFormats(numbered)), slide);

      final compressed = await PdfToolsService.compress(a, dpi: 100, quality: 60);
      expect(_sizes(await PdfToolsService.pageFormats(compressed)), slide);

      final cropped = await PdfToolsService.cropPages(
        a,
        pageIndices: [0],
        leftFrac: 0.25,
        topFrac: 0.5,
        rightFrac: 0.75,
        bottomFrac: 1,
      );
      expect(_sizes(await PdfToolsService.pageFormats(cropped)), ['480x270', '960x540']);
    });
  }, skip: skip != null);

  testWidgets('pages render as PNG or JPEG at the requested resolution', (tester) async {
    await tester.runAsync(() async {
      final a = await _slides(1);
      final png = (await PdfToolsService.rasterPages(a, dpi: 72)).single;
      final jpeg = (await PdfToolsService.rasterPages(a, dpi: 144, format: PageImageFormat.jpeg)).single;
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
      expect(jpeg.sublist(0, 2), [0xFF, 0xD8]);
      final decoded = img.decodeJpg(jpeg)!;
      expect((decoded.width, decoded.height), (1920, 1080));
      // The red box must come out red, not blue (PDFium renders BGRA).
      var red = 0, blue = 0;
      for (final pixel in decoded) {
        if (pixel.r > 200 && pixel.b < 80) red++;
        if (pixel.b > 200 && pixel.r < 80) blue++;
      }
      expect(red, greaterThan(1000));
      expect(blue, 0);
    });
  }, skip: skip != null);
}
