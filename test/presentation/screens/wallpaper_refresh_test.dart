import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/core/services/wallpaper_service.dart';
import 'package:zen_launcher/presentation/screens/home_screen.dart';

void main() {
  testWidgets(
      'Double tap on home screen triggers wallpaper sync and recenter posture',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // Set a known initial resting pitch
    WallpaperService.instance.setRestingPitch(4.0);
    expect(WallpaperService.instance.restingPitch, 4.0);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify HomeScreen renders with gesture detector
    final gestureFinder = find.byType(GestureDetector);
    expect(gestureFinder, findsWidgets);

    // Double-tap on center of screen
    await tester.tap(find.byType(HomeScreen));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(HomeScreen));
    // Settle past double-tap window (kDoubleTapTimeout is 300ms)
    await tester.pump(const Duration(milliseconds: 400));

    // Verify restingPitch was recentered to default holding pitch (6.0 in HomeScreen)
    expect(WallpaperService.instance.restingPitch, 6.0);

    // Cancel pending timer from sync failure in headless test before invariant check
    WallpaperService.instance.cancelTimerForTesting();
  });
}
