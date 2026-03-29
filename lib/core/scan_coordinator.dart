import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:littlebrother/alerts/alert_engine.dart';
import 'package:littlebrother/analyzer/lb_analyzer.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/db/oui_lookup.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/core/platform/platform_info.dart';
import 'package:littlebrother/core/wake_lock.dart';
import 'package:littlebrother/modules/ble/ble_scanner.dart';
import 'package:littlebrother/modules/cell/cell_scanner.dart';
import 'package:littlebrother/modules/gps/gps_tracker.dart';
import 'package:littlebrother/modules/wifi/wifi_scanner.dart';
import 'package:littlebrother/opsec/opsec_controller.dart';

/// Central orchestrator: manages scanner lifecycle, feeds analyzer,
/// persists observations, routes threats to alert engine.
class ScanCoordinator {
  final _uuid  = const Uuid();
  final _db    = LBDatabase.instance;

  late final WifiScanner  _wifi;
  late final BleScanner   _ble;
  late final CellScanner  _cell;
  late final GpsTracker   _gps;
  late final LBAnalyzer   _analyzer;
  late final AlertEngine  _alerts;
  late final OpsecController _opsec;

  // Merge stream: all signals from all scanners
  final _signalCtrl = StreamController<List<LBSignal>>.broadcast();
  Stream<List<LBSignal>> get signalStream => _signalCtrl.stream;
  Stream<LBThreatEvent>  get threatStream => _alerts.threatStream;
  Stream<bool>           get wifiThrottleStream => _wifi.throttledStream;
  bool get isWifiThrottled => _wifi.isThrottled;

  String? _sessionId;
  DateTime? _sessionStartTime;
  bool _processingSignals = false;
  bool get isScanning => _sessionId != null;
  String? get sessionId => _sessionId;

  static const _maxSignalsCache = 5000;
  final _latestSignals = <String, LBSignal>{};
  List<LBSignal> get latestSignals => _latestSignals.values.toList();

  void _pruneSignalsCache() {
    if (_latestSignals.length > _maxSignalsCache) {
      final toRemove = _latestSignals.keys
          .take(_latestSignals.length - _maxSignalsCache)
          .toList();
      for (final key in toRemove) {
        _latestSignals.remove(key);
      }
    }
  }

  // Live counters
  int get wifiCount  => _latestSignals.values.where((s) => s.signalType == LBSignalType.wifi).length;
  int get bleCount   => _latestSignals.values.where((s) => s.signalType == LBSignalType.ble).length;
  int get cellCount  => _latestSignals.values.where((s) => s.signalType == LBSignalType.cell).length;
  int _threatCount   = 0;
  int get threatCount => _threatCount;

  String _currentNetworkType = '---';
  String get currentNetworkType => _currentNetworkType;

  StreamSubscription<List<LBSignal>>? _wifiSub;
  StreamSubscription<List<LBSignal>>? _bleSub;
  StreamSubscription<List<LBSignal>>? _cellSub;

  Future<void> init() async {
    debugPrint('LB_COORD init start (${LBPlatform.name})');
    await OuiLookup.instance.init();
    debugPrint('LB_COORD OUI loaded');

    _alerts   = AlertEngine(_db);
    _opsec    = OpsecController();
    _wifi     = WifiScanner();
    _ble      = BleScanner();
    _cell     = CellScanner();
    _gps      = GpsTracker();
    _analyzer = LBAnalyzer(_db);

    try {
      await _alerts.init();
      debugPrint('LB_COORD alerts init done');
    } catch (e) {
      debugPrint('LB_COORD alerts init failed (non-fatal): $e');
    }

    if (LBPlatform.supportsRfKill) {
      await _opsec.init();
      debugPrint('LB_COORD opsec init done');
      _alerts.onOpsecTrigger = () async {
        await _opsec.killRf();
      };
    } else {
      debugPrint('LB_COORD opsec: not available on ${LBPlatform.name}');
    }

    final gpsStarted = await _gps.start();
    if (gpsStarted) {
      debugPrint('LB_COORD gps started');
    } else {
      debugPrint('LB_COORD gps failed to start - location features disabled');
    }

    _alerts.threatStream.listen((_) {
      _threatCount++;
    });

    debugPrint('LB_COORD init complete');
  }

  Future<void> startScan() async {
    if (isScanning) return;
    
    _wifiSub?.cancel();
    _bleSub?.cancel();
    _cellSub?.cancel();
    _threatCount = 0;
    _latestSignals.clear();
    
    try {
      _sessionId = _uuid.v4();
      _sessionStartTime = DateTime.now();
      debugPrint('LB_COORD startScan session=$_sessionId');

      debugPrint('LB_COORD inserting session to DB');
      final session = LBSession(id: _sessionId!, startedAt: _sessionStartTime!);
      await _db.insertSession(session);
      debugPrint('LB_COORD session inserted');

      debugPrint('LB_COORD subscribing to wifi stream');
      _wifiSub = _wifi.stream.listen((signals) {
        debugPrint('LB_COORD wifi batch: ${signals.length} signals');
        _onSignals(signals);
      }, onError: (e) => debugPrint('LB_COORD wifi stream error: $e'), onDone: () {
        debugPrint('LB_COORD wifi stream done');
      });

      debugPrint('LB_COORD subscribing to ble stream');
      _bleSub = _ble.stream.listen((signals) {
        debugPrint('LB_COORD ble batch: ${signals.length} signals');
        _onSignals(signals);
      }, onError: (e) => debugPrint('LB_COORD ble stream error: $e'), onDone: () {
        debugPrint('LB_COORD ble stream done');
      });

      debugPrint('LB_COORD starting wifi scanner');
      await _wifi.start(_sessionId!);
      debugPrint('LB_COORD wifi scanner started, isRunning=${_wifi.isRunning}');

      debugPrint('LB_COORD starting ble scanner');
      await _ble.start(_sessionId!);
      debugPrint('LB_COORD ble scanner started, isRunning=${_ble.isRunning}');

      if (LBPlatform.supportsCellScanning) {
        debugPrint('LB_COORD starting cell scanner');
        _cellSub = _cell.stream.listen((signals) {
          debugPrint('LB_COORD cell batch: ${signals.length} signals');
          _onSignals(signals);
        }, onError: (e) => debugPrint('LB_COORD cell stream error: $e'), onDone: () {
          debugPrint('LB_COORD cell stream done');
        });
        await _cell.start(_sessionId!);
        debugPrint('LB_COORD cell scanner started, isRunning=${_cell.isRunning}');
      } else {
        debugPrint('LB_COORD cell scanner: not available on ${LBPlatform.name}');
      }

      if (LBPlatform.supportsWakeLock) {
        await LBWakeLock.acquire();
        debugPrint('LB_COORD wake lock acquired');
      }
    } catch (e, st) {
      debugPrint('LB_COORD startScan ERROR: $e\n$st');
    }
  }

