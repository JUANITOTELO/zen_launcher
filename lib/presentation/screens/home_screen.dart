import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Needed for SystemChrome & MethodChannel
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wallpaper_manager_plus/wallpaper_manager_plus.dart';

import '../../core/services/app_cache_service.dart'; // Added for app launching
import '../../domain/models/zen_app.dart'; // Added for ZenApp type
import '../widgets/clock_widget.dart';
import '../drawers/smart_app_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // Channel to communicate with MainActivity.kt
  static const _platform = MethodChannel('com.zen.launcher/utils');

  final String _imageUrl = "https://juanitotelo.net/daily.webp";
  File? _localFile;
  bool _isSyncing = false;
  Timer? _timer;

  // Carousel Controller
  // Start at 1000 so we can swipe left immediately (Infinite illusion)
  // 1000 % 3 == 1 (Home Screen)
  final PageController _pageController = PageController(initialPage: 1000);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initBackground();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // 2. Handle Lifecycle Changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _initBackground() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/daily_wallpaper.webp');

    if (await file.exists()) {
      setState(() => _localFile = file);
      final lastModified = await file.lastModified();
      final difference = DateTime.now().difference(lastModified);

      if (difference.inHours >= 24) {
        _syncWallpaper();
      } else {
        final timeUntilNextUpdate = const Duration(hours: 24) - difference;
        _scheduleNextUpdate(timeUntilNextUpdate);
      }
    } else {
      _syncWallpaper();
    }
  }

  void _scheduleNextUpdate(Duration waitDuration) {
    _timer?.cancel();
    _timer = Timer(waitDuration, () {
      _syncWallpaper();
    });
  }

  Future<void> _syncWallpaper() async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);

    try {
      final response = await http.get(Uri.parse(_imageUrl));
      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/daily_wallpaper.webp');

        await file.writeAsBytes(response.bodyBytes);
        await FileImage(file).evict();

        WallpaperManagerPlus().setWallpaper(
          file,
          WallpaperManagerPlus.bothScreens,
        );

        _scheduleNextUpdate(const Duration(hours: 24));

        if (mounted) {
          setState(() => _localFile = file);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Zen refreshed.'),
              duration: Duration(milliseconds: 800),
              backgroundColor: Color.fromARGB(199, 238, 238, 238),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Wallpaper Error: $e");
      _scheduleNextUpdate(const Duration(hours: 1));
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _expandNotifications() async {
    try {
      await _platform.invokeMethod('expandNotifications');
    } catch (e) {
      _showSystemBars();
    }
  }

  void _showSystemBars() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  void _openAppDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      barrierColor: Colors.black26,
      builder: (context) => const SmartAppListDrawer(),
    ).then((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
  }

  void _launchAppByCategory(List<String> packageCandidates, String keyword) {
    final apps = AppCacheService.instance.apps;
    ZenApp? target;
    try {
      target = apps.firstWhere(
        (app) => packageCandidates.contains(app.info.packageName),
      );
    } catch (_) {
      try {
        target = apps.firstWhere(
          (app) => app.info.name.toLowerCase().contains(keyword),
        );
      } catch (_) {}
    }

    if (target != null) {
      AppCacheService.instance.launchApp(target);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$keyword app not found'),
          backgroundColor: Colors.white10,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _launchPhone() {
    _launchAppByCategory([
      'com.google.android.dialer',
      'com.android.dialer',
      'com.samsung.android.dialer',
      'com.android.contacts',
    ], 'phone');
  }

  void _launchCamera() {
    _launchAppByCategory([
      'com.google.android.GoogleCamera',
      'com.android.camera',
      'com.sec.android.app.camera',
      'com.oneplus.camera',
      'com.motorola.camera2',
    ], 'camera');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onDoubleTap: () {
          if (_pageController.hasClients) {
            int currentIndex = _pageController.page!.round() % 3;
            if (currentIndex == 1) _syncWallpaper();
          }
        },
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity! < -500) {
            _openAppDrawer();
          } else if (details.primaryVelocity! > 500) {
            _expandNotifications();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Static Background Layer
            if (_localFile != null)
              Image.file(_localFile!, fit: BoxFit.cover, gaplessPlayback: true)
            else
              const DecoratedBox(
                decoration: BoxDecoration(color: Colors.black38),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(color: Colors.black38),
            ),

            // 3. Infinite Carousel
            PageView.builder(
              controller: _pageController,
              itemBuilder: (context, index) {
                // Modulo math to create the loop
                // 0: Notes, 1: Home, 2: Calendar
                final pageIndex = index % 3;

                if (pageIndex == 0) return const _QuickNotesPage();
                if (pageIndex == 1) return _buildHomePage();
                return const _ZenCalendarPage();
              },
            ),

            // 4. Loading Indicator Overlay
            if (_isSyncing)
              const Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white30,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomePage() {
    return SafeArea(
      child: Column(
        children: [
          const Spacer(flex: 2),
          const ClockWidget(),
          const Spacer(flex: 3),

          // Quick Access Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _QuickAccessButton(
                  icon: Icons.phone_outlined,
                  onTap: _launchPhone,
                ),
                GestureDetector(
                  onTap: _openAppDrawer,
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
                _QuickAccessButton(
                  icon: Icons.camera_alt_outlined,
                  onTap: _launchCamera,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAccessButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QuickAccessButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white70, size: 28),
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        highlightColor: Colors.white10,
        padding: const EdgeInsets.all(12),
      ),
    );
  }
}

// --- NEW CAROUSEL PAGES ---

class _QuickNotesPage extends StatefulWidget {
  const _QuickNotesPage();

  @override
  State<_QuickNotesPage> createState() => _QuickNotesPageState();
}

class _QuickNotesPageState extends State<_QuickNotesPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();

  @override
  bool get wantKeepAlive => true; // Keep text when swiping away

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/quick_note.txt');
      if (await file.exists()) {
        final text = await file.readAsString();
        if (mounted) _controller.text = text;
      }
    } catch (e) {
      debugPrint("Error loading note: $e");
    }
  }

  Future<void> _saveNote(String text) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/quick_note.txt');
      await file.writeAsString(text);
    } catch (e) {
      debugPrint("Error saving note: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "THOUGHTS",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: _saveNote,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  height: 1.5,
                  fontFamily: 'Roboto',
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: "Type something...",
                  hintStyle: TextStyle(color: Colors.white24),
                ),
                cursorColor: Colors.amberAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZenCalendarPage extends StatelessWidget {
  const _ZenCalendarPage();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
    final firstDayOffset = DateTime(now.year, now.month, 1).weekday - 1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "FOCUS",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            Text(
              "${now.day}",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 80,
                fontWeight: FontWeight.w200,
              ),
            ),
            Text(
              "EVENTS TODAY",
              style: TextStyle(
                color: Colors.amberAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            // Minimal Month Visualization
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: daysInMonth + firstDayOffset,
              itemBuilder: (context, index) {
                if (index < firstDayOffset) return const SizedBox();
                final day = index - firstDayOffset + 1;
                final isToday = day == now.day;

                return Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? const BoxDecoration(
                            color: Colors.white24,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      "$day",
                      style: TextStyle(
                        color: isToday ? Colors.white : Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
