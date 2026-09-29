import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/core/services/wallpaper_service.dart';
import 'package:zen_launcher/presentation/widgets/wallpaper_tuning_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WallpaperTuningSheet', () {
    testWidgets('renders optical controls, presets, and sliders',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WallpaperTuningSheet(currentPitch: 6.5),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Title
      expect(find.text('2.5D Holographic Optics'), findsOneWidget);

      // Verify Mode Chips
      expect(find.text('🪟 Window'), findsOneWidget);
      expect(find.text('🎭 Diorama'), findsOneWidget);
      expect(find.text('🔮 Pop-Out'), findsOneWidget);

      // Verify Sliders
      expect(find.text('Fine-Detail Protection'), findsOneWidget);
      expect(find.text('3D Perspective Keystone'), findsOneWidget);
      expect(find.text('Depth Disparity Intensity'), findsOneWidget);
      expect(find.text('Focal Plane Depth'), findsOneWidget);
      expect(find.text('Holographic Sheen & Relief'), findsOneWidget);

      // Verify Buttons
      expect(find.text('Recenter Posture'), findsOneWidget);
      expect(find.text('Sync Wallpaper'), findsOneWidget);
    });

    testWidgets('tapping preset chip updates WallpaperService parameters',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WallpaperTuningSheet(currentPitch: 6.5),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap '🎭 Diorama' chip
      await tester.tap(find.text('🎭 Diorama'));
      await tester.pumpAndSettle();

      expect(WallpaperService.instance.focusPlane, 0.50);
      expect(WallpaperService.instance.depthIntensity, 0.048);

      // Tap '🔮 Pop-Out' chip
      await tester.tap(find.text('🔮 Pop-Out'));
      await tester.pumpAndSettle();

      expect(WallpaperService.instance.focusPlane, 0.15);
      expect(WallpaperService.instance.depthIntensity, 0.052);
    });

    testWidgets('tapping recenter posture updates resting pitch and shows snackbar',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WallpaperTuningSheet(currentPitch: 7.8),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recenter Posture'));
      await tester.pump();

      expect(WallpaperService.instance.restingPitch, 7.8);
      expect(
        find.text('Orientation recentered to current holding posture'),
        findsOneWidget,
      );
    });

    testWidgets('shows metadata dialog when info icon is tapped',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      WallpaperService.instance.setHolographicAssetsForTesting(
        metadata: {
          'title': 'Test Architectural Wonder',
          'prompt': 'Futuristic floating spire',
          'vector': {
            'typology': 'Monumental cantilever',
            'atmosphere': 'Luminous mist',
            'materials': 'Obsidian glass',
          },
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WallpaperTuningSheet(currentPitch: 6.0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final infoButton = find.byTooltip('Wallpaper Telemetry');
      expect(infoButton, findsOneWidget);

      await tester.tap(infoButton);
      await tester.pumpAndSettle();

      expect(find.text('Test Architectural Wonder'), findsOneWidget);
      expect(find.text('Futuristic floating spire'), findsOneWidget);
      expect(find.text('Luminous mist'), findsOneWidget);
      expect(find.text('Obsidian glass'), findsOneWidget);
    });
  });
}
