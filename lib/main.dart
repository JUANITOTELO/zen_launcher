import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wallpaper_manager_plus/wallpaper_manager_plus.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // 2. Initialize Core Services (Fire and Forget)
  // We start loading apps immediately so they are ready by the time the user swipes.
  AppCacheService.instance.init();

  runApp(const ZenLauncherApp());
}

// -----------------------------------------------------------------------------
// DATA LAYER: SQLite Database
// -----------------------------------------------------------------------------
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

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    const sql = '''
    CREATE TABLE app_stats (
      package_name TEXT PRIMARY KEY,
      usage_count INTEGER DEFAULT 0,
      is_hidden INTEGER DEFAULT 0
    )
    ''';
    await db.execute(sql);
  }

  Future<Map<String, int>> getAllUsageCounts() async {
    final db = await instance.database;
    final result = await db.query('app_stats');

    // Convert List<Map> to Map<String, int> for O(1) lookup
    final Map<String, int> map = {};
    for (var row in result) {
      map[row['package_name'] as String] = row['usage_count'] as int;
    }
    return map;
  }

  Future<void> incrementUsage(String packageName) async {
    final db = await instance.database;
    await db.rawInsert(
      'INSERT INTO app_stats (package_name, usage_count) VALUES (?, 1) ON CONFLICT(package_name) DO UPDATE SET usage_count = usage_count + 1',
      [packageName],
    );
  }
}

// -----------------------------------------------------------------------------
// DOMAIN MODEL
// -----------------------------------------------------------------------------
class ZenApp {
  final AppInfo info;
  int usageCount;
  // Pre-calculate lower case name for faster search filtering
  final String normalizedName;

  ZenApp({required this.info, required this.usageCount})
    : normalizedName = info.name.toLowerCase();
}

// -----------------------------------------------------------------------------
// SERVICE LAYER: Singleton Cache & State
// -----------------------------------------------------------------------------
class AppCacheService extends ChangeNotifier {
  // Singleton pattern
  static final AppCacheService instance = AppCacheService._();
  AppCacheService._();

  List<ZenApp> _cachedApps = [];
  bool _isLoaded = false;

  List<ZenApp> get apps => List.unmodifiable(_cachedApps);
  bool get isLoaded => _isLoaded;

  Future<void> init() async {
    if (_isLoaded) return;

    // Parallel Execution: Fetch OS apps and DB stats simultaneously
    final appsFuture = InstalledApps.getInstalledApps(
      withIcon: true,
      packageNamePrefix: '',
    );
    final statsFuture = ZenDatabase.instance.getAllUsageCounts();

    final results = await Future.wait([appsFuture, statsFuture]);

    final List<AppInfo> rawApps = results[0] as List<AppInfo>;
    final Map<String, int> usageStats = results[1] as Map<String, int>;

    // O(n) Merge
    _cachedApps = rawApps.map((app) {
      final count = usageStats[app.packageName] ?? 0;
      return ZenApp(info: app, usageCount: count);
    }).toList();

    _sortApps();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> launchApp(ZenApp app) async {
    // 1. Optimistic UI Update
    app.usageCount++;
    _sortApps(); // Re-sort immediately
    notifyListeners();

    // 2. Persist to SQLite (Fire and forget)
    ZenDatabase.instance.incrementUsage(app.info.packageName);

    // 3. Launch
    InstalledApps.startApp(app.info.packageName);
  }

  void _sortApps() {
    _cachedApps.sort((a, b) {
      int comparison = b.usageCount.compareTo(a.usageCount);
      if (comparison != 0) return comparison;
      return a.normalizedName.compareTo(b.normalizedName);
    });
  }
}

// -----------------------------------------------------------------------------
// UI LAYER
// -----------------------------------------------------------------------------

class ZenLauncherApp extends StatelessWidget {
  const ZenLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Zen Launcher',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black12,
        // Performance optimization: prevent ink sparks from calculating too much
        splashFactory: InkRipple.splashFactory,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white, fontFamily: 'Roboto'),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String _imageUrl = "https://juanitotelo.net/daily.webp";
  File? _localFile;
  bool _isSyncing = false;
  Timer? _timer; // Keep a reference to cancel it later

  @override
  void initState() {
    super.initState();
    _initBackground();
  }

  @override
  void dispose() {
    _timer?.cancel(); // Always clean up timers!
    super.dispose();
  }

  Future<void> _initBackground() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/daily_wallpaper.webp');

