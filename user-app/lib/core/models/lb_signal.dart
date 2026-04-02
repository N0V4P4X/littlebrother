import 'dart:convert';
import 'package:littlebrother/core/constants/lb_constants.dart';

/// Unified signal model — all scanner types normalize into this.
class LBSignal {
  final String id;           // UUID
  final String sessionId;
  final String signalType;   // LBSignalType.*
  final String identifier;   // BSSID / MAC / cellKey
  final String displayName;  // SSID / device name / carrier
  final int rssi;            // dBm
  final double distanceM;    // estimated meters
  final int riskScore;       // 0–100
  final double? lat;
  final double? lon;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;
  final int threatFlag;      // LBThreatFlag.*

  const LBSignal({
    required this.id,
    required this.sessionId,
    required this.signalType,
    required this.identifier,
    required this.displayName,
    required this.rssi,
    required this.distanceM,
    required this.riskScore,
    this.lat,
    this.lon,
    required this.metadata,
    required this.timestamp,
    this.threatFlag = LBThreatFlag.clean,
  });

  factory LBSignal.fromMap(Map<String, dynamic> m) => LBSignal(
    id:          m['id'] as String? ?? '',
    sessionId:   m['session_id'] as String? ?? '',
    signalType:  m['signal_type'] as String? ?? '',
    identifier:  m['identifier'] as String? ?? '',
    displayName: m['display_name'] as String? ?? '',
    rssi:        (m['rssi'] as num?)?.toInt() ?? -100,
    distanceM:   (m['distance_m'] as num?)?.toDouble() ?? -1.0,
    riskScore:   (m['risk_score'] as num?)?.toInt() ?? 0,
    lat:         (m['lat'] as num?)?.toDouble(),
    lon:         (m['lon'] as num?)?.toDouble(),
    metadata:    _safeJsonDecode(m['metadata_json']),
    timestamp:   m['ts'] != null
        ? DateTime.fromMillisecondsSinceEpoch((m['ts'] as num).toInt())
        : DateTime.now(),
    threatFlag:  (m['threat_flag'] as num?)?.toInt() ?? LBThreatFlag.clean,
  );

  static Map<String, dynamic> _safeJsonDecode(dynamic value) {
    if (value == null) return {};
    if (value is String) {
      try {
        return jsonDecode(value) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }
    return {};
  }

  Map<String, dynamic> toMap() => {
    'id':            id,
    'session_id':    sessionId,
    'signal_type':   signalType,
    'identifier':    identifier,
    'display_name':  displayName,
    'rssi':          rssi,
    'distance_m':    distanceM,
    'risk_score':    riskScore,
    'lat':           lat,
    'lon':           lon,
    'metadata_json': jsonEncode(metadata),
    'ts':            timestamp.millisecondsSinceEpoch,
    'threat_flag':   threatFlag,
  };

  LBSignal copyWith({
    int? riskScore,
    int? threatFlag,
    double? lat,
    double? lon,
    double? distanceM,
    Map<String, dynamic>? metadata,
  }) => LBSignal(
    id:          id,
    sessionId:   sessionId,
    signalType:  signalType,
    identifier:  identifier,
    displayName: displayName,
    rssi:        rssi,
    distanceM:   distanceM ?? this.distanceM,
    riskScore:   riskScore ?? this.riskScore,
    lat:         lat ?? this.lat,
    lon:         lon ?? this.lon,
    metadata:    metadata ?? Map<String, dynamic>.from(this.metadata),
    timestamp:   timestamp,
    threatFlag:  threatFlag ?? this.threatFlag,
  );

  @override
  String toString() =>
    'LBSignal($signalType:$identifier rssi=$rssi risk=$riskScore)';
}

/// Threat event model
class LBThreatEvent {
  final int? id;
  final String threatType;
  final int severity;
  final String identifier;
  final Map<String, dynamic> evidence;
  final double? lat;
  final double? lon;
  final DateTime timestamp;
  final bool dismissed;

  const LBThreatEvent({
    this.id,
    required this.threatType,
    required this.severity,
    required this.identifier,
    required this.evidence,
    this.lat,
    this.lon,
    required this.timestamp,
    this.dismissed = false,
  });

  factory LBThreatEvent.fromMap(Map<String, dynamic> m) => LBThreatEvent(
    id:          m['id'] as int?,
    threatType:  m['threat_type'] as String? ?? 'unknown',
    severity:    (m['severity'] as num?)?.toInt() ?? 0,
    identifier:  m['identifier'] as String? ?? '',
    evidence:    _safeEvidenceDecode(m['evidence_json']),
    lat:         m['lat'] != null ? (m['lat'] as num).toDouble() : null,
    lon:         m['lon'] != null ? (m['lon'] as num).toDouble() : null,
    timestamp:   m['ts'] != null
        ? DateTime.fromMillisecondsSinceEpoch((m['ts'] as num).toInt())
        : DateTime.now(),
    dismissed:   (m['dismissed'] as int?) == 1,
  );

  static Map<String, dynamic> _safeEvidenceDecode(dynamic value) {
    if (value == null) return {};
    if (value is String) {
      try {
        return jsonDecode(value) as Map<String, dynamic>;
      } catch (_) {
        return {'raw': value.toString()};
      }
    }
    return {};
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'threat_type':   threatType,
    'severity':      severity,
    'identifier':    identifier,
    'evidence_json': jsonEncode(evidence),
    'lat':           lat,
    'lon':           lon,
    'ts':            timestamp.millisecondsSinceEpoch,
    'dismissed':     dismissed ? 1 : 0,
  };

  String get severityLabel => switch (severity) {
    LBSeverity.info     => 'INFO',
    LBSeverity.low      => 'LOW',
    LBSeverity.medium   => 'MEDIUM',
    LBSeverity.high     => 'HIGH',
    LBSeverity.critical => 'CRITICAL',
    _                   => 'UNKNOWN',
  };
}

/// Scan session model
class LBSession {
  final String id;
  final DateTime startedAt;
  DateTime? endedAt;
  int observationCount;
  int threatCount;

  LBSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.observationCount = 0,
    this.threatCount = 0,
  });

  factory LBSession.fromMap(Map<String, dynamic> m) => LBSession(
    id:               m['id'] as String,
    startedAt:        DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
    endedAt:          m['ended_at'] != null
                        ? DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int)
                        : null,
    observationCount: m['observation_count'] as int? ?? 0,
    threatCount:      m['threat_count'] as int? ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'id':                id,
    'started_at':        startedAt.millisecondsSinceEpoch,
    'ended_at':          endedAt?.millisecondsSinceEpoch,
    'observation_count': observationCount,
    'threat_count':      threatCount,
  };
}
