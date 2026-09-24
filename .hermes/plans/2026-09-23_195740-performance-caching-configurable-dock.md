# Performance Caching, Persistent App Updates, Configurable Dock, App Drawer Actions & Atomic Decoupling

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Transform Zen Launcher into a high-performance, resilient launcher with instant SQLite cold boot, update preservation, configurable dock shortcuts, rich app drawer actions (uninstall, app settings, custom renaming), and an atomic decoupled architecture.

**Architecture:** A SQLite-first persistence strategy caches installed app metadata, custom aliases, and launcher settings to guarantee instantaneous startup (<20ms) and preserve usage stats across package updates, with native Android lifecycle broadcasts (`ACTION_PACKAGE_REPLACED`, `ACTION_PACKAGE_REMOVED`). The UI layer is decoupled into atomic domain models, services (`WallpaperService`, `QuickActionService`, `AppCacheService`), extracted pages (`QuickNotesPage`, `ZenCalendarPage`), a customizable `HomeDock`, and a minimalist `AppActionsSheet` for drawer item long-press operations.

**Tech Stack:** Flutter 3.10+ / Dart 3, SQLite (`sqflite`), `installed_apps` 2.1.0, Android Kotlin Native Channels (`EventChannel`, `BroadcastReceiver`), Material Icons, `path_provider`, `wallpaper_manager_plus`.

---

## Current Context & Assumptions

- **Root directory:** `/home/hto/Documents/flutter-apps/zen_launcher`
- **Flutter execution flag:** Always run tests with `--no-version-check` (e.g. `flutter test --no-version-check`) due to file ownership on the Flutter version check stamp.
- **Current state:**
  - `home_screen.dart` is 634 lines and handles wallpaper syncing, timers, notes, calendar, and dock.
  - `app_cache_service.dart` does not persist app metadata or icons to SQLite; cold starts must wait for slow IPC with `InstalledApps.getInstalledApps(withIcon: true)`.
  - `MainActivity.kt` misses `ACTION_PACKAGE_REPLACED`, causing app updates to go unnoticed.
  - Phone and Camera quick access buttons are hardcoded.
  - `AppListItem` only supports tap-to-launch; there is no way to uninstall, open system app settings, or assign custom names to apps.
  - `installed_apps` package already provides `InstalledApps.uninstallApp(packageName)` and `InstalledApps.openSettings(packageName)`.

---

## File Structure Plan

```
lib/
├── core/
│   ├── constants/
│   │   └── app_constants.dart             [NEW: Default packages, database keys]
│   └── services/
│       ├── app_cache_service.dart         [MODIFY: Cold boot DB cache, background sync, renaming]
│       ├── quick_action_service.dart      [NEW: Slot management, persistence, launching]
│       └── wallpaper_service.dart         [NEW: Wallpaper download, 24h timer, platform sync]
├── data/
│   └── database/
│       └── zen_database.dart              [MODIFY: Schema v3, app_cache, custom_name, launcher_settings]
├── domain/
│   └── models/
│       ├── quick_action_slot.dart         [NEW: Enum & slot configuration models]
│       └── zen_app.dart                   [MODIFY: Custom name & displayName support]
├── presentation/
│   ├── drawers/
│   │   └── smart_app_drawer.dart          [MODIFY: Pass long-press to open app actions sheet]
│   ├── pages/
│   │   ├── quick_notes_page.dart          [NEW: Extracted thoughts page with lock/unlock]
│   │   └── zen_calendar_page.dart         [NEW: Extracted focus calendar visualization]
│   ├── screens/
│   │   └── home_screen.dart               [MODIFY: Slim orchestrator ~120 lines]
│   └── widgets/
│       ├── app_actions_sheet.dart         [NEW: Minimalist sheet for uninstall, settings, rename]
│       ├── app_list_item.dart             [MODIFY: Support onLongPress callback & displayName]
│       ├── clock_widget.dart              [UNCHANGED]
│       ├── home_dock.dart                 [NEW: Customizable bottom dock]
│       └── quick_action_picker_sheet.dart [NEW: Minimalist app picker bottom sheet]
android/
└── app/src/main/kotlin/com/example/zen_launcher/
    └── MainActivity.kt                    [MODIFY: Add ACTION_PACKAGE_REPLACED broadcast]
```

---

## Step-by-Step Implementation Tasks

### Task 1: Native Broadcast Receiver for Package Updates

**Objective:** Add `Intent.ACTION_PACKAGE_REPLACED` to `MainActivity.kt` so Android app updates trigger Flutter cache synchronization.

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/zen_launcher/MainActivity.kt:31-36`

**Step 1: Inspect and apply update to MainActivity.kt**
Add `addAction(Intent.ACTION_PACKAGE_REPLACED)` to the `IntentFilter`.

```kotlin
                    // 2. Define what we are listening for
                    val filter = IntentFilter().apply {
                        addAction(Intent.ACTION_PACKAGE_ADDED)
                        addAction(Intent.ACTION_PACKAGE_REMOVED)
                        addAction(Intent.ACTION_PACKAGE_FULLY_REMOVED)
                        addAction(Intent.ACTION_PACKAGE_REPLACED)
                        addDataScheme("package") // Essential: Listen for package changes
                    }
```

**Step 2: Verification**
Run: `git diff android/app/src/main/kotlin/com/example/zen_launcher/MainActivity.kt`
Expected: Diff shows `addAction(Intent.ACTION_PACKAGE_REPLACED)` added cleanly.

**Step 3: Commit**
```bash
git add android/app/src/main/kotlin/com/example/zen_launcher/MainActivity.kt
git commit -m "feat(android): listen for ACTION_PACKAGE_REPLACED broadcast"
```

---

### Task 2: Constants & Domain Models (QuickActionSlot & ZenApp Custom Renaming)

**Objective:** Define app constants, `QuickActionSlot`, and update `ZenApp` to support custom display names/renaming.

**Files:**
- Create: `lib/core/constants/app_constants.dart`
- Create: `lib/domain/models/quick_action_slot.dart`
- Modify: `lib/domain/models/zen_app.dart`
- Create: `test/domain/models/zen_app_test.dart`
- Create: `test/domain/models/quick_action_slot_test.dart`

**Step 1: Write failing tests**
Create `test/domain/models/quick_action_slot_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/domain/models/quick_action_slot.dart';

void main() {
  group('QuickActionSlot', () {
    test('enum contains left and right slots', () {
      expect(QuickActionSlot.values.length, 2);
      expect(QuickActionSlot.left.key, 'quick_action_left');
      expect(QuickActionSlot.right.key, 'quick_action_right');
    });

    test('default label reflects phone and camera', () {
      expect(QuickActionSlot.left.defaultLabel, 'Phone');
      expect(QuickActionSlot.right.defaultLabel, 'Camera');
    });
  });
}
```

Create `test/domain/models/zen_app_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:installed_apps/app_category.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/platform_type.dart';
import 'package:zen_launcher/domain/models/zen_app.dart';

void main() {
  group('ZenApp Custom Name', () {
    const info = AppInfo(
      name: 'Original Name',
      icon: null,
      packageName: 'com.example.app',
      versionName: '1.0',
      versionCode: 1,
      platformType: PlatformType.android,
      installedTimestamp: 0,
      isSystemApp: false,
      isLaunchableApp: true,
      category: AppCategory.other,
    );

    test('displayName returns info.name when customName is null or empty', () {
      final app = ZenApp(info: info, usageCount: 0, firstSeenTimestamp: 0);
      expect(app.displayName, 'Original Name');
      expect(app.normalizedName, 'original name');
    });

    test('displayName returns customName and updates normalizedName when customName is set', () {
      final app = ZenApp(
        info: info,
        usageCount: 0,
        firstSeenTimestamp: 0,
        customName: 'Custom Alias',
      );
      expect(app.displayName, 'Custom Alias');
      expect(app.normalizedName, 'custom alias');
    });
  });
}
```

**Step 2: Run test to verify failure**
Run: `flutter test --no-version-check test/domain/models/zen_app_test.dart test/domain/models/quick_action_slot_test.dart`
Expected: FAIL — `quick_action_slot.dart` missing, `displayName` / `customName` not in `ZenApp`.

**Step 3: Implement minimal code**
Create `lib/core/constants/app_constants.dart`:

```dart
class AppConstants {
  static const String dbName = 'zen_launcher.db';
  static const int dbVersion = 3;

