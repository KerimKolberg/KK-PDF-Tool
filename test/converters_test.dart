import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:doc_scanner/screens/tools/markdown_to_pdf_screen.dart';
import 'package:doc_scanner/services/file_picker_service.dart';
import 'package:doc_scanner/services/markdown_pdf_service.dart';
import 'package:doc_scanner/services/pptx_writer_service.dart';
import 'package:doc_scanner/utils/layout.dart';
import 'package:doc_scanner/widgets/tool_drop_zone.dart';
import 'package:doc_scanner/widgets/tool_layout.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('Markdown becomes a PDF', () async {
    final pdf = await MarkdownPdfService.convert(
      '# Title\n\nSome *text* and a list:\n\n- one\n- two\n',
    );
    expect(utf8.decode(pdf.sublist(0, 5)), '%PDF-');
  });

  test('a PPTX has one slide and one picture per page', () {
    final page = Uint8List.fromList(img.encodePng(img.Image(width: 16, height: 9)));
    final archive = ZipDecoder().decodeBytes(PptxWriterService.buildPptx([page, page, page]));
    final names = [for (final file in archive) file.name];
    expect(names.where((n) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(n)), hasLength(3));
    expect(names.where((n) => n.startsWith('ppt/media/')), hasLength(3));
    expect(names, contains('[Content_Types].xml'));
  });

  group('files handed to a tool', () {
    const pdfs = [
      XTypeGroup(label: 'PDF', extensions: ['pdf']),
    ];

    test('only files of a fitting type reach the tool', () async {
      FilePickers.setDropped([XFile('a.docx'), XFile('b.PDF'), XFile('c.pdf')]);
      final files = await FilePickers.openMany('test', pdfs);
      expect([for (final f in files) f.path], ['b.PDF', 'c.pdf']);
      expect(FilePickers.clearDropped(), isFalse);
    });

    test('an unsuitable file is reported instead of opening a dialog', () async {
      FilePickers.setDropped([XFile('photo.jpg')]);
      expect(await FilePickers.openOne('test', pdfs), isNull);
      expect(FilePickers.clearDropped(), isTrue);
    });

    testWidgets('a tool opened for a file starts with that file loaded', (tester) async {
      final file = File('${Directory.systemTemp.createTempSync('md').path}/Notes.md')
        ..writeAsStringSync('# Hello');
      AppPlatform.debugIsWindows = false;
      addTearDown(() => AppPlatform.debugIsWindows = null);

      ToolDropZone.openWithFiles([file.path]);
      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(home: MarkdownToPdfScreen()));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(find.byType(FilePickPanel), findsNothing);
      expect(find.widgetWithText(SelectedFileTile, 'Notes'), findsOneWidget);
    });
  });
}
