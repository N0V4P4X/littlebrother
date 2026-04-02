import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:uuid/uuid.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/core/db/oui_lookup.dart';

class WifiScanner {
  final _uuid = const Uuid();

  StreamSubscription<List<WiFiAccessPoint>>? _platformSub;
  Timer? _nudgeTimer;
  DateTime? _lastResultTime;

  final _controller = StreamController<List<LBSignal>>.broadcast();
  final _throttleCtrl = StreamController<bool>.broadcast();

  Stream<List<LBSignal>> get stream => _controller.stream;
  Stream<bool> get throttledStream => _throttleCtrl.stream;
  bool get isRunning => _platformSub != null;
  bool get isThrottled => _isThrottled;

  bool _isThrottled = false;
  bool _canScan = true;

  Future<void> start(String sessionId, {bool foreground = true}) async {
    if (isRunning) return;

    final canGet = await WiFiScan.instance.canGetScannedResults();
    debugPrint('LB_WIFI canGetScannedResults=$canGet');
    if (canGet != CanGetScannedResults.yes) {
      debugPrint('LB_WIFI cannot get results — bailing');
      return;
    }

    _platformSub = WiFiScan.instance.onScannedResultsAvailable.listen(
      (aps) {
        debugPrint('LB_WIFI onScannedResultsAvailable: ${aps.length} APs');
        _onResults(aps, sessionId);
      },
      onError: (e) => debugPrint('LB_WIFI platform sub error: $e'),
      onDone: () => debugPrint('LB_WIFI platform sub done'),
    );
    debugPrint('LB_WIFI subscribed to onScannedResultsAvailable');

    final cached = await WiFiScan.instance.getScannedResults();
    debugPrint('LB_WIFI cached results on start: ${cached.length} APs');
    if (cached.isNotEmpty) _onResults(cached, sessionId);

    final interval = foreground
        ? LBScanInterval.wifiForegroundMs
        : LBScanInterval.wifiBackgroundMs;

    _nudgeTimer = Timer.periodic(Duration(milliseconds: interval), (_) {
      if (!_nudgeTimer!.isActive) return;
      _nudgeOnce(sessionId);
    });

    final can = await WiFiScan.instance.canStartScan();
    debugPrint('LB_WIFI initial canStartScan=$can');
    if (can == CanStartScan.yes) {
      await WiFiScan.instance.startScan();
      debugPrint('LB_WIFI initial startScan called');
    }
  }

  Future<void> _nudgeOnce(String sessionId) async {
    final can = await WiFiScan.instance.canStartScan();
    debugPrint('LB_WIFI nudge canStartScan=$can');
    _canScan = can == CanStartScan.yes;

    final nowThrottled = !_canScan && _lastResultTime != null;
    if (nowThrottled != _isThrottled) {
      _isThrottled = nowThrottled;
      _throttleCtrl.add(_isThrottled);
    }

    if (_canScan) {
      await WiFiScan.instance.startScan();
      debugPrint('LB_WIFI startScan called');
    }
  }

  Future<void> stop() async {
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
    _isThrottled = false;
    _lastResultTime = null;
    _canScan = true;
    await _platformSub?.cancel();
    _platformSub = null;
  }

  void _onResults(List<WiFiAccessPoint> aps, String sessionId) {
    debugPrint('LB_WIFI _onResults called with ${aps.length} APs');
    if (_controller.isClosed) {
      debugPrint('LB_WIFI controller is closed, skipping');
      return;
    }
    _lastResultTime = DateTime.now();
    if (aps.isEmpty) {
      debugPrint('LB_WIFI results empty, not emitting');
      return;
    }
    final now = DateTime.now();
    final signals = aps.map((ap) => _normalize(ap, sessionId, now)).toList();
    debugPrint('LB_WIFI emitting ${signals.length} signals to stream');
    _controller.add(signals);

    if (_isThrottled) {
      _isThrottled = false;
      _throttleCtrl.add(false);
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
        'frequency_mhz':     ap.frequency,
        'channel':           channel,
        'band':              band,
        'security':          security,
        'capabilities':      ap.capabilities,
        'vendor':            vendor,
        'channel_width_mhz': ap.channelWidth?.index ?? -1,
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

  int _computeRisk(WiFiAccessPoint ap) {
    var score = 0;
    final caps = ap.capabilities.toUpperCase();
    final security = _parseSecurity(ap.capabilities);

    if (security == 'OPEN')         score += 40;
    if (security == 'WEP')          score += 35;
    if (caps.contains('TKIP') && !caps.contains('CCMP')) score += 15;
    if (ap.ssid.isEmpty)            score += 10;
    if (ap.frequency < 3000 && ap.level > -50) score += 10;

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
    if (freq >= 2412 && freq <= 2484) {
      if (freq == 2484) return 14;
      return (freq - 2412) ~/ 5 + 1;
    }
    if (freq >= 5180 && freq <= 5885) return (freq - 5000) ~/ 5;
    if (freq >= 5955 && freq <= 7115) return (freq - 5955) ~/ 5 + 1;
    return -1;
  }

  void dispose() {
    stop();
    _controller.close();
    _throttleCtrl.close();
  }
}
