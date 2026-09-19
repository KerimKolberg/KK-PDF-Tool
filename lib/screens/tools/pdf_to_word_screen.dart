import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'cloud_convert_screen.dart';

/// Converts a PDF to an editable .docx by round-tripping it through the
/// user's own Google Drive (Docs), which OCRs scanned/image-based pages.
class PdfToWordScreen extends StatelessWidget {
  const PdfToWordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CloudConvertScreen(
      title: 'PDF → Word',
      pickButtonLabel: 'PDF wählen',
      pickIcon: Icons.picture_as_pdf_outlined,
      convertButtonLabel: 'In Word umwandeln',
      convertIcon: Icons.description_outlined,
      typeGroup: const XTypeGroup(label: 'PDF', extensions: ['pdf']),
      sourceExtension: 'pdf',
      outputExtension: 'docx',
      convert: (drive, bytes, fileName) => drive.pdfToWord(bytes, fileName),
    );
  }
}
