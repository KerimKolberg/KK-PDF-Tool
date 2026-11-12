import 'package:doc_scanner/l10n.dart';
import 'package:doc_scanner/screens/tools_screen.dart';
import 'package:doc_scanner/widgets/file_actions.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _titles(List<String> kinds) => [for (final t in ToolsScreen.toolsFor(kinds)) t.title];

void main() {
  test('one PDF offers the PDF tools', () {
    final titles = _titles(['pdf']);
    expect(titles, containsAll([tr('PDF aufteilen', 'Split PDF'), tr('PDF komprimieren', 'Compress PDF'), 'PDF → Word']));
    expect(titles, isNot(contains(tr('Bilder → PDF', 'Images → PDF'))));
  });

  test('several PDFs only offer tools that take several files', () {
    expect(_titles(['pdf', 'pdf']), [tr('PDFs zusammenführen', 'Merge PDFs'), tr('PDF drehen', 'Rotate PDF')]);
  });

  test('images and other types', () {
    expect(_titles(['jpg', 'png']), [tr('Bilder → PDF', 'Images → PDF')]);
    expect(_titles(['docx']), ['Word → PDF']);
    expect(_titles(['pdf', 'jpg']), isEmpty);
    expect(isSupportedFile('Lebenslauf.PDF'), isTrue);
    expect(isSupportedFile('notes.exe'), isFalse);
  });
}
