import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';

import '../../core/services/app_cache_service.dart';
import '../../core/services/quick_action_service.dart';
import '../../domain/models/quick_action_slot.dart';
import '../../domain/models/zen_app.dart';

class AppActionsSheet extends StatelessWidget {
  final ZenApp zenApp;

  const AppActionsSheet({super.key, required this.zenApp});

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: zenApp.displayName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'RENAME APP',
          style: TextStyle(color: Colors.amberAccent, fontSize: 13, letterSpacing: 1.5),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: zenApp.info.name,
            hintStyle: const TextStyle(color: Colors.white24),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.amberAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppCacheService.instance.renameApp(zenApp, null);
              Navigator.of(ctx).pop();
            },
            child: const Text('RESET', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              AppCacheService.instance.renameApp(zenApp, controller.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('SAVE', style: TextStyle(color: Colors.amberAccent)),
          ),
        ],
      ),
    );
  }

  void _uninstallApp(BuildContext context) {
    HapticFeedback.lightImpact();
    InstalledApps.uninstallApp(zenApp.info.packageName);
    Navigator.of(context).pop();
  }

  void _openSettings(BuildContext context) {
    HapticFeedback.lightImpact();
    InstalledApps.openSettings(zenApp.info.packageName);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          color: Colors.black.withOpacity(0.85),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  if (zenApp.info.icon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Image.memory(zenApp.info.icon!, fit: BoxFit.contain),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zenApp.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          zenApp.info.packageName,
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.edit_outlined, color: Colors.white70, size: 22),
                title: const Text('Rename', style: TextStyle(color: Colors.white, fontSize: 15)),
                onTap: () {
                  Navigator.of(context).pop();
                  _showRenameDialog(context);
                },
              ),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.settings_outlined, color: Colors.white70, size: 22),
                title: const Text('App Settings', style: TextStyle(color: Colors.white, fontSize: 15)),
                onTap: () => _openSettings(context),
              ),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                title: const Text('Uninstall', style: TextStyle(color: Colors.redAccent, fontSize: 15)),
                onTap: () => _uninstallApp(context),
              ),
              const Divider(color: Colors.white12, height: 16),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.chevron_left, color: Colors.white54, size: 22),
                title: const Text('Set as Left Shortcut', style: TextStyle(color: Colors.white70, fontSize: 14)),
                onTap: () {
                  HapticFeedback.lightImpact();
                  QuickActionService.instance.setCustomApp(
                    slot: QuickActionSlot.left,
                    packageName: zenApp.info.packageName,
                    label: zenApp.displayName,
                  );
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.chevron_right, color: Colors.white54, size: 22),
                title: const Text('Set as Right Shortcut', style: TextStyle(color: Colors.white70, fontSize: 14)),
                onTap: () {
                  HapticFeedback.lightImpact();
                  QuickActionService.instance.setCustomApp(
                    slot: QuickActionSlot.right,
                    packageName: zenApp.info.packageName,
                    label: zenApp.displayName,
                  );
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
