import 'package:installed_apps/app_info.dart';

class ZenApp {
  final AppInfo info;
  int usageCount;
  final int firstSeenTimestamp; // Unix millis
  String? customName;
  bool isHidden;

  ZenApp({
    required this.info,
    required this.usageCount,
    required this.firstSeenTimestamp,
    this.customName,
    this.isHidden = false,
  });

  String get displayName =>
      (customName != null && customName!.trim().isNotEmpty)
          ? customName!.trim()
          : info.name;

  String get normalizedName => displayName.toLowerCase();

  // It is "New" if it was seen less than 3 hours ago
  bool get isNew {
    // If timestamp is 0, it's an old app from before we started tracking
    if (firstSeenTimestamp == 0) return false;

    final installTime = DateTime.fromMillisecondsSinceEpoch(firstSeenTimestamp);
    final diff = DateTime.now().difference(installTime);
    return diff.inHours < 3;
  }
}
