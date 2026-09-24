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
        custom_name TEXT,
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
          custom_name TEXT,
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
             package_name, app_name, custom_name, version_name, version_code, 
             is_system_app, installed_timestamp, icon, updated_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(package_name) DO UPDATE SET
             app_name = excluded.app_name,
             custom_name = COALESCE(excluded.custom_name, app_cache.custom_name),
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
          app.customName,
          app.versionName,
          app.versionCode,
          app.isSystemApp ? 1 : 0,
          app.installedTimestamp,
          app.icon,
          now,
        ],
      );

      if (app.usageCount > 0 || app.firstSeenTimestamp > 0) {
        batch.rawInsert(
          '''INSERT INTO app_stats (package_name, usage_count, first_seen, custom_name)
             VALUES (?, ?, ?, ?)
             ON CONFLICT(package_name) DO UPDATE SET
               usage_count = MAX(app_stats.usage_count, excluded.usage_count),
               first_seen = CASE WHEN app_stats.first_seen = 0 THEN excluded.first_seen ELSE app_stats.first_seen END,
               custom_name = COALESCE(excluded.custom_name, app_stats.custom_name)
          ''',
          [app.packageName, app.usageCount, app.firstSeenTimestamp, app.customName],
        );
      }
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
        COALESCE(s.custom_name, c.custom_name) as custom_name
      FROM app_cache c
      LEFT JOIN app_stats s ON c.package_name = s.package_name
      ORDER BY COALESCE(s.usage_count, 0) DESC, LOWER(COALESCE(s.custom_name, c.custom_name, c.app_name)) ASC
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