    if (await file.exists()) {
      setState(() => _localFile = file);

      // Check how old the file is
      final lastModified = await file.lastModified();
      final difference = DateTime.now().difference(lastModified);

      if (difference.inHours >= 24) {
        // It's old, sync immediately
        _syncWallpaper();
      } else {
        // It's fresh, wait for the remainder of the 24 hours
        final timeUntilNextUpdate = const Duration(hours: 24) - difference;
        _scheduleNextUpdate(timeUntilNextUpdate);
      }
    } else {
      // File doesn't exist, sync immediately
      _syncWallpaper();
    }
  }

  void _scheduleNextUpdate(Duration waitDuration) {
    _timer?.cancel();
    _timer = Timer(waitDuration, () {
      _syncWallpaper();
    });
    debugPrint(
      "Next wallpaper sync scheduled in: ${waitDuration.inHours} hours",
    );
  }

  Future<void> _syncWallpaper() async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);

    try {
      final response = await http.get(Uri.parse(_imageUrl));
      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/daily_wallpaper.webp');

        // writing bytes updates the 'lastModified' timestamp automatically
        await file.writeAsBytes(response.bodyBytes);

        WallpaperManagerPlus().setWallpaper(
          file,
          WallpaperManagerPlus.homeScreen,
        );

        // Schedule the next one for exactly 24 hours from now
        _scheduleNextUpdate(const Duration(hours: 24));

        if (mounted) {
          setState(() => _localFile = file);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Zen refreshed.'),
              duration: Duration(milliseconds: 800),
              backgroundColor: Colors.white10,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Wallpaper Error: $e");
      // If error, try again in 1 hour instead of 24
      _scheduleNextUpdate(const Duration(hours: 1));
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _openAppDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      // Use barrier color to avoid stacking blurs
      barrierColor: Colors.black26,
      builder: (context) => const SmartAppListDrawer(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity! < -500) {
            _openAppDrawer();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_localFile != null)
              Image.file(_localFile!, fit: BoxFit.cover, gaplessPlayback: true)
            else
              const DecoratedBox(
                decoration: BoxDecoration(color: Colors.black38),
              ),

            // Optimization: Constant overlay, don't rebuild
            const DecoratedBox(
              decoration: BoxDecoration(color: Colors.black38),
            ),

            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _syncWallpaper,
                child: const SizedBox.expand(),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  const ClockWidget(),
                  const Spacer(flex: 3),
                  if (_isSyncing)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white30,
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: _openAppDrawer,
                    behavior: HitTestBehavior.opaque, // Better touch target
                    child: Container(
                      padding: const EdgeInsets.all(30),
                      child: Column(children: [const SizedBox(height: 10)]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Separated clock logic to prevent rebuilding entire screen every second
class ClockWidget extends StatelessWidget {
  const ClockWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final now = DateTime.now();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateFormat('h:mm').format(now),
              style: const TextStyle(
                fontSize: 90,
                height: 0.9,
                fontWeight: FontWeight.w100,
                color: Colors.white,
                letterSpacing: -2,
              ),
            ),
            Text(
              DateFormat('EEEE, MMM d').format(now).toUpperCase(),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white38,
                letterSpacing: 4,
              ),
            ),
          ],
        );
      },
    );
  }
}

class SmartAppListDrawer extends StatefulWidget {
  const SmartAppListDrawer({super.key});

  @override
  State<SmartAppListDrawer> createState() => _SmartAppListDrawerState();
}

class _SmartAppListDrawerState extends State<SmartAppListDrawer> {
  final TextEditingController _searchController = TextEditingController();

  // We don't store the massive list here anymore.
  // We just store the filtered view.
  List<ZenApp> _filteredApps = [];

  @override
  void initState() {
    super.initState();
    // Initial fetch from memory
    _updateFilteredList();

    // Listen for text changes
    _searchController.addListener(_updateFilteredList);

    // Listen for Service changes (in case usages update while drawer is open)
    AppCacheService.instance.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _searchController.dispose();
    AppCacheService.instance.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) _updateFilteredList();
  }

  void _updateFilteredList() {
    final allApps = AppCacheService.instance.apps;
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredApps = allApps;
      } else {
        // Efficient filtering using the pre-calculated normalized name
        _filteredApps = allApps
            .where((app) => app.normalizedName.contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Check if the service is ready (it should be, since we called init in main)
    if (!AppCacheService.instance.isLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white24),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      // Snap feels more native
      snap: true,
      builder: (_, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: ColoredBox(
              color: Colors.black26,
              child: Column(
                children: [
                  _buildSearchBar(),
                  const Divider(color: Colors.white12, height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      // Use itemExtent for performance boost if height is fixed
                      itemExtent: 72,
                      itemCount: _filteredApps.length,
                      itemBuilder: (context, index) {
                        final app = _filteredApps[index];
                        // Pass Key to ensure efficient updating if list changes
                        return AppListItem(
                          key: ValueKey(app.info.packageName),
                          zenApp: app,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 25, 25, 15),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.2),
        decoration: const InputDecoration(
          hintText: 'Search...',
          hintStyle: TextStyle(color: Colors.white24, fontSize: 18),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        cursorColor: Colors.white,
      ),
    );
  }
}

class AppListItem extends StatelessWidget {
  final ZenApp zenApp;

  const AppListItem({super.key, required this.zenApp});

  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => AppCacheService.instance.launchApp(zenApp),
      splashColor: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 25),
        child: Row(
          children: [
            Expanded(
              child: Text(
                zenApp.info.name,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
              ),
            ),
            const SizedBox(width: 15),
            SizedBox(
              width: 28,
              height: 28,
              child: zenApp.info.icon != null
                  ? ColorFiltered(
                      colorFilter: _grayscaleFilter,
                      // Optimization: gaplessPlayback prevents flickering
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
