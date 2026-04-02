import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/core/db/oui_lookup.dart';

class BleScanner {
  final _uuid = const Uuid();
  StreamSubscription<List<ScanResult>>? _sub;
  final _controller = StreamController<List<LBSignal>>.broadcast();
  static const _maxTrackedDevices = 1000;
  static const _entryMaxAge = Duration(minutes: 10);

  // Track last-seen timestamps per MAC for interval estimation
  final _lastSeen = <String, DateTime>{};
  // Track advertising intervals per MAC (rolling average)
  final _advIntervals = <String, List<int>>{};

  void _cleanupStaleEntries() {
    final now = DateTime.now();
    _lastSeen.removeWhere((_, ts) => now.difference(ts) > _entryMaxAge);
    if (_lastSeen.length > _maxTrackedDevices) {
      final oldest = _lastSeen.keys.take(_lastSeen.length - _maxTrackedDevices);
      for (final key in oldest) {
        _lastSeen.remove(key);
        _advIntervals.remove(key);
      }
    }
  }

  Stream<List<LBSignal>> get stream => _controller.stream;
  bool get isRunning => _sub != null;

  Future<void> start(String sessionId) async {
    if (isRunning) return;

    final adapterState = await FlutterBluePlus.adapterState.first;
    debugPrint('LB_BLE adapterState=$adapterState');
    if (adapterState != BluetoothAdapterState.on) {
      debugPrint('LB_BLE adapter not on — bailing');
      return;
    }

    debugPrint('LB_BLE calling startScan');
    await FlutterBluePlus.startScan(
      timeout: const Duration(days: 365),
      continuousUpdates: false,
      removeIfGone: const Duration(seconds: 30),
    );
    debugPrint('LB_BLE startScan returned');

    _sub = FlutterBluePlus.scanResults.listen((results) {
      debugPrint('LB_BLE scanResults batch: ${results.length} devices');
      _cleanupStaleEntries();
      final now = DateTime.now();
      final signals = results
          .map((r) => _normalize(r, sessionId, now))
          .whereType<LBSignal>()
          .toList();
      debugPrint('LB_BLE emitting ${signals.length} signals to stream');
      if (!_controller.isClosed) {
        _controller.add(signals);
      }
    }, onError: (e) => debugPrint('LB_BLE scanResults error: $e'), onDone: () {
      debugPrint('LB_BLE scanResults stream done');
    });
    debugPrint('LB_BLE subscribed to scanResults');
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await FlutterBluePlus.stopScan();
    _lastSeen.clear();
    _advIntervals.clear();
  }

  LBSignal? _normalize(ScanResult result, String sessionId, DateTime now) {
    final mac = result.device.remoteId.str;
    final rssi = result.rssi;
    if (rssi > 20 || rssi < -127) return null;

    // Advertising interval estimation
    int? intervalMs;
    if (_lastSeen.containsKey(mac)) {
      final delta = now.difference(_lastSeen[mac]!).inMilliseconds;
      if (delta > 0 && delta < 10000) {
        final intervals = _advIntervals.putIfAbsent(mac, () => []);
        intervals.add(delta);
        if (intervals.length > 10) intervals.removeAt(0);
        if (intervals.length > 1) {
          intervalMs = intervals.reduce((a, b) => a + b) ~/ intervals.length;
        } else if (intervals.isNotEmpty) {
          intervalMs = intervals.first;
        }
      }
    }
    _lastSeen[mac] = now;

    final adv = result.advertisementData;
    final manufacturerData = adv.manufacturerData; // Map<int, List<int>>
    final mfgId    = manufacturerData.keys.firstOrNull;
    final mfgBytes = mfgId != null ? manufacturerData[mfgId] : null;
    final mfgHex   = mfgBytes != null
        ? mfgBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()
        : '';

    final vendor = OuiLookup.instance.resolve(mac);
    final isRandomized = OuiLookup.instance.isRandomized(mac);
    final trackerType = _identifyTracker(mfgId, mfgHex, adv.serviceUuids);
    final distanceM = _estimateDistance(rssi, adv.txPowerLevel);

    var riskScore = 0;
    if (trackerType != null) riskScore += 60;
    if (isRandomized && intervalMs != null && intervalMs < LBThresholds.bleAggressiveIntervalMs) {
      riskScore += 20;
    }
    if (vendor.isEmpty && adv.serviceUuids.isEmpty) riskScore += 15;
    riskScore = riskScore.clamp(0, 100);

    return LBSignal(
      id:          _uuid.v4(),
      sessionId:   sessionId,
      signalType:  LBSignalType.ble,
      identifier:  mac,
      displayName: adv.advName.isNotEmpty ? adv.advName : (vendor.isNotEmpty ? vendor : mac),
      rssi:        rssi,
      distanceM:   distanceM,
      riskScore:   riskScore,
      metadata: {
        'manufacturer_id':         mfgId,
        'manufacturer_data':       mfgHex,
        'vendor':                  vendor,
        'service_uuids':           adv.serviceUuids.map((u) => u.toString()).toList(),
        'connectable':             adv.connectable,
        'advertising_interval_ms': intervalMs,
        'is_randomized_mac':       isRandomized,
        'tracker_type':            trackerType,
        'tx_power':                adv.txPowerLevel,
        'adv_name':                adv.advName,
      },
      timestamp: now,
    );
  }

  /// Returns tracker type string if known signature matches, else null.
  String? _identifyTracker(int? mfgId, String mfgHex, List<Guid> serviceUuids) {
    // Apple AirTag: mfgId=0x004C, byte[0]=0x12, length pattern
    if (mfgId == 0x004C && mfgHex.startsWith('12')) return 'AirTag';

    // Tile: service UUID FEEDxxxx
    if (serviceUuids.any((u) => u.toString().toUpperCase().startsWith('FEED'))) return 'Tile';

    // Samsung SmartTag: mfgId=0x0075
    if (mfgId == 0x0075) return 'SmartTag';

    // Chipolo: service UUID FE6F
    if (serviceUuids.any((u) => u.toString().toUpperCase().contains('FE6F'))) return 'Chipolo';

    // TrackR / generic: mfgId=0x0157
    if (mfgId == 0x0157) return 'TrackR';

    return null;
  }

  double _estimateDistance(int rssi, int? txPower) {
    final tx = txPower ?? LBPathLoss.defaultTxPowerDbm;
    final exp = (tx - rssi) / (10 * LBPathLoss.nIndoor);
    return math.pow(10, exp).toDouble();
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
