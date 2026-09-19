import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'cloud_convert_screen.dart';

/// Converts a .pptx to a real, text-preserving PDF by round-tripping it
/// through the user's own Google Drive (Slides).
class PptxToPdfScreen extends StatelessWidget {
  const PptxToPdfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CloudConvertScreen(
      title: 'PowerPoint → PDF',
      pickButtonLabel: 'PowerPoint-Datei wählen',
      pickIcon: Icons.slideshow_outlined,
      convertButtonLabel: 'In PDF umwandeln',
      convertIcon: Icons.picture_as_pdf_outlined,
      typeGroup: const XTypeGroup(label: 'PowerPoint', extensions: ['pptx']),
      sourceExtension: 'pptx',
      outputExtension: 'pdf',
      convert: (drive, bytes, fileName) => drive.pptxToPdf(bytes, fileName),
    );
  }
}
