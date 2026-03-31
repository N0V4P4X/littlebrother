import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';

class CellCapabilities {
  final bool hasPhoneStatePermission;
  final bool hasLocationPermission;
  final bool locationEnabled;
  final bool allCellInfoAvailable;
  final bool allCellInfoEmpty;
  final int androidVersion;
  final String manufacturer;
  final String model;
  final bool supportsNr;
  final String diagnosis;
  const CellCapabilities({
    required this.hasPhoneStatePermission,
    required this.hasLocationPermission,
    required this.locationEnabled,
    required this.allCellInfoAvailable,
    required this.allCellInfoEmpty,
    required this.androidVersion,
    required this.manufacturer,
    required this.model,
    required this.supportsNr,
    required this.diagnosis,
  });
  factory CellCapabilities.fromMap(Map<String, dynamic> m) => CellCapabilities(
    hasPhoneStatePermission:  m['hasPhoneStatePermission'] as bool? ?? false,
    hasLocationPermission:   m['hasLocationPermission'] as bool? ?? false,
    locationEnabled:         m['locationEnabled'] as bool? ?? false,
    allCellInfoAvailable:   m['allCellInfoAvailable'] as bool? ?? false,
    allCellInfoEmpty:       m['allCellInfoEmpty'] as bool? ?? true,
    androidVersion:         m['androidVersion'] as int? ?? 0,
    manufacturer:           m['manufacturer'] as String? ?? '',
    model:                  m['model'] as String? ?? '',
    supportsNr:             m['supportsNr'] as bool? ?? false,
    diagnosis:              m['diagnosis'] as String? ?? 'UNKNOWN',
  );
  String get diagnosisMessage {
    return switch (diagnosis) {
      'OK' => 'All systems go',
      'MISSING_PHONE_STATE_PERMISSION' => 'READ_PHONE_STATE permission denied',
      'MISSING_LOCATION_PERMISSION' => 'Location permission denied',
      'LOCATION_DISABLED' => 'Location services are disabled',
      'ALL_CELL_INFO_NOT_AVAILABLE' => 'allCellInfo API unavailable on this device',
      'ALL_CELL_INFO_EMPTY' => 'allCellInfo returned empty (possible OEM restriction)',
      _ => 'Unknown: $diagnosis',
    };
  }
  bool get isOperational => diagnosis == 'OK';
}

class CellScanner {
  static const _channel = MethodChannel(LBChannels.cell);
  final _uuid = const Uuid();
  Timer? _timer;
  final _controller = StreamController<List<LBSignal>>.broadcast();

  final _servingCellHistory = <({String cellKey, DateTime ts, int? timingAdvance})>[];
  final _tacHistory = <({String tac, DateTime ts})>[];
  final _neighborSnapshots = <({List<String> neighbors, DateTime ts})>[];

  CellCapabilities? _lastCapabilities;
  CellCapabilities? get lastCapabilities => _lastCapabilities;

  int _consecutiveEmptyCount = 0;
  int get consecutiveEmptyCount => _consecutiveEmptyCount;

  Stream<List<LBSignal>> get stream => _controller.stream;
  bool get isRunning => _timer != null;

  String? _lastNetworkType;

