import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scan_document.dart';
import 'document_builder.dart';
import 'document_store.dart';
import 'downloads_export_service.dart';
import 'pdf_service.dart';
import 'pdf_tools_service.dart';
import 'searchable_pdf_service.dart';

enum ShareFormat { originalPdf, smallPdf, images }

class PreparedShare {
  final List<XFile> files;

  /// Shown to the user, e.g. when the original was shared instead of a
  /// "smaller" copy that wouldn't actually have been smaller.
  final String? note;

  const PreparedShare(this.files, {this.note});
}

/// Builds the files for sharing a library document: the original PDF, a
/// smaller PDF for e-mail/messengers, or the pages as JPG images. Files are
/// written to a temp "share" folder under the document's title, so the
/// recipient sees a sensible file name instead of "document.pdf".
class DocumentShareService {
  final DocumentStore store;

  DocumentShareService(this.store);

  /// Longest side of pages in the smaller PDF (~140 dpi on A4).
  static const smallMaxSide = 1600;
  static const smallQuality = 60;

  Future<Directory> _freshShareDir() async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'share'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    return dir;
  }

  Future<PreparedShare> prepare(ScanDocument doc, ShareFormat format) async {
    final name = DownloadsExportService.safeFileName(doc.title);
    final dir = await _freshShareDir();
    final original = File(await store.pdfPath(doc.id));

    Future<PreparedShare> shareOriginal({String? note}) async {
      final copy = await original.copy(p.join(dir.path, '$name.pdf'));
      return PreparedShare([XFile(copy.path, mimeType: 'application/pdf')], note: note);
    }

    switch (format) {
      case ShareFormat.originalPdf:
        return shareOriginal();

      case ShareFormat.smallPdf:
        // With stored OCR positions the stored page images are exactly the
        // ones that were recognised, so the smaller copy stays searchable.
        var ocr = await store.readOcr(doc.id);
        List<Uint8List> pages;
        if (ocr != null && ocr.length == doc.pageCount) {
          final files = await store.pageFiles(doc.id, doc.pageCount);
          pages = [for (final f in files) await f.readAsBytes()];
        } else {
          ocr = null;
          pages = await DocumentBuilder.loadEditablePages(store, doc);
        }
        final small = await PdfToolsService.shrinkImages(
          pages,
          maxSide: smallMaxSide,
          quality: smallQuality,
        );
        final pdf = ocr != null
            ? await SearchablePdfService.build(small, ocr)
            : await PdfService.buildPdf(small);
        if (pdf.length >= await original.length() * 0.9) {
          return shareOriginal(note: 'Die PDF ist schon klein - das Original wird geteilt.');
        }
        final file = File(p.join(dir.path, '$name (klein).pdf'));
        await file.writeAsBytes(pdf, flush: true);
        return PreparedShare([XFile(file.path, mimeType: 'application/pdf')]);

      case ShareFormat.images:
        final pages = await DocumentBuilder.loadEditablePages(store, doc);
        final jpegs = await PdfToolsService.shrinkImages(pages, maxSide: 2400, quality: 85);
        final digits = '${jpegs.length}'.length;
        final files = <XFile>[];
        for (var i = 0; i < jpegs.length; i++) {
          final suffix = jpegs.length == 1 ? '' : ' - Seite ${(i + 1).toString().padLeft(digits, '0')}';
          final file = File(p.join(dir.path, '$name$suffix.jpg'));
          await file.writeAsBytes(jpegs[i], flush: true);
          files.add(XFile(file.path, mimeType: 'image/jpeg'));
        }
        return PreparedShare(files);
    }
  }
}