  // Default candidate packages for auto-discovery
  static const List<String> defaultPhonePackages = [
    'com.google.android.dialer',
    'com.android.dialer',
    'com.samsung.android.dialer',
    'com.android.contacts',
  ];

  static const List<String> defaultCameraPackages = [
    'com.google.android.GoogleCamera',
    'com.android.camera',
    'com.sec.android.app.camera',
    'com.oneplus.camera',
    'com.motorola.camera2',
  ];

  static const List<String> defaultClockPackages = [
    'com.google.android.deskclock',
    'com.android.deskclock',
    'com.sec.android.app.clockpackage',
    'com.oneplus.deskclock',
    'com.miui.deskclock',
    'com.coloros.alarmclock',
    'com.asus.deskclock',
  ];
}
```

Create `lib/domain/models/quick_action_slot.dart`:

```dart
enum QuickActionSlot {
  left(key: 'quick_action_left', defaultLabel: 'Phone'),
  right(key: 'quick_action_right', defaultLabel: 'Camera');

  final String key;
  final String defaultLabel;

  const QuickActionSlot({required this.key, required this.defaultLabel});
}

class QuickActionConfig {
  final QuickActionSlot slot;
  final String? packageName;
  final String? customLabel;

  const QuickActionConfig({
    required this.slot,
    this.packageName,
    this.customLabel,
  });

  bool get isCustom => packageName != null && packageName!.isNotEmpty;

  QuickActionConfig copyWith({
    String? packageName,
    String? customLabel,
    bool clearCustom = false,
  }) {
    return QuickActionConfig(
      slot: slot,
      packageName: clearCustom ? null : (packageName ?? this.packageName),
      customLabel: clearCustom ? null : (customLabel ?? this.customLabel),
    );
  }
}
```

Update `lib/domain/models/zen_app.dart`:

```dart
import 'package:installed_apps/app_info.dart';

class ZenApp {
  final AppInfo info;
  int usageCount;
  final int firstSeenTimestamp; // Unix millis
  String? customName;

  ZenApp({
    required this.info,
    required this.usageCount,
    required this.firstSeenTimestamp,
    this.customName,
  });

  String get displayName =>
      (customName != null && customName!.trim().isNotEmpty)
          ? customName!.trim()
          : info.name;

  String get normalizedName => displayName.toLowerCase();

  // It is "New" if it was seen less than 3 hours ago
  bool get isNew {
    if (firstSeenTimestamp == 0) return false;
    final installTime = DateTime.fromMillisecondsSinceEpoch(firstSeenTimestamp);
    final diff = DateTime.now().difference(installTime);
    return diff.inHours < 3;
  }
}
```

**Step 4: Run test to verify pass**
Run: `flutter test --no-version-check test/domain/models/zen_app_test.dart test/domain/models/quick_action_slot_test.dart`
Expected: PASS — All tests passed!

**Step 5: Commit**
```bash
git add lib/core/constants/app_constants.dart lib/domain/models/quick_action_slot.dart lib/domain/models/zen_app.dart test/domain/models/quick_action_slot_test.dart test/domain/models/zen_app_test.dart
git commit -m "feat(domain): add QuickActionSlot models and ZenApp custom renaming support"
```

---

### Task 3: Database Schema v3 (App Cache, Custom Names & Launcher Settings)

**Objective:** Upgrade `ZenDatabase` to version 3 to persist cached apps, custom aliases/renames, and launcher settings.

**Files:**
- Modify: `lib/data/database/zen_database.dart`
- Create: `test/data/database/zen_database_test.dart`

**Step 1: Write failing test**
Create `test/data/database/zen_database_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
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
```

**Step 2: Run test to verify failure**
Run: `flutter test --no-version-check test/data/database/zen_database_test.dart`
Expected: FAIL — `ZenDatabase.testInstance` and new methods not defined.

**Step 3: Implement minimal code**
Update `lib/data/database/zen_database.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../../core/constants/app_constants.dart';

class CachedAppRecord {
  final String packageName;
  final String appName;
  final String versionName;
  final int versionCode;
  final bool isSystemApp;
  final Uint8List? icon;
  final int installedTimestamp;
  final int usageCount;
  final int firstSeenTimestamp;
  final String? customName;

  CachedAppRecord({
    required this.packageName,
    required this.appName,
    required this.versionName,
    required this.versionCode,
    required this.isSystemApp,
    this.icon,
    required this.installedTimestamp,
    this.usageCount = 0,
    this.firstSeenTimestamp = 0,
    this.customName,
  });
}

class ZenDatabase {
  static final ZenDatabase instance = ZenDatabase._init();
  static Database? _database;

  ZenDatabase._init();

  @visibleForTesting
  factory ZenDatabase.testInstance() => ZenDatabase._init();

