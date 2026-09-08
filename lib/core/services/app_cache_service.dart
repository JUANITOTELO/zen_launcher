import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import '../../data/database/zen_database.dart';
import '../../domain/models/zen_app.dart';

class AppCacheService extends ChangeNotifier {
  static final AppCacheService instance = AppCacheService._();
  AppCacheService._();

  // Requires native implementation in MainActivity.kt
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
    if (_isLoaded) return;
    try {
      await _fetchApps();
      _startListeningToChanges();
    } catch (e) {
      debugPrint("Error initializing AppCacheService: $e");
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  void _startListeningToChanges() {
    if (!Platform.isAndroid) return;
    _appChangeSubscription?.cancel();
    try {
      _appChangeSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          debugPrint("Native App Event detected: $event");
          _fetchApps();
        },
        onError: (error) {
          debugPrint("Error listening to app changes: $error");
        },
      );
    } catch (e) {
      debugPrint("Error setting up app changes event channel: $e");
    }
  }

  Future<void> _fetchApps() async {
    List<AppInfo> rawApps = [];
    Map<String, Map<String, dynamic>> stats = {};

    try {
      rawApps = await InstalledApps.getInstalledApps(
        excludeSystemApps: false,
        withIcon: true,
        packageNamePrefix: '',
      );
    } catch (e) {
      debugPrint("Error fetching installed apps: $e");
    }

    try {
      stats = await ZenDatabase.instance.getAllStats();
    } catch (e) {
      debugPrint("Error fetching app stats from database: $e");
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final bool isFreshInstall = stats.isEmpty;

    List<ZenApp> tempApps = [];

    for (var app in rawApps) {
      int usage = 0;
      int firstSeen = 0;

      if (stats.containsKey(app.packageName)) {
        usage = stats[app.packageName]!['usage'];
        firstSeen = stats[app.packageName]!['first_seen'];
      } else {
        // Unknown app (New Install OR First run of Launcher)
        firstSeen = isFreshInstall ? 0 : now;
        try {
          ZenDatabase.instance.registerApp(app.packageName, firstSeen);
        } catch (_) {}
      }

      tempApps.add(
        ZenApp(info: app, usageCount: usage, firstSeenTimestamp: firstSeen),
      );
    }

    _cachedApps = tempApps;
    _sortApps();
    notifyListeners();
  }

  Future<void> launchApp(ZenApp app) async {
    app.usageCount++;
    _sortApps();
    notifyListeners();
    try {
      ZenDatabase.instance.incrementUsage(app.info.packageName);
    } catch (_) {}
    try {
      InstalledApps.startApp(app.info.packageName);
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
