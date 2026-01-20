import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/services/app_cache_service.dart';
import '../../../domain/models/zen_app.dart';

class ClockWidget extends StatelessWidget {
  const ClockWidget({super.key});

  void _launchClockApp(BuildContext context) {
    final apps = AppCacheService.instance.apps;

    // Priority list of known clock package names
    final clockPackages = [
      'com.google.android.deskclock', // Google
      'com.android.deskclock', // AOSP
      'com.sec.android.app.clockpackage', // Samsung
      'com.oneplus.deskclock', // OnePlus
      'com.miui.deskclock', // Xiaomi
      'com.coloros.alarmclock', // Oppo
      'com.asus.deskclock', // Asus
    ];

    ZenApp? targetApp;

    try {
      // 1. Try to find a match in the known package list
      targetApp = apps.firstWhere(
        (app) => clockPackages.contains(app.info.packageName),
      );
    } catch (_) {
      // 2. Fallback: Search for an app explicitly named "Clock"
      try {
        targetApp = apps.firstWhere(
          (app) => app.info.name.toLowerCase() == 'clock',
        );
      } catch (_) {
        // No clock found
      }
    }

    if (targetApp != null) {
      AppCacheService.instance.launchApp(targetApp);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No Clock app found.'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.white10,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _launchClockApp(context),
      behavior: HitTestBehavior.opaque,
      child: StreamBuilder(
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
      ),
    );
  }
}
