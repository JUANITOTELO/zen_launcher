import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/app_cache_service.dart';
import '../../core/services/quick_action_service.dart';
import '../../domain/models/quick_action_slot.dart';
import '../../domain/models/zen_app.dart';
import 'quick_action_picker_sheet.dart';

class HomeDock extends StatelessWidget {
  final VoidCallback onOpenDrawer;

  const HomeDock({super.key, required this.onOpenDrawer});

  void _openConfigSheet(BuildContext context, QuickActionSlot slot) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => QuickActionPickerSheet(slot: slot),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        QuickActionService.instance,
        AppCacheService.instance,
      ]),
      builder: (context, _) {
        final leftConfig = QuickActionService.instance.getConfig(QuickActionSlot.left);
        final rightConfig = QuickActionService.instance.getConfig(QuickActionSlot.right);
        final apps = AppCacheService.instance.apps;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _DockActionButton(
                key: const Key('dock_left_action_button'),
                slot: QuickActionSlot.left,
                config: leftConfig,
                installedApps: apps,
                defaultIcon: Icons.phone_outlined,
                onTap: () => QuickActionService.instance.launchSlot(context, QuickActionSlot.left),
                onLongPress: () => _openConfigSheet(context, QuickActionSlot.left),
              ),
              GestureDetector(
                key: const Key('dock_drawer_handle'),
                onTap: onOpenDrawer,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 80,
                  height: 60,
                  alignment: Alignment.bottomCenter,
                  child: const Icon(
                    Icons.keyboard_arrow_up,
                    color: Colors.white24,
                    size: 20,
                  ),
                ),
              ),
              _DockActionButton(
                key: const Key('dock_right_action_button'),
                slot: QuickActionSlot.right,
                config: rightConfig,
                installedApps: apps,
                defaultIcon: Icons.camera_alt_outlined,
                onTap: () => QuickActionService.instance.launchSlot(context, QuickActionSlot.right),
                onLongPress: () => _openConfigSheet(context, QuickActionSlot.right),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DockActionButton extends StatelessWidget {
  final QuickActionSlot slot;
  final QuickActionConfig config;
  final List<ZenApp> installedApps;
  final IconData defaultIcon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _DockActionButton({
    super.key,
    required this.slot,
    required this.config,
    required this.installedApps,
    required this.defaultIcon,
    required this.onTap,
    required this.onLongPress,
  });

  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    Widget iconWidget;

    if (config.isCustom) {
      ZenApp? matchedApp;
      try {
        matchedApp = installedApps.firstWhere((a) => a.info.packageName == config.packageName);
      } catch (_) {}

      if (matchedApp != null && matchedApp.info.icon != null) {
        iconWidget = SizedBox(
          width: 26,
          height: 26,
          child: ColorFiltered(
            colorFilter: _grayscaleFilter,
            child: Image.memory(
              matchedApp.info.icon!,
              fit: BoxFit.contain,
            ),
          ),
        );
      } else {
        iconWidget = const Icon(Icons.widgets_outlined, color: Colors.white70, size: 26);
      }
    } else {
      iconWidget = Icon(defaultIcon, color: Colors.white70, size: 28);
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(24),
      splashColor: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: iconWidget,
      ),
    );
  }
}
