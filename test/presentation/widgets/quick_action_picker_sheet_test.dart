import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installed_apps/app_category.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/platform_type.dart';
import 'package:zen_launcher/core/services/app_cache_service.dart';
import 'package:zen_launcher/domain/models/quick_action_slot.dart';
import 'package:zen_launcher/domain/models/zen_app.dart';
import 'package:zen_launcher/presentation/widgets/quick_action_picker_sheet.dart';

void main() {
  testWidgets('QuickActionPickerSheet renders slot title, reset option, and app list', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    AppCacheService.instance.setAppsForTesting([
      ZenApp(
        info: const AppInfo(
          name: 'Zen Browser',
          icon: null,
          packageName: 'com.zen.browser',
          versionName: '1.0',
          versionCode: 1,
          platformType: PlatformType.nativeOrOthers,
          installedTimestamp: 0,
          isSystemApp: false,
          isLaunchableApp: true,
          category: AppCategory.undefined,
        ),
        usageCount: 0,
        firstSeenTimestamp: 0,
      ),
    ]);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QuickActionPickerSheet(slot: QuickActionSlot.left),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('CONFIGURE LEFT SHORTCUT'), findsOneWidget);
    expect(find.text('Reset to Default (Phone)'), findsOneWidget);
    expect(find.text('Zen Browser'), findsOneWidget);
  });
}
