import 'package:flutter_test/flutter_test.dart';
import 'package:installed_apps/app_category.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/platform_type.dart';
import 'package:zen_launcher/domain/models/zen_app.dart';

void main() {
  group('ZenApp Custom Name', () {
    const info = AppInfo(
      name: 'Original Name',
      icon: null,
      packageName: 'com.example.app',
      versionName: '1.0',
      versionCode: 1,
      platformType: PlatformType.nativeOrOthers,
      installedTimestamp: 0,
      isSystemApp: false,
      isLaunchableApp: true,
      category: AppCategory.undefined,
    );

    test('displayName returns info.name when customName is null or empty', () {
      final app = ZenApp(info: info, usageCount: 0, firstSeenTimestamp: 0);
      expect(app.displayName, 'Original Name');
      expect(app.normalizedName, 'original name');
    });

    test('displayName returns customName and updates normalizedName when customName is set', () {
      final app = ZenApp(
        info: info,
        usageCount: 0,
        firstSeenTimestamp: 0,
        customName: 'Custom Alias',
      );
      expect(app.displayName, 'Custom Alias');
      expect(app.normalizedName, 'custom alias');
    });
  });
}
