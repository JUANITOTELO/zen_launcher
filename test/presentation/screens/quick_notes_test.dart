import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/presentation/screens/home_screen.dart';

void main() {
  testWidgets('Quick notes page can toggle lock and unlock editing', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll to page 999 (Notes)
    final pageView = tester.widget<PageView>(find.byType(PageView));
    pageView.controller!.jumpToPage(999);
    await tester.pumpAndSettle();

    expect(find.text('THOUGHTS'), findsOneWidget);
    final lockButtonFinder = find.byKey(const Key('notes_lock_button'));
    expect(lockButtonFinder, findsOneWidget);

    final textFieldFinder = find.byKey(const Key('notes_text_field'));
    expect(textFieldFinder, findsOneWidget);

    TextField textField = tester.widget<TextField>(textFieldFinder);
    expect(textField.readOnly, isFalse);

    // Tap lock button to toggle
    await tester.tap(lockButtonFinder);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    textField = tester.widget<TextField>(textFieldFinder);
    expect(textField.readOnly, isTrue);

    // Tap again to unlock
    await tester.tap(lockButtonFinder);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    textField = tester.widget<TextField>(textFieldFinder);
    expect(textField.readOnly, isFalse);
  });
}
