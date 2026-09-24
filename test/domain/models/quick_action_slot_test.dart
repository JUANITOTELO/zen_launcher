import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/domain/models/quick_action_slot.dart';

void main() {
  group('QuickActionSlot', () {
    test('enum contains left and right slots', () {
      expect(QuickActionSlot.values.length, 2);
      expect(QuickActionSlot.left.key, 'quick_action_left');
      expect(QuickActionSlot.right.key, 'quick_action_right');
    });

    test('default label reflects phone and camera', () {
      expect(QuickActionSlot.left.defaultLabel, 'Phone');
      expect(QuickActionSlot.right.defaultLabel, 'Camera');
    });
  });
}
