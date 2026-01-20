import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/services/app_cache_service.dart';
import '../../../domain/models/zen_app.dart';
import '../widgets/app_list_item.dart';

class SmartAppListDrawer extends StatefulWidget {
  const SmartAppListDrawer({super.key});

  @override
  State<SmartAppListDrawer> createState() => _SmartAppListDrawerState();
}

class _SmartAppListDrawerState extends State<SmartAppListDrawer> {
  final TextEditingController _searchController = TextEditingController();
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
    _searchController.dispose();
    AppCacheService.instance.removeListener(_onServiceUpdate);
    super.dispose();
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

    return DraggableScrollableSheet(
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
                            ),
                            childCount: _allApps.length,
                          ),
                        ),
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
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 25, 25, 15),
      child: TextField(
        controller: _searchController,
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
    );
  }
}
