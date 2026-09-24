import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/presentation/pages/zen_calendar_page.dart';

void main() {
  testWidgets('ZenCalendarPage renders focus header, day number, and month grid', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ZenCalendarPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FOCUS'), findsOneWidget);
    expect(find.text('EVENTS TODAY'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
  });
}
