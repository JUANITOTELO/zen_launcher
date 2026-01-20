import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class ZenDatabase {
  static final ZenDatabase instance = ZenDatabase._init();
  static Database? _database;

  ZenDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('zen_launcher.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
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
        first_seen INTEGER DEFAULT 0
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE app_stats ADD COLUMN first_seen INTEGER DEFAULT 0',
      );
    }
  }

  /// Returns map of PackageName -> {usage, firstSeen}
  Future<Map<String, Map<String, dynamic>>> getAllStats() async {
    final db = await instance.database;
    final result = await db.query('app_stats');

    final Map<String, Map<String, dynamic>> map = {};
    for (var row in result) {
      map[row['package_name'] as String] = {
        'usage': row['usage_count'] as int,
        'first_seen': row['first_seen'] as int,
      };
    }
    return map;
  }

  Future<void> registerApp(String packageName, int timestamp) async {
    final db = await instance.database;
    await db.rawInsert(
      'INSERT OR IGNORE INTO app_stats (package_name, usage_count, first_seen) VALUES (?, 0, ?)',
      [packageName, timestamp],
    );
  }

  Future<void> incrementUsage(String packageName) async {
    final db = await instance.database;
    await db.rawInsert(
      '''INSERT INTO app_stats (package_name, usage_count, first_seen) 
         VALUES (?, 1, ?) 
         ON CONFLICT(package_name) DO UPDATE SET usage_count = usage_count + 1''',
      [packageName, DateTime.now().millisecondsSinceEpoch],
    );
  }
}
