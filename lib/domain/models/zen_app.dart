import 'package:installed_apps/app_info.dart';

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
