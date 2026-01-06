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

    return await openDatabase(
      path,
      version: 2, // INCREASED VERSION
      onCreate: _createDB,
      onUpgrade: _onUpgrade, // Handle migration
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE app_stats (
        package_name TEXT PRIMARY KEY,
        usage_count INTEGER DEFAULT 0,
        is_hidden INTEGER DEFAULT 0,
        first_seen INTEGER DEFAULT 0  -- New column
      )
    ''');
  }

  // Handle existing users
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE app_stats ADD COLUMN first_seen INTEGER DEFAULT 0',
      );
    }
  }

  // Returns map of PackageName -> {usage, firstSeen}
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
    // Only insert if not exists. If exists, we don't want to overwrite the old timestamp.
    await db.rawInsert(
      'INSERT OR IGNORE INTO app_stats (package_name, usage_count, first_seen) VALUES (?, 0, ?)',
      [packageName, timestamp],
    );
  }

  Future<void> incrementUsage(String packageName) async {
    final db = await instance.database;
    // Ensure record exists (edge case) then update
    await db.rawInsert(
      '''INSERT INTO app_stats (package_name, usage_count, first_seen) 
         VALUES (?, 1, ?) 
         ON CONFLICT(package_name) DO UPDATE SET usage_count = usage_count + 1''',
      [packageName, DateTime.now().millisecondsSinceEpoch],
    );
  }
}

// -----------------------------------------------------------------------------
// DOMAIN MODEL
// -----------------------------------------------------------------------------
class ZenApp {
  final AppInfo info;
  int usageCount;
  final int firstSeenTimestamp; // Unix millis
  final String normalizedName;

  ZenApp({
    required this.info,
    required this.usageCount,
    required this.firstSeenTimestamp,
  }) : normalizedName = info.name.toLowerCase();

  // It is "New" if it was seen less than 3 hours ago
  bool get isNew {
    // If timestamp is 0, it's an old app from before we started tracking
    if (firstSeenTimestamp == 0) return false;

    final installTime = DateTime.fromMillisecondsSinceEpoch(firstSeenTimestamp);
    final diff = DateTime.now().difference(installTime);
    return diff.inHours < 3;
  }
}

// -----------------------------------------------------------------------------
// SERVICE LAYER: Singleton Cache & State
// -----------------------------------------------------------------------------
class AppCacheService extends ChangeNotifier {
  static final AppCacheService instance = AppCacheService._();
  AppCacheService._();

  // The Native Channel we just built in Kotlin
  static const _eventChannel = EventChannel(
    'com.zen.launcher/app_change_events',
  );

  List<ZenApp> _cachedApps = [];
  bool _isLoaded = false;

  StreamSubscription? _appChangeSubscription;

  List<ZenApp> get apps => List.unmodifiable(_cachedApps);
  bool get isLoaded => _isLoaded;

  Future<void> init() async {
    if (_isLoaded) return;

    // 1. Initial Load
    await _fetchApps();

    // 2. Start listening to the native radio station
    _startListeningToChanges();

    _isLoaded = true;
  }

  void _startListeningToChanges() {
    _appChangeSubscription?.cancel();

    // Listen to the stream from Kotlin
    _appChangeSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        debugPrint("Native App Event detected: $event");
        // Reload the list whenever an event comes in
        _fetchApps();
      },
      onError: (error) {
        debugPrint("Error listening to app changes: $error");
      },
    );
  }

  Future<void> _fetchApps() async {
    final appsFuture = InstalledApps.getInstalledApps(
      excludeSystemApps: false,
      withIcon: true,
      packageNamePrefix: '',
    );
    final statsFuture = ZenDatabase.instance.getAllStats();

    final results = await Future.wait([appsFuture, statsFuture]);
    final List<AppInfo> rawApps = results[0] as List<AppInfo>;
    final Map<String, Map<String, dynamic>> stats =
        results[1] as Map<String, Map<String, dynamic>>;

    final int now = DateTime.now().millisecondsSinceEpoch;
    final bool isFreshInstall = stats.isEmpty;

    List<ZenApp> tempApps = [];

    for (var app in rawApps) {
      int usage = 0;
      int firstSeen = 0;

      if (stats.containsKey(app.packageName)) {
        // Known app
        usage = stats[app.packageName]!['usage'];
        firstSeen = stats[app.packageName]!['first_seen'];
      } else {
        // Unknown app (New Install OR First run of Launcher)
        // If it's the first ever run of the launcher, don't mark everything as "New"
        firstSeen = isFreshInstall ? 0 : now;

        // Fire and forget: save to DB so it persists across reboots
        ZenDatabase.instance.registerApp(app.packageName, firstSeen);
      }

      tempApps.add(
        ZenApp(info: app, usageCount: usage, firstSeenTimestamp: firstSeen),
      );
    }

    _cachedApps = tempApps;
    _sortApps();
    notifyListeners();
  }

  // ... (Keep launchApp and _sortApps as they were) ...
  Future<void> launchApp(ZenApp app) async {
    app.usageCount++;
    _sortApps();
    notifyListeners();
    ZenDatabase.instance.incrementUsage(app.info.packageName);
    InstalledApps.startApp(app.info.packageName);
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
          WallpaperManagerPlus.bothScreens,
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
  List<ZenApp> _newApps = [];
  List<ZenApp> _allApps = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _updateFilteredList();
    _searchController.addListener(_updateFilteredList);
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
    final all = AppCacheService.instance.apps;
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _isSearching = false;
        // Logic: Separate New from Old
        _newApps = all.where((app) => app.isNew).toList();
        // The main list contains everything (or you can exclude new ones if you prefer)
        // Usually, users expect "All Apps" to contain everything.
        _allApps = all;
      } else {
        _isSearching = true;
        _newApps = []; // Hide new section when searching
        _allApps = all
            .where((app) => app.normalizedName.contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AppCacheService.instance.isLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white24),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
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
                    child: CustomScrollView(
                      controller: scrollController,
                      slivers: [
                        // 1. NEW APPS SECTION
                        if (_newApps.isNotEmpty) ...[
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(25, 20, 25, 5),
                              child: Text(
                                "RECENTLY INSTALLED",
                                style: TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => AppListItem(
                                key: ValueKey(
                                  "new_${_newApps[index].info.packageName}",
                                ),
                                zenApp: _newApps[index],
                                isHighlighted: true, // Special visual flag
                              ),
                              childCount: _newApps.length,
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 10)),
                        ],

                        // 2. ALL APPS HEADER (Only show if we have a New section to separate from)
                        if (_newApps.isNotEmpty && !_isSearching)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(25, 10, 25, 5),
                              child: Text(
                                "ALL APPS",
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),

                        // 3. MAIN LIST
                        SliverFixedExtentList(
                          itemExtent: 72,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => AppListItem(
                              key: ValueKey(_allApps[index].info.packageName),
                              zenApp: _allApps[index],
                            ),
                            childCount: _allApps.length,
                          ),
                        ),

                        // Bottom padding for navigation bar
                        const SliverToBoxAdapter(child: SizedBox(height: 50)),
                      ],
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
        style: const TextStyle(color: Colors.white, fontSize: 18),
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
  final bool isHighlighted;

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

  const AppListItem({
    super.key,
    required this.zenApp,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => AppCacheService.instance.launchApp(zenApp),
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
                      zenApp.info.name,
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
                  // THE ICON INDICATOR
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
