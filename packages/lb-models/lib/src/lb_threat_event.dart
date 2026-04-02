import 'signal_types.dart';

class LBThreatEvent {
  final String id;
  final String? sessionId;
  final ThreatType threatType;
  final int severity;
  final String? identifier;
  final SignalType? signalType;
  final Map<String, dynamic> evidence;
  final DateTime detectedAt;

  LBThreatEvent({
    required this.id,
    this.sessionId,
    required this.threatType,
    required this.severity,
    this.identifier,
    this.signalType,
    Map<String, dynamic>? evidence,
    DateTime? detectedAt,
  })  : evidence = evidence ?? {},
        detectedAt = detectedAt ?? DateTime.now();

  factory LBThreatEvent.fromMap(Map<String, dynamic> map) {
    final evidenceRaw = map['evidence_json'];
    Map<String, dynamic> evidence = {};
    if (evidenceRaw != null) {
      if (evidenceRaw is String) {
        try {
          evidence = _safeEvidenceDecode(evidenceRaw);
        } catch (_) {}
      } else if (evidenceRaw is Map) {
        evidence = Map<String, dynamic>.from(evidenceRaw);
      }
    }

    return LBThreatEvent(
      id: map['id'] as String? ?? '',
      sessionId: map['session_id'] as String?,
      threatType: ThreatType.fromString(map['threat_type'] as String? ?? 'unknown'),
      severity: (map['severity'] as num?)?.toInt() ?? 0,
      identifier: map['identifier'] as String?,
      signalType: map['signal_type'] != null
          ? SignalType.fromString(map['signal_type'] as String)
          : null,
      evidence: evidence,
      detectedAt: map['detected_at'] is DateTime
          ? map['detected_at'] as DateTime
          : DateTime.tryParse(map['detected_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'threat_type': threatType.name,
      'severity': severity,
      'identifier': identifier,
      'signal_type': signalType?.dbValue,
      'evidence_json': evidence,
      'detected_at': detectedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory LBThreatEvent.fromJson(Map<String, dynamic> json) =>
      LBThreatEvent.fromMap(json);

  static Map<String, dynamic> _safeEvidenceDecode(String source) {
    try {
      return Map<String, dynamic>.from(_parseJson(source));
    } catch (_) {
      return {};
    }
  }

  static Map<String, dynamic> _parseJson(String source) {
    throw UnimplementedError('Use json.decode from dart:convert');
  }

  @override
  String toString() {
    return 'LBThreatEvent(id: $id, type: ${threatType.displayName}, '
        'severity: $severity, detected: $detectedAt)';
  }
}
