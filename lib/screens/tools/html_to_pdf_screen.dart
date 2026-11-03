import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'cloud_convert_screen.dart';
import '../../l10n.dart';

/// Converts an .html file to PDF by round-tripping it through the user's
/// own Google Drive (Docs imports basic HTML formatting).
class HtmlToPdfScreen extends StatelessWidget {
  const HtmlToPdfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CloudConvertScreen(
      title: 'HTML → PDF',
      pickButtonLabel: tr('HTML-Datei wählen', 'Choose HTML file'),
      pickIcon: Icons.code,
      convertButtonLabel: tr('In PDF umwandeln', 'Convert to PDF'),
      convertIcon: Icons.picture_as_pdf_outlined,
      typeGroup: const XTypeGroup(label: 'HTML', extensions: ['html', 'htm']),
      sourceExtension: 'html',
      outputExtension: 'pdf',
      convert: (drive, bytes, fileName) => drive.htmlToPdf(bytes, fileName),
    );
  }
}
