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
            platformType: PlatformType.nativeOrOthers,
            installedTimestamp: r.installedTimestamp,
            isSystemApp: r.isSystemApp,
            isLaunchableApp: true,
            category: AppCategory.undefined,
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
