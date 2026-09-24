import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/app_cache_service.dart';
import '../../core/services/quick_action_service.dart';
import '../../domain/models/quick_action_slot.dart';
import '../../domain/models/zen_app.dart';

class QuickActionPickerSheet extends StatefulWidget {
  final QuickActionSlot slot;

  const QuickActionPickerSheet({super.key, required this.slot});

  @override
  State<QuickActionPickerSheet> createState() => _QuickActionPickerSheetState();
}

class _QuickActionPickerSheetState extends State<QuickActionPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<ZenApp> _filteredApps = [];

  @override
  void initState() {
    super.initState();
    _filteredApps = AppCacheService.instance.apps;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    final all = AppCacheService.instance.apps;
    if (!mounted) return;
    setState(() {
      if (query.isEmpty) {
        _filteredApps = all;
      } else {
        _filteredApps = all
            .where((app) => app.normalizedName.contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.slot == QuickActionSlot.left
        ? "CONFIGURE LEFT SHORTCUT"
        : "CONFIGURE RIGHT SHORTCUT";

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          color: Colors.black.withOpacity(0.85),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search app to assign...',
                  hintStyle: const TextStyle(color: Colors.white30),
                  prefixIcon: const Icon(Icons.search, color: Colors.white30, size: 20),
                  filled: true,
                  fillColor: Colors.white10,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.refresh, color: Colors.white70),
                title: Text(
                  'Reset to Default (${widget.slot.defaultLabel})',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  QuickActionService.instance.resetToDefault(widget.slot);
                  Navigator.of(context).pop();
                },
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: false,
                  itemCount: _filteredApps.length,
                  itemBuilder: (context, index) {
                    final app = _filteredApps[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: app.info.icon != null
                          ? SizedBox(
                              width: 32,
                              height: 32,
                              child: Image.memory(
                                app.info.icon!,
                                fit: BoxFit.contain,
                              ),
                            )
                          : const Icon(Icons.android, color: Colors.white38, size: 28),
                      title: Text(
                        app.displayName,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        app.info.packageName,
                        style: const TextStyle(color: Colors.white30, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        QuickActionService.instance.setCustomApp(
                          slot: widget.slot,
                          packageName: app.info.packageName,
                          label: app.displayName,
                        );
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
