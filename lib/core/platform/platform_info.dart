import 'dart:io' show Platform;

class LBPlatform {
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS     => Platform.isIOS;
  static bool get isLinux   => Platform.isLinux;
  static bool get isMacOS   => Platform.isMacOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isDesktop => isLinux || isMacOS || isWindows;

  /// Cell scanning requires Android — no public API on iOS, no cellular on desktop.
  static bool get supportsCellScanning => isAndroid;

  /// Wi-Fi AP scanning: Android (wifi_scan), Linux (nmcli), macOS (networksetup).
  /// Windows has very limited support via netsh.
  static bool get supportsWifiScanning => isAndroid || isLinux || isMacOS;

  /// RF kill (airplane mode) is Android-only.
  static bool get supportsRfKill => isAndroid;

  /// Wake lock via PowerManager is Android-only.
  static bool get supportsWakeLock => isAndroid;

  /// BLE scanning works on all platforms via flutter_blue_plus.
  static bool get supportsBleScanning => true;

  static String get name {
    if (isAndroid) return 'Android';
    if (isIOS)     return 'iOS';
    if (isLinux)   return 'Linux';
    if (isMacOS)   return 'macOS';
    if (isWindows) return 'Windows';
    return 'Unknown';
  }
}
