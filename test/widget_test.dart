import 'package:flutter_test/flutter_test.dart';

import 'package:doc_scanner/main.dart';

void main() {
  testWidgets('App startet und zeigt die Bibliotheksansicht', (tester) async {
    await tester.pumpWidget(const DocScannerApp());
    await tester.pump();

    expect(find.text('Meine Scans'), findsOneWidget);
    expect(find.text('Neuer Scan'), findsOneWidget);
  });
}
