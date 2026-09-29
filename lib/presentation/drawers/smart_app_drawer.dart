import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/app_cache_service.dart';
import '../../../domain/models/zen_app.dart';
import '../widgets/app_actions_sheet.dart';
import '../widgets/app_list_item.dart';
import '../widgets/hidden_apps_sheet.dart';
import '../widgets/pin_auth_dialog.dart';

class SmartAppListDrawer extends StatefulWidget {
  const SmartAppListDrawer({super.key});

  @override
  State<SmartAppListDrawer> createState() => _SmartAppListDrawerState();
}

class _SmartAppListDrawerState extends State<SmartAppListDrawer> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<ZenApp> _newApps = [];
  List<ZenApp> _allApps = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _updateFilteredList();
    _searchController.addListener(_updateFilteredList);
    AppCacheService.instance.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    AppCacheService.instance.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _dismissKeyboard() {
    _searchFocusNode.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
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

  void _openHiddenApps() {
    _dismissKeyboard();
    PinAuthDialog.show(
      context: context,
      onSuccess: (ctx) {
        HiddenAppsSheet.show(ctx);
      },
    );
  }

  void _onServiceUpdate() {
    if (mounted) _updateFilteredList();
  }

  void _updateFilteredList() {
    final all = AppCacheService.instance.apps;
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _isSearching = false;
        _newApps = all.where((app) => app.isNew).toList();
        _allApps = all;
      } else {
        _isSearching = true;
        _newApps = [];
        _allApps = all
            .where((app) => app.normalizedName.contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AppCacheService.instance.isLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white24),
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _dismissKeyboard();
      },
      child: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.translucent,
        child: DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          snap: true,
          builder: (_, scrollController) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: ColoredBox(
                  color: Colors.black26,
                  child: Column(
                    children: [
                      _buildSearchBar(),
                      const Divider(color: Colors.white12, height: 1),
                      Expanded(
                        child: CustomScrollView(
                          controller: scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          slivers: [
                            if (_newApps.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(25, 20, 25, 5),
                                  child: Text(
                                    "RECENTLY INSTALLED",
                                    style: TextStyle(
                                      color: Colors.amberAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => AppListItem(
                                    key: ValueKey(
                                      "new_${_newApps[index].info.packageName}",
                                    ),
                                    zenApp: _newApps[index],
                                    isHighlighted: true,
                                    onLongPress: () => _openAppActions(_newApps[index]),
                                  ),
                                  childCount: _newApps.length,
                                ),
                              ),
                              const SliverToBoxAdapter(child: SizedBox(height: 10)),
                            ],
                            if (_newApps.isNotEmpty && !_isSearching)
                              const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(25, 10, 25, 5),
                                  child: Text(
                                    "ALL APPS",
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            SliverFixedExtentList(
                              itemExtent: 72,
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => AppListItem(
                                  key: ValueKey(_allApps[index].info.packageName),
                                  zenApp: _allApps[index],
                                  onLongPress: () => _openAppActions(_allApps[index]),
                                ),
                                childCount: _allApps.length,
                              ),
                            ),
                            if (AppCacheService.instance.hiddenApps.isNotEmpty &&
                                !_isSearching) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(25, 20, 25, 10),
                                  child: InkWell(
                                    onTap: _openHiddenApps,
                                    borderRadius: BorderRadius.circular(14),
                                    splashColor: Colors.tealAccent.withValues(alpha: 0.1),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.04),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.white10),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.lock_outline,
                                              color: Colors.tealAccent, size: 16),
                                          const SizedBox(width: 8),
                                          Text(
                                            'HIDDEN APPS (${AppCacheService.instance.hiddenApps.length})',
                                            style: const TextStyle(
                                              color: Colors.tealAccent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.2,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SliverToBoxAdapter(child: SizedBox(height: 50)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 20, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 18),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              cursorColor: Colors.white,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline, color: Colors.white54, size: 20),
            tooltip: 'Hidden Apps',
            onPressed: _openHiddenApps,
          ),
        ],
      ),
    );
  }
}
