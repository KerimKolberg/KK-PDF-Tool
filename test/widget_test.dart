import 'package:doc_scanner/l10n.dart';
import 'package:doc_scanner/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => L10n.language.value = 'de');

  testWidgets('App startet und zeigt die Bibliotheksansicht', (tester) async {
    await tester.pumpWidget(const DocScannerApp());
    await tester.pump();

    expect(find.text('Meine Scans'), findsOneWidget);
    expect(find.text('Neuer Scan'), findsOneWidget);
  });

  testWidgets('switches the whole UI to English', (tester) async {
    await tester.pumpWidget(const DocScannerApp());
    await tester.pump();

    L10n.language.value = 'en';
    await tester.pump();

    expect(find.text('My scans'), findsOneWidget);
    expect(find.text('New scan'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('Meine Scans'), findsNothing);
  });
}
