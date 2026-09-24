import 'package:flutter/material.dart';
import '../../data/database/zen_database.dart';
import '../../domain/models/quick_action_slot.dart';
import '../../domain/models/zen_app.dart';
import '../constants/app_constants.dart';
import 'app_cache_service.dart';

class QuickActionService extends ChangeNotifier {
  static QuickActionService instance = QuickActionService(ZenDatabase.instance);

  final ZenDatabase _database;
  final Map<QuickActionSlot, QuickActionConfig> _configs = {
    QuickActionSlot.left: const QuickActionConfig(slot: QuickActionSlot.left),
    QuickActionSlot.right: const QuickActionConfig(slot: QuickActionSlot.right),
  };

  QuickActionService(this._database);

  QuickActionConfig getConfig(QuickActionSlot slot) => _configs[slot]!;

  Future<void> init() async {
    try {
      final leftPkg = await _database.getSetting(QuickActionSlot.left.key);
      final leftLbl = await _database.getSetting('${QuickActionSlot.left.key}_label');
      _configs[QuickActionSlot.left] = QuickActionConfig(
        slot: QuickActionSlot.left,
        packageName: leftPkg,
        customLabel: leftLbl,
      );

      final rightPkg = await _database.getSetting(QuickActionSlot.right.key);
      final rightLbl = await _database.getSetting('${QuickActionSlot.right.key}_label');
      _configs[QuickActionSlot.right] = QuickActionConfig(
        slot: QuickActionSlot.right,
        packageName: rightPkg,
        customLabel: rightLbl,
      );
    } catch (e) {
      debugPrint("Error loading quick action settings: $e");
    } finally {
      notifyListeners();
    }
  }

  Future<void> setCustomApp({
    required QuickActionSlot slot,
    required String packageName,
    required String label,
  }) async {
    _configs[slot] = QuickActionConfig(
      slot: slot,
      packageName: packageName,
      customLabel: label,
    );
    notifyListeners();

    try {
      await _database.setSetting(slot.key, packageName);
      await _database.setSetting('${slot.key}_label', label);
    } catch (e) {
      debugPrint("Error saving quick action setting: $e");
    }
  }

  Future<void> resetToDefault(QuickActionSlot slot) async {
    _configs[slot] = QuickActionConfig(slot: slot);
    notifyListeners();

    try {
      await _database.removeSetting(slot.key);
      await _database.removeSetting('${slot.key}_label');
    } catch (e) {
      debugPrint("Error resetting quick action setting: $e");
    }
  }

  ZenApp? resolveTargetApp(QuickActionSlot slot, List<ZenApp> installedApps) {
    final config = _configs[slot]!;

    if (config.isCustom) {
      try {
        return installedApps.firstWhere(
          (app) => app.info.packageName == config.packageName,
        );
      } catch (_) {
        return null;
      }
    }

    if (slot == QuickActionSlot.left) {
      try {
        return installedApps.firstWhere(
          (app) => AppConstants.defaultPhonePackages.contains(app.info.packageName),
        );
      } catch (_) {
        try {
          return installedApps.firstWhere(
            (app) => app.displayName.toLowerCase().contains('phone'),
          );
        } catch (_) {
          return null;
        }
      }
    } else {
      try {
        return installedApps.firstWhere(
          (app) => AppConstants.defaultCameraPackages.contains(app.info.packageName),
        );
      } catch (_) {
        try {
          return installedApps.firstWhere(
            (app) => app.displayName.toLowerCase().contains('camera'),
          );
        } catch (_) {
          return null;
        }
      }
    }
  }

  void launchSlot(BuildContext context, QuickActionSlot slot) {
    final apps = AppCacheService.instance.apps;
    final target = resolveTargetApp(slot, apps);

    if (target != null) {
      AppCacheService.instance.launchApp(target);
    } else {
      final label = _configs[slot]?.customLabel ?? slot.defaultLabel;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label app not found'),
          backgroundColor: Colors.white10,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }
}
