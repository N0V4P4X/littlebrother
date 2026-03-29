import 'package:flutter/services.dart';

/// Thin Dart wrapper around the native WakeLockHandler channel.
/// Acquires a PARTIAL_WAKE_LOCK so scan timers keep firing
/// when the screen is off. Must be released when scanning stops.
class LBWakeLock {
  static const _channel = MethodChannel('art.n0v4.littlebrother/wake');

  static Future<void> acquire() async {
    try {
      await _channel.invokeMethod<void>('acquire');
    } on PlatformException catch (_) {
      // Not fatal — scanning works but may be throttled with screen off.
    }
  }

  static Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } on PlatformException catch (_) {
      // Ignore.
    }
  }
}
