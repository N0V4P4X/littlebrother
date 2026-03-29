import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';

class CellScanner {
  static const _channel = MethodChannel(LBChannels.cell);
  final _uuid = const Uuid();
  Timer? _timer;
  final _controller = StreamController<List<LBSignal>>.broadcast();

  // Track serving cell history for instability detection
  final _servingCellHistory = <({String cellKey, DateTime ts})>[];

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
      final List<dynamic> rawCells =
          await _channel.invokeMethod('getAllCellInfo') as List<dynamic>;
      final Map<String, dynamic> serviceState =
          await _channel.invokeMethod('getServiceState') as Map<String, dynamic>;

      debugPrint('LB_CELL raw cells: ${rawCells.length}, networkType=${serviceState['networkTypeName']}');

      final now = DateTime.now();
      final networkType = serviceState['networkTypeName'] as String? ?? 'UNKNOWN';
      final signals = <LBSignal>[];

      for (final raw in rawCells) {
        final cell = Map<String, dynamic>.from(raw as Map<Object?, Object?>);
        final signal = _normalize(cell, sessionId, now, serviceState);
        if (signal != null) signals.add(signal);
      }

      debugPrint('LB_CELL normalized ${signals.length} signals');

      if (_lastNetworkType != null && _lastNetworkType != networkType) {
        _injectDowngradeEvent(signals, _lastNetworkType!, networkType, sessionId, now);
      }
      _lastNetworkType = networkType;

      final serving = signals.where((s) => s.metadata['is_serving'] == true).firstOrNull;
      if (serving != null) {
        _servingCellHistory.add((cellKey: serving.identifier, ts: now));
        final cutoff = now.subtract(const Duration(minutes: 2));
        _servingCellHistory.removeWhere((e) => e.ts.isBefore(cutoff));
      }

      debugPrint('LB_CELL emitting ${signals.length} signals to stream');
      if (!_controller.isClosed) {
        _controller.add(signals);
      }
    } on PlatformException catch (e) {
      debugPrint('LB_CELL PlatformException: ${e.code} — ${e.message}');
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
      riskScore:   0, // set by analyzer
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
        // NR-specific
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
    // A special synthetic signal to alert the analyzer of a network type change.
    // Type: 'cell', identifier: 'DOWNGRADE', riskScore=0 (analyzer scores it).
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
    // Timing Advance: each unit ≈ 78.12 meters (LTE TA) / 550m (GSM TA)
    final ta = cell['timingAdvance'] as int?;
    if (ta == null || ta < 0 || ta > 1282) return -1;
    return ta * 78.12; // LTE approximation
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

  /// How many times has the serving cell changed in the last 60 seconds?
  int servingCellChangesPerMinute() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    final recent = _servingCellHistory
        .where((e) => e.ts.isAfter(cutoff))
        .map((e) => e.cellKey)
        .toList();
    if (recent.length < 2) return 0;
    var changes = 0;
    for (var i = 1; i < recent.length; i++) {
      if (recent[i] != recent[i - 1]) changes++;
    }
    return changes;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
