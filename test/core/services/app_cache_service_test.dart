import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:installed_apps/app_category.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/platform_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zen_launcher/core/services/app_cache_service.dart';
import 'package:zen_launcher/data/database/zen_database.dart';
import 'package:zen_launcher/domain/models/zen_app.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AppCacheService Caching, Renaming & Updates', () {
    setUp(() async {
      await ZenDatabase.instance.initInMemory();
    });

    tearDown(() async {
      await ZenDatabase.instance.close();
    });

    test('cold boot populates apps immediately from SQLite cache', () async {
      await ZenDatabase.instance.saveCachedApps([
        CachedAppRecord(
          packageName: 'com.test.instant',
          appName: 'Instant App',
          versionName: '1.0',
          versionCode: 1,
          isSystemApp: false,
          icon: Uint8List(0),
          installedTimestamp: 1000,
          usageCount: 5,
          firstSeenTimestamp: 500,
          customName: 'Custom Fast App',
        ),
      ]);

      final service = AppCacheService.instance;
      await service.loadFromDatabaseCache();

      expect(service.isLoaded, isTrue);
      expect(service.apps.length, 1);
      expect(service.apps.first.displayName, 'Custom Fast App');
      expect(service.apps.first.usageCount, 5);
      expect(service.apps.first.firstSeenTimestamp, 500);
    });

    test('renameApp updates app display name and persists in database', () async {
      final app = ZenApp(
        info: const AppInfo(
          name: 'Original',
          icon: null,
          packageName: 'com.test.rename',
          versionName: '1.0',
          versionCode: 1,
          platformType: PlatformType.nativeOrOthers,
          installedTimestamp: 0,
          isSystemApp: false,
          isLaunchableApp: true,
          category: AppCategory.undefined,
        ),
        usageCount: 0,
        firstSeenTimestamp: 0,
      );

      final service = AppCacheService.instance;
      service.setAppsForTesting([app]);

      await service.renameApp(app, 'New Zen Name');
      expect(app.displayName, 'New Zen Name');

      final stats = await ZenDatabase.instance.getAllStats();
      expect(stats['com.test.rename']!['custom_name'], 'New Zen Name');
    });

    test('reconcileInstalledApps preserves existing stats and first-seen on updates', () async {
      await ZenDatabase.instance.registerApp('com.test.app', 1000);
      await ZenDatabase.instance.incrementUsage('com.test.app'); // usage = 1

      final service = AppCacheService.instance;

      final rawApps = [
        const AppInfo(
          name: 'Updated App Name',
          icon: null,
          packageName: 'com.test.app',
          versionName: '2.0.0',
          versionCode: 2,
          platformType: PlatformType.nativeOrOthers,
          installedTimestamp: 1000,
          isSystemApp: false,
          isLaunchableApp: true,
          category: AppCategory.undefined,
        ),
      ];

      await service.reconcileInstalledApps(rawApps);

      expect(service.apps.length, 1);
      final updatedApp = service.apps.firstWhere((a) => a.info.packageName == 'com.test.app');
      expect(updatedApp.info.name, 'Updated App Name');
      expect(updatedApp.usageCount, 1); // Preserved!
      expect(updatedApp.firstSeenTimestamp, 1000); // Preserved!
    });

    test('apps filters out hidden apps while hiddenApps retains them', () async {
      final app1 = ZenApp(
        info: const AppInfo(
          name: 'Public App',
          icon: null,
          packageName: 'com.test.public',
          versionName: '1.0',
          versionCode: 1,
          platformType: PlatformType.nativeOrOthers,
          installedTimestamp: 0,
          isSystemApp: false,
          isLaunchableApp: true,
          category: AppCategory.undefined,
        ),
        usageCount: 0,
        firstSeenTimestamp: 0,
        isHidden: false,
      );

      final app2 = ZenApp(
        info: const AppInfo(
          name: 'Secret App',
          icon: null,
          packageName: 'com.test.secret',
          versionName: '1.0',
          versionCode: 1,
          platformType: PlatformType.nativeOrOthers,
          installedTimestamp: 0,
          isSystemApp: false,
          isLaunchableApp: true,
          category: AppCategory.undefined,
        ),
        usageCount: 0,
        firstSeenTimestamp: 0,
        isHidden: true,
      );

      final service = AppCacheService.instance;
      service.setAppsForTesting([app1, app2]);

      expect(service.apps.length, 1);
      expect(service.apps.first.displayName, 'Public App');

      expect(service.hiddenApps.length, 1);
      expect(service.hiddenApps.first.displayName, 'Secret App');

      expect(service.allApps.length, 2);

      // Toggle public app to hidden
      await service.toggleHideApp(app1);
      expect(service.apps.length, 0);
      expect(service.hiddenApps.length, 2);

      // Verify persisted in DB
      final stats = await ZenDatabase.instance.getAllStats();
      expect(stats['com.test.public']!['is_hidden'], isTrue);

      // Unhide secret app
      await service.setAppHidden(app2, false);
      expect(service.apps.length, 1);
      expect(service.apps.first.displayName, 'Secret App');
      expect(service.hiddenApps.length, 1);
    });

    test('PIN authentication setup, verification, and removal', () async {
      final service = AppCacheService.instance;

      // Initially no PIN
      await service.removePin();
      expect(await service.hasPin(), isFalse);

      // Set PIN
      await service.setPin('1234');
      expect(await service.hasPin(), isTrue);

      // Verify correct PIN
      expect(await service.verifyPin('1234'), isTrue);

      // Verify wrong PIN
      expect(await service.verifyPin('9999'), isFalse);
      expect(await service.verifyPin('123'), isFalse);

      // Remove PIN
      await service.removePin();
      expect(await service.hasPin(), isFalse);
    });
  });
}
