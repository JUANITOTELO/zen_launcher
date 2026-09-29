import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wallpaper_manager_plus/wallpaper_manager_plus.dart';
import '../../data/database/zen_database.dart';

class WallpaperService extends ChangeNotifier {
  static WallpaperService instance = WallpaperService();

  final ZenDatabase _database;

  WallpaperService([ZenDatabase? database])
      : _database = database ?? ZenDatabase.instance;

  static const String endpointJson = 'https://juanitotelo.net/daily.json';
  static const String fallbackColorUrl = 'https://juanitotelo.net/daily.webp';
  static const String fallbackDepthUrl =
      'https://juanitotelo.net/daily_depth.webp';

  File? _localFile;
  File? _depthFile;
  ui.Image? _colorImage;
  ui.Image? _depthImage;
  ui.FragmentShader? _shader;
  Map<String, dynamic>? _metadata;

  int _wallpaperVersion = 0;
  bool _isSyncing = false;
  Timer? _timer;

  // Parallax & Portal Tuning Parameters (Cinematic Calibration)
  double _focusPlane = 0.85;
  double _depthIntensity = 0.055;
  double _overscan = 1.15;
  double _sheen = 0.0015;
  double _detailSensitivity = 0.75;
  double _perspectiveWarp = 0.38;
  bool _invertX = false;
  bool _invertY = false;
  double _restingPitch = 6.0;
  bool _lockTouchPosition = false;

  File? get wallpaperFile => _localFile;
  File? get depthFile => _depthFile;
  ui.Image? get colorImage => _colorImage;
  ui.Image? get depthImage => _depthImage;
  ui.FragmentShader? get shader => _shader;
  Map<String, dynamic>? get metadata => _metadata;
  int get wallpaperVersion => _wallpaperVersion;
  bool get isSyncing => _isSyncing;
  bool get isHolographicReady =>
      _colorImage != null && _depthImage != null && _shader != null;

  double get focusPlane => _focusPlane;
  double get depthIntensity => _depthIntensity;
  double get overscan => _overscan;
  double get sheen => _sheen;
  double get detailSensitivity => _detailSensitivity;
  double get perspectiveWarp => _perspectiveWarp;
  bool get invertX => _invertX;
  bool get invertY => _invertY;
  double get restingPitch => _restingPitch;
  bool get lockTouchPosition => _lockTouchPosition;

