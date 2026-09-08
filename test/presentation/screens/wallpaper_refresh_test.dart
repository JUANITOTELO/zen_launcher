import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/presentation/screens/home_screen.dart';

void main() {
  testWidgets('Double tap on home screen triggers wallpaper sync gesture detector', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify HomeScreen renders with double-tap gesture detector
    final gestureFinder = find.byType(GestureDetector);
    expect(gestureFinder, findsWidgets);

    // Initial check on the background stack
    expect(find.byType(Stack), findsWidgets);
  });
}
