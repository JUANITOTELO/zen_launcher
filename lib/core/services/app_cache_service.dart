import 'dart:async';
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

  Future<void> init() async {
    if (_isLoaded) return;
    await _fetchApps();
    _startListeningToChanges();
    _isLoaded = true;
  }

  void _startListeningToChanges() {
    _appChangeSubscription?.cancel();
    _appChangeSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        debugPrint("Native App Event detected: $event");
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
        usage = stats[app.packageName]!['usage'];
        firstSeen = stats[app.packageName]!['first_seen'];
      } else {
        // Unknown app (New Install OR First run of Launcher)
        firstSeen = isFreshInstall ? 0 : now;
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