  Future<void> start(String sessionId) async {
    if (isRunning) return;
    await _scan(sessionId);
    _timer = Timer.periodic(
      const Duration(milliseconds: LBScanInterval.cellForegroundMs),
      (_) => _scan(sessionId),
    );
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _scan(String sessionId) async {
    try {
      try {
        final capsRaw = await _channel.invokeMethod('getCellCapabilities');
        if (capsRaw != null) {
          _lastCapabilities = CellCapabilities.fromMap(
            Map<String, dynamic>.from(capsRaw as Map<Object?, Object?>)
          );
        }
      } catch (e) {
        debugPrint('LB_CELL getCellCapabilities error: $e');
      }

      final List<dynamic> rawCells =
          await _channel.invokeMethod('getAllCellInfo') as List<dynamic>;
      final serviceStateRaw = await _channel.invokeMethod('getServiceState');
      final Map<String, dynamic> serviceState = 
          serviceStateRaw != null 
              ? Map<String, dynamic>.from(serviceStateRaw as Map<Object?, Object?>)
              : <String, dynamic>{};

      debugPrint('LB_CELL raw cells: ${rawCells.length}, networkType=${serviceState['networkTypeName']}');

      if (rawCells.isEmpty) {
        _consecutiveEmptyCount++;
        debugPrint('LB_CELL empty result (consecutive: $_consecutiveEmptyCount) — diagnosis: ${_lastCapabilities?.diagnosis ?? 'unknown'}');
      } else {
        _consecutiveEmptyCount = 0;
      }

      final now = DateTime.now();
      final networkType = serviceState['networkTypeName'] as String? ?? 'UNKNOWN';
      final signals = <LBSignal>[];

      for (final raw in rawCells) {
        try {
          final cell = Map<String, dynamic>.from(raw as Map<Object?, Object?>);
          final signal = _normalize(cell, sessionId, now, serviceState);
          if (signal != null) signals.add(signal);
        } catch (e) {
          debugPrint('LB_CELL cell parse error: $e');
        }
      }

      debugPrint('LB_CELL normalized ${signals.length} signals');

      if (_lastNetworkType != null && _lastNetworkType != networkType) {
        _injectDowngradeEvent(signals, _lastNetworkType!, networkType, sessionId, now);
      }
      _lastNetworkType = networkType;

      final serving = signals.where((s) => s.metadata['is_serving'] == true).firstOrNull;
      if (serving != null) {
        final ta = serving.metadata['timingAdvance'] as int?;
        _servingCellHistory.add((cellKey: serving.identifier, ts: now, timingAdvance: ta));
        final cutoff = now.subtract(const Duration(minutes: 2));
        _servingCellHistory.removeWhere((e) => e.ts.isBefore(cutoff));

        final tac = serving.metadata['tac']?.toString() ?? serving.metadata['lac']?.toString() ?? '';
        if (tac.isNotEmpty) {
          _tacHistory.add((tac: tac, ts: now));
          final tacCutoff = now.subtract(const Duration(minutes: 2));
          _tacHistory.removeWhere((e) => e.ts.isBefore(tacCutoff));
        }
      }

      final neighborIds = signals
          .where((s) => s.metadata['is_serving'] != true)
          .map((s) => s.identifier)
          .toList();
      if (neighborIds.isNotEmpty || serving != null) {
        _neighborSnapshots.add((neighbors: neighborIds, ts: now));
        final snapCutoff = now.subtract(const Duration(minutes: 5));
        _neighborSnapshots.removeWhere((e) => e.ts.isBefore(snapCutoff));
      }

      debugPrint('LB_CELL emitting ${signals.length} signals to stream');
      if (!_controller.isClosed) {
        _controller.add(signals);
      }
    } on PlatformException catch (e) {
      debugPrint('LB_CELL PlatformException: ${e.code} — ${e.message}');
      _consecutiveEmptyCount++;
      if (!_controller.isClosed) _controller.add([]);
    } catch (e) {
      debugPrint('LB_CELL unexpected error: $e');
    }
  }

  LBSignal? _normalize(
    Map<String, dynamic> cell,
    String sessionId,
    DateTime now,
    Map<String, dynamic> serviceState,
  ) {
    final type    = cell['type'] as String? ?? 'UNKNOWN';
    final cellKey = cell['cellKey'] as String? ?? '';
    if (cellKey.isEmpty) return null;

    final isServing = cell['isServing'] as bool? ?? false;
    final rssi = _bestRssi(cell, type);
    final displayName = _buildDisplayName(cell, serviceState, isServing);

    return LBSignal(
      id:          _uuid.v4(),
      sessionId:   sessionId,
      signalType:  isServing ? LBSignalType.cell : LBSignalType.cellNeighbor,
      identifier:  cellKey,
      displayName: displayName,
      rssi:        rssi,
      distanceM:   _estimateDistanceFromTa(cell),
      riskScore:   0,
      metadata: {
        'type':            type,
        'mcc':             cell['mcc'],
        'mnc':             cell['mnc'],
        'cell_key':        cellKey,
        'is_serving':      isServing,
        'tac':             cell['tac'] ?? cell['lac'],
        'ci':              cell['ci'] ?? cell['cid'] ?? cell['nci'],
        'pci':             cell['pci'],
        'earfcn':          cell['earfcn'] ?? cell['arfcn'] ?? cell['uarfcn'],
        'bandwidth':       cell['bandwidth'],
        'rsrp':            cell['rsrp'],
        'rsrq':            cell['rsrq'],
        'sinr':            cell['sinr'] ?? cell['rssnr'] ?? cell['ssSinr'],
        'timing_advance':  cell['timingAdvance'],
        'band':            cell['band'],
        'network_type_name': serviceState['networkTypeName'],
        'operator':        serviceState['operatorName'],
        'is_roaming':      serviceState['isRoaming'],
        'ss_rsrp':         cell['ssRsrp'],
        'ss_rsrq':         cell['ssRsrq'],
        'ss_sinr':         cell['ssSinr'],
      },
      timestamp: now,
    );
  }

  void _injectDowngradeEvent(
    List<LBSignal> signals,
    String from,
    String to,
    String sessionId,
    DateTime now,
  ) {
    signals.add(LBSignal(
      id:          _uuid.v4(),
      sessionId:   sessionId,
      signalType:  LBSignalType.cell,
      identifier:  'DOWNGRADE_EVENT',
      displayName: 'Network Downgrade: $from → $to',
      rssi:        0,
      distanceM:   0,
      riskScore:   0,
      metadata: {
        'event':    'downgrade',
        'from':     from,
        'to':       to,
        'is_gsm_downgrade': to == 'GSM',
      },
      timestamp: now,
    ));
  }

  int _bestRssi(Map<String, dynamic> cell, String type) {
    switch (type) {
      case 'LTE':  return cell['rsrp'] as int? ?? cell['rssi'] as int? ?? -100;
      case 'NR':   return cell['ssRsrp'] as int? ?? -100;
      case 'UMTS': return cell['rssi'] as int? ?? -100;
      case 'GSM':  return cell['rssi'] as int? ?? -100;
      default:     return cell['rssi'] as int? ?? -100;
    }
  }

  double _estimateDistanceFromTa(Map<String, dynamic> cell) {
    final ta = cell['timingAdvance'] as int?;
    if (ta == null || ta < 0 || ta > 1282) return -1;
    return ta * 78.12;
  }

  String _buildDisplayName(
    Map<String, dynamic> cell,
    Map<String, dynamic> serviceState,
    bool isServing,
  ) {
    final type     = cell['type'] as String? ?? '?';
    final operator = serviceState['operatorName'] as String? ?? '';
    final ci       = cell['ci'] ?? cell['cid'] ?? cell['nci'] ?? '?';
    if (isServing) {
      return operator.isNotEmpty ? '$operator ($type)' : '$type Cell $ci';
    }
    return '$type Neighbor #$ci';
  }

  int servingCellChangesPerMinute() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    final recent = _servingCellHistory
        .where((e) => e.ts.isAfter(cutoff))
        .map<String>((e) => e.cellKey)
        .toList();
    if (recent.length < 2) return 0;
    var changes = 0;
    for (var i = 1; i < recent.length; i++) {
      if (recent[i] != recent[i - 1]) changes++;
    }
    return changes;
  }

