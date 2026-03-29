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

  // Subscription to the platform scan-results-available broadcast.
  StreamSubscription<List<WiFiAccessPoint>>? _platformSub;

  // Periodic timer that nudges startScan when the OS allows it.
  // We keep trying even when throttled so we pick up the next allowed window.
  Timer? _nudgeTimer;

  final _controller = StreamController<List<LBSignal>>.broadcast();

  Stream<List<LBSignal>> get stream => _controller.stream;
  bool get isRunning => _platformSub != null;

  /// Start Wi-Fi scanning for [sessionId].
  ///
  /// Strategy: subscribe to [onScannedResultsAvailable] which fires on every
  /// scan the platform (or any other app) completes — this works even when the
  /// device is already connected to Wi-Fi and regardless of Android's
  /// [startScan] throttle. We also nudge [startScan] periodically so fresh
  /// scans are requested when the OS allows them.
  Future<void> start(String sessionId, {bool foreground = true}) async {
    if (isRunning) return;

    // Guard: we need at least canGetScannedResults.yes to read results.
    final canGet = await WiFiScan.instance.canGetScannedResults();
    debugPrint('LB_WIFI canGetScannedResults=$canGet');
    if (canGet != CanGetScannedResults.yes) {
      debugPrint('LB_WIFI cannot get results — bailing');
      return;
    }

    // Subscribe to the platform broadcast first so we never miss a result.
    _platformSub = WiFiScan.instance.onScannedResultsAvailable.listen(
      (aps) {
        debugPrint('LB_WIFI onScannedResultsAvailable: ${aps.length} APs');
        _onResults(aps, sessionId);
      },
    );
    debugPrint('LB_WIFI subscribed to onScannedResultsAvailable');

    // Emit whatever is already cached so the UI is not blank on first open.
    final cached = await WiFiScan.instance.getScannedResults();
    debugPrint('LB_WIFI cached results on start: ${cached.length} APs');
    if (cached.isNotEmpty) _onResults(cached, sessionId);

    // Nudge startScan periodically.
    final interval = foreground
        ? LBScanInterval.wifiForegroundMs
        : LBScanInterval.wifiBackgroundMs;

    _nudgeTimer = Timer.periodic(Duration(milliseconds: interval), (_) async {
      final can = await WiFiScan.instance.canStartScan();
      debugPrint('LB_WIFI nudge canStartScan=$can');
      if (can == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        debugPrint('LB_WIFI startScan called');
      }
    });

    // Kick off an immediate scan attempt.
    final can = await WiFiScan.instance.canStartScan();
    debugPrint('LB_WIFI initial canStartScan=$can');
    if (can == CanStartScan.yes) {
      await WiFiScan.instance.startScan();
      debugPrint('LB_WIFI initial startScan called');
    }
  }

  Future<void> stop() async {
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
    await _platformSub?.cancel();
    _platformSub = null;
  }

  void _onResults(List<WiFiAccessPoint> aps, String sessionId) {
    if (aps.isEmpty || _controller.isClosed) return;
    final now = DateTime.now();
    final signals = aps.map((ap) => _normalize(ap, sessionId, now)).toList();
    _controller.add(signals);
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
        'channel_width_mhz': ap.channelWidth ?? -1,
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
  }
}
