import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zen_launcher/data/database/zen_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ZenDatabase v3', () {
    late ZenDatabase dbService;

    setUp(() async {
      dbService = ZenDatabase.testInstance();
      final db = await dbService.initInMemory();
      expect(await db.getVersion(), 3);
    });

    test('saves and retrieves launcher settings', () async {
      await dbService.setSetting('quick_action_left', 'com.example.phone');
      final val = await dbService.getSetting('quick_action_left');
      expect(val, 'com.example.phone');

      final missing = await dbService.getSetting('non_existent');
      expect(missing, isNull);
    });

    test('caches apps and preserves usage stats and custom names across updates', () async {
      // 1. Insert app stats with custom name
      await dbService.registerApp('com.example.chat', 123456);
      await dbService.incrementUsage('com.example.chat');
      await dbService.setCustomAppName('com.example.chat', 'My Messenger');

      // 2. Cache app details
      await dbService.saveCachedApps([
        CachedAppRecord(
          packageName: 'com.example.chat',
          appName: 'ChatApp',
          versionName: '1.0.0',
          versionCode: 1,
          isSystemApp: false,
          icon: Uint8List.fromList([1, 2, 3]),
          installedTimestamp: 123456,
        ),
      ]);

      // 3. Retrieve cached apps joined with stats
      final cached = await dbService.getCachedApps();
      expect(cached.length, 1);
      expect(cached.first.packageName, 'com.example.chat');
      expect(cached.first.appName, 'ChatApp');
      expect(cached.first.usageCount, 1);
      expect(cached.first.firstSeenTimestamp, 123456);
      expect(cached.first.customName, 'My Messenger');

      // 4. Update app version in cache: usage count and custom name must NOT be lost
      await dbService.saveCachedApps([
        CachedAppRecord(
          packageName: 'com.example.chat',
          appName: 'ChatApp Updated',
          versionName: '2.0.0',
          versionCode: 2,
          isSystemApp: false,
          icon: Uint8List.fromList([4, 5, 6]),
          installedTimestamp: 123456,
        ),
      ]);

      final updated = await dbService.getCachedApps();
      expect(updated.length, 1);
      expect(updated.first.appName, 'ChatApp Updated');
      expect(updated.first.usageCount, 1); // Preserved!
      expect(updated.first.firstSeenTimestamp, 123456); // Preserved!
      expect(updated.first.customName, 'My Messenger'); // Preserved!
    });
  });
}
