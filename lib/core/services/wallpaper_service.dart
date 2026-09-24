import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wallpaper_manager_plus/wallpaper_manager_plus.dart';

class WallpaperService extends ChangeNotifier {
  static final WallpaperService instance = WallpaperService();

  final String _imageUrl = "https://juanitotelo.net/daily.webp";
  File? _localFile;
  int _wallpaperVersion = 0;
  bool _isSyncing = false;
  Timer? _timer;

  File? get wallpaperFile => _localFile;
  int get wallpaperVersion => _wallpaperVersion;
  bool get isSyncing => _isSyncing;

  @visibleForTesting
  void setLocalFileForTesting(File file) {
    _localFile = file;
    _wallpaperVersion = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  Future<void> initBackground() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/daily_wallpaper.webp');

      if (await file.exists()) {
        _localFile = file;
        notifyListeners();

        final lastModified = await file.lastModified();
        final difference = DateTime.now().difference(lastModified);

        if (difference.inHours >= 24) {
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
      final cacheBustedUrl = Uri.parse(
        '$_imageUrl?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http.get(
        cacheBustedUrl,
        headers: const {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
        },
      );

      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/daily_wallpaper.webp');

        await file.writeAsBytes(response.bodyBytes);
        await FileImage(file).evict();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();

        if (Platform.isAndroid) {
          try {
            WallpaperManagerPlus().setWallpaper(
              file,
              WallpaperManagerPlus.bothScreens,
            );
          } catch (e) {
            debugPrint("WallpaperManager platform error: $e");
          }
        }

        _scheduleNextUpdate(const Duration(hours: 24));
        _localFile = file;
        _wallpaperVersion = DateTime.now().millisecondsSinceEpoch;
        return true;
      } else {
        return false;
      }
    } catch (e) {
      debugPrint("Wallpaper sync error: $e");
      _scheduleNextUpdate(const Duration(hours: 1));
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
