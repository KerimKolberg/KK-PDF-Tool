import 'dart:typed_data';

import 'package:doc_scanner/l10n.dart';
import 'package:doc_scanner/screens/edit_pages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Page i is an image i+1 pixels wide, so the saved order can be read back.
final _pages = [
  for (var i = 0; i < 5; i++) Uint8List.fromList(img.encodePng(img.Image(width: i + 1, height: 2))),
];

List<int> _order(List<Uint8List> pages) => [for (final p in pages) img.decodePng(p)!.width - 1];

Future<List<Uint8List>?> _edit(WidgetTester tester, Future<void> Function() actions) async {
  List<Uint8List>? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          result = await Navigator.of(context).push<List<Uint8List>>(
            MaterialPageRoute(builder: (_) => EditPagesScreen(pages: _pages)),
          );
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await actions();
  await tester.tap(find.text(tr('Speichern', 'Save')));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('selected pages move to the start together', (tester) async {
    final result = await _edit(tester, () async {
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.tap(find.byType(Checkbox).at(3));
      await tester.pump();
      expect(find.text(tr('2 ausgewählt', '2 selected')), findsOneWidget);
      await tester.tap(find.byTooltip(tr('Weitere Aktionen', 'More actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('An den Anfang', 'Move to start')));
      await tester.pumpAndSettle();
    });
    expect(_order(result!), [1, 3, 0, 2, 4]);
  });

  testWidgets('move down and delete work on the selection', (tester) async {
    final result = await _edit(tester, () async {
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byTooltip(tr('Nach unten', 'Move down')));
      await tester.pump();
      // Now [2, 0, 1, 3, 4] with 0 and 1 still selected; deselect 0, delete 1.
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byTooltip(tr('Löschen', 'Delete'))));
      await tester.pumpAndSettle();
    });
    expect(_order(result!), [2, 0, 3, 4]);
  });
}
