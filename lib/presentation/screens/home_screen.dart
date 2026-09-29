import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/wallpaper_service.dart';
import '../drawers/smart_app_drawer.dart';
import '../pages/quick_notes_page.dart';
import '../pages/zen_calendar_page.dart';
import '../widgets/clock_widget.dart';
import '../widgets/hidden_apps_sheet.dart';
import '../widgets/holographic_viewport.dart';
import '../widgets/home_dock.dart';
import '../widgets/pin_auth_dialog.dart';
import '../widgets/wallpaper_tuning_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _platform = MethodChannel('com.zen.launcher/utils');

  // Carousel Controller: initialPage 1000 % 3 == 1 (Home Screen)
  final PageController _pageController = PageController(initialPage: 1000);
  double _lastPitch = 6.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WallpaperService.instance.initBackground();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
  }

  void _openWallpaperTuningSheet() async {
    HapticFeedback.mediumImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => WallpaperTuningSheet(currentPitch: _lastPitch),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (action == 'open_hidden_apps' && mounted) {
      PinAuthDialog.show(
        context: context,
        onSuccess: (ctx) {
          HiddenAppsSheet.show(ctx);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: WallpaperService.instance,
      builder: (context, _) {
        final File? wallpaperFile = WallpaperService.instance.wallpaperFile;
        final int wallpaperVersion = WallpaperService.instance.wallpaperVersion;
        final bool isSyncing = WallpaperService.instance.isSyncing;
        final bool isHolographic =
            WallpaperService.instance.isHolographicReady;

        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: GestureDetector(
            onLongPress: () {
              if (_pageController.hasClients) {
                int currentIndex = _pageController.page!.round() % 3;
                if (currentIndex == 1) {
                  _openWallpaperTuningSheet();
                }
              } else {
                _openWallpaperTuningSheet();
              }
            },
            onDoubleTap: () {
              HapticFeedback.lightImpact();
              WallpaperService.instance.recenterHoldingAngle(_lastPitch);
              if (_pageController.hasClients) {
                int currentIndex = _pageController.page!.round() % 3;
                if (currentIndex == 1) {
                  WallpaperService.instance.syncWallpaper();
                }
              } else {
                WallpaperService.instance.syncWallpaper();
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
                // 1. Wallpaper Background Layer (2.5D Holographic Shader or Fallback)
                if (isHolographic)
                  HolographicViewport(
                    key: ValueKey('holographic_vp_$wallpaperVersion'),
                    colorImage: WallpaperService.instance.colorImage!,
                    depthImage: WallpaperService.instance.depthImage!,
                    shader: WallpaperService.instance.shader!,
                    focusPlane: WallpaperService.instance.focusPlane,
                    depthIntensity:
                        WallpaperService.instance.depthIntensity,
                    overscan: WallpaperService.instance.overscan,
                    sheen: WallpaperService.instance.sheen,
                    detailSensitivity:
                        WallpaperService.instance.detailSensitivity,
                    perspectiveWarp:
                        WallpaperService.instance.perspectiveWarp,
                    invertX: WallpaperService.instance.invertX,
                    invertY: WallpaperService.instance.invertY,
                    restingPitch: WallpaperService.instance.restingPitch,
                    lockTouchPosition:
                        WallpaperService.instance.lockTouchPosition,
                    onPitchUpdate: (pitch) => _lastPitch = pitch,
                  )
                else if (wallpaperFile != null)
                  Image.file(
                    wallpaperFile,
                    key: ValueKey('wallpaper_$wallpaperVersion'),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
                else
                  const DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black38),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black38),
                ),

                // 2. Infinite Carousel (0: Notes, 1: Home, 2: Calendar)
                PageView.builder(
                  controller: _pageController,
                  itemBuilder: (context, index) {
                    final pageIndex = index % 3;
                    if (pageIndex == 0) return const QuickNotesPage();
                    if (pageIndex == 1) return _buildHomePage();
                    return const ZenCalendarPage();
                  },
                ),

                // 3. Loading Indicator Overlay
                if (isSyncing)
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
      },
    );
  }

  Widget _buildHomePage() {
    return SafeArea(
      child: Column(
        children: [
          const Spacer(flex: 2),
          const ClockWidget(),
          const Spacer(flex: 3),
          HomeDock(onOpenDrawer: _openAppDrawer),
        ],
      ),
    );
  }
}
