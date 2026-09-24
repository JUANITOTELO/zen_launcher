import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zen_launcher/core/services/quick_action_service.dart';
import 'package:zen_launcher/data/database/zen_database.dart';
import 'package:zen_launcher/domain/models/quick_action_slot.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('QuickActionService', () {
    late QuickActionService service;

    setUp(() async {
      await ZenDatabase.instance.initInMemory();
      service = QuickActionService(ZenDatabase.instance);
      await service.init();
    });

    test('defaults to null packages for left and right slots', () {
      expect(service.getConfig(QuickActionSlot.left).isCustom, isFalse);
      expect(service.getConfig(QuickActionSlot.right).isCustom, isFalse);
    });

    test('sets custom package and persists in database', () async {
      await service.setCustomApp(
        slot: QuickActionSlot.left,
        packageName: 'com.whatsapp',
        label: 'WhatsApp',
      );

      expect(service.getConfig(QuickActionSlot.left).isCustom, isTrue);
      expect(service.getConfig(QuickActionSlot.left).packageName, 'com.whatsapp');
      expect(service.getConfig(QuickActionSlot.left).customLabel, 'WhatsApp');

      final reloadedService = QuickActionService(ZenDatabase.instance);
      await reloadedService.init();
      expect(reloadedService.getConfig(QuickActionSlot.left).packageName, 'com.whatsapp');
    });

    test('resets slot to default', () async {
      await service.setCustomApp(
        slot: QuickActionSlot.right,
        packageName: 'com.instagram.android',
        label: 'Instagram',
      );
      expect(service.getConfig(QuickActionSlot.right).isCustom, isTrue);

      await service.resetToDefault(QuickActionSlot.right);
      expect(service.getConfig(QuickActionSlot.right).isCustom, isFalse);
      expect(service.getConfig(QuickActionSlot.right).packageName, isNull);
    });
  });
}
