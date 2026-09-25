import 'package:flutter/material.dart';

import 'tools/compress_pdf_screen.dart';
import 'tools/crop_pdf_screen.dart';
import 'tools/html_to_pdf_screen.dart';
import 'tools/images_to_pdf_screen.dart';
import 'tools/markdown_to_pdf_screen.dart';
import 'tools/merge_pdf_screen.dart';
import 'tools/pdf_to_images_screen.dart';
import 'tools/pdf_to_pptx_screen.dart';
import 'tools/pdf_to_word_screen.dart';
import 'tools/pptx_to_pdf_screen.dart';
import 'tools/rotate_pdf_screen.dart';
import 'tools/split_pdf_screen.dart';
import 'tools/text_from_image_screen.dart';
import 'tools/watermark_pdf_screen.dart';
import 'tools/word_to_pdf_screen.dart';

class _ToolEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
  final bool needsInternet;
  const _ToolEntry(
    this.title,
    this.subtitle,
    this.icon,
    this.builder, {
    this.needsInternet = false,
  });
}

class _ToolSection {
  final String title;
  final List<_ToolEntry> tools;
  const _ToolSection(this.title, this.tools);
}

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  static final _sections = <_ToolSection>[
    _ToolSection('Umwandeln', [
      _ToolEntry(
        'Bilder → PDF',
        'Mehrere Bilder zu einer PDF zusammenfassen',
        Icons.image_outlined,
        (_) => const ImagesToPdfScreen(),
      ),
      _ToolEntry(
        'PDF → Bilder',
        'Jede Seite einer PDF als Bild exportieren',
        Icons.photo_library_outlined,
        (_) => const PdfToImagesScreen(),
      ),
      _ToolEntry(
        'PDF → PowerPoint',
        'Jede Seite als Bild-Folie (offline, nicht text-editierbar)',
        Icons.slideshow_outlined,
        (_) => const PdfToPptxScreen(),
      ),
      _ToolEntry(
        'PowerPoint → PDF',
        'Echte Konvertierung über dein Google-Konto',
        Icons.picture_as_pdf_outlined,
        (_) => const PptxToPdfScreen(),
        needsInternet: true,
      ),
      _ToolEntry(
        'Word → PDF',
        'Echte Konvertierung über dein Google-Konto',
        Icons.picture_as_pdf_outlined,
        (_) => const WordToPdfScreen(),
        needsInternet: true,
      ),
      _ToolEntry(
        'PDF → Word',
        'Editierbar, mit Texterkennung über dein Google-Konto',
        Icons.description_outlined,
        (_) => const PdfToWordScreen(),
        needsInternet: true,
      ),
      _ToolEntry(
        'HTML → PDF',
        'Über dein Google-Konto',
        Icons.code,
        (_) => const HtmlToPdfScreen(),
        needsInternet: true,
      ),
      _ToolEntry(
        'Markdown → PDF',
        'Formatierter Text aus .md-Dateien (offline)',
        Icons.article_outlined,
        (_) => const MarkdownToPdfScreen(),
      ),
      _ToolEntry(
        'Text aus Bild (OCR)',
        'Text aus einem Foto erkennen, kopieren oder als .txt speichern',
        Icons.text_snippet_outlined,
        (_) => const TextFromImageScreen(),
        needsInternet: true,
      ),
    ]),
    _ToolSection('Bearbeiten', [
      _ToolEntry(
        'PDFs zusammenführen',
        'Mehrere PDFs in einer Reihenfolge verbinden',
        Icons.merge_type,
        (_) => const MergePdfScreen(),
      ),
      _ToolEntry(
        'PDF aufteilen',
        'Nach Seitenbereich in mehrere PDFs aufteilen',
        Icons.content_cut,
        (_) => const SplitPdfScreen(),
      ),
      _ToolEntry(
        'PDF drehen',
        'Ganze Datei(en) oder einzelne Seiten',
        Icons.rotate_right,
        (_) => const RotatePdfScreen(),
      ),
      _ToolEntry(
        'PDF zuschneiden',
        'Ränder auf allen oder gewählten Seiten entfernen',
        Icons.crop,
        (_) => const CropPdfScreen(),
      ),
      _ToolEntry(
        'Wasserzeichen',
        'Text diagonal über jede Seite legen',
        Icons.water_drop_outlined,
        (_) => const WatermarkPdfScreen(),
      ),
      _ToolEntry(
        'PDF komprimieren',
        'Dateigröße durch geringere Qualität verkleinern',
        Icons.compress,
        (_) => const CompressPdfScreen(),
      ),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Werkzeuge')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final section in _sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text(
                section.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            for (final tool in section.tools)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor:
                          Theme.of(context).colorScheme.onPrimaryContainer,
                      child: Icon(tool.icon),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(tool.title,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        if (tool.needsInternet) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.cloud_outlined,
                              size: 16,
                              color: Theme.of(context).colorScheme.outline),
                        ],
                      ],
                    ),
                    subtitle: Text(tool.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: tool.builder),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
