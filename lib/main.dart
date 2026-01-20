import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/services/app_cache_service.dart';
import 'presentation/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set to Immersive Sticky for true full screen
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [], // Passing empty list hides both top and bottom bars
  );

  // 1. Initialize System UI
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // 2. Initialize Core Services
  AppCacheService.instance.init();

  runApp(const ZenLauncherApp());
}

class ZenLauncherApp extends StatelessWidget {
  const ZenLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Zen Launcher',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black12,
        splashFactory: InkRipple.splashFactory,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white, fontFamily: 'Roboto'),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
