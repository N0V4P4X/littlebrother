import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';

class DeauthDetector {
  final _findingsController = StreamController<DeauthFinding>.broadcast();
  Stream<DeauthFinding> get findingsStream => _findingsController.stream;

  static const _deauthCountWindow = Duration(seconds: 30);
  static const _deauthThreshold = 10;
  static const _apDisappearThreshold = 0.4;
  static const _minApCount = 10;

  final Map<String, DateTime> _seenAps = {};
  final List<_ApEvent> _apEvents = [];
  int _lastApCount = 0;
  Timer? _monitorTimer;

  bool _isMonitoring = false;

  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;
    _monitorTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkForDeauthPatterns(),
    );
    debugPrint('LB_DEAUTH: Monitoring started');
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    debugPrint('LB_DEAUTH: Monitoring stopped');
  }

  void onWifiBatch(List<LBSignal> signals) {
    if (!_isMonitoring) return;
    
    final currentAps = <String, LBSignal>{};
    for (final s in signals) {
      if (s.signalType == LBSignalType.wifi) {
        currentAps[s.identifier] = s;
      }
    }

    final now = DateTime.now();
    final currentBssids = currentAps.keys.toSet();
    final previousBssids = _seenAps.keys.toSet();

    final disappeared = previousBssids.difference(currentBssids);
    final appeared = currentBssids.difference(previousBssids);

    for (final bssid in disappeared) {
      _apEvents.add(_ApEvent(
        bssid: bssid,
        eventType: _ApEventType.disappeared,
        timestamp: now,
      ));
    }

    for (final bssid in appeared) {
      _apEvents.add(_ApEvent(
        bssid: bssid,
        eventType: _ApEventType.appeared,
        timestamp: now,
      ));
    }

    _seenAps.clear();
    for (final entry in currentAps.entries) {
      _seenAps[entry.key] = entry.value.timestamp;
    }

    final eventCutoff = now.subtract(_deauthCountWindow);
    _apEvents.removeWhere((e) => e.timestamp.isBefore(eventCutoff));

    final currentCount = currentAps.length;
    if (_lastApCount > _minApCount && currentCount < _lastApCount * (1 - _apDisappearThreshold)) {
      final dropCount = _lastApCount - currentCount;
      final dropPercent = (dropCount / _lastApCount * 100).toStringAsFixed(1);
      
      debugPrint('LB_DEAUTH: AP count dropped from $_lastApCount to $currentCount ($dropPercent%)');
      
      if (dropCount >= 5) {
        final finding = DeauthFinding(
          type: DeauthFindingType.apDisappearance,
          severity: dropCount >= 15 ? LBSeverity.critical : (dropCount >= 10 ? LBSeverity.high : LBSeverity.medium),
          identifier: 'deauth_storm',
          detail: '$dropCount APs disappeared suddenly ($dropPercent% drop)',
          evidence: {
            'previous_count': _lastApCount,
            'current_count': currentCount,
            'drop_count': dropCount,
            'drop_percent': dropPercent,
            'disappeared_bssids': disappeared.toList(),
          },
        );
        _emitFinding(finding);
      }
    }

    _lastApCount = currentCount;
  }

  void _checkForDeauthPatterns() {
    if (!_isMonitoring) return;
    
    final now = DateTime.now();
    final windowStart = now.subtract(_deauthCountWindow);
    
    final recentDisappear = _apEvents
        .where((e) => e.eventType == _ApEventType.disappeared && e.timestamp.isAfter(windowStart))
        .length;
    
    if (recentDisappear >= _deauthThreshold) {
      final finding = DeauthFinding(
        type: DeauthFindingType.deauthStorm,
        severity: recentDisappear >= 30 ? LBSeverity.critical : (recentDisappear >= 20 ? LBSeverity.high : LBSeverity.medium),
        identifier: 'deauth_storm',
        detail: '$recentDisappear AP disappearances in ${_deauthCountWindow.inSeconds}s - possible deauth attack',
        evidence: {
          'event_count': recentDisappear,
          'window_seconds': _deauthCountWindow.inSeconds,
        },
      );
      _emitFinding(finding);
    }
  }

  void _emitFinding(DeauthFinding finding) {
    debugPrint('LB_DEAUTH: ${finding.type} - ${finding.detail}');
    if (!_findingsController.isClosed) {
      _findingsController.add(finding);
    }
  }

  void addTrustedNetwork(String bssid, String ssid) {
    debugPrint('LB_DEAUTH: Added trusted network: $ssid ($bssid)');
  }

  void clearTrustedNetworks() {
    debugPrint('LB_DEAUTH: Cleared trusted networks');
  }

  void dispose() {
    stopMonitoring();
    _findingsController.close();
  }
}

enum _ApEventType { appeared, disappeared }

class _ApEvent {
  final String bssid;
  final _ApEventType eventType;
  final DateTime timestamp;

  _ApEvent({
    required this.bssid,
    required this.eventType,
    required this.timestamp,
  });
}

enum DeauthFindingType {
  deauthStorm,
  apDisappearance,
  trustedNetworkDown,
}

class DeauthFinding {
  final DeauthFindingType type;
  final int severity;
  final String identifier;
  final String detail;
  final Map<String, dynamic> evidence;
  final DateTime timestamp;

  DeauthFinding({
    required this.type,
    required this.severity,
    required this.identifier,
    required this.detail,
    Map<String, dynamic>? evidence,
    DateTime? timestamp,
  })  : evidence = evidence ?? {},
        timestamp = timestamp ?? DateTime.now();

  LBThreatEvent toThreatEvent() {
    return LBThreatEvent(
      threatType: LBThreatType.deauthStorm,
      severity: severity,
      identifier: identifier,
      evidence: {
        ...evidence,
        'finding_type': type.name,
        'detail': detail,
      },
      timestamp: timestamp,
    );
  }
}
