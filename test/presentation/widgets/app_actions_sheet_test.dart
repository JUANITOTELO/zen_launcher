import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installed_apps/app_category.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/platform_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zen_launcher/core/services/app_cache_service.dart';
import 'package:zen_launcher/data/database/zen_database.dart';
import 'package:zen_launcher/domain/models/zen_app.dart';
import 'package:zen_launcher/presentation/widgets/app_actions_sheet.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await ZenDatabase.instance.initInMemory();
  });

  tearDown(() async {
    await ZenDatabase.instance.close();
  });
  testWidgets(
      'AppActionsSheet shows rename, settings, hide, and uninstall options',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final app = ZenApp(
      info: const AppInfo(
        name: 'Browser Pro',
        icon: null,
        packageName: 'com.browser.pro',
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
    );
    AppCacheService.instance.setAppsForTesting([app]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppActionsSheet(zenApp: app),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Browser Pro'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('App Settings'), findsOneWidget);
    expect(find.text('Hide App'), findsOneWidget);
    expect(find.text('Uninstall'), findsOneWidget);
    expect(find.text('Set as Left Shortcut'), findsOneWidget);
    expect(find.text('Set as Right Shortcut'), findsOneWidget);

    // Tap Hide App
    await tester.tap(find.text('Hide App'));
    await tester.pump();

    expect(app.isHidden, isTrue);
  });

  testWidgets('AppActionsSheet shows Unhide App when app is hidden',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final hiddenApp = ZenApp(
      info: const AppInfo(
        name: 'Secret Vault',
        icon: null,
        packageName: 'com.secret.vault',
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
      isHidden: true,
    );
    AppCacheService.instance.setAppsForTesting([hiddenApp]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppActionsSheet(zenApp: hiddenApp),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Unhide App'), findsOneWidget);

    // Tap Unhide App
    await tester.tap(find.text('Unhide App'));
    await tester.pump();

    expect(hiddenApp.isHidden, isFalse);
  });
}
