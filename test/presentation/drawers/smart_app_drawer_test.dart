import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/core/services/app_cache_service.dart';
import 'package:zen_launcher/presentation/drawers/smart_app_drawer.dart';

void main() {
  testWidgets('SmartAppListDrawer has focus node and dismisses keyboard on scroll/tap', (WidgetTester tester) async {
    AppCacheService.instance.setAppsForTesting([]);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SmartAppListDrawer(),
        ),
      ),
    );
    await tester.pump();

    // Verify search field exists
    final searchFieldFinder = find.byType(TextField);
    expect(searchFieldFinder, findsOneWidget);

    final TextField textField = tester.widget<TextField>(searchFieldFinder);
    expect(textField.focusNode, isNotNull);

    // Verify CustomScrollView has keyboardDismissBehavior set to onDrag
    final scrollViewFinder = find.byType(CustomScrollView);
    expect(scrollViewFinder, findsOneWidget);
    final CustomScrollView scrollView = tester.widget<CustomScrollView>(scrollViewFinder);
    expect(scrollView.keyboardDismissBehavior, ScrollViewKeyboardDismissBehavior.onDrag);
  });
}
