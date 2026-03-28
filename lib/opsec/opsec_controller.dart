import 'package:flutter/services.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';

/// Controls RF kill sequences and OPSEC automation.
class OpsecController {
  static const _channel = MethodChannel(LBChannels.opsec);

  bool _airplaneModeAvailable = false;

  Future<void> init() async {
    try {
      _airplaneModeAvailable =
          await _channel.invokeMethod('canWriteSettings') as bool? ?? false;
    } on PlatformException {
      _airplaneModeAvailable = false;
    }
  }

  bool get canKillRf => _airplaneModeAvailable;

  /// Full RF kill: attempt airplane mode, fallback to Wi-Fi + BT disable.
  /// Returns description of what was accomplished.
  Future<String> killRf() async {
    final results = <String>[];

    if (_airplaneModeAvailable) {
      try {
        final ok = await _channel.invokeMethod('setAirplaneMode', {'enable': true}) as bool?;
        if (ok == true) {
          results.add('Airplane mode enabled');
          return results.join(', ');
        }
      } on PlatformException catch (e) {
        results.add('Airplane mode failed: ${e.message}');
      }
    }

    // Fallback: Wi-Fi disable
    try {
      final result = await _channel.invokeMethod('setWifiEnabled', {'enable': false}) as bool?;
      if (result == true) {
        results.add('Wi-Fi disabled');
      } else {
        results.add('Wi-Fi panel opened (user confirmation required)');
      }
    } on PlatformException {
      results.add('Wi-Fi disable unavailable');
    }

    return results.isEmpty ? 'RF kill failed — manual action required' : results.join('; ');
  }

  Future<String> restoreRf() async {
    if (_airplaneModeAvailable) {
      try {
        await _channel.invokeMethod('setAirplaneMode', {'enable': false});
        return 'Airplane mode disabled';
      } on PlatformException {/* fall through */}
    }
    return 'Manual RF restore required';
  }

  Future<void> requestWriteSettingsPermission() async {
    try {
      await _channel.invokeMethod('requestWriteSettings');
    } on PlatformException {/* user must handle */}
  }
}
