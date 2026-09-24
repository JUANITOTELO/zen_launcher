import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/core/services/wallpaper_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WallpaperService', () {
    test('initial state has no file and is not syncing', () {
      final service = WallpaperService();
      expect(service.isSyncing, isFalse);
      expect(service.wallpaperFile, isNull);
      expect(service.wallpaperVersion, 0);
    });

    test('notifyListeners triggers on sync status update', () {
      final service = WallpaperService();
      bool notified = false;
      service.addListener(() => notified = true);

      service.setLocalFileForTesting(File('/dummy/path.webp'));
      expect(notified, isTrue);
      expect(service.wallpaperFile?.path, '/dummy/path.webp');
    });
  });
}
