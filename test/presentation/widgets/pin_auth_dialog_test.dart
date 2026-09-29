import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zen_launcher/core/services/app_cache_service.dart';
import 'package:zen_launcher/data/database/zen_database.dart';
import 'package:zen_launcher/presentation/widgets/pin_auth_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PinAuthDialog', () {
    setUp(() async {
      await ZenDatabase.instance.initInMemory();
      await AppCacheService.instance.removePin();
    });

    tearDown(() async {
      await ZenDatabase.instance.close();
    });

    testWidgets('PIN setup flow prompts, confirms, and calls onSuccess on match',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool successCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinAuthDialog(
              initialMode: PinMode.setup,
              onSuccess: (ctx) => successCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CREATE 4-DIGIT PIN'), findsOneWidget);

      // Enter 1, 2, 3, 4
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pump();

      // Now in confirm mode
      expect(find.text('CONFIRM PIN'), findsOneWidget);

      // Confirm 1, 2, 3, 4
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      expect(successCalled, isTrue);
      expect(await AppCacheService.instance.verifyPin('1234'), isTrue);
    });

    testWidgets('PIN setup handles mismatch gracefully',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinAuthDialog(
              initialMode: PinMode.setup,
              onSuccess: (ctx) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter 1, 2, 3, 4
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }

      // Confirm with wrong digits: 9, 9, 9, 9
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.text('9'));
        await tester.pump();
      }

      expect(find.text('PINs did not match. Try again.'), findsOneWidget);
    });

    testWidgets('PIN verification mode verifies correct and incorrect PIN',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.runAsync(() => AppCacheService.instance.setPin('5678'));
      bool successCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinAuthDialog(
              initialMode: PinMode.verify,
              onSuccess: (ctx) => successCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ENTER 4-DIGIT PIN'), findsOneWidget);

      // Enter wrong PIN: 1, 1, 1, 1
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.text('1'));
        await tester.pump();
      }
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.text('Incorrect PIN'), findsOneWidget);
      expect(successCalled, isFalse);

      // Now enter correct PIN: 5, 6, 7, 8
      for (final digit in ['5', '6', '7', '8']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      expect(successCalled, isTrue);
    });
  });
}
