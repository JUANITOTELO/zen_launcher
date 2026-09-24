import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zen_launcher/core/services/app_cache_service.dart';
import 'package:zen_launcher/core/services/quick_action_service.dart';
import 'package:zen_launcher/data/database/zen_database.dart';
import 'package:zen_launcher/presentation/widgets/home_dock.dart';

void main() {
  testWidgets('HomeDock renders left button, drawer pull handle, and right button', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    AppCacheService.instance.setAppsForTesting([]);

    bool drawerOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeDock(
            onOpenDrawer: () => drawerOpened = true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('dock_left_action_button')), findsOneWidget);
    expect(find.byKey(const Key('dock_drawer_handle')), findsOneWidget);
    expect(find.byKey(const Key('dock_right_action_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dock_drawer_handle')));
    expect(drawerOpened, isTrue);
  });
}
