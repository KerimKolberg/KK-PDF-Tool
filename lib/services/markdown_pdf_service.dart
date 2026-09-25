import 'dart:typed_data';

import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Renders Markdown source straight into a styled PDF, fully offline - no
/// HTML/cloud round-trip needed. Headings, emphasis, links, lists,
/// blockquotes, code blocks, tables and horizontal rules get matching PDF
/// styling. Embedded images are shown as a small placeholder line, since
/// reliably resolving local/remote image paths is out of scope.
class MarkdownPdfService {
  static const _blockTags = {
    'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'ul', 'ol', 'li',
    'blockquote', 'pre', 'hr',
    'table', 'thead', 'tbody', 'tr', 'th', 'td',
  };

  static const _baseStyle = pw.TextStyle(fontSize: 11, lineSpacing: 2);

  static Future<Uint8List> convert(String source) async {
    final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
        .parseLines(source.replaceAll('\r\n', '\n').split('\n'));

    final mono = pw.Font.courier();
    final widgets = _renderBlocks(nodes, mono, _baseStyle, 0);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => widgets,
      ),
    );
    return doc.save();
  }

  static List<pw.Widget> _renderBlocks(
    List<md.Node> nodes,
    pw.Font mono,
    pw.TextStyle style,
    int depth,
  ) {
    final widgets = <pw.Widget>[];
    for (final node in nodes) {
      final widget = _renderBlock(node, mono, style, depth);
      if (widget != null) widgets.add(widget);
    }
    return widgets;
  }

  static pw.Widget? _renderBlock(
    md.Node node,
    pw.Font mono,
    pw.TextStyle style,
    int depth,
  ) {
    if (node is md.Text) {
      if (node.text.trim().isEmpty) return null;
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.RichText(text: pw.TextSpan(children: _inline([node], style, mono))),
      );
    }
    if (node is! md.Element) return null;

    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(node.tag.substring(1));
        return pw.Padding(
          padding: pw.EdgeInsets.only(top: level <= 2 ? 16 : 10, bottom: 6),
          child: pw.RichText(
            text: pw.TextSpan(
              children: _inline(node.children ?? const [], _headingStyle(level), mono),
            ),
          ),
        );

      case 'p':
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.RichText(
            text: pw.TextSpan(children: _inline(node.children ?? const [], style, mono)),
          ),
        );

      case 'hr':
        return pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 10),
          height: 0.8,
          color: PdfColors.grey400,
        );

      case 'blockquote':
        final quoteStyle = style.copyWith(
          fontStyle: pw.FontStyle.italic,
          color: PdfColors.grey700,
        );
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.only(left: 12, top: 2, bottom: 2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(color: PdfColors.grey400, width: 3),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: _renderBlocks(node.children ?? const [], mono, quoteStyle, depth),
          ),
        );

      case 'pre':
        final codeText = node.textContent.replaceAll(RegExp(r'\n$'), '');
        return pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(codeText, style: pw.TextStyle(font: mono, fontSize: 9.5)),
        );

      case 'ul':
        return _renderList(node, false, mono, style, depth);
      case 'ol':
        return _renderList(node, true, mono, style, depth);

      case 'table':
        return _renderTable(node, style);

      default:
        // Unknown/unsupported block tag: fall back to its plain text content.
        final text = node.textContent.trim();
        if (text.isEmpty) return null;
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(text, style: style),
        );
    }
  }

  static pw.Widget _renderList(
    md.Element listEl,
    bool ordered,
    pw.Font mono,
    pw.TextStyle style,
    int depth,
  ) {
    final items = (listEl.children ?? const [])
        .whereType<md.Element>()
        .where((e) => e.tag == 'li')
        .toList();
    var index = int.tryParse(listEl.attributes['start'] ?? '') ?? 1;

    final rows = <pw.Widget>[];
    for (final li in items) {
      final marker = ordered ? '$index.' : '•';
      if (ordered) index++;

      final children = li.children ?? const <md.Node>[];
      final blockChildren =
          children.where((c) => c is md.Element && _blockTags.contains(c.tag)).toList();
      final inlineChildren =
          children.where((c) => !(c is md.Element && _blockTags.contains(c.tag))).toList();

      final content = <pw.Widget>[];
      if (inlineChildren.isNotEmpty) {
        content.add(
          pw.RichText(text: pw.TextSpan(children: _inline(inlineChildren, style, mono))),
        );
      }
      content.addAll(_renderBlocks(blockChildren, mono, style, depth + 1));

      rows.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(left: 14.0 * depth, bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 18, child: pw.Text(marker, style: style)),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: content,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: rows);
  }

  static pw.Widget _renderTable(md.Element table, pw.TextStyle style) {
    List<String>? headerRow;
    final bodyRows = <List<String>>[];

    for (final section in table.children ?? const []) {
      if (section is! md.Element) continue;
      final isHead = section.tag == 'thead';
      final isBody = section.tag == 'tbody';
      if (!isHead && !isBody) continue;

      for (final tr in section.children ?? const []) {
        if (tr is! md.Element || tr.tag != 'tr') continue;
        final row = [
          for (final cell in tr.children ?? const [])
            if (cell is md.Element) cell.textContent.trim(),
        ];
        if (isHead) {
          headerRow = row;
        } else {
          bodyRows.add(row);
        }
      }
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.TableHelper.fromTextArray(
        headers: headerRow,
        data: bodyRows,
        cellStyle: style.copyWith(fontSize: 9.5),
        headerStyle: style.copyWith(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
        cellAlignment: pw.Alignment.centerLeft,
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
    );
  }

  static List<pw.InlineSpan> _inline(
    List<md.Node> nodes,
    pw.TextStyle style,
    pw.Font mono,
  ) {
    final spans = <pw.InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        spans.add(pw.TextSpan(text: node.text, style: style));
        continue;
      }
      if (node is! md.Element) continue;

      switch (node.tag) {
        case 'strong':
          spans.add(pw.TextSpan(
            children: _inline(
              node.children ?? const [],
              style.copyWith(fontWeight: pw.FontWeight.bold),
              mono,
            ),
          ));
          break;
        case 'em':
          spans.add(pw.TextSpan(
            children: _inline(
              node.children ?? const [],
              style.copyWith(fontStyle: pw.FontStyle.italic),
              mono,
            ),
          ));
          break;
        case 'del':
          spans.add(pw.TextSpan(
            children: _inline(
              node.children ?? const [],
              style.copyWith(decoration: pw.TextDecoration.lineThrough),
              mono,
            ),
          ));
          break;
        case 'code':
          spans.add(pw.TextSpan(
            text: node.textContent,
            style: style.copyWith(font: mono, fontSize: (style.fontSize ?? 11) - 0.5),
          ));
          break;
        case 'a':
          final href = node.attributes['href'] ?? '';
          spans.add(pw.TextSpan(
            children: _inline(
              node.children ?? const [],
              style.copyWith(color: PdfColors.blue700, decoration: pw.TextDecoration.underline),
              mono,
            ),
            annotation: href.isEmpty ? null : pw.AnnotationUrl(href),
          ));
          break;
        case 'br':
          spans.add(pw.TextSpan(text: '\n', style: style));
          break;
        case 'img':
          final alt = node.attributes['alt'] ?? 'Bild';
          spans.add(pw.TextSpan(
            text: '[$alt]',
            style: style.copyWith(fontStyle: pw.FontStyle.italic, color: PdfColors.grey600),
          ));
          break;
        default:
          spans.add(pw.TextSpan(children: _inline(node.children ?? const [], style, mono)));
      }
    }
    return spans;
  }

  static pw.TextStyle _headingStyle(int level) {
    const sizes = {1: 22.0, 2: 18.0, 3: 15.0, 4: 13.0, 5: 12.0, 6: 11.0};
    return pw.TextStyle(
      fontSize: sizes[level] ?? 11,
      fontWeight: pw.FontWeight.bold,
    );
  }
}
