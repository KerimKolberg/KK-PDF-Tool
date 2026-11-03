import 'dart:io';

import 'package:flutter/material.dart';

import 'annotate_pages_screen.dart';
import 'tools/annotate_pdf_screen.dart';
import 'tools/compress_pdf_screen.dart';
import 'tools/crop_pdf_screen.dart';
import 'tools/html_to_pdf_screen.dart';
import 'tools/images_to_pdf_screen.dart';
import 'tools/markdown_to_pdf_screen.dart';
import 'tools/merge_pdf_screen.dart';
import 'tools/page_numbers_screen.dart';
import 'tools/pdf_to_images_screen.dart';
import 'tools/pdf_to_pptx_screen.dart';
import 'tools/pdf_to_word_screen.dart';
import 'tools/pptx_to_pdf_screen.dart';
import 'tools/rotate_pdf_screen.dart';
import 'tools/searchable_pdf_screen.dart';
import 'tools/split_pdf_screen.dart';
import 'tools/text_from_image_screen.dart';
import 'tools/watermark_pdf_screen.dart';
import 'tools/word_to_pdf_screen.dart';
import '../l10n.dart';

class _ToolEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
  final bool needsInternet;
  final bool androidOnly;
  const _ToolEntry(
    this.title,
    this.subtitle,
    this.icon,
    this.builder, {
    this.needsInternet = false,
    this.androidOnly = false,
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
    _ToolSection(tr('Umwandeln', 'Convert'), [
      _ToolEntry(
        tr('Bilder → PDF', 'Images → PDF'),
        tr('Mehrere Bilder zu einer PDF zusammenfassen', 'Combine several images into one PDF'),
        Icons.image_outlined,
        (_) => const ImagesToPdfScreen(),
      ),
      _ToolEntry(
        tr('PDF → Bilder', 'PDF → images'),
        tr('Jede Seite einer PDF als Bild exportieren', 'Export every page of a PDF as an image'),
        Icons.photo_library_outlined,
        (_) => const PdfToImagesScreen(),
      ),
      _ToolEntry(
        'PDF → PowerPoint',
        tr('Jede Seite als Bild-Folie (offline, nicht text-editierbar)', 'Every page as a picture slide (offline, text not editable)'),
        Icons.slideshow_outlined,
        (_) => const PdfToPptxScreen(),
      ),
      _ToolEntry(
        'PowerPoint → PDF',
        tr('Echte Konvertierung über dein Google-Konto', 'Real conversion through your Google account'),
        Icons.picture_as_pdf_outlined,
        (_) => const PptxToPdfScreen(),
        needsInternet: true,
      ),
      _ToolEntry(
        'Word → PDF',
        tr('Echte Konvertierung über dein Google-Konto', 'Real conversion through your Google account'),
        Icons.picture_as_pdf_outlined,
        (_) => const WordToPdfScreen(),
        needsInternet: true,
      ),
      _ToolEntry(
        'PDF → Word',
        tr('Editierbar, mit Texterkennung über dein Google-Konto', 'Editable, with text recognition through your Google account'),
        Icons.description_outlined,
        (_) => const PdfToWordScreen(),
        needsInternet: true,
      ),
      _ToolEntry(
        'HTML → PDF',
        tr('Über dein Google-Konto', 'Through your Google account'),
        Icons.code,
        (_) => const HtmlToPdfScreen(),
        needsInternet: true,
      ),
      _ToolEntry(
        'Markdown → PDF',
        tr('Formatierter Text aus .md-Dateien (offline)', 'Formatted text from .md files (offline)'),
        Icons.article_outlined,
        (_) => const MarkdownToPdfScreen(),
      ),
      _ToolEntry(
        tr('Text aus Bild (OCR)', 'Text from image (OCR)'),
        tr('Text aus einem Foto erkennen, kopieren oder als .txt speichern', 'Recognize text in a photo, copy it or save it as .txt'),
        Icons.text_snippet_outlined,
        (_) => const TextFromImageScreen(),
        needsInternet: !Platform.isAndroid,
      ),
      _ToolEntry(
        tr('PDF durchsuchbar machen', 'Make PDF searchable'),
        tr('Gescannte PDF mit unsichtbarer Textebene (offline)', 'Scanned PDF with an invisible text layer (offline)'),
        Icons.manage_search,
        (_) => const SearchablePdfScreen(),
        androidOnly: true,
      ),
    ]),
    _ToolSection(tr('Bearbeiten', 'Edit'), [
      _ToolEntry(
        tr('PDF ausfüllen & unterschreiben', 'Fill in & sign PDF'),
        tr('Text, Datum, Haken und Unterschrift einfügen', 'Insert text, date, check marks and signature'),
        Icons.edit_note,
        (_) => const AnnotatePdfScreen(mode: AnnotateMode.fill),
      ),
      _ToolEntry(
        tr('PDF markieren & zeichnen', 'Highlight & draw on PDF'),
        tr('Mit Stift und Textmarker auf Seiten zeichnen', 'Draw on pages with pen and highlighter'),
        Icons.brush_outlined,
        (_) => const AnnotatePdfScreen(mode: AnnotateMode.draw),
      ),
      _ToolEntry(
        tr('Seitenzahlen & Kopfzeile', 'Page numbers & header'),
        tr('Seitenzahlen, Kopf- und Fußzeile hinzufügen', 'Add page numbers, header and footer'),
        Icons.format_list_numbered,
        (_) => const PageNumbersScreen(),
      ),
      _ToolEntry(
        tr('PDFs zusammenführen', 'Merge PDFs'),
        tr('Mehrere PDFs in einer Reihenfolge verbinden', 'Join several PDFs in a chosen order'),
        Icons.merge_type,
        (_) => const MergePdfScreen(),
      ),
      _ToolEntry(
        tr('PDF aufteilen', 'Split PDF'),
        tr('Nach Seitenbereich in mehrere PDFs aufteilen', 'Split into several PDFs by page range'),
        Icons.content_cut,
        (_) => const SplitPdfScreen(),
      ),
      _ToolEntry(
        tr('PDF drehen', 'Rotate PDF'),
        tr('Ganze Datei(en) oder einzelne Seiten', 'Whole file(s) or single pages'),
        Icons.rotate_right,
        (_) => const RotatePdfScreen(),
      ),
      _ToolEntry(
        tr('PDF zuschneiden', 'Crop PDF'),
        tr('Ränder auf allen oder gewählten Seiten entfernen', 'Remove margins on all or chosen pages'),
        Icons.crop,
        (_) => const CropPdfScreen(),
      ),
      _ToolEntry(
        tr('Wasserzeichen', 'Watermark'),
        tr('Text diagonal über jede Seite legen', 'Lay text diagonally across every page'),
        Icons.water_drop_outlined,
        (_) => const WatermarkPdfScreen(),
      ),
      _ToolEntry(
        tr('PDF komprimieren', 'Compress PDF'),
        tr('Dateigröße durch geringere Qualität verkleinern', 'Reduce file size by lowering quality'),
        Icons.compress,
        (_) => const CompressPdfScreen(),
      ),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Werkzeuge', 'Tools'))),
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
              if (!tool.androidOnly || Platform.isAndroid)
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
