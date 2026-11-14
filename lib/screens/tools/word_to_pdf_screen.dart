import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../l10n.dart';
import 'cloud_convert_screen.dart';

/// Converts a .docx to PDF by round-tripping it through the user's own
/// Google Drive (Docs).
class WordToPdfScreen extends StatelessWidget {
  const WordToPdfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CloudConvertScreen(
      title: 'Word → PDF',
      pickButtonLabel: tr('Word-Datei wählen', 'Choose Word file'),
      pickIcon: Icons.description_outlined,
      convertButtonLabel: tr('In PDF umwandeln', 'Convert to PDF'),
      convertIcon: Icons.picture_as_pdf_outlined,
      typeGroup: const XTypeGroup(label: 'Word', extensions: ['docx']),
      sourceExtension: 'docx',
      outputExtension: 'pdf',
      convert: (drive, bytes, fileName) => drive.docxToPdf(bytes, fileName),
    );
  }
}
