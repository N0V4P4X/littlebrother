import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:littlebrother/alerts/alert_engine.dart';
import 'package:littlebrother/analyzer/lb_analyzer.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/db/oui_lookup.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
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

  String? _sessionId;
  bool get isScanning => _sessionId != null;
  String? get sessionId => _sessionId;

  // Latest signal cache per identifier (for UI list binding)
  final _latestSignals = <String, LBSignal>{};
  List<LBSignal> get latestSignals => _latestSignals.values.toList();

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
    await OuiLookup.instance.init();

    _alerts  = AlertEngine(_db);
    _opsec   = OpsecController();
    _wifi    = WifiScanner();
    _ble     = BleScanner();
    _cell    = CellScanner();
    _gps     = GpsTracker();
    _analyzer = LBAnalyzer(_db);

    await _alerts.init();
    await _opsec.init();
    await _gps.start();

    // Wire OPSEC auto-trigger
    _alerts.onOpsecTrigger = () async {
      await _opsec.killRf();
    };

    // Forward threats to threat counter
    _alerts.threatStream.listen((_) {
      _threatCount++;
    });
  }

  Future<void> startScan() async {
    if (isScanning) return;
    _sessionId = _uuid.v4();
    final session = LBSession(id: _sessionId!, startedAt: DateTime.now());
    await _db.insertSession(session);

    _wifiSub = _wifi.stream.listen((signals) => _onSignals(signals));
    _bleSub  = _ble.stream.listen((signals) => _onSignals(signals));
    _cellSub = _cell.stream.listen((signals) => _onSignals(signals));

    await _wifi.start(_sessionId!);
    await _ble.start(_sessionId!);
    await _cell.start(_sessionId!);
  }

  Future<void> stopScan() async {
    if (!isScanning) return;
    await _wifi.stop();
    await _ble.stop();
    await _cell.stop();
    _wifiSub?.cancel();
    _bleSub?.cancel();
    _cellSub?.cancel();

    // Close session
    final stats = await _db.getSessionStats(_sessionId!);
    final session = LBSession(
      id: _sessionId!,
      startedAt: DateTime.now(), // placeholder — we don't store start
      endedAt: DateTime.now(),
      observationCount: stats['total'] ?? 0,
      threatCount: _threatCount,
    );
    await _db.updateSession(session);
    _sessionId = null;
  }

  Future<void> _onSignals(List<LBSignal> signals) async {
    if (_sessionId == null || signals.isEmpty) return;

    // Stamp GPS onto each signal
    final geotagged = signals.map((s) {
      if (_gps.hasFreshFix && _gps.lastPosition != null) {
        return s.copyWith(
          lat: _gps.lastPosition!.latitude,
          lon: _gps.lastPosition!.longitude,
        );
      }
      return s;
    }).toList();

    // Update latest cache
    for (final s in geotagged) {
      if (s.identifier != 'DOWNGRADE_EVENT') {
        _latestSignals[s.identifier] = s;
      }
    }

    // Update network type display
    final cell = geotagged.where((s) =>
        s.signalType == LBSignalType.cell &&
        s.metadata['is_serving'] == true).firstOrNull;
    if (cell != null) {
      final nt = cell.metadata['network_type_name'] as String?;
      if (nt != null) _currentNetworkType = nt;
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
      servingCellChangesPerMinute: _cell.servingCellChangesPerMinute(),
    );
    if (threats.isNotEmpty) {
      await _alerts.handleThreatEvents(threats);
    }

    // Broadcast to UI
    if (!_signalCtrl.isClosed) {
      _signalCtrl.add(geotagged);
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
    _cell.dispose();
    _gps.dispose();
    _alerts.dispose();
    _signalCtrl.close();
  }
}
