import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/core/db/oui_lookup.dart';

class WifiScanner {
  final _uuid = const Uuid();
  Timer? _timer;
  DateTime? _lastResultTime;

  final _controller = StreamController<List<LBSignal>>.broadcast();
  final _throttleCtrl = StreamController<bool>.broadcast();

  Stream<List<LBSignal>> get stream => _controller.stream;
  Stream<bool> get throttledStream => _throttleCtrl.stream;
  bool get isRunning => _timer != null;
  bool get isThrottled => false;

  Future<void> start(String sessionId, {bool foreground = true}) async {
    if (isRunning) return;
    await _scan(sessionId);
    final interval = foreground
        ? LBScanInterval.wifiForegroundMs
        : LBScanInterval.wifiBackgroundMs;
    _timer = Timer.periodic(Duration(milliseconds: interval), (_) => _scan(sessionId));
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _scan(String sessionId) async {
    try {
      final result = await Process.run('nmcli', ['-t', '-f', 'SSID,BSSID,SIGNAL,CHAN,FREQ,SECURITY', 'device', 'wifi', 'list']);
      if (result.exitCode != 0) {
        debugPrint('LB_WIFI nmcli failed: ${result.stderr}');
        return;
      }
      final lines = (result.stdout as String).split('\n').where((l) => l.isNotEmpty).toList();
      debugPrint('LB_WIFI nmcli: ${lines.length} networks');
      if (lines.isEmpty) return;
      final now = DateTime.now();
      final signals = <LBSignal>[];
      for (final line in lines) {
        final parts = line.split(':');
        if (parts.length < 6) continue;
        final ssid = parts[0];
        final bssid = parts[1];
        final signal = int.tryParse(parts[2]) ?? -100;
        final channel = int.tryParse(parts[3]) ?? -1;
        final freq = _channelToFreq(channel);
        final security = parts.sublist(5).join(':');
        if (bssid.isEmpty || bssid == '--') continue;
        final ap = _NmcliAccessPoint(ssid: ssid, bssid: bssid, signal: signal, channel: channel, freq: freq, security: security);
        signals.add(_normalize(ap, sessionId, now));
      }
      if (!_controller.isClosed) _controller.add(signals);
    } catch (e) {
      debugPrint('LB_WIFI scan error: $e');
    }
  }

  int _channelToFreq(int channel) {
    if (channel >= 1 && channel <= 13) return 2407 + channel * 5;
    if (channel == 14) return 2484;
    if (channel >= 36 && channel <= 64) return 5000 + channel * 5;
    if (channel >= 100 && channel <= 144) return 5000 + channel * 5;
    if (channel >= 149 && channel <= 165) return 5000 + channel * 5;
    return 0;
  }

  LBSignal _normalize(_NmcliAccessPoint ap, String sessionId, DateTime now) {
    final vendor = OuiLookup.instance.resolve(ap.bssid);
    final rssi = ap.signal;
    final distanceM = _estimateDistance(rssi);
    final riskScore = _computeRisk(ap);
    final band = _bandFromChannel(ap.channel);
    final security = _parseSecurity(ap.security);

    return LBSignal(
      id:          _uuid.v4(),
      sessionId:   sessionId,
      signalType:  LBSignalType.wifi,
      identifier:  ap.bssid,
      displayName: ap.ssid.isEmpty ? '[hidden]' : ap.ssid,
      rssi:        rssi,
      distanceM:   distanceM,
      riskScore:   riskScore,
      metadata: {
        'frequency_mhz':     ap.freq,
        'channel':           ap.channel,
        'band':              band,
        'security':          security,
        'capabilities':      ap.security,
        'vendor':            vendor,
        'channel_width_mhz': -1,
        'ssid':              ap.ssid,
        'is_hidden':         ap.ssid.isEmpty,
        'is_randomized':     OuiLookup.instance.isRandomized(ap.bssid),
      },
      timestamp: now,
    );
  }

  double _estimateDistance(int rssi, {int txPower = LBPathLoss.defaultTxPowerDbm}) {
    final exp = (txPower - rssi) / (10 * LBPathLoss.nIndoor);
    return math.pow(10, exp).toDouble();
  }

  int _computeRisk(_NmcliAccessPoint ap) {
    var score = 0;
    final security = _parseSecurity(ap.security);
    if (security == 'OPEN') score += 40;
    if (security == 'WEP') score += 35;
    if (ap.ssid.isEmpty) score += 10;
    return score.clamp(0, 100);
  }

  String _parseSecurity(String security) {
    final s = security.toUpperCase();
    if (s.contains('WPA3')) return 'WPA3';
    if (s.contains('WPA2')) return 'WPA2';
    if (s.contains('WPA')) return 'WPA';
    if (s.contains('WEP')) return 'WEP';
    if (s.isEmpty || s == '--') return 'OPEN';
    return 'UNKNOWN';
  }

  String _bandFromChannel(int channel) {
    if (channel >= 1 && channel <= 13) return '2.4GHz';
    if (channel >= 36) return '5GHz';
    return 'UNKNOWN';
  }

  void dispose() {
    stop();
    _controller.close();
    _throttleCtrl.close();
  }
}

class _NmcliAccessPoint {
  final String ssid;
  final String bssid;
  final int signal;
  final int channel;
  final int freq;
  final String security;
  _NmcliAccessPoint({
    required this.ssid,
    required this.bssid,
    required this.signal,
    required this.channel,
    required this.freq,
    required this.security,
  });
}
