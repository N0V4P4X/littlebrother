import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:littlebrother/alerts/alert_engine.dart';
import 'package:littlebrother/analyzer/lb_analyzer.dart';
import 'package:littlebrother/analyzer/spyware_detector.dart';
import 'package:littlebrother/analyzer/deauth_detector.dart';
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
import 'package:littlebrother/modules/mqtt/mqtt_scanner.dart';
import 'package:littlebrother/modules/shell/shell_scanner.dart';
import 'package:littlebrother/modules/bt_classic/bt_classic_scanner.dart';
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
  late final ShellScanner _shell;
  late final MqttScanner  _mqtt;
  late final BtClassicScanner _btClassic;
  late final SpywareDetector _spywareDetector;
  late final DeauthDetector _deauthDetector;

  // Merge stream: all signals from all scanners
  final _signalCtrl = StreamController<List<LBSignal>>.broadcast();
  Stream<List<LBSignal>> get signalStream => _signalCtrl.stream;
  Stream<LBThreatEvent>  get threatStream => _alerts.threatStream;
  Stream<bool>           get wifiThrottleStream => _wifi.throttledStream;
  bool get isWifiThrottled => _wifi.isThrottled;

  String? _sessionId;
  DateTime? _sessionStartTime;
  // Signal queue — batches are enqueued rather than dropped when the previous
  // batch is still being processed (DB writes + analyzer can be slow).
  final _signalQueue = ListQueue<List<LBSignal>>();
  bool _drainingQueue = false;
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

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) {
      stderr.write('LB_COORD: already initialized, skipping\n');
      return;
    }
    stderr.write('LB_COORD: init start (${LBPlatform.name})\n');
    debugPrint('LB_COORD init start (${LBPlatform.name})');
    await OuiLookup.instance.init();
    stderr.write('LB_COORD: OUI loaded\n');
    debugPrint('LB_COORD OUI loaded');

    _alerts   = AlertEngine(_db);
    _opsec    = OpsecController();
    _wifi     = WifiScanner();
    _ble      = BleScanner();
    _cell     = CellScanner();
    _gps      = GpsTracker.instance;
    _analyzer = LBAnalyzer(_db);
    _spywareDetector = SpywareDetector(_db);
    _deauthDetector = DeauthDetector();
    _shell    = ShellScanner();
    // MQTT scanner disabled temporarily due to API complexity
    // _mqtt     = MqttScanner(
    //   brokerUrl: 'test.mosquitto.org', // Public test broker
    //   port: 1883,
    //   topics: ['lb/signals/#'],
    // );
    _mqtt = MqttScanner(brokerUrl: 'test.mosquitto.org');
    _btClassic = BtClassicScanner();

    try {
      await _alerts.init();
      stderr.write('LB_COORD: alerts init done\n');
      debugPrint('LB_COORD alerts init done');
      
      // Route deauth findings to alert engine
      _deauthDetector.findingsStream.listen((finding) async {
        final event = finding.toThreatEvent();
        await _alerts.handleThreatEvents([event]);
      });
    } catch (e) {
      stderr.write('LB_COORD: alerts init failed (non-fatal): $e\n');
      debugPrint('LB_COORD alerts init failed (non-fatal): $e');
    }

    if (LBPlatform.supportsRfKill) {
      await _opsec.init();
      stderr.write('LB_COORD: opsec init done\n');
      debugPrint('LB_COORD opsec init done');
      _alerts.onOpsecTrigger = () async {
        await _opsec.killRf();
      };
    } else {
      stderr.write('LB_COORD: opsec: not available on ${LBPlatform.name}\n');
      debugPrint('LB_COORD opsec: not available on ${LBPlatform.name}');
    }

    final gpsStarted = await _gps.start();
    if (gpsStarted) {
      stderr.write('LB_COORD: gps started\n');
      debugPrint('LB_COORD gps started');
    } else {
      stderr.write('LB_COORD: gps failed to start - location features disabled\n');
      debugPrint('LB_COORD gps failed to start - location features disabled');
    }

    _alerts.threatStream.listen((_) {
      _threatCount++;
      stderr.write('LB_COORD: threat detected (count: $_threatCount)\n');
    });

    stderr.write('LB_COORD: init complete\n');
    debugPrint('LB_COORD init complete');
    _initialized = true;
  }

  Future<bool> _waitForGps({int timeoutSeconds = 90}) async {
    final gps = _gps;
    final startTime = DateTime.now();
    final timeout = Duration(seconds: timeoutSeconds);
    
    // If already has fresh fix, return immediately
    if (gps.hasFreshFix) {
      return true;
    }
    
    stderr.write('LB_COORD: waiting for GPS fresh fix (max ${timeoutSeconds}s)\n');
    debugPrint('LB_COORD: waiting for GPS fresh fix');
    
    while (DateTime.now().difference(startTime) < timeout) {
      await Future.delayed(const Duration(seconds: 1));
      if (gps.hasFreshFix) {
        stderr.write('LB_COORD: GPS acquired after ${DateTime.now().difference(startTime).inSeconds}s\n');
        debugPrint('LB_COORD: GPS acquired');
        return true;
      }
    }
    
    stderr.write('LB_COORD: GPS timeout after ${timeoutSeconds}s\n');
    debugPrint('LB_COORD: GPS timeout');
    return false;
  }

  Future<void> startScan() async {
    if (isScanning) return;
    
    // Wait for GPS fresh fix (max 90 seconds)
    final gpsReady = await _waitForGps(timeoutSeconds: 90);
    if (!gpsReady) {
      stderr.write('LB_COORD: GPS not ready after 90s, starting scan anyway\n');
      debugPrint('LB_COORD: GPS not ready, scanning may have reduced position accuracy');
    } else {
      stderr.write('LB_COORD: GPS ready, starting scan\n');
      debugPrint('LB_COORD: GPS fresh fix acquired');
    }
    
    stderr.write('LB_COORD: startScan called\n');
    _wifiSub?.cancel();
    _bleSub?.cancel();
    _cellSub?.cancel();
    _threatCount = 0;
    _latestSignals.clear();
    _signalQueue.clear();
    _drainingQueue = false;
    
    // Set session ID BEFORE the try block so stopScan() can safely reference it
    // even if an error occurs during startup
    _sessionId = _uuid.v4();
    _sessionStartTime = DateTime.now();
    
    try {
      stderr.write('LB_COORD: startScan session=$_sessionId\n');
      debugPrint('LB_COORD startScan session=$_sessionId');

      stderr.write('LB_COORD: inserting session to DB\n');
      debugPrint('LB_COORD inserting session to DB');
      final session = LBSession(id: _sessionId!, startedAt: _sessionStartTime!);
      await _db.insertSession(session);
      stderr.write('LB_COORD: session inserted\n');
      debugPrint('LB_COORD session inserted');

      stderr.write('LB_COORD: subscribing to wifi stream\n');
      debugPrint('LB_COORD subscribing to wifi stream');
      _wifiSub = _wifi.stream.listen(
        (List<LBSignal> signals) {
          debugPrint('LB_COORD wifi batch: ${signals.length} signals');
          _deauthDetector.onWifiBatch(signals);
          _onSignals(signals);
        },
        onError: (e) {
          stderr.write('LB_COORD: wifi stream error: $e\n');
          debugPrint('LB_COORD wifi stream error: $e');
        },
        onDone: () {
          stderr.write('LB_COORD: wifi stream done\n');
          debugPrint('LB_COORD wifi stream done');
        }
      );

      stderr.write('LB_COORD: subscribing to ble stream\n');
      debugPrint('LB_COORD subscribing to ble stream');
      _bleSub = _ble.stream.listen(
        (List<LBSignal> signals) {
          debugPrint('LB_COORD ble batch: ${signals.length} signals');
          _onSignals(signals);
        },
        onError: (e) {
          stderr.write('LB_COORD: ble stream error: $e\n');
          debugPrint('LB_COORD ble stream error: $e');
        },
        onDone: () {
          stderr.write('LB_COORD: ble stream done\n');
          debugPrint('LB_COORD ble stream done');
        }
      );

      stderr.write('LB_COORD: starting wifi scanner\n');
      debugPrint('LB_COORD starting wifi scanner');
      await _wifi.start(_sessionId!);
      stderr.write('LB_COORD: wifi scanner started, isRunning=${_wifi.isRunning}\n');
      debugPrint('LB_COORD wifi scanner started, isRunning=${_wifi.isRunning}');

      // Start deauth monitoring after WiFi starts
      _deauthDetector.startMonitoring();

      stderr.write('LB_COORD: starting ble scanner\n');
      debugPrint('LB_COORD starting ble scanner');
      await _ble.start(_sessionId!);
      stderr.write('LB_COORD: ble scanner started, isRunning=${_ble.isRunning}\n');
      debugPrint('LB_COORD ble scanner started, isRunning=${_ble.isRunning}');

      // Start passive spyware monitoring
      _spywareDetector.startPassiveMonitoring();

      if (LBPlatform.supportsCellScanning) {
        stderr.write('LB_COORD: starting cell scanner\n');
        debugPrint('LB_COORD starting cell scanner');
        _cellSub = _cell.stream.listen(
          (List<LBSignal> signals) {
            debugPrint('LB_COORD cell batch: ${signals.length} signals');
            _onSignals(signals);
          },
          onError: (e) {
            stderr.write('LB_COORD: cell stream error: $e\n');
            debugPrint('LB_COORD: cell stream error: $e');
          },
          onDone: () {
            stderr.write('LB_COORD: cell stream done\n');
            debugPrint('LB_COORD cell stream done');
          }
        );
        await _cell.start(_sessionId!);
        stderr.write('LB_COORD: cell scanner started, isRunning=${_cell.isRunning}\n');
        debugPrint('LB_COORD cell scanner started, isRunning=${_cell.isRunning}');
      } else {
        stderr.write('LB_COORD: cell scanner: not available on ${LBPlatform.name}\n');
        debugPrint('LB_COORD cell scanner: not available on ${LBPlatform.name}');
      }

      // Start Shell Scanner
      stderr.write('LB_COORD: starting shell scanner\n');
      await _shell.start(_sessionId!);
      stderr.write('LB_COORD: shell scanner started\n');

      // Start Bluetooth Classic Scanner (Linux only)
      if (Platform.isLinux) {
        stderr.write('LB_COORD: starting Bluetooth Classic scanner\n');
        await _btClassic.start(_sessionId!);
        stderr.write('LB_COORD: Bluetooth Classic scanner started\n');
      } else {
        stderr.write('LB_COORD: Bluetooth Classic scanner: not available on ${LBPlatform.name}\n');
        debugPrint('LB_COORD Bluetooth Classic scanner: not available on ${LBPlatform.name}');
      }

      if (LBPlatform.supportsWakeLock) {
        await LBWakeLock.acquire();
        stderr.write('LB_COORD: wake lock acquired\n');
        debugPrint('LB_COORD wake lock acquired');
      }
      
      stderr.write('LB_COORD: startScan completed successfully\n');
    } catch (e, st) {
      stderr.write('LB_COORD: startScan ERROR: $e\n$st\n');
      debugPrint('LB_COORD startScan ERROR: $e\n$st');
      // Rollback: clear session so stopScan won't try to update a partial session
      _sessionId = null;
      _sessionStartTime = null;
      _wifiSub?.cancel();
      _bleSub?.cancel();
      _cellSub?.cancel();
      rethrow;
    }
  }

  Future<void> stopScan() async {
    if (!isScanning) return;
    stderr.write('LB_COORD: stopScan called\n');

    stderr.write('LB_COORD: stopping wifi scanner\n');
    await _wifi.stop();
    stderr.write('LB_COORD: stopping ble scanner\n');
    await _ble.stop();
    if (LBPlatform.supportsCellScanning) {
      stderr.write('LB_COORD: stopping cell scanner\n');
      await _cell.stop();
    }
    
    // Stop Shell Scanner
    stderr.write('LB_COORD: stopping shell scanner\n');
    await _shell.stop();
    
    // Stop MQTT Scanner (if enabled)
    // stderr.write('LB_COORD: stopping MQTT scanner\n');
    // await _mqtt.stop();
    
    // Stop Bluetooth Classic Scanner (Linux only)
    if (Platform.isLinux) {
      stderr.write('LB_COORD: stopping Bluetooth Classic scanner\n');
      await _btClassic.stop();
    }

    // Stop passive spyware monitoring
    _spywareDetector.stopPassiveMonitoring();
    _deauthDetector.stopMonitoring();
    
    if (LBPlatform.supportsWakeLock) {
      await LBWakeLock.release();
      stderr.write('LB_COORD: wake lock released\n');
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
    _signalQueue.clear(); // discard any queued batches from the ended session
    stderr.write('LB_COORD: scan stopped\n');
    debugPrint('LB_COORD scan stopped');
  }


  /// Called by every scanner stream listener.  Enqueues the batch and starts
  /// the drain loop if it is not already running.  No batch is ever dropped —
  /// if processing is in progress the batch simply waits its turn.
  void _onSignals(List<LBSignal> signals) {
    if (_sessionId == null || signals.isEmpty) return;
    _signalQueue.add(signals);
    _drainSignalQueue();
  }

  Future<void> _drainSignalQueue() async {
    if (_drainingQueue) return;
    _drainingQueue = true;
    try {
      while (_signalQueue.isNotEmpty) {
        final batch = _signalQueue.removeFirst();
        final sessionAtStart = _sessionId;
        if (sessionAtStart == null) {
          _signalQueue.clear();
          break;
        }
        await _processBatch(batch, sessionAtStart);
      }
    } finally {
      _drainingQueue = false;
    }
  }

  Future<void> _processBatch(List<LBSignal> signals, String sessionId) async {
    try {
      debugPrint('LB_COORD _onSignals processing ${signals.length} signals');

      // Stamp GPS onto each signal
      final geotagged = signals.map((s) {
        if (_gps.hasFreshFix && _gps.lastPosition != null) {
          final pos = _gps.lastPosition!;
          final stamped = s.copyWith(
            lat: pos.latitude,
            lon: pos.longitude,
          );
          // Store GPS accuracy for deduplication logic
          stamped.metadata['gps_accuracy'] = pos.accuracy;
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
      stderr.write('LB_COORD: persisted ${geotagged.length} signals to DB\n');

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

      // Update known devices (skip downgrade events)
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
    } catch (e, st) {
      stderr.write('LB_COORD: _processBatch error: $e\n$st\n');
      debugPrint('LB_COORD _processBatch error: $e\n$st');
    }
  }
  
  void setOpsecAutoEnabled(bool enabled) {
    _alerts.opsecAutoEnabled = enabled;
  }
  
  OpsecController get opsec => _opsec;
  
  SpywareDetector get spywareDetector => _spywareDetector;
  
  DeauthDetector get deauthDetector => _deauthDetector;
  
  void dispose() {
    stopScan();
    _wifi.dispose();
    _ble.dispose();
    if (LBPlatform.supportsCellScanning) {
      _cell.dispose();
    }
    _gps.dispose();
    _alerts.dispose();
    _shell.dispose();
    _mqtt.dispose();
    if (Platform.isLinux) {
      _btClassic.dispose();
    }
    _spywareDetector.dispose();
    _deauthDetector.dispose();
    _signalCtrl.close();
  }
}