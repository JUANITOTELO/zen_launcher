import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installed_apps/app_category.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/platform_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zen_launcher/core/services/app_cache_service.dart';
import 'package:zen_launcher/data/database/zen_database.dart';
import 'package:zen_launcher/domain/models/zen_app.dart';
import 'package:zen_launcher/presentation/widgets/hidden_apps_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('HiddenAppsSheet', () {
    setUp(() async {
      await ZenDatabase.instance.initInMemory();
    });

    testWidgets('shows empty state when no hidden apps exist',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppCacheService.instance.setAppsForTesting([]);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HiddenAppsSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HIDDEN APPS (0)'), findsOneWidget);
      expect(find.text('NO HIDDEN APPS'), findsOneWidget);
    });

    testWidgets('renders hidden apps and allows unhiding an app',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final hiddenApp = ZenApp(
        info: const AppInfo(
          name: 'Private Notes',
          icon: null,
          packageName: 'com.secret.notes',
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
        const MaterialApp(
          home: Scaffold(
            body: HiddenAppsSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HIDDEN APPS (1)'), findsOneWidget);
      expect(find.text('Private Notes'), findsOneWidget);

      // Tap unhide icon
      final unhideButton = find.byTooltip('Unhide App');
      expect(unhideButton, findsOneWidget);
      await tester.tap(unhideButton);
      await tester.pumpAndSettle();

      // App is now unhidden
      expect(hiddenApp.isHidden, isFalse);
      expect(find.text('NO HIDDEN APPS'), findsOneWidget);
    });
  });
}
