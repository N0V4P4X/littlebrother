import 'dart:async';
import 'dart:math' as math;
import 'package:wifi_scan/wifi_scan.dart';
import 'package:uuid/uuid.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/core/db/oui_lookup.dart';

class WifiScanner {
  final _uuid = const Uuid();
  Timer? _timer;
  final _controller = StreamController<List<LBSignal>>.broadcast();

  Stream<List<LBSignal>> get stream => _controller.stream;
  bool get isRunning => _timer != null;

  /// Start continuous Wi-Fi scanning. [sessionId] is the active session UUID.
  Future<void> start(String sessionId, {bool foreground = true}) async {
    if (isRunning) return;
    final interval = foreground
        ? LBScanInterval.wifiForegroundMs
        : LBScanInterval.wifiBackgroundMs;

    // Immediate first scan
    await _scan(sessionId);

    _timer = Timer.periodic(Duration(milliseconds: interval), (_) async {
      await _scan(sessionId);
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _scan(String sessionId) async {
    // Check capability
    final can = await WiFiScan.instance.canStartScan();
    if (can != CanStartScan.yes) return;

    final started = await WiFiScan.instance.startScan();
    if (!started) return;

    final results = await WiFiScan.instance.getScannedResults();
    final now = DateTime.now();
    final signals = results.map((ap) => _normalize(ap, sessionId, now)).toList();

    if (!_controller.isClosed) {
      _controller.add(signals);
    }
  }

  LBSignal _normalize(WiFiAccessPoint ap, String sessionId, DateTime now) {
    final vendor = OuiLookup.instance.resolve(ap.bssid);
    final rssi = ap.level;
    final distanceM = _estimateDistance(rssi);
    final riskScore = _computeRisk(ap);
    final band = _bandFromFrequency(ap.frequency);
    final channel = _channelFromFrequency(ap.frequency);
    final security = _parseSecurity(ap.capabilities);

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
        'frequency_mhz':    ap.frequency,
        'channel':          channel,
        'band':             band,
        'security':         security,
        'capabilities':     ap.capabilities,
        'vendor':           vendor,
        'channel_width_mhz': ap.channelWidth ?? -1,
        'ssid':             ap.ssid,
        'is_hidden':        ap.ssid.isEmpty,
        'is_randomized':    OuiLookup.instance.isRandomized(ap.bssid),
      },
      timestamp: now,
    );
  }

  /// Path-loss distance estimate.
  /// d = 10 ^ ((TxPower - RSSI) / (10 × n))
  double _estimateDistance(int rssi, {int txPower = LBPathLoss.defaultTxPowerDbm}) {
    final exp = (txPower - rssi) / (10 * LBPathLoss.nIndoor);
    return math.pow(10, exp).toDouble();
  }

  int _computeRisk(WiFiAccessPoint ap) {
    var score = 0;
    final caps = ap.capabilities.toUpperCase();
    final security = _parseSecurity(ap.capabilities);

    if (security == 'OPEN')         score += 40;
    if (security == 'WEP')          score += 35;
    if (caps.contains('TKIP') && !caps.contains('CCMP')) score += 15;
    if (ap.ssid.isEmpty)            score += 10; // hidden SSID
    if (ap.frequency < 3000 && ap.level > -50) score += 10; // 2.4GHz close proximity

    return score.clamp(0, 100);
  }

  String _parseSecurity(String caps) {
    final c = caps.toUpperCase();
    if (c.contains('WPA3'))  return 'WPA3';
    if (c.contains('WPA2'))  return 'WPA2';
    if (c.contains('WPA'))   return 'WPA';
    if (c.contains('WEP'))   return 'WEP';
    if (c.contains('[ESS]') || c.isEmpty) return 'OPEN';
    return 'UNKNOWN';
  }

  String _bandFromFrequency(int freq) {
    if (freq < 3000) return '2.4GHz';
    if (freq < 5945) return '5GHz';
    return '6GHz';
  }

  int _channelFromFrequency(int freq) {
    // 2.4 GHz
    if (freq >= 2412 && freq <= 2484) {
      if (freq == 2484) return 14;
      return (freq - 2412) ~/ 5 + 1;
    }
    // 5 GHz
    if (freq >= 5180 && freq <= 5885) {
      return (freq - 5000) ~/ 5;
    }
    // 6 GHz
    if (freq >= 5955 && freq <= 7115) {
      return (freq - 5955) ~/ 5 + 1;
    }
    return -1;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