  Future<void> stopScan() async {
    if (!isScanning) return;
    await _wifi.stop();
    await _ble.stop();
    if (LBPlatform.supportsCellScanning) {
      await _cell.stop();
    }
    if (LBPlatform.supportsWakeLock) {
      await LBWakeLock.release();
    }
    _wifiSub?.cancel();
    _bleSub?.cancel();
    _cellSub?.cancel();

    final stats = await _db.getSessionStats(_sessionId!);
    final session = LBSession(
      id: _sessionId!,
      startedAt: _sessionStartTime ?? DateTime.now(),
      endedAt: DateTime.now(),
      observationCount: stats['total'] ?? 0,
      threatCount: _threatCount,
    );
    await _db.updateSession(session);
    _sessionId = null;
    _sessionStartTime = null;
    _threatCount = 0;
    debugPrint('LB_COORD scan stopped');
  }

  Future<void> _onSignals(List<LBSignal> signals) async {
    if (_processingSignals) {
      debugPrint('LB_COORD _onSignals: already processing, skipping batch');
      return;
    }
    if (_sessionId == null) {
      debugPrint('LB_COORD _onSignals: no session, skipping');
      return;
    }
    if (signals.isEmpty) {
      debugPrint('LB_COORD _onSignals: empty batch, skipping');
      return;
    }
    
    _processingSignals = true;
    
    try {
      debugPrint('LB_COORD _onSignals processing ${signals.length} signals');

      // Stamp GPS onto each signal
      final geotagged = signals.map((s) {
        if (_gps.hasFreshFix && _gps.lastPosition != null) {
          final stamped = s.copyWith(
            lat: _gps.lastPosition!.latitude,
            lon: _gps.lastPosition!.longitude,
          );
          if (_gps.currentGeohash != null) {
            stamped.metadata['geohash'] = _gps.currentGeohash!;
          }
          return stamped;
        }
        return s;
      }).toList();

      // Update latest cache
      for (final s in geotagged) {
      if (s.identifier != 'DOWNGRADE_EVENT') {
        _latestSignals[s.identifier] = s;
      }
    }
    _pruneSignalsCache();

    // Update network type display
    final cell = geotagged.where((s) =>
        s.signalType == LBSignalType.cell &&
        s.metadata['is_serving'] == true).firstOrNull;
    if (cell != null) {
      final nt = cell.metadata['network_type_name'] as String?;
      if (nt != null) _currentNetworkType = nt;
    } else {
      _currentNetworkType = '---';
    }

    // Persist batch
    await _db.insertObservationBatch(geotagged);

    // Update cell baselines
    for (final s in geotagged) {
      if ((s.signalType == LBSignalType.cell || s.signalType == LBSignalType.cellNeighbor) &&
          s.identifier != 'DOWNGRADE_EVENT' &&
          _gps.currentGeohash != null) {
        await _db.upsertCellBaseline(
          geohash:     _gps.currentGeohash!,
          cellKey:     s.identifier,
          networkType: s.metadata['type'] as String? ?? 'UNKNOWN',
          rssi:        s.rssi,
        );
      }
    }

    // Update known devices
    for (final s in geotagged) {
      if (s.identifier != 'DOWNGRADE_EVENT') {
        final vendor = s.metadata['vendor'] as String? ?? '';
        await _db.upsertKnownDevice(s, vendor);
      }
    }

    // Run analyzer
    final threats = await _analyzer.analyze(
      geotagged,
      geohash: _gps.currentGeohash,
      servingCellChangesPerMinute: LBPlatform.supportsCellScanning
          ? _cell.servingCellChangesPerMinute() : 0,
      tacChangesPerMinute: LBPlatform.supportsCellScanning
          ? _cell.tacChangesPerMinute() : 0,
      neighborInstabilityScore: LBPlatform.supportsCellScanning
          ? _cell.neighborInstabilityScore() : 0,
    );
    if (threats.isNotEmpty) {
      await _alerts.handleThreatEvents(threats);
    }

    // Broadcast to UI
    if (!_signalCtrl.isClosed) {
      _signalCtrl.add(geotagged);
    }
    } finally {
      _processingSignals = false;
    }
  }

  void setOpsecAutoEnabled(bool enabled) {
    _alerts.opsecAutoEnabled = enabled;
  }

  OpsecController get opsec => _opsec;

  void dispose() {
    stopScan();
    _wifi.dispose();
    _ble.dispose();
    if (LBPlatform.supportsCellScanning) {
      _cell.dispose();
    }
    _gps.dispose();
    _alerts.dispose();
    _signalCtrl.close();
  }
}