  @visibleForTesting
  Future<Database> initInMemory() async {
    _database = await openDatabase(
      inMemoryDatabasePath,
      version: AppConstants.dbVersion,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
    return _database!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(AppConstants.dbName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE app_stats (
        package_name TEXT PRIMARY KEY,
        usage_count INTEGER DEFAULT 0,
        is_hidden INTEGER DEFAULT 0,
        first_seen INTEGER DEFAULT 0,
        custom_name TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE app_cache (
        package_name TEXT PRIMARY KEY,
        app_name TEXT NOT NULL,
        version_name TEXT,
        version_code INTEGER,
        is_system_app INTEGER DEFAULT 0,
        installed_timestamp INTEGER DEFAULT 0,
        icon BLOB,
        updated_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE launcher_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE app_stats ADD COLUMN first_seen INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE app_stats ADD COLUMN custom_name TEXT',
      );

      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_cache (
          package_name TEXT PRIMARY KEY,
          app_name TEXT NOT NULL,
          version_name TEXT,
          version_code INTEGER,
          is_system_app INTEGER DEFAULT 0,
          installed_timestamp INTEGER DEFAULT 0,
          icon BLOB,
          updated_at INTEGER
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS launcher_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
  }

  /// Returns map of PackageName -> {usage, firstSeen, customName}
  Future<Map<String, Map<String, dynamic>>> getAllStats() async {
    final db = await database;
    final result = await db.query('app_stats');

    final Map<String, Map<String, dynamic>> map = {};
    for (var row in result) {
      map[row['package_name'] as String] = {
        'usage': (row['usage_count'] as int?) ?? 0,
        'first_seen': (row['first_seen'] as int?) ?? 0,
        'custom_name': row['custom_name'] as String?,
      };
    }
    return map;
  }

  Future<void> registerApp(String packageName, int timestamp) async {
    final db = await database;
    await db.rawInsert(
      'INSERT OR IGNORE INTO app_stats (package_name, usage_count, first_seen) VALUES (?, 0, ?)',
      [packageName, timestamp],
    );
  }

  Future<void> incrementUsage(String packageName) async {
    final db = await database;
    await db.rawInsert(
      '''INSERT INTO app_stats (package_name, usage_count, first_seen) 
         VALUES (?, 1, ?) 
         ON CONFLICT(package_name) DO UPDATE SET usage_count = usage_count + 1''',
      [packageName, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> setCustomAppName(String packageName, String? customName) async {
    final db = await database;
    await db.rawInsert(
      '''INSERT INTO app_stats (package_name, usage_count, first_seen, custom_name)
         VALUES (?, 0, ?, ?)
         ON CONFLICT(package_name) DO UPDATE SET custom_name = excluded.custom_name''',
      [packageName, DateTime.now().millisecondsSinceEpoch, customName],
    );
  }

  // --- App Cache Operations ---

  Future<void> saveCachedApps(List<CachedAppRecord> apps) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final app in apps) {
      batch.rawInsert(
        '''INSERT INTO app_cache (
             package_name, app_name, version_name, version_code, 
             is_system_app, installed_timestamp, icon, updated_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(package_name) DO UPDATE SET
             app_name = excluded.app_name,
             version_name = excluded.version_name,
             version_code = excluded.version_code,
             is_system_app = excluded.is_system_app,
             installed_timestamp = excluded.installed_timestamp,
             icon = excluded.icon,
             updated_at = excluded.updated_at
        ''',
        [
          app.packageName,
          app.appName,
          app.versionName,
          app.versionCode,
          app.isSystemApp ? 1 : 0,
          app.installedTimestamp,
          app.icon,
          now,
        ],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<CachedAppRecord>> getCachedApps() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT 
        c.package_name,
        c.app_name,
        c.version_name,
        c.version_code,
        c.is_system_app,
        c.installed_timestamp,
        c.icon,
        COALESCE(s.usage_count, 0) as usage_count,
        COALESCE(s.first_seen, 0) as first_seen,
        s.custom_name
      FROM app_cache c
      LEFT JOIN app_stats s ON c.package_name = s.package_name
      ORDER BY COALESCE(s.usage_count, 0) DESC, LOWER(COALESCE(s.custom_name, c.app_name)) ASC
    ''');

    return results.map((row) {
      return CachedAppRecord(
        packageName: row['package_name'] as String,
        appName: row['app_name'] as String,
        versionName: (row['version_name'] as String?) ?? '1.0.0',
        versionCode: (row['version_code'] as int?) ?? 1,
        isSystemApp: (row['is_system_app'] as int?) == 1,
        icon: row['icon'] as Uint8List?,
        installedTimestamp: (row['installed_timestamp'] as int?) ?? 0,
        usageCount: (row['usage_count'] as int?) ?? 0,
        firstSeenTimestamp: (row['first_seen'] as int?) ?? 0,
        customName: row['custom_name'] as String?,
      );
    }).toList();
  }

  Future<void> removeCachedApps(List<String> packageNames) async {
    if (packageNames.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(packageNames.length, '?').join(',');
    await db.rawDelete(
      'DELETE FROM app_cache WHERE package_name IN ($placeholders)',
      packageNames,
    );
  }

  // --- Launcher Settings Operations ---

  Future<String?> getSetting(String key) async {
    final db = await database;
    final res = await db.query(
      'launcher_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (res.isEmpty) return null;
    return res.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.rawInsert(
      '''INSERT INTO launcher_settings (key, value) VALUES (?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value''',
      [key, value],
    );
  }

  Future<void> removeSetting(String key) async {
    final db = await database;
    await db.delete(
      'launcher_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
  }
}
```

**Step 4: Run test to verify pass**
Run: `flutter test --no-version-check test/data/database/zen_database_test.dart`
Expected: PASS — All tests passed!

**Step 5: Commit**
```bash
git add lib/data/database/zen_database.dart test/data/database/zen_database_test.dart
git commit -m "feat(database): upgrade to v3 with app_cache, custom_name, and launcher_settings"
```

---

### Task 4: Quick Action Service

**Objective:** Create `QuickActionService` to manage left/right dock button configurations, persist selections in `ZenDatabase`, and resolve launches with fallbacks.

**Files:**
- Create: `lib/core/services/quick_action_service.dart`
- Create: `test/core/services/quick_action_service_test.dart`

**Step 1: Write failing test**
Create `test/core/services/quick_action_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zen_launcher/core/services/quick_action_service.dart';
import 'package:zen_launcher/data/database/zen_database.dart';
import 'package:zen_launcher/domain/models/quick_action_slot.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('QuickActionService', () {
    late QuickActionService service;

    setUp(() async {
      await ZenDatabase.instance.initInMemory();
      service = QuickActionService(ZenDatabase.instance);
      await service.init();
    });

    test('defaults to null packages for left and right slots', () {
      expect(service.getConfig(QuickActionSlot.left).isCustom, isFalse);
      expect(service.getConfig(QuickActionSlot.right).isCustom, isFalse);
    });

    test('sets custom package and persists in database', () async {
      await service.setCustomApp(
        slot: QuickActionSlot.left,
        packageName: 'com.whatsapp',
        label: 'WhatsApp',
      );

      expect(service.getConfig(QuickActionSlot.left).isCustom, isTrue);
      expect(service.getConfig(QuickActionSlot.left).packageName, 'com.whatsapp');
      expect(service.getConfig(QuickActionSlot.left).customLabel, 'WhatsApp');

      final reloadedService = QuickActionService(ZenDatabase.instance);
      await reloadedService.init();
      expect(reloadedService.getConfig(QuickActionSlot.left).packageName, 'com.whatsapp');
    });

    test('resets slot to default', () async {
      await service.setCustomApp(
        slot: QuickActionSlot.right,
        packageName: 'com.instagram.android',
        label: 'Instagram',
      );
      expect(service.getConfig(QuickActionSlot.right).isCustom, isTrue);

      await service.resetToDefault(QuickActionSlot.right);
      expect(service.getConfig(QuickActionSlot.right).isCustom, isFalse);
      expect(service.getConfig(QuickActionSlot.right).packageName, isNull);
    });
  });
}
```

**Step 2: Run test to verify failure**
Run: `flutter test --no-version-check test/core/services/quick_action_service_test.dart`
Expected: FAIL — `QuickActionService` does not exist.

**Step 3: Write minimal implementation**
Create `lib/core/services/quick_action_service.dart`:

```dart
import 'package:flutter/material.dart';
import '../../data/database/zen_database.dart';
import '../../domain/models/quick_action_slot.dart';
import '../../domain/models/zen_app.dart';
import '../constants/app_constants.dart';
import 'app_cache_service.dart';

class QuickActionService extends ChangeNotifier {
  static QuickActionService instance = QuickActionService(ZenDatabase.instance);

  final ZenDatabase _database;
  final Map<QuickActionSlot, QuickActionConfig> _configs = {
    QuickActionSlot.left: const QuickActionConfig(slot: QuickActionSlot.left),
    QuickActionSlot.right: const QuickActionConfig(slot: QuickActionSlot.right),
  };

  QuickActionService(this._database);

  QuickActionConfig getConfig(QuickActionSlot slot) => _configs[slot]!;

  Future<void> init() async {
    try {
      final leftPkg = await _database.getSetting(QuickActionSlot.left.key);
      final leftLbl = await _database.getSetting('${QuickActionSlot.left.key}_label');
      _configs[QuickActionSlot.left] = QuickActionConfig(
        slot: QuickActionSlot.left,
        packageName: leftPkg,
        customLabel: leftLbl,
      );

      final rightPkg = await _database.getSetting(QuickActionSlot.right.key);
      final rightLbl = await _database.getSetting('${QuickActionSlot.right.key}_label');
      _configs[QuickActionSlot.right] = QuickActionConfig(
        slot: QuickActionSlot.right,
        packageName: rightPkg,
        customLabel: rightLbl,
      );
    } catch (e) {
      debugPrint("Error loading quick action settings: $e");
    } finally {
      notifyListeners();
    }
  }

  Future<void> setCustomApp({
    required QuickActionSlot slot,
    required String packageName,
    required String label,
  }) async {
    _configs[slot] = QuickActionConfig(
      slot: slot,
      packageName: packageName,
      customLabel: label,
    );
    notifyListeners();

    try {
      await _database.setSetting(slot.key, packageName);
      await _database.setSetting('${slot.key}_label', label);
    } catch (e) {
      debugPrint("Error saving quick action setting: $e");
    }
  }

  Future<void> resetToDefault(QuickActionSlot slot) async {
    _configs[slot] = QuickActionConfig(slot: slot);
    notifyListeners();

    try {
      await _database.removeSetting(slot.key);
      await _database.removeSetting('${slot.key}_label');
    } catch (e) {
      debugPrint("Error resetting quick action setting: $e");
    }
  }

  ZenApp? resolveTargetApp(QuickActionSlot slot, List<ZenApp> installedApps) {
    final config = _configs[slot]!;

    if (config.isCustom) {
      try {
        return installedApps.firstWhere(
          (app) => app.info.packageName == config.packageName,
        );
      } catch (_) {
        return null;
      }
    }

    if (slot == QuickActionSlot.left) {
      try {
        return installedApps.firstWhere(
          (app) => AppConstants.defaultPhonePackages.contains(app.info.packageName),
        );
      } catch (_) {
        try {
          return installedApps.firstWhere(
            (app) => app.displayName.toLowerCase().contains('phone'),
          );
        } catch (_) {
          return null;
        }
      }
    } else {
      try {
        return installedApps.firstWhere(
          (app) => AppConstants.defaultCameraPackages.contains(app.info.packageName),
        );
      } catch (_) {
        try {
          return installedApps.firstWhere(
            (app) => app.displayName.toLowerCase().contains('camera'),
          );
        } catch (_) {
          return null;
        }
      }
    }
  }

  void launchSlot(BuildContext context, QuickActionSlot slot) {
    final apps = AppCacheService.instance.apps;
    final target = resolveTargetApp(slot, apps);

    if (target != null) {
      AppCacheService.instance.launchApp(target);
    } else {
      final label = _configs[slot]?.customLabel ?? slot.defaultLabel;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label app not found'),
          backgroundColor: Colors.white10,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }
}
```

**Step 4: Run test to verify pass**
Run: `flutter test --no-version-check test/core/services/quick_action_service_test.dart`
Expected: PASS — All tests passed!

**Step 5: Commit**
```bash
git add lib/core/services/quick_action_service.dart test/core/services/quick_action_service_test.dart
git commit -m "feat(services): add QuickActionService with slot resolution & persistence"
```

---

### Task 5: Cold-Boot App Cache, Renaming & Preservation in AppCacheService

**Objective:** Refactor `AppCacheService` to load cached apps instantly from `ZenDatabase` on cold boot (<20ms), support custom app renaming (`renameApp`), run background sync with `InstalledApps`, and preserve usage stats and first-seen timestamps across updates.

**Files:**
- Modify: `lib/core/services/app_cache_service.dart`
- Create: `test/core/services/app_cache_service_test.dart`

**Step 1: Write failing test**
Create `test/core/services/app_cache_service_test.dart`:

```dart
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
          platformType: PlatformType.android,
          installedTimestamp: 0,
          isSystemApp: false,
          isLaunchableApp: true,
          category: AppCategory.other,
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
          platformType: PlatformType.android,
          installedTimestamp: 1000,
          isSystemApp: false,
          isLaunchableApp: true,
          category: AppCategory.other,
        ),
      ];

      await service.reconcileInstalledApps(rawApps);

      expect(service.apps.length, 1);
      final updatedApp = service.apps.firstWhere((a) => a.info.packageName == 'com.test.app');
      expect(updatedApp.info.name, 'Updated App Name');
      expect(updatedApp.usageCount, 1); // Preserved!
      expect(updatedApp.firstSeenTimestamp, 1000); // Preserved!
    });
  });
}
```

**Step 2: Run test to verify failure**
Run: `flutter test --no-version-check test/core/services/app_cache_service_test.dart`
Expected: FAIL — `loadFromDatabaseCache` / `renameApp` not defined.

**Step 3: Implement minimal code**
Update `lib/core/services/app_cache_service.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_category.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/platform_type.dart';

import '../../data/database/zen_database.dart';
import '../../domain/models/zen_app.dart';

class AppCacheService extends ChangeNotifier {
  static final AppCacheService instance = AppCacheService._();
  AppCacheService._();

  static const _eventChannel = EventChannel(
    'com.zen.launcher/app_change_events',
  );

  List<ZenApp> _cachedApps = [];
  bool _isLoaded = false;
  StreamSubscription? _appChangeSubscription;

  List<ZenApp> get apps => List.unmodifiable(_cachedApps);
  bool get isLoaded => _isLoaded;

  @visibleForTesting
  void setAppsForTesting(List<ZenApp> apps) {
    _cachedApps = apps;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> init() async {
    // 1. Fast path: load instantly from local SQLite cache (<20ms)
    await loadFromDatabaseCache();

    // 2. Background sync: scan installed packages & update cache
    unawaited(_syncInstalledApps());

    // 3. Listen to native Android package updates/installs/uninstalls
    _startListeningToChanges();
  }

  Future<void> loadFromDatabaseCache() async {
    try {
      final cachedRecords = await ZenDatabase.instance.getCachedApps();
      if (cachedRecords.isNotEmpty) {
        _cachedApps = cachedRecords.map((r) {
          final info = AppInfo(
            name: r.appName,
            icon: r.icon,
            packageName: r.packageName,
            versionName: r.versionName,
            versionCode: r.versionCode,
            platformType: PlatformType.android,
            installedTimestamp: r.installedTimestamp,
            isSystemApp: r.isSystemApp,
            isLaunchableApp: true,
            category: AppCategory.other,
          );
          return ZenApp(
            info: info,
            usageCount: r.usageCount,
            firstSeenTimestamp: r.firstSeenTimestamp,
            customName: r.customName,
          );
        }).toList();
        _sortApps();
        _isLoaded = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error loading from database cache: $e");
    }
  }

  void _startListeningToChanges() {
    if (!Platform.isAndroid) return;
    _appChangeSubscription?.cancel();
    try {
      _appChangeSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          debugPrint("Native App Event detected: $event");
          _syncInstalledApps();
        },
        onError: (error) {
          debugPrint("Error listening to app changes: $error");
        },
      );
    } catch (e) {
      debugPrint("Error setting up app changes event channel: $e");
    }
  }

  Future<void> _syncInstalledApps() async {
    List<AppInfo> rawApps = [];
    try {
      rawApps = await InstalledApps.getInstalledApps(
        excludeSystemApps: false,
        withIcon: true,
        packageNamePrefix: '',
      );
    } catch (e) {
      debugPrint("Error fetching installed apps: $e");
      return;
    }

    await reconcileInstalledApps(rawApps);
  }

  @visibleForTesting
  Future<void> reconcileInstalledApps(List<AppInfo> rawApps) async {
    Map<String, Map<String, dynamic>> stats = {};
    try {
      stats = await ZenDatabase.instance.getAllStats();
    } catch (e) {
      debugPrint("Error fetching app stats from database: $e");
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final bool isFreshInstall = stats.isEmpty && _cachedApps.isEmpty;

    final List<ZenApp> updatedApps = [];
    final List<CachedAppRecord> recordsToCache = [];
    final Set<String> activePackageNames = {};

    for (final app in rawApps) {
      activePackageNames.add(app.packageName);
      int usage = 0;
      int firstSeen = 0;
      String? customName;

      if (stats.containsKey(app.packageName)) {
        usage = stats[app.packageName]!['usage'] as int;
        firstSeen = stats[app.packageName]!['first_seen'] as int;
        customName = stats[app.packageName]!['custom_name'] as String?;
      } else {
        firstSeen = isFreshInstall ? 0 : now;
        try {
          await ZenDatabase.instance.registerApp(app.packageName, firstSeen);
        } catch (_) {}
      }

      updatedApps.add(
        ZenApp(
          info: app,
          usageCount: usage,
          firstSeenTimestamp: firstSeen,
          customName: customName,
        ),
      );

      recordsToCache.add(
        CachedAppRecord(
          packageName: app.packageName,
          appName: app.name,
          versionName: app.versionName,
          versionCode: app.versionCode,
          isSystemApp: app.isSystemApp,
          icon: app.icon,
          installedTimestamp: app.installedTimestamp,
          usageCount: usage,
          firstSeenTimestamp: firstSeen,
          customName: customName,
        ),
      );
    }

    // Persist to database cache
    try {
      await ZenDatabase.instance.saveCachedApps(recordsToCache);

      // Clean uninstalled apps from DB cache
      final existingDbRecords = await ZenDatabase.instance.getCachedApps();
      final stalePackages = existingDbRecords
          .map((r) => r.packageName)
          .where((pkg) => !activePackageNames.contains(pkg))
          .toList();
      if (stalePackages.isNotEmpty) {
        await ZenDatabase.instance.removeCachedApps(stalePackages);
      }
    } catch (e) {
      debugPrint("Error saving cached apps to database: $e");
    }

    _cachedApps = updatedApps;
    _sortApps();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> renameApp(ZenApp app, String? newName) async {
    final clean = (newName != null && newName.trim().isNotEmpty) ? newName.trim() : null;
    app.customName = clean;
    _sortApps();
    notifyListeners();

    try {
      await ZenDatabase.instance.setCustomAppName(app.info.packageName, clean);
    } catch (e) {
      debugPrint("Error persisting custom app name: $e");
    }
  }

  Future<void> launchApp(ZenApp app) async {
    app.usageCount++;
    _sortApps();
    notifyListeners();
    try {
      await ZenDatabase.instance.incrementUsage(app.info.packageName);
    } catch (_) {}
    try {
      await InstalledApps.startApp(app.info.packageName);
    } catch (e) {
      debugPrint("Error launching app: $e");
    }
  }

  void _sortApps() {
    _cachedApps.sort((a, b) {
      int comparison = b.usageCount.compareTo(a.usageCount);
      if (comparison != 0) return comparison;
      return a.normalizedName.compareTo(b.normalizedName);
    });
  }

  @override
  void dispose() {
    _appChangeSubscription?.cancel();
    super.dispose();
  }
}
```

**Step 4: Run test to verify pass**
Run: `flutter test --no-version-check test/core/services/app_cache_service_test.dart`
Expected: PASS — All tests passed!

**Step 5: Commit**
```bash
git add lib/core/services/app_cache_service.dart test/core/services/app_cache_service_test.dart
git commit -m "feat(services): implement instant cold boot cache, renaming, and resilient reconciliation"
```

---

### Task 6: Decouple Wallpaper Logic into WallpaperService

**Objective:** Extract all wallpaper downloading, cache busting, 24-hour scheduling, image caching, and platform setting logic out of `HomeScreen` into a clean, testable `WallpaperService`.

**Files:**
- Create: `lib/core/services/wallpaper_service.dart`
- Create: `test/core/services/wallpaper_service_test.dart`

**Step 1: Write failing test**
Create `test/core/services/wallpaper_service_test.dart`:

```dart
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
```

**Step 2: Run test to verify failure**
Run: `flutter test --no-version-check test/core/services/wallpaper_service_test.dart`
Expected: FAIL — `WallpaperService` does not exist.

**Step 3: Write minimal implementation**
Create `lib/core/services/wallpaper_service.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wallpaper_manager_plus/wallpaper_manager_plus.dart';

class WallpaperService extends ChangeNotifier {
  static final WallpaperService instance = WallpaperService();

  final String _imageUrl = "https://juanitotelo.net/daily.webp";
  File? _localFile;
  int _wallpaperVersion = 0;
  bool _isSyncing = false;
  Timer? _timer;

  File? get wallpaperFile => _localFile;
  int get wallpaperVersion => _wallpaperVersion;
  bool get isSyncing => _isSyncing;

  @visibleForTesting
  void setLocalFileForTesting(File file) {
    _localFile = file;
    _wallpaperVersion = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  Future<void> initBackground() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/daily_wallpaper.webp');

      if (await file.exists()) {
        _localFile = file;
        notifyListeners();

        final lastModified = await file.lastModified();
        final difference = DateTime.now().difference(lastModified);

        if (difference.inHours >= 24) {
          await syncWallpaper();
        } else {
          final timeUntilNextUpdate = const Duration(hours: 24) - difference;
          _scheduleNextUpdate(timeUntilNextUpdate);
        }
      } else {
        await syncWallpaper();
      }
    } catch (e) {
      debugPrint("Error initializing wallpaper: $e");
    }
  }

  void _scheduleNextUpdate(Duration waitDuration) {
    _timer?.cancel();
    _timer = Timer(waitDuration, () {
      syncWallpaper();
    });
  }

  Future<bool> syncWallpaper() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    notifyListeners();

    try {
      final cacheBustedUrl = Uri.parse(
        '$_imageUrl?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http.get(
        cacheBustedUrl,
        headers: const {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
        },
      );

      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/daily_wallpaper.webp');

        await file.writeAsBytes(response.bodyBytes);
        await FileImage(file).evict();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();

        if (Platform.isAndroid) {
          try {
            WallpaperManagerPlus().setWallpaper(
              file,
              WallpaperManagerPlus.bothScreens,
            );
          } catch (e) {
            debugPrint("WallpaperManager platform error: $e");
          }
        }

        _scheduleNextUpdate(const Duration(hours: 24));
        _localFile = file;
        _wallpaperVersion = DateTime.now().millisecondsSinceEpoch;
        return true;
      } else {
        return false;
      }
    } catch (e) {
      debugPrint("Wallpaper sync error: $e");
      _scheduleNextUpdate(const Duration(hours: 1));
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
```

**Step 4: Run test to verify pass**
Run: `flutter test --no-version-check test/core/services/wallpaper_service_test.dart`
Expected: PASS — All tests passed!

**Step 5: Commit**
```bash
git add lib/core/services/wallpaper_service.dart test/core/services/wallpaper_service_test.dart
git commit -m "feat(services): decouple WallpaperService with scheduling and platform management"
```

---

### Task 7: Extract Quick Notes Page and Zen Calendar Page

**Objective:** Decouple `_QuickNotesPage` and `_ZenCalendarPage` from `HomeScreen` into independent, reusable presentation pages.

**Files:**
- Create: `lib/presentation/pages/quick_notes_page.dart`
- Create: `lib/presentation/pages/zen_calendar_page.dart`
- Create: `test/presentation/pages/zen_calendar_page_test.dart`

**Step 1: Write failing test**
Create `test/presentation/pages/zen_calendar_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/presentation/pages/zen_calendar_page.dart';

void main() {
  testWidgets('ZenCalendarPage renders focus header, day number, and month grid', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ZenCalendarPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FOCUS'), findsOneWidget);
    expect(find.text('EVENTS TODAY'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
  });
}
```

**Step 2: Run test to verify failure**
Run: `flutter test --no-version-check test/presentation/pages/zen_calendar_page_test.dart`
Expected: FAIL — `ZenCalendarPage` does not exist.

**Step 3: Write minimal implementation**
Create `lib/presentation/pages/quick_notes_page.dart`:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class QuickNotesPage extends StatefulWidget {
  const QuickNotesPage({super.key});

  @override
  State<QuickNotesPage> createState() => _QuickNotesPageState();
}

class _QuickNotesPageState extends State<QuickNotesPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLocked = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadNote();
    _loadLockState();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadLockState() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/quick_note_locked.txt');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (mounted) {
          setState(() {
            _isLocked = content.trim() == 'true';
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading note lock state: $e");
    }
  }

  Future<void> _saveLockState(bool locked) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/quick_note_locked.txt');
      await file.writeAsString(locked ? 'true' : 'false');
    } catch (e) {
      debugPrint("Error saving note lock state: $e");
    }
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
    });
    if (_isLocked) {
      _focusNode.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
    _saveLockState(_isLocked);
  }

  Future<void> _loadNote() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/quick_note.txt');
      if (await file.exists()) {
        final text = await file.readAsString();
        if (mounted) _controller.text = text;
      }
    } catch (e) {
      debugPrint("Error loading note: $e");
    }
  }

  Future<void> _saveNote(String text) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/quick_note.txt');
      await file.writeAsString(text);
    } catch (e) {
      debugPrint("Error saving note: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "THOUGHTS",
                  style: TextStyle(
                    color: Color.fromARGB(207, 255, 255, 255),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                IconButton(
                  key: const Key('notes_lock_button'),
                  icon: Icon(
                    _isLocked ? Icons.lock_outline : Icons.lock_open_rounded,
                    size: 18,
                    color: _isLocked ? Colors.white38 : Colors.amberAccent,
                  ),
                  tooltip: _isLocked ? "Unlock notes" : "Lock notes",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 18,
                  onPressed: _toggleLock,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: TextField(
                key: const Key('notes_text_field'),
                controller: _controller,
                focusNode: _focusNode,
                readOnly: _isLocked,
                showCursor: !_isLocked,
                onChanged: _saveNote,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: _isLocked ? "Notes locked." : "Type something...",
                  hintStyle: const TextStyle(color: Colors.white24),
                ),
                cursorColor: Colors.amberAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Create `lib/presentation/pages/zen_calendar_page.dart`:

```dart
import 'package:flutter/material.dart';

class ZenCalendarPage extends StatelessWidget {
  const ZenCalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
    final firstDayOffset = DateTime(now.year, now.month, 1).weekday - 1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "FOCUS",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            Text(
              "${now.day}",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 80,
                fontWeight: FontWeight.w200,
              ),
            ),
            const Text(
              "EVENTS TODAY",
              style: TextStyle(
                color: Colors.amberAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: daysInMonth + firstDayOffset,
              itemBuilder: (context, index) {
                if (index < firstDayOffset) return const SizedBox();
                final day = index - firstDayOffset + 1;
                final isToday = day == now.day;

                return Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? const BoxDecoration(
                            color: Colors.white24,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      "$day",
                      style: TextStyle(
                        color: isToday ? Colors.white : Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 4: Run test to verify pass**
Run: `flutter test --no-version-check test/presentation/pages/zen_calendar_page_test.dart`
Expected: PASS — All tests passed!

**Step 5: Commit**
```bash
git add lib/presentation/pages/quick_notes_page.dart lib/presentation/pages/zen_calendar_page.dart test/presentation/pages/zen_calendar_page_test.dart
git commit -m "refactor(pages): extract QuickNotesPage and ZenCalendarPage from HomeScreen"
```

---

### Task 8: Minimalist Quick Action Picker Bottom Sheet

**Objective:** Create `QuickActionPickerSheet` to allow the user to configure either quick action slot with an installed app or reset to default with search and grayscale icon preview.

**Files:**
- Create: `lib/presentation/widgets/quick_action_picker_sheet.dart`
- Create: `test/presentation/widgets/quick_action_picker_sheet_test.dart`

**Step 1: Write failing test**
Create `test/presentation/widgets/quick_action_picker_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installed_apps/app_category.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/platform_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zen_launcher/core/services/app_cache_service.dart';
import 'package:zen_launcher/core/services/quick_action_service.dart';
import 'package:zen_launcher/data/database/zen_database.dart';
import 'package:zen_launcher/domain/models/quick_action_slot.dart';
import 'package:zen_launcher/domain/models/zen_app.dart';
import 'package:zen_launcher/presentation/widgets/quick_action_picker_sheet.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('QuickActionPickerSheet renders slot title, reset option, and app list', (tester) async {
    await ZenDatabase.instance.initInMemory();
    AppCacheService.instance.setAppsForTesting([
      ZenApp(
        info: const AppInfo(
          name: 'Zen Browser',
          icon: null,
          packageName: 'com.zen.browser',
          versionName: '1.0',
          versionCode: 1,
          platformType: PlatformType.android,
          installedTimestamp: 0,
          isSystemApp: false,
          isLaunchableApp: true,
          category: AppCategory.other,
        ),
        usageCount: 0,
        firstSeenTimestamp: 0,
      ),
    ]);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QuickActionPickerSheet(slot: QuickActionSlot.left),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CONFIGURE LEFT SHORTCUT'), findsOneWidget);
    expect(find.text('Reset to Default (Phone)'), findsOneWidget);
    expect(find.text('Zen Browser'), findsOneWidget);
  });
}
```

**Step 2: Run test to verify failure**
Run: `flutter test --no-version-check test/presentation/widgets/quick_action_picker_sheet_test.dart`
Expected: FAIL — `QuickActionPickerSheet` does not exist.

**Step 3: Write minimal implementation**
Create `lib/presentation/widgets/quick_action_picker_sheet.dart`:

```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/app_cache_service.dart';
import '../../core/services/quick_action_service.dart';
import '../../domain/models/quick_action_slot.dart';
import '../../domain/models/zen_app.dart';

class QuickActionPickerSheet extends StatefulWidget {
  final QuickActionSlot slot;

  const QuickActionPickerSheet({super.key, required this.slot});

  @override
  State<QuickActionPickerSheet> createState() => _QuickActionPickerSheetState();
}

class _QuickActionPickerSheetState extends State<QuickActionPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<ZenApp> _filteredApps = [];

  @override
  void initState() {
    super.initState();
    _filteredApps = AppCacheService.instance.apps;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    final all = AppCacheService.instance.apps;
    setState(() {
      if (query.isEmpty) {
        _filteredApps = all;
      } else {
        _filteredApps = all
            .where((app) => app.normalizedName.contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.slot == QuickActionSlot.left
        ? "CONFIGURE LEFT SHORTCUT"
        : "CONFIGURE RIGHT SHORTCUT";

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          color: Colors.black.withOpacity(0.85),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search app to assign...',
                  hintStyle: const TextStyle(color: Colors.white30),
                  prefixIcon: const Icon(Icons.search, color: Colors.white30, size: 20),
                  filled: true,
                  fillColor: Colors.white10,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.refresh, color: Colors.white70),
                title: Text(
                  'Reset to Default (${widget.slot.defaultLabel})',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  QuickActionService.instance.resetToDefault(widget.slot);
                  Navigator.of(context).pop();
                },
              ),
              const Divider(color: Colors.white12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredApps.length,
                  itemBuilder: (context, index) {
                    final app = _filteredApps[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: app.info.icon != null
                          ? SizedBox(
                              width: 32,
                              height: 32,
                              child: Image.memory(
                                app.info.icon!,
                                fit: BoxFit.contain,
                              ),
                            )
                          : const Icon(Icons.android, color: Colors.white38, size: 28),
                      title: Text(
                        app.displayName,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        app.info.packageName,
                        style: const TextStyle(color: Colors.white30, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        QuickActionService.instance.setCustomApp(
                          slot: widget.slot,
                          packageName: app.info.packageName,
                          label: app.displayName,
                        );
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Step 4: Run test to verify pass**
Run: `flutter test --no-version-check test/presentation/widgets/quick_action_picker_sheet_test.dart`
Expected: PASS — All tests passed!

**Step 5: Commit**
```bash
git add lib/presentation/widgets/quick_action_picker_sheet.dart test/presentation/widgets/quick_action_picker_sheet_test.dart
git commit -m "feat(widgets): add QuickActionPickerSheet for minimalist shortcut customization"
```

---

### Task 9: App Actions Bottom Sheet (Uninstall, App Settings, Renaming, Dock Assign)

**Objective:** Create `AppActionsSheet` for app drawer long-press interactions, allowing users to rename apps, launch Android system app settings, request app uninstallation, or assign to quick dock slots.

**Files:**
- Create: `lib/presentation/widgets/app_actions_sheet.dart`
- Create: `test/presentation/widgets/app_actions_sheet_test.dart`

**Step 1: Write failing test**
Create `test/presentation/widgets/app_actions_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installed_apps/app_category.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/platform_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zen_launcher/core/services/app_cache_service.dart';
import 'package:zen_launcher/core/services/quick_action_service.dart';
import 'package:zen_launcher/data/database/zen_database.dart';
import 'package:zen_launcher/domain/models/zen_app.dart';
import 'package:zen_launcher/presentation/widgets/app_actions_sheet.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('AppActionsSheet shows rename, settings, and uninstall options', (tester) async {
    await ZenDatabase.instance.initInMemory();
    await QuickActionService.instance.init();

    final app = ZenApp(
      info: const AppInfo(
        name: 'Browser Pro',
        icon: null,
        packageName: 'com.browser.pro',
        versionName: '1.0',
        versionCode: 1,
        platformType: PlatformType.android,
        installedTimestamp: 0,
        isSystemApp: false,
        isLaunchableApp: true,
        category: AppCategory.other,
      ),
      usageCount: 0,
      firstSeenTimestamp: 0,
    );
    AppCacheService.instance.setAppsForTesting([app]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppActionsSheet(zenApp: app),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Browser Pro'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('App Settings'), findsOneWidget);
    expect(find.text('Uninstall'), findsOneWidget);
    expect(find.text('Set as Left Shortcut'), findsOneWidget);
    expect(find.text('Set as Right Shortcut'), findsOneWidget);
  });
}
```

**Step 2: Run test to verify failure**
Run: `flutter test --no-version-check test/presentation/widgets/app_actions_sheet_test.dart`
Expected: FAIL — `AppActionsSheet` does not exist.

**Step 3: Write minimal implementation**
Create `lib/presentation/widgets/app_actions_sheet.dart`:

```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';

import '../../core/services/app_cache_service.dart';
import '../../core/services/quick_action_service.dart';
import '../../domain/models/quick_action_slot.dart';
import '../../domain/models/zen_app.dart';

class AppActionsSheet extends StatelessWidget {
  final ZenApp zenApp;

  const AppActionsSheet({super.key, required this.zenApp});

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: zenApp.displayName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'RENAME APP',
          style: TextStyle(color: Colors.amberAccent, fontSize: 13, letterSpacing: 1.5),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: zenApp.info.name,
            hintStyle: const TextStyle(color: Colors.white24),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.amberAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppCacheService.instance.renameApp(zenApp, null);
              Navigator.of(ctx).pop();
            },
            child: const Text('RESET', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              AppCacheService.instance.renameApp(zenApp, controller.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('SAVE', style: TextStyle(color: Colors.amberAccent)),
          ),
        ],
      ),
    );
  }

  void _uninstallApp(BuildContext context) {
    HapticFeedback.lightImpact();
    InstalledApps.uninstallApp(zenApp.info.packageName);
    Navigator.of(context).pop();
  }

  void _openSettings(BuildContext context) {
    HapticFeedback.lightImpact();
    InstalledApps.openSettings(zenApp.info.packageName);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          color: Colors.black.withOpacity(0.85),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  if (zenApp.info.icon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Image.memory(zenApp.info.icon!, fit: BoxFit.contain),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zenApp.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          zenApp.info.packageName,
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.edit_outlined, color: Colors.white70, size: 22),
                title: const Text('Rename', style: TextStyle(color: Colors.white, fontSize: 15)),
                onTap: () {
                  Navigator.of(context).pop();
                  _showRenameDialog(context);
                },
              ),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.settings_outlined, color: Colors.white70, size: 22),
                title: const Text('App Settings', style: TextStyle(color: Colors.white, fontSize: 15)),
                onTap: () => _openSettings(context),
              ),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                title: const Text('Uninstall', style: TextStyle(color: Colors.redAccent, fontSize: 15)),
                onTap: () => _uninstallApp(context),
              ),
              const Divider(color: Colors.white12, height: 16),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.chevron_left, color: Colors.white54, size: 22),
                title: const Text('Set as Left Shortcut', style: TextStyle(color: Colors.white70, fontSize: 14)),
                onTap: () {
                  HapticFeedback.lightImpact();
                  QuickActionService.instance.setCustomApp(
                    slot: QuickActionSlot.left,
                    packageName: zenApp.info.packageName,
                    label: zenApp.displayName,
                  );
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.chevron_right, color: Colors.white54, size: 22),
                title: const Text('Set as Right Shortcut', style: TextStyle(color: Colors.white70, fontSize: 14)),
                onTap: () {
                  HapticFeedback.lightImpact();
                  QuickActionService.instance.setCustomApp(
                    slot: QuickActionSlot.right,
                    packageName: zenApp.info.packageName,
                    label: zenApp.displayName,
                  );
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Step 4: Run test to verify pass**
Run: `flutter test --no-version-check test/presentation/widgets/app_actions_sheet_test.dart`
Expected: PASS — All tests passed!

**Step 5: Commit**
```bash
git add lib/presentation/widgets/app_actions_sheet.dart test/presentation/widgets/app_actions_sheet_test.dart
git commit -m "feat(widgets): add AppActionsSheet for rename, settings, uninstall, and dock pinning"
```

---

### Task 10: Wire AppListItem Long-Press & App Drawer Actions

**Objective:** Update `AppListItem` to display `zenApp.displayName` and accept an `onLongPress` callback; update `SmartAppListDrawer` to open `AppActionsSheet` on long press.

**Files:**
- Modify: `lib/presentation/widgets/app_list_item.dart`
- Modify: `lib/presentation/drawers/smart_app_drawer.dart`
- Verify: `test/presentation/drawers/smart_app_drawer_test.dart`

**Step 1: Update `lib/presentation/widgets/app_list_item.dart`**
Add `onLongPress` parameter and use `zenApp.displayName`.

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../domain/models/zen_app.dart';
import '../../../core/services/app_cache_service.dart';

class AppListItem extends StatelessWidget {
  final ZenApp zenApp;
  final bool isHighlighted;
  final VoidCallback? onLongPress;

  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ]);

  const AppListItem({
    super.key,
    required this.zenApp,
    this.isHighlighted = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        FocusScope.of(context).unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        AppCacheService.instance.launchApp(zenApp);
      },
      onLongPress: onLongPress,
      splashColor: Colors.white10,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 25,
          vertical: zenApp.isNew ? 5 : 0,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      zenApp.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        color: isHighlighted
                            ? Colors.amberAccent
                            : Colors.white,
                        fontWeight: isHighlighted
                            ? FontWeight.bold
                            : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                  if (zenApp.isNew)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "NEW",
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            SizedBox(
              width: 28,
              height: 28,
              child: zenApp.info.icon != null
                  ? ColorFiltered(
                      colorFilter: _grayscaleFilter,
                      child: Image.memory(
                        zenApp.info.icon!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    )
                  : const Icon(Icons.android, size: 28, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 2: Update `SmartAppListDrawer` in `lib/presentation/drawers/smart_app_drawer.dart`**
Add helper to show `AppActionsSheet`:

```dart
  void _openAppActions(ZenApp app) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AppActionsSheet(zenApp: app),
    );
  }
```

Pass `onLongPress: () => _openAppActions(...)` in both the `_newApps` list builder and the `_allApps` list builder.

**Step 3: Run test to verify pass**
Run: `flutter test --no-version-check test/presentation/drawers/smart_app_drawer_test.dart`
Expected: PASS — All tests passed!

**Step 4: Commit**
```bash
git add lib/presentation/widgets/app_list_item.dart lib/presentation/drawers/smart_app_drawer.dart
git commit -m "feat(drawer): support long press for app actions sheet and custom display names"
```

---

### Task 11: Decouple Bottom Dock into HomeDock Widget

**Objective:** Create `HomeDock` widget containing the configurable left button, center app drawer pull handle, and configurable right button with dynamic icon rendering and long-press configuration triggers.

**Files:**
- Create: `lib/presentation/widgets/home_dock.dart`
- Create: `test/presentation/widgets/home_dock_test.dart`

**Step 1: Write failing test**
Create `test/presentation/widgets/home_dock_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zen_launcher/core/services/app_cache_service.dart';
import 'package:zen_launcher/core/services/quick_action_service.dart';
import 'package:zen_launcher/data/database/zen_database.dart';
import 'package:zen_launcher/domain/models/quick_action_slot.dart';
import 'package:zen_launcher/presentation/widgets/home_dock.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('HomeDock renders left button, drawer pull handle, and right button', (tester) async {
    await ZenDatabase.instance.initInMemory();
    await QuickActionService.instance.init();
    AppCacheService.instance.setAppsForTesting([]);

    bool drawerOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeDock(
            onOpenDrawer: () => drawerOpened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dock_left_action_button')), findsOneWidget);
    expect(find.byKey(const Key('dock_drawer_handle')), findsOneWidget);
    expect(find.byKey(const Key('dock_right_action_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dock_drawer_handle')));
    expect(drawerOpened, isTrue);
  });
}
```

**Step 2: Run test to verify failure**
Run: `flutter test --no-version-check test/presentation/widgets/home_dock_test.dart`
Expected: FAIL — `HomeDock` does not exist.

**Step 3: Write minimal implementation**
Create `lib/presentation/widgets/home_dock.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/app_cache_service.dart';
import '../../core/services/quick_action_service.dart';
import '../../domain/models/quick_action_slot.dart';
import '../../domain/models/zen_app.dart';
import 'quick_action_picker_sheet.dart';

class HomeDock extends StatelessWidget {
  final VoidCallback onOpenDrawer;

  const HomeDock({super.key, required this.onOpenDrawer});

  void _openConfigSheet(BuildContext context, QuickActionSlot slot) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => QuickActionPickerSheet(slot: slot),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        QuickActionService.instance,
        AppCacheService.instance,
      ]),
      builder: (context, _) {
        final leftConfig = QuickActionService.instance.getConfig(QuickActionSlot.left);
        final rightConfig = QuickActionService.instance.getConfig(QuickActionSlot.right);
        final apps = AppCacheService.instance.apps;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _DockActionButton(
                key: const Key('dock_left_action_button'),
                slot: QuickActionSlot.left,
                config: leftConfig,
                installedApps: apps,
                defaultIcon: Icons.phone_outlined,
                onTap: () => QuickActionService.instance.launchSlot(context, QuickActionSlot.left),
                onLongPress: () => _openConfigSheet(context, QuickActionSlot.left),
              ),
              GestureDetector(
                key: const Key('dock_drawer_handle'),
                onTap: onOpenDrawer,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 80,
                  height: 60,
                  alignment: Alignment.bottomCenter,
                  child: const Icon(
                    Icons.keyboard_arrow_up,
                    color: Colors.white24,
                    size: 20,
                  ),
                ),
              ),
              _DockActionButton(
                key: const Key('dock_right_action_button'),
                slot: QuickActionSlot.right,
                config: rightConfig,
                installedApps: apps,
                defaultIcon: Icons.camera_alt_outlined,
                onTap: () => QuickActionService.instance.launchSlot(context, QuickActionSlot.right),
                onLongPress: () => _openConfigSheet(context, QuickActionSlot.right),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DockActionButton extends StatelessWidget {
  final QuickActionSlot slot;
  final QuickActionConfig config;
  final List<ZenApp> installedApps;
  final IconData defaultIcon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _DockActionButton({
    super.key,
    required this.slot,
    required this.config,
    required this.installedApps,
    required this.defaultIcon,
    required this.onTap,
    required this.onLongPress,
  });

  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    Widget iconWidget;

    if (config.isCustom) {
      ZenApp? matchedApp;
      try {
        matchedApp = installedApps.firstWhere((a) => a.info.packageName == config.packageName);
      } catch (_) {}

      if (matchedApp != null && matchedApp.info.icon != null) {
        iconWidget = SizedBox(
          width: 26,
          height: 26,
          child: ColorFiltered(
            colorFilter: _grayscaleFilter,
            child: Image.memory(
              matchedApp.info.icon!,
              fit: BoxFit.contain,
            ),
          ),
        );
      } else {
        iconWidget = const Icon(Icons.widgets_outlined, color: Colors.white70, size: 26);
      }
    } else {
      iconWidget = Icon(defaultIcon, color: Colors.white70, size: 28);
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(24),
      splashColor: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: iconWidget,
      ),
    );
  }
}
```

**Step 4: Run test to verify pass**
Run: `flutter test --no-version-check test/presentation/widgets/home_dock_test.dart`
Expected: PASS — All tests passed!

**Step 5: Commit**
```bash
git add lib/presentation/widgets/home_dock.dart test/presentation/widgets/home_dock_test.dart
git commit -m "feat(widgets): add modular HomeDock widget with customizable actions"
```

---

### Task 12: Refactor HomeScreen into Lean Orchestrator

**Objective:** Clean up `HomeScreen` from 634 lines to ~130 lines, delegating to `WallpaperService`, `QuickNotesPage`, `ZenCalendarPage`, and `HomeDock`.

**Files:**
- Modify: `lib/presentation/screens/home_screen.dart`
- Modify: `lib/main.dart` (initialize `QuickActionService` and `WallpaperService`)
- Verify: `test/presentation/screens/wallpaper_refresh_test.dart` and `test/presentation/screens/quick_notes_test.dart`.

**Step 1: Refactor `lib/presentation/screens/home_screen.dart`**
Replace `lib/presentation/screens/home_screen.dart` with:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/wallpaper_service.dart';
import '../drawers/smart_app_drawer.dart';
import '../pages/quick_notes_page.dart';
import '../pages/zen_calendar_page.dart';
import '../widgets/clock_widget.dart';
import '../widgets/home_dock.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _platform = MethodChannel('com.zen.launcher/utils');

  // Carousel Controller: initialPage 1000 % 3 == 1 (Home Screen)
  final PageController _pageController = PageController(initialPage: 1000);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WallpaperService.instance.initBackground();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _expandNotifications() async {
    try {
      await _platform.invokeMethod('expandNotifications');
    } catch (e) {
      _showSystemBars();
    }
  }

  void _showSystemBars() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  void _openAppDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      barrierColor: Colors.black26,
      builder: (context) => const SmartAppListDrawer(),
    ).then((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: WallpaperService.instance,
      builder: (context, _) {
        final File? wallpaperFile = WallpaperService.instance.wallpaperFile;
        final int wallpaperVersion = WallpaperService.instance.wallpaperVersion;
        final bool isSyncing = WallpaperService.instance.isSyncing;

        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: GestureDetector(
            onDoubleTap: () {
              if (_pageController.hasClients) {
                int currentIndex = _pageController.page!.round() % 3;
                if (currentIndex == 1) {
                  WallpaperService.instance.syncWallpaper();
                }
              }
            },
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity! < -500) {
                _openAppDrawer();
              } else if (details.primaryVelocity! > 500) {
                _expandNotifications();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Static Wallpaper Background Layer
                if (wallpaperFile != null)
                  Image.file(
                    wallpaperFile,
                    key: ValueKey('wallpaper_$wallpaperVersion'),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
                else
                  const DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black38),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black38),
                ),

                // 2. Infinite Carousel (0: Notes, 1: Home, 2: Calendar)
                PageView.builder(
                  controller: _pageController,
                  itemBuilder: (context, index) {
                    final pageIndex = index % 3;
                    if (pageIndex == 0) return const QuickNotesPage();
                    if (pageIndex == 1) return _buildHomePage();
                    return const ZenCalendarPage();
                  },
                ),

                // 3. Loading Indicator Overlay
                if (isSyncing)
                  const Positioned(
                    bottom: 50,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white30,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHomePage() {
    return SafeArea(
      child: Column(
        children: [
          const Spacer(flex: 2),
          const ClockWidget(),
          const Spacer(flex: 3),
          HomeDock(onOpenDrawer: _openAppDrawer),
        ],
      ),
    );
  }
}
```

**Step 2: Update `lib/main.dart` to initialize QuickActionService**
Update `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/services/app_cache_service.dart';
import 'core/services/quick_action_service.dart';
import 'presentation/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set to Immersive Sticky for true full screen
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  );

  // 1. Initialize System UI
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // 2. Initialize Core Services
  await AppCacheService.instance.init();
  await QuickActionService.instance.init();

  runApp(const ZenLauncherApp());
}

class ZenLauncherApp extends StatelessWidget {
  const ZenLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Zen Launcher',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black12,
        splashFactory: InkRipple.splashFactory,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white, fontFamily: 'monospace'),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
```

**Step 3: Run all tests to verify pass**
Run: `flutter test --no-version-check`
Expected output:
```
All tests passed!
```

**Step 4: Commit**
```bash
git add lib/presentation/screens/home_screen.dart lib/main.dart
git commit -m "refactor(screens): decouple HomeScreen into lightweight orchestrator and wire up services"
```

---

### Task 13: End-to-End Test & Analysis Verification

**Objective:** Run static analysis and all unit, widget, and integration tests to verify zero regressions.

**Files:**
- Test all: `test/`

**Step 1: Run flutter analyze**
Run: `flutter analyze --no-version-check`
Expected: `No issues found!` (or zero errors/warnings).

**Step 2: Run all unit and widget tests**
Run: `flutter test --no-version-check`
Expected: All tests passed across all suites.

**Step 3: Verification commit**
```bash
git status
```
Confirm clean working tree.

---

## Risks, Tradeoffs, and Open Questions

1. **System App Uninstallation:**
   - *Android Constraint:* Calling `InstalledApps.uninstallApp` on a pre-installed system app will not uninstall it; Android prompts to disable or displays that system apps cannot be uninstalled.
   - *Design:* `AppActionsSheet` routes to `InstalledApps.openSettings` as an alternative so the user can disable or force-stop system apps cleanly.
2. **Renaming Persistence:**
   - *Resilience:* Renamed app aliases (`custom_name`) are stored in SQLite `app_stats` keyed by `package_name`. Even if an app receives an APK update or version bump, its custom alias remains intact.
3. **App Icon Memory & Storage Tradeoff:**
   - *Storage:* Caching icon BLOBs directly in SQLite avoids multiple slow IPC roundtrips on cold start, keeping launcher boot under 20ms.
