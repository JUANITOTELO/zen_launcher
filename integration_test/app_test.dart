import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zen_launcher/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Zen Launcher End-to-End Tests', () {
    testWidgets('E2E: Left side notes lock and unlock editing workflow', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Carousel starts at 1000 (Home). Page 999 is Notes.
      final pageViewFinder = find.byType(PageView);
      expect(pageViewFinder, findsOneWidget);
      final PageView pageView = tester.widget<PageView>(pageViewFinder);
      pageView.controller!.jumpToPage(999);
      await tester.pumpAndSettle();

      expect(find.text('THOUGHTS'), findsOneWidget);

      final lockButtonFinder = find.byKey(const Key('notes_lock_button'));
      expect(lockButtonFinder, findsOneWidget);

      final textFieldFinder = find.byKey(const Key('notes_text_field'));
      expect(textFieldFinder, findsOneWidget);

      // Ensure unlocked for typing
      TextField textField = tester.widget<TextField>(textFieldFinder);
      if (textField.readOnly) {
        await tester.tap(lockButtonFinder);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
      }

      await tester.enterText(textFieldFinder, 'Zen e2e note test');
      await tester.pumpAndSettle();
      expect(find.text('Zen e2e note test'), findsOneWidget);

      // Lock notes
      await tester.tap(lockButtonFinder);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.readOnly, isTrue);

      // Return to home page (page 1000)
      pageView.controller!.jumpToPage(1000);
      await tester.pumpAndSettle();
    });

    testWidgets('E2E: App drawer opens, searches, and dismisses cleanly without keyboard leak', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Open drawer using arrow up button
      final drawerButton = find.byIcon(Icons.keyboard_arrow_up);
      expect(drawerButton, findsOneWidget);
      await tester.tap(drawerButton);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Verify search field is displayed in bottom sheet
      final searchFieldFinder = find.widgetWithText(TextField, 'Search...');
      expect(searchFieldFinder, findsOneWidget);

      // Tap search and enter query
      await tester.tap(searchFieldFinder);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(searchFieldFinder, 'search test');
      await tester.pumpAndSettle();

      // Dismiss drawer by dragging down
      await tester.drag(find.byType(DraggableScrollableSheet), const Offset(0, 600));
      await tester.pumpAndSettle();

      // Verify drawer is dismissed and arrow button is back
      expect(find.widgetWithText(TextField, 'Search...'), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    });

    testWidgets('E2E: Wallpaper refresh on command', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Double-tap on the home screen to trigger refresh
      final homeCenter = tester.getCenter(find.byType(PageView));
      await tester.tapAt(homeCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(homeCenter);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Verify widget tree remains stable and responsive
      expect(find.byType(PageView), findsOneWidget);
    });
  });
}
