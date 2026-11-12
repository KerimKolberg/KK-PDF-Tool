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
import '../utils/layout.dart';
import 'home_shell.dart';

const _pdf = {'pdf'};
const _images = {'jpg', 'jpeg', 'png', 'webp'};

class ToolEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
  final bool needsInternet;
  final bool androidOnly;

  /// File extensions the tool takes as input.
  final Set<String> accepts;

  /// Whether it takes several files at once.
  final bool multiple;

  const ToolEntry(
    this.title,
    this.subtitle,
    this.icon,
    this.builder, {
    required this.accepts,
    this.multiple = false,
    this.needsInternet = false,
    this.androidOnly = false,
  });

  bool get available => !androidOnly || AppPlatform.isAndroid;
}

class _ToolSection {
  final String title;
  final List<ToolEntry> tools;
  const _ToolSection(this.title, this.tools);
}

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  /// The tools that can take [extensions] (one per file, lower case) as
  /// input, in the order of the tools page.
  static List<ToolEntry> toolsFor(List<String> extensions) => [
        for (final section in _sections)
          for (final tool in section.tools)
            if (tool.available &&
                extensions.isNotEmpty &&
                (extensions.length == 1 || tool.multiple) &&
                extensions.every(tool.accepts.contains))
              tool,
      ];

  // A getter, not a cached field, so the texts follow the current language.
  static List<_ToolSection> get _sections => [
    _ToolSection(tr('Umwandeln', 'Convert'), [
      ToolEntry(
        tr('Bilder → PDF', 'Images → PDF'),
        tr('Mehrere Bilder zu einer PDF zusammenfassen', 'Combine several images into one PDF'),
        Icons.image_outlined,
        (_) => const ImagesToPdfScreen(),
        accepts: _images, multiple: true,
      ),
      ToolEntry(
        tr('PDF → Bilder', 'PDF → images'),
        tr('Jede Seite einer PDF als Bild exportieren', 'Export every page of a PDF as an image'),
        Icons.photo_library_outlined,
        (_) => const PdfToImagesScreen(),
        accepts: _pdf,
      ),
      ToolEntry(
        'PDF → PowerPoint',
        tr('Jede Seite als Bild-Folie (offline, nicht text-editierbar)', 'Every page as a picture slide (offline, text not editable)'),
        Icons.slideshow_outlined,
        (_) => const PdfToPptxScreen(),
        accepts: _pdf,
      ),
      ToolEntry(
        'PowerPoint → PDF',
        tr('Echte Konvertierung über dein Google-Konto', 'Real conversion through your Google account'),
        Icons.picture_as_pdf_outlined,
        (_) => const PptxToPdfScreen(),
        accepts: {'pptx'},
        needsInternet: true,
      ),
      ToolEntry(
        'Word → PDF',
        tr('Echte Konvertierung über dein Google-Konto', 'Real conversion through your Google account'),
        Icons.picture_as_pdf_outlined,
        (_) => const WordToPdfScreen(),
        accepts: {'docx'},
        needsInternet: true,
      ),
      ToolEntry(
        'PDF → Word',
        tr('Editierbar, mit Texterkennung über dein Google-Konto', 'Editable, with text recognition through your Google account'),
        Icons.description_outlined,
        (_) => const PdfToWordScreen(),
        accepts: _pdf,
        needsInternet: true,
      ),
      ToolEntry(
        'HTML → PDF',
        tr('Über dein Google-Konto', 'Through your Google account'),
        Icons.code,
        (_) => const HtmlToPdfScreen(),
        accepts: {'html', 'htm'},
        needsInternet: true,
      ),
      ToolEntry(
        'Markdown → PDF',
        tr('Formatierter Text aus .md-Dateien (offline)', 'Formatted text from .md files (offline)'),
        Icons.article_outlined,
        (_) => const MarkdownToPdfScreen(),
        accepts: {'md', 'markdown', 'txt'},
      ),
      ToolEntry(
        tr('Text aus Bild (OCR)', 'Text from image (OCR)'),
        tr('Text aus einem Foto erkennen, kopieren oder als .txt speichern', 'Recognize text in a photo, copy it or save it as .txt'),
        Icons.text_snippet_outlined,
        (_) => const TextFromImageScreen(),
        accepts: _images,
        needsInternet: !AppPlatform.isAndroid,
      ),
      ToolEntry(
        tr('PDF durchsuchbar machen', 'Make PDF searchable'),
        tr('Gescannte PDF mit unsichtbarer Textebene (offline)', 'Scanned PDF with an invisible text layer (offline)'),
        Icons.manage_search,
        (_) => const SearchablePdfScreen(),
        accepts: _pdf,
        androidOnly: true,
      ),
    ]),
    _ToolSection(tr('Bearbeiten', 'Edit'), [
      ToolEntry(
        tr('PDF ausfüllen & unterschreiben', 'Fill in & sign PDF'),
        tr('Text, Datum, Haken und Unterschrift einfügen', 'Insert text, date, check marks and signature'),
        Icons.edit_note,
        (_) => const AnnotatePdfScreen(mode: AnnotateMode.fill),
        accepts: _pdf,
      ),
      ToolEntry(
        tr('PDF markieren & zeichnen', 'Highlight & draw on PDF'),
        tr('Mit Stift und Textmarker auf Seiten zeichnen', 'Draw on pages with pen and highlighter'),
        Icons.brush_outlined,
        (_) => const AnnotatePdfScreen(mode: AnnotateMode.draw),
        accepts: _pdf,
      ),
      ToolEntry(
        tr('Seitenzahlen & Kopfzeile', 'Page numbers & header'),
        tr('Seitenzahlen, Kopf- und Fußzeile hinzufügen', 'Add page numbers, header and footer'),
        Icons.format_list_numbered,
        (_) => const PageNumbersScreen(),
        accepts: _pdf,
      ),
      ToolEntry(
        tr('PDFs zusammenführen', 'Merge PDFs'),
        tr('Mehrere PDFs in einer Reihenfolge verbinden', 'Join several PDFs in a chosen order'),
        Icons.merge_type,
        (_) => const MergePdfScreen(),
        accepts: _pdf, multiple: true,
      ),
      ToolEntry(
        tr('PDF aufteilen', 'Split PDF'),
        tr('Nach Seitenbereich in mehrere PDFs aufteilen', 'Split into several PDFs by page range'),
        Icons.content_cut,
        (_) => const SplitPdfScreen(),
        accepts: _pdf,
      ),
      ToolEntry(
        tr('PDF drehen', 'Rotate PDF'),
        tr('Ganze Datei(en) oder einzelne Seiten', 'Whole file(s) or single pages'),
        Icons.rotate_right,
        (_) => const RotatePdfScreen(),
        accepts: _pdf, multiple: true,
      ),
      ToolEntry(
        tr('PDF zuschneiden', 'Crop PDF'),
        tr('Ränder auf allen oder gewählten Seiten entfernen', 'Remove margins on all or chosen pages'),
        Icons.crop,
        (_) => const CropPdfScreen(),
        accepts: _pdf,
      ),
      ToolEntry(
        tr('Wasserzeichen', 'Watermark'),
        tr('Text diagonal über jede Seite legen', 'Lay text diagonally across every page'),
        Icons.water_drop_outlined,
        (_) => const WatermarkPdfScreen(),
        accepts: _pdf,
      ),
      ToolEntry(
        tr('PDF komprimieren', 'Compress PDF'),
        tr('Dateigröße durch geringere Qualität verkleinern', 'Reduce file size by lowering quality'),
        Icons.compress,
        (_) => const CompressPdfScreen(),
        accepts: _pdf,
      ),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Werkzeuge', 'Tools')),
        actions: const [SettingsButton()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final side = centeredPadding(constraints.maxWidth, maxWidth: 1160).left;
          return CustomScrollView(
            slivers: [
              for (final section in _sections) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side + 4, 12, side, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      section.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 0, side, 12),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 380,
                      mainAxisExtent: 92,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    delegate: SliverChildListDelegate([
                      for (final tool in section.tools)
                        if (tool.available) _ToolCard(tool),
                    ]),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final ToolEntry tool;

  const _ToolCard(this.tool);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: tool.builder)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(tool.icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tool.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (tool.needsInternet) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: tr('Braucht Internet und dein Google-Konto',
                                'Needs internet and your Google account'),
                            child: Icon(Icons.cloud_outlined, size: 16, color: scheme.outline),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tool.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