  @visibleForTesting
  void setLocalFileForTesting(File file) {
    _localFile = file;
    _wallpaperVersion = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  @visibleForTesting
  void setHolographicAssetsForTesting({
    ui.Image? colorImage,
    ui.Image? depthImage,
    ui.FragmentShader? shader,
    Map<String, dynamic>? metadata,
  }) {
    if (colorImage != null) _colorImage = colorImage;
    if (depthImage != null) _depthImage = depthImage;
    if (shader != null) _shader = shader;
    if (metadata != null) _metadata = metadata;
    notifyListeners();
  }

  @visibleForTesting
  void cancelTimerForTesting() {
    _timer?.cancel();
    _timer = null;
  }

  void setFocusPlane(double val) {
    _focusPlane = val;
    notifyListeners();
    _saveSetting('wallpaper_focus_plane', val.toString());
  }

  void setDepthIntensity(double val) {
    _depthIntensity = val;
    notifyListeners();
    _saveSetting('wallpaper_depth_intensity', val.toString());
  }

  void setOverscan(double val) {
    _overscan = val;
    notifyListeners();
    _saveSetting('wallpaper_overscan', val.toString());
  }

  void setSheen(double val) {
    _sheen = val;
    notifyListeners();
    _saveSetting('wallpaper_sheen', val.toString());
  }

  void setDetailSensitivity(double val) {
    _detailSensitivity = val;
    notifyListeners();
    _saveSetting('wallpaper_detail_sensitivity', val.toString());
  }

  void setPerspectiveWarp(double val) {
    _perspectiveWarp = val;
    notifyListeners();
    _saveSetting('wallpaper_perspective_warp', val.toString());
  }

  void setInvertX(bool val) {
    _invertX = val;
    notifyListeners();
    _saveSetting('wallpaper_invert_x', val.toString());
  }

  void setInvertY(bool val) {
    _invertY = val;
    notifyListeners();
    _saveSetting('wallpaper_invert_y', val.toString());
  }

  void setRestingPitch(double val) {
    _restingPitch = val;
    notifyListeners();
    _saveSetting('wallpaper_resting_pitch', val.toString());
  }

  void setLockTouchPosition(bool val) {
    _lockTouchPosition = val;
    notifyListeners();
    _saveSetting('wallpaper_lock_touch_position', val.toString());
  }

  void applyPreset({
    required double focusPlane,
    required double depthIntensity,
    required double overscan,
    required double detailSensitivity,
    required double perspectiveWarp,
  }) {
    _focusPlane = focusPlane;
    _depthIntensity = depthIntensity;
    _overscan = overscan;
    _detailSensitivity = detailSensitivity;
    _perspectiveWarp = perspectiveWarp;
    notifyListeners();

    _saveSetting('wallpaper_focus_plane', focusPlane.toString());
    _saveSetting('wallpaper_depth_intensity', depthIntensity.toString());
    _saveSetting('wallpaper_overscan', overscan.toString());
    _saveSetting('wallpaper_detail_sensitivity', detailSensitivity.toString());
    _saveSetting('wallpaper_perspective_warp', perspectiveWarp.toString());
  }

  void recenterHoldingAngle(double currentPitch) {
    _restingPitch = currentPitch;
    notifyListeners();
    _saveSetting('wallpaper_resting_pitch', currentPitch.toString());
  }

  Future<void> _saveSetting(String key, String value) async {
    try {
      await _database.setSetting(key, value);
    } catch (_) {
      // In test environments, databaseFactory may be uninitialized
    }
  }

  Future<void> initBackground() async {
    await _loadSavedSettings();
    await _loadShader();

    try {
      final directory = await getApplicationDocumentsDirectory();
      final colorFile = File('${directory.path}/daily_wallpaper.webp');
      final depthFile = File('${directory.path}/daily_depth.webp');
      final metaFile = File('${directory.path}/daily_meta.json');

      if (await metaFile.exists()) {
        try {
          final metaJson = await metaFile.readAsString();
          _metadata = jsonDecode(metaJson) as Map<String, dynamic>;
        } catch (_) {}
      }

      if (await colorFile.exists() && await depthFile.exists()) {
        _localFile = colorFile;
        _depthFile = depthFile;

        // Decode cached images immediately for zero-latency frame 1 startup
        try {
          final colorBytes = await colorFile.readAsBytes();
          final depthBytes = await depthFile.readAsBytes();
          _colorImage = await _decodeImage(colorBytes);
          _depthImage = await _decodeImage(depthBytes);
          _wallpaperVersion = DateTime.now().millisecondsSinceEpoch;
        } catch (e) {
          debugPrint("Error decoding cached wallpaper images: $e");
        }

        notifyListeners();

        final lastModified = await colorFile.lastModified();
        final difference = DateTime.now().difference(lastModified);

        if (difference.inHours >= 24 ||
            _colorImage == null ||
            _depthImage == null) {
          await syncWallpaper();
        } else {
          final timeUntilNextUpdate = const Duration(hours: 24) - difference;
          _scheduleNextUpdate(timeUntilNextUpdate);
        }
      } else {
        await syncWallpaper();
      }
    } catch (e) {
      debugPrint("Error initializing wallpaper: $e");
    }
  }

  Future<void> _loadShader() async {
    try {
      final program =
          await ui.FragmentProgram.fromAsset('shaders/holographic.frag');
      _shader = program.fragmentShader();
    } catch (e) {
      debugPrint("Could not load fragment shader: $e");
    }
  }

  Future<void> _loadSavedSettings() async {
    try {
      final fp = await _database.getSetting('wallpaper_focus_plane');
      if (fp != null) _focusPlane = double.tryParse(fp) ?? _focusPlane;

      final di = await _database.getSetting('wallpaper_depth_intensity');
      if (di != null) _depthIntensity = double.tryParse(di) ?? _depthIntensity;

      final os = await _database.getSetting('wallpaper_overscan');
      if (os != null) _overscan = double.tryParse(os) ?? _overscan;

      final sh = await _database.getSetting('wallpaper_sheen');
      if (sh != null) _sheen = double.tryParse(sh) ?? _sheen;

      final ds = await _database.getSetting('wallpaper_detail_sensitivity');
      if (ds != null) {
        _detailSensitivity = double.tryParse(ds) ?? _detailSensitivity;
      }

      final pw = await _database.getSetting('wallpaper_perspective_warp');
      if (pw != null) {
        _perspectiveWarp = double.tryParse(pw) ?? _perspectiveWarp;
      }

      final ix = await _database.getSetting('wallpaper_invert_x');
      if (ix != null) _invertX = ix == 'true';

      final iy = await _database.getSetting('wallpaper_invert_y');
      if (iy != null) _invertY = iy == 'true';

      final rp = await _database.getSetting('wallpaper_resting_pitch');
      if (rp != null) _restingPitch = double.tryParse(rp) ?? _restingPitch;

      final ltp = await _database.getSetting('wallpaper_lock_touch_position');
      if (ltp != null) _lockTouchPosition = ltp == 'true';
    } catch (_) {
      // In test environments, databaseFactory may be uninitialized
    }
  }

  void _scheduleNextUpdate(Duration waitDuration) {
    _timer?.cancel();
    _timer = Timer(waitDuration, () {
      syncWallpaper();
    });
  }

  Future<bool> syncWallpaper() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    notifyListeners();

    try {
      if (_shader == null) {
        await _loadShader();
      }

      // 1. Fetch telemetry & URLs
      Map<String, dynamic> meta = {};
      try {
        final metaResponse = await http.get(
          Uri.parse(
              '$endpointJson?t=${DateTime.now().millisecondsSinceEpoch}'),
          headers: const {
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
          },
        );
        if (metaResponse.statusCode == 200) {
          meta = jsonDecode(metaResponse.body) as Map<String, dynamic>;
        }
      } catch (e) {
        debugPrint("Error fetching wallpaper metadata: $e");
      }

      final String colorUrl = meta['image_url'] != null
          ? (meta['image_url'].toString().startsWith('http')
              ? meta['image_url']
              : 'https://juanitotelo.net/${meta['image_url']}')
          : fallbackColorUrl;

      final String depthUrl = meta['depth_url'] != null
          ? (meta['depth_url'].toString().startsWith('http')
              ? meta['depth_url']
              : 'https://juanitotelo.net/${meta['depth_url']}')
          : fallbackDepthUrl;

      // 2. Fetch color and depth bytes concurrently
      final colorBytesFuture = http.readBytes(
        Uri.parse('$colorUrl?t=${DateTime.now().millisecondsSinceEpoch}'),
        headers: const {'Cache-Control': 'no-cache'},
      );
      final depthBytesFuture = http.readBytes(
        Uri.parse('$depthUrl?t=${DateTime.now().millisecondsSinceEpoch}'),
        headers: const {'Cache-Control': 'no-cache'},
      );

      final results = await Future.wait([colorBytesFuture, depthBytesFuture]);
      final Uint8List colorBytes = results[0];
      final Uint8List depthBytes = results[1];

      final directory = await getApplicationDocumentsDirectory();
      final colorFile = File('${directory.path}/daily_wallpaper.webp');
      final depthFile = File('${directory.path}/daily_depth.webp');
      final metaFile = File('${directory.path}/daily_meta.json');

      await colorFile.writeAsBytes(colorBytes);
      await depthFile.writeAsBytes(depthBytes);
      if (meta.isNotEmpty) {
        await metaFile.writeAsString(jsonEncode(meta));
      }

      final colorImage = await _decodeImage(colorBytes);
      final depthImage = await _decodeImage(depthBytes);

      await FileImage(colorFile).evict();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      if (Platform.isAndroid) {
        try {
          WallpaperManagerPlus().setWallpaper(
            colorFile,
            WallpaperManagerPlus.bothScreens,
          );
        } catch (e) {
          debugPrint("WallpaperManager platform error: $e");
        }
      }

      _localFile = colorFile;
      _depthFile = depthFile;
      _colorImage = colorImage;
      _depthImage = depthImage;
      if (meta.isNotEmpty) {
        _metadata = meta;
      }
      _wallpaperVersion = DateTime.now().millisecondsSinceEpoch;
      _scheduleNextUpdate(const Duration(hours: 24));
      return true;
    } catch (e) {
      debugPrint("Wallpaper sync error: $e");
      _scheduleNextUpdate(const Duration(hours: 1));
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
