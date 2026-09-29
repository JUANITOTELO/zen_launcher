import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/app_cache_service.dart';
import '../../domain/models/zen_app.dart';
import 'app_actions_sheet.dart';
import 'pin_auth_dialog.dart';

class HiddenAppsSheet extends StatefulWidget {
  const HiddenAppsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      barrierColor: Colors.black45,
      builder: (context) => const HiddenAppsSheet(),
    );
  }

  @override
  State<HiddenAppsSheet> createState() => _HiddenAppsSheetState();
}

class _HiddenAppsSheetState extends State<HiddenAppsSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openAppActions(ZenApp app) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AppActionsSheet(zenApp: app),
    );
  }

  void _changePin() {
    HapticFeedback.lightImpact();
    PinAuthDialog.show(
      context: context,
      initialMode: PinMode.changePin,
      onSuccess: (ctx) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PIN updated successfully',
              style: TextStyle(fontFamily: 'monospace'),
            ),
            duration: Duration(seconds: 2),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppCacheService.instance,
      builder: (context, _) {
        final hiddenApps = AppCacheService.instance.hiddenApps;
        final filteredApps = _query.isEmpty
            ? hiddenApps
            : hiddenApps
                .where((a) => a.normalizedName.contains(_query))
                .toList();

        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          snap: true,
          builder: (context, scrollController) {
            return ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  color: const Color(0xFF101114).withValues(alpha: 0.96),
                  child: Column(
                    children: [
                      // Handle bar
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),

                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.visibility_off_outlined,
                                    color: Colors.tealAccent, size: 20),
                                const SizedBox(width: 10),
                                Text(
                                  'HIDDEN APPS (${hiddenApps.length})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.password,
                                      color: Colors.white60, size: 20),
                                  tooltip: 'Change PIN',
                                  onPressed: _changePin,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.white60, size: 20),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Search Bar
                      if (hiddenApps.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontFamily: 'monospace'),
                              decoration: const InputDecoration(
                                hintText: 'Search hidden apps...',
                                hintStyle: TextStyle(
                                    color: Colors.white30,
                                    fontSize: 14,
                                    fontFamily: 'monospace'),
                                border: InputBorder.none,
                                isDense: true,
                                icon: Icon(Icons.search,
                                    color: Colors.white38, size: 18),
                              ),
                            ),
                          ),
                        ),

                      const Divider(color: Colors.white10, height: 1),

                      // Body
                      Expanded(
                        child: hiddenApps.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: filteredApps.length,
                                itemBuilder: (context, index) {
                                  final app = filteredApps[index];
                                  return _buildAppItem(app);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off_outlined,
                color: Colors.white24, size: 48),
            const SizedBox(height: 16),
            const Text(
              'NO HIDDEN APPS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Long-press any app in the drawer and select "Hide App" to keep it out of sight.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white30,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppItem(ZenApp app) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: app.info.icon != null
          ? SizedBox(
              width: 38,
              height: 38,
              child: Image.memory(app.info.icon!, fit: BoxFit.contain),
            )
          : const Icon(Icons.apps, color: Colors.white54, size: 38),
      title: Text(
        app.displayName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontFamily: 'monospace',
        ),
      ),
      subtitle: Text(
        app.info.packageName,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.visibility_outlined,
            color: Colors.tealAccent, size: 22),
        tooltip: 'Unhide App',
        onPressed: () {
          HapticFeedback.lightImpact();
          AppCacheService.instance.setAppHidden(app, false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${app.displayName} restored to drawer',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).pop();
        AppCacheService.instance.launchApp(app);
      },
      onLongPress: () => _openAppActions(app),
    );
  }
}
