class AppConstants {
  static const String dbName = 'zen_launcher.db';
  static const int dbVersion = 3;

  // Default candidate packages for auto-discovery
  static const List<String> defaultPhonePackages = [
    'com.google.android.dialer',
    'com.android.dialer',
    'com.samsung.android.dialer',
    'com.android.contacts',
  ];

  static const List<String> defaultCameraPackages = [
    'com.google.android.GoogleCamera',
    'com.android.camera',
    'com.sec.android.app.camera',
    'com.oneplus.camera',
    'com.motorola.camera2',
  ];

  static const List<String> defaultClockPackages = [
    'com.google.android.deskclock',
    'com.android.deskclock',
    'com.sec.android.app.clockpackage',
    'com.oneplus.deskclock',
    'com.miui.deskclock',
    'com.coloros.alarmclock',
    'com.asus.deskclock',
  ];
}
