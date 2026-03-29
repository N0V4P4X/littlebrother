import 'package:flutter/services.dart';

class LBWakeLock {
  static const _channel = MethodChannel('art.n0v4.littlebrother/wake');

  static Future<void> acquire() async {
    try {
      await _channel.invokeMethod<void>('acquire');
    } on PlatformException catch (_) {}
  }

  static Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } on PlatformException catch (_) {}
  }
}
