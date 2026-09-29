import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/presentation/widgets/holographic_viewport.dart';

// Helper to create a 1x1 test ui.Image in memory
Future<ui.Image> createTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..color = const ui.Color(0xFF00FF00);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), paint);
  final picture = recorder.endRecording();
  return await picture.toImage(1, 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HolographicViewport & HolographicPainter', () {
    late ui.Image dummyColorImage;
    late ui.Image dummyDepthImage;
    late ui.FragmentShader realShader;

    setUpAll(() async {
      dummyColorImage = await createTestImage();
      dummyDepthImage = await createTestImage();
      final program =
          await ui.FragmentProgram.fromAsset('shaders/holographic.frag');
      realShader = program.fragmentShader();
    });

    test('shouldRepaint returns false when properties are identical', () {
      final painter1 = HolographicPainter(
        shader: realShader,
        colorImage: dummyColorImage,
        depthImage: dummyDepthImage,
        tilt: const ui.Offset(0.1, 0.2),
        focusPlane: 0.85,
        depthIntensity: 0.055,
        overscan: 1.15,
        sheen: 0.0015,
        detailSensitivity: 0.75,
        perspectiveWarp: 0.38,
      );

      final painter2 = HolographicPainter(
        shader: realShader,
        colorImage: dummyColorImage,
        depthImage: dummyDepthImage,
        tilt: const ui.Offset(0.1, 0.2),
        focusPlane: 0.85,
        depthIntensity: 0.055,
        overscan: 1.15,
        sheen: 0.0015,
        detailSensitivity: 0.75,
        perspectiveWarp: 0.38,
      );

      expect(painter1.shouldRepaint(painter2), isFalse);
    });

    test('shouldRepaint returns true when tilt or optical params change', () {
      final base = HolographicPainter(
        shader: realShader,
        colorImage: dummyColorImage,
        depthImage: dummyDepthImage,
        tilt: const ui.Offset(0.1, 0.2),
        focusPlane: 0.85,
        depthIntensity: 0.055,
        overscan: 1.15,
        sheen: 0.0015,
        detailSensitivity: 0.75,
        perspectiveWarp: 0.38,
      );

      final differentTilt = HolographicPainter(
        shader: realShader,
        colorImage: dummyColorImage,
        depthImage: dummyDepthImage,
        tilt: const ui.Offset(0.3, 0.4),
        focusPlane: 0.85,
        depthIntensity: 0.055,
        overscan: 1.15,
        sheen: 0.0015,
        detailSensitivity: 0.75,
        perspectiveWarp: 0.38,
      );

      final differentFocus = HolographicPainter(
        shader: realShader,
        colorImage: dummyColorImage,
        depthImage: dummyDepthImage,
        tilt: const ui.Offset(0.1, 0.2),
        focusPlane: 0.50,
        depthIntensity: 0.055,
        overscan: 1.15,
        sheen: 0.0015,
        detailSensitivity: 0.75,
        perspectiveWarp: 0.38,
      );

      expect(base.shouldRepaint(differentTilt), isTrue);
      expect(base.shouldRepaint(differentFocus), isTrue);
    });

    test('HolographicPainter.paint executes without error', () {
      final painter = HolographicPainter(
        shader: realShader,
        colorImage: dummyColorImage,
        depthImage: dummyDepthImage,
        tilt: const ui.Offset(0.1, 0.2),
        focusPlane: 0.85,
        depthIntensity: 0.055,
        overscan: 1.15,
        sheen: 0.0015,
        detailSensitivity: 0.75,
        perspectiveWarp: 0.38,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      expect(
        () => painter.paint(canvas, const Size(400, 800)),
        returnsNormally,
      );
    });

    testWidgets('HolographicViewport mounts and renders CustomPaint',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HolographicViewport(
              colorImage: dummyColorImage,
              depthImage: dummyDepthImage,
              shader: realShader,
              focusPlane: 0.85,
              depthIntensity: 0.055,
              overscan: 1.15,
              sheen: 0.0015,
              detailSensitivity: 0.75,
              perspectiveWarp: 0.38,
              invertX: false,
              invertY: false,
              restingPitch: 6.0,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
