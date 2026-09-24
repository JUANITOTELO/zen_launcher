enum QuickActionSlot {
  left(key: 'quick_action_left', defaultLabel: 'Phone'),
  right(key: 'quick_action_right', defaultLabel: 'Camera');

  final String key;
  final String defaultLabel;

  const QuickActionSlot({required this.key, required this.defaultLabel});
}

class QuickActionConfig {
  final QuickActionSlot slot;
  final String? packageName;
  final String? customLabel;

  const QuickActionConfig({
    required this.slot,
    this.packageName,
    this.customLabel,
  });

  bool get isCustom => packageName != null && packageName!.isNotEmpty;

  QuickActionConfig copyWith({
    String? packageName,
    String? customLabel,
    bool clearCustom = false,
  }) {
    return QuickActionConfig(
      slot: slot,
      packageName: clearCustom ? null : (packageName ?? this.packageName),
      customLabel: clearCustom ? null : (customLabel ?? this.customLabel),
    );
  }
}
