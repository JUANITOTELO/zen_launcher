import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

class HolographicViewport extends StatefulWidget {
  final ui.Image colorImage;
  final ui.Image depthImage;
  final ui.FragmentShader shader;
  final double focusPlane;
  final double depthIntensity;
  final double overscan;
  final double sheen;
  final double detailSensitivity;
  final double perspectiveWarp;
  final bool invertX;
  final bool invertY;
  final double restingPitch;
  final bool lockTouchPosition;
  final bool enableTouch;
  final ValueChanged<double>? onPitchUpdate;

  const HolographicViewport({
    super.key,
    required this.colorImage,
    required this.depthImage,
    required this.shader,
    required this.focusPlane,
    required this.depthIntensity,
    required this.overscan,
    required this.sheen,
    required this.detailSensitivity,
    required this.perspectiveWarp,
    required this.invertX,
    required this.invertY,
    required this.restingPitch,
    this.lockTouchPosition = false,
    this.enableTouch = false,
    this.onPitchUpdate,
  });

  @override
  State<HolographicViewport> createState() => _HolographicViewportState();
}

class _HolographicViewportState extends State<HolographicViewport>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Offset _currentTilt = Offset.zero;
  Offset _sensorTilt = Offset.zero;
  Offset _touchOffset = Offset.zero;
  Offset _touchVelocity = Offset.zero;
  bool _isUserTouching = false;

  StreamSubscription<AccelerometerEvent>? _sensorSubscription;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initTicker();
    _startSensors();
  }

  void _initTicker() {
    _ticker = createTicker((_) {
      if (!mounted) return;

      if (!widget.enableTouch || !_isUserTouching) {
        if (!widget.lockTouchPosition) {
          if (_touchOffset.distanceSquared > 0.00002) {
            _touchOffset += _touchVelocity * 0.016;
            _touchVelocity *= 0.85;
            _touchOffset *= 0.90;
          } else {
            _touchOffset = Offset.zero;
            _touchVelocity = Offset.zero;
          }
        }
      }

      final Offset target = (widget.enableTouch && _isUserTouching)
          ? _touchOffset
          : Offset(
              (_sensorTilt.dx + _touchOffset.dx).clamp(-1.0, 1.0),
              (_sensorTilt.dy + _touchOffset.dy).clamp(-1.0, 1.0),
            );

      final double factor =
          (widget.enableTouch && _isUserTouching) ? 0.24 : 0.12;
      final newTilt = Offset(
        ui.lerpDouble(_currentTilt.dx, target.dx, factor) ?? target.dx,
        ui.lerpDouble(_currentTilt.dy, target.dy, factor) ?? target.dy,
      );

      // Avoid redundant rebuilds if motion is imperceptible
      if ((newTilt - _currentTilt).distanceSquared > 0.000001) {
        setState(() {
          _currentTilt = newTilt;
        });
      }
    });

    _ticker.start();
  }

  void _startSensors() {
    _sensorSubscription?.cancel();
    try {
      _sensorSubscription = accelerometerEventStream().listen(
        (AccelerometerEvent event) {
          widget.onPitchUpdate?.call(event.y);

          // Roll (X axis)
          double x = (event.x / 4.0).clamp(-1.0, 1.0);
          // Pitch (Y axis calibrated to natural ~50-60° holding angle)
          double y =
              ((event.y - widget.restingPitch) / 3.5).clamp(-1.0, 1.0);

          if (widget.invertX) x = -x;
          if (widget.invertY) y = -y;

          _sensorTilt = Offset(x, y);
        },
        onError: (_) {
          // Sensor stream unavailable or errored (fallback to neutral tilt)
        },
        cancelOnError: false,
      );
    } catch (_) {
      // Sensor platform channel missing (desktop / testing environment)
    }
  }

  void _stopSensors() {
    _sensorSubscription?.cancel();
    _sensorSubscription = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_ticker.isActive) _ticker.start();
      _startSensors();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_ticker.isActive) _ticker.stop();
      _stopSensors();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSensors();
    _ticker.dispose();
    super.dispose();
  }

  void _handlePanStart(DragStartDetails details) {
    _isUserTouching = true;
    _touchVelocity = Offset.zero;
    _touchOffset = _currentTilt;
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    double deltaX = details.delta.dx / (size.width * 0.40);
    double deltaY = details.delta.dy / (size.height * 0.40);

    if (widget.invertX) deltaX = -deltaX;
    if (widget.invertY) deltaY = -deltaY;

    _touchOffset = Offset(
      (_touchOffset.dx + deltaX).clamp(-1.0, 1.0),
      (_touchOffset.dy + deltaY).clamp(-1.0, 1.0),
    );
  }

  void _handlePanEnd(DragEndDetails details, Size size) {
    _isUserTouching = false;
    double vx = details.velocity.pixelsPerSecond.dx / (size.width * 0.40);
    double vy = details.velocity.pixelsPerSecond.dy / (size.height * 0.40);

    if (widget.invertX) vx = -vx;
    if (widget.invertY) vy = -vy;

    _touchVelocity = Offset(vx.clamp(-3.0, 3.0), vy.clamp(-3.0, 3.0));
  }

  void _handlePanCancel() {
    _isUserTouching = false;
    _touchVelocity = Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    final customPaint = CustomPaint(
      size: Size.infinite,
      painter: HolographicPainter(
        shader: widget.shader,
        colorImage: widget.colorImage,
        depthImage: widget.depthImage,
        tilt: _currentTilt,
        focusPlane: widget.focusPlane,
        depthIntensity: widget.depthIntensity,
        overscan: widget.overscan,
        sheen: widget.sheen,
        detailSensitivity: widget.detailSensitivity,
        perspectiveWarp: widget.perspectiveWarp,
      ),
    );

    if (!widget.enableTouch) {
      return customPaint;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _handlePanStart,
          onPanUpdate: (details) => _handlePanUpdate(details, size),
          onPanEnd: (details) => _handlePanEnd(details, size),
          onPanCancel: _handlePanCancel,
          child: customPaint,
        );
      },
    );
  }
}

class HolographicPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image colorImage;
  final ui.Image depthImage;
  final Offset tilt;
  final double focusPlane;
  final double depthIntensity;
  final double overscan;
  final double sheen;
  final double detailSensitivity;
  final double perspectiveWarp;

  HolographicPainter({
    required this.shader,
    required this.colorImage,
    required this.depthImage,
    required this.tilt,
    required this.focusPlane,
    required this.depthIntensity,
    required this.overscan,
    required this.sheen,
    required this.detailSensitivity,
    required this.perspectiveWarp,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Uniforms mapping to shaders/holographic.frag:
    // 0: u_resolution.x, 1: u_resolution.y
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);

    // 2: u_offset.x, 3: u_offset.y
    shader.setFloat(2, tilt.dx);
    shader.setFloat(3, tilt.dy);

    // 4: u_focus_plane, 5: u_depth_intensity, 6: u_overscan, 7: u_sheen
    shader.setFloat(4, focusPlane);
    shader.setFloat(5, depthIntensity);
    shader.setFloat(6, overscan);
    shader.setFloat(7, sheen);

    // 8: u_detail_sensitivity, 9: u_perspective_warp
    shader.setFloat(8, detailSensitivity);
    shader.setFloat(9, perspectiveWarp);

    // Samplers: 0 = u_image, 1 = u_depth
    shader.setImageSampler(0, colorImage);
    shader.setImageSampler(1, depthImage);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant HolographicPainter oldDelegate) {
    return oldDelegate.tilt != tilt ||
        oldDelegate.focusPlane != focusPlane ||
        oldDelegate.depthIntensity != depthIntensity ||
        oldDelegate.overscan != overscan ||
        oldDelegate.sheen != sheen ||
        oldDelegate.detailSensitivity != detailSensitivity ||
        oldDelegate.perspectiveWarp != perspectiveWarp ||
        oldDelegate.colorImage != colorImage ||
        oldDelegate.depthImage != depthImage;
  }
}