  int tacChangesPerMinute() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    final recent = _tacHistory
        .where((e) => e.ts.isAfter(cutoff))
        .map((e) => e.tac)
        .toList();
    if (recent.length < 2) return 0;
    var changes = 0;
    for (var i = 1; i < recent.length; i++) {
      if (recent[i] != recent[i - 1]) changes++;
    }
    return changes;
  }

  int neighborInstabilityScore() {
    if (_neighborSnapshots.length < 3) return 0;
    final sets = _neighborSnapshots.map((s) => s.neighbors.toSet()).toList();
    final first = sets.first;
    final identicalCount = sets.where((s) => s.difference(first).isEmpty && first.difference(s).isEmpty).length;
    if (identicalCount == sets.length && first.isNotEmpty) return 90;
    if (identicalCount == sets.length && first.isEmpty) return 70;
    var totalDiff = 0;
    for (var i = 1; i < sets.length; i++) {
      final union = sets[i].union(sets[i - 1]).length;
      if (union > 0) {
        totalDiff += sets[i].difference(sets[i - 1]).length + sets[i - 1].difference(sets[i]).length;
      }
    }
    final avgChange = totalDiff / (sets.length - 1);
    if (avgChange > 5) return 80;
    if (avgChange > 3) return 50;
    return 0;
  }

  int? get lastTimingAdvance {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(seconds: 30));
    for (var i = _servingCellHistory.length - 1; i >= 0; i--) {
      final entry = _servingCellHistory[i];
      if (entry.ts.isAfter(cutoff) && entry.timingAdvance != null) {
        return entry.timingAdvance;
      }
    }
    return null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
