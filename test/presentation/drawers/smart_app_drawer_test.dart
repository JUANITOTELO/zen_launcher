import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installed_apps/app_category.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/platform_type.dart';
import 'package:zen_launcher/core/services/app_cache_service.dart';
import 'package:zen_launcher/domain/models/zen_app.dart';
import 'package:zen_launcher/presentation/drawers/smart_app_drawer.dart';

void main() {
  testWidgets(
      'SmartAppListDrawer has focus node and dismisses keyboard on scroll/tap',
      (WidgetTester tester) async {
    AppCacheService.instance.setAppsForTesting([]);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SmartAppListDrawer(),
        ),
      ),
    );
    await tester.pump();

    // Verify search field exists
    final searchFieldFinder = find.byType(TextField);
    expect(searchFieldFinder, findsOneWidget);

    final TextField textField = tester.widget<TextField>(searchFieldFinder);
    expect(textField.focusNode, isNotNull);

    // Verify CustomScrollView has keyboardDismissBehavior set to onDrag
    final scrollViewFinder = find.byType(CustomScrollView);
    expect(scrollViewFinder, findsOneWidget);
    final CustomScrollView scrollView =
        tester.widget<CustomScrollView>(scrollViewFinder);
    expect(scrollView.keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag);
  });

  testWidgets(
      'SmartAppListDrawer excludes hidden apps and renders hidden apps controls',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final visibleApp = ZenApp(
      info: const AppInfo(
        name: 'Visible Calculator',
        icon: null,
        packageName: 'com.calc.visible',
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
      isHidden: false,
    );

    final hiddenApp = ZenApp(
      info: const AppInfo(
        name: 'Hidden Vault',
        icon: null,
        packageName: 'com.vault.hidden',
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

    AppCacheService.instance.setAppsForTesting([visibleApp, hiddenApp]);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SmartAppListDrawer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Visible app is shown
    expect(find.text('Visible Calculator'), findsOneWidget);

    // Hidden app is NOT shown in main list
    expect(find.text('Hidden Vault'), findsNothing);

    // Header has lock icon
    expect(find.byTooltip('Hidden Apps'), findsOneWidget);

    // Bottom tile is rendered
    expect(find.text('HIDDEN APPS (1)'), findsOneWidget);
  });
}
