// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:inara_pos/main.dart';
import 'package:inara_pos/providers/unified_database_provider.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    // Smoke test: ensure the root widget builds without throwing.
    await tester.pumpWidget(
      InaraPOSApp(databaseProvider: UnifiedDatabaseProvider()),
    );
    // Don't use pumpAndSettle here: the app can show indefinite animations
    // (e.g., loading indicators) during async initialization which will never
    // "settle" in a widget test environment.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(InaraPOSApp), findsOneWidget);
  });
}
