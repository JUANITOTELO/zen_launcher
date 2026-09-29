import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zen_launcher/core/services/wallpaper_service.dart';
import 'package:zen_launcher/data/database/zen_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('WallpaperService', () {
    test('initial state has no file and is not syncing', () {
      final service = WallpaperService();
      expect(service.isSyncing, isFalse);
      expect(service.wallpaperFile, isNull);
      expect(service.wallpaperVersion, 0);
      expect(service.isHolographicReady, isFalse);
    });

    test('default holographic tuning parameters match calibration', () {
      final service = WallpaperService();
      expect(service.focusPlane, 0.85);
      expect(service.depthIntensity, 0.055);
      expect(service.overscan, 1.15);
      expect(service.sheen, 0.0015);
      expect(service.detailSensitivity, 0.75);
      expect(service.perspectiveWarp, 0.38);
      expect(service.invertX, isFalse);
      expect(service.invertY, isFalse);
      expect(service.restingPitch, 6.0);
      expect(service.lockTouchPosition, isFalse);
    });

    test('notifyListeners triggers on sync status update', () {
      final service = WallpaperService();
      bool notified = false;
      service.addListener(() => notified = true);

      service.setLocalFileForTesting(File('/dummy/path.webp'));
      expect(notified, isTrue);
      expect(service.wallpaperFile?.path, '/dummy/path.webp');
    });

    test('optical setters update values and notify listeners', () {
      final service = WallpaperService();
      int notifyCount = 0;
      service.addListener(() => notifyCount++);

      service.setFocusPlane(0.5);
      expect(service.focusPlane, 0.5);

      service.setDepthIntensity(0.08);
      expect(service.depthIntensity, 0.08);

      service.setOverscan(1.2);
      expect(service.overscan, 1.2);

      service.setSheen(0.005);
      expect(service.sheen, 0.005);

      service.setDetailSensitivity(0.9);
      expect(service.detailSensitivity, 0.9);

      service.setPerspectiveWarp(0.5);
      expect(service.perspectiveWarp, 0.5);

      service.setInvertX(true);
      expect(service.invertX, isTrue);

      service.setInvertY(true);
      expect(service.invertY, isTrue);

      service.setRestingPitch(7.2);
      expect(service.restingPitch, 7.2);

      service.setLockTouchPosition(true);
      expect(service.lockTouchPosition, isTrue);

      expect(notifyCount, 10);
    });

    test('applyPreset updates multiple optical values at once', () {
      final service = WallpaperService();
      bool notified = false;
      service.addListener(() => notified = true);

      service.applyPreset(
        focusPlane: 0.15,
        depthIntensity: 0.052,
        overscan: 1.14,
        detailSensitivity: 0.80,
        perspectiveWarp: 0.35,
      );

      expect(notified, isTrue);
      expect(service.focusPlane, 0.15);
      expect(service.depthIntensity, 0.052);
      expect(service.overscan, 1.14);
      expect(service.detailSensitivity, 0.80);
      expect(service.perspectiveWarp, 0.35);
    });

    test('recenterHoldingAngle updates restingPitch and notifies', () {
      final service = WallpaperService();
      bool notified = false;
      service.addListener(() => notified = true);

      service.recenterHoldingAngle(8.5);
      expect(notified, isTrue);
      expect(service.restingPitch, 8.5);
    });

    test('persists optical settings to ZenDatabase', () async {
      final testDb = ZenDatabase.testInstance();
      await testDb.initInMemory();

      final service = WallpaperService(testDb);
      service.setFocusPlane(0.42);
      service.setInvertX(true);

      // Verify stored in launcher_settings
      final storedFp = await testDb.getSetting('wallpaper_focus_plane');
      final storedIx = await testDb.getSetting('wallpaper_invert_x');
      expect(storedFp, '0.42');
      expect(storedIx, 'true');
    });
  });
}
