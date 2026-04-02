class LBSession {
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int observationCount;
  final int threatCount;
  final Map<String, dynamic>? metadata;

  LBSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.observationCount = 0,
    this.threatCount = 0,
    this.metadata,
  });

  bool get isActive => endedAt == null;

  Duration get duration {
    final end = endedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  LBSession copyWith({
    String? id,
    DateTime? startedAt,
    DateTime? endedAt,
    int? observationCount,
    int? threatCount,
    Map<String, dynamic>? metadata,
  }) {
    return LBSession(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      observationCount: observationCount ?? this.observationCount,
      threatCount: threatCount ?? this.threatCount,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'observation_count': observationCount,
      'threat_count': threatCount,
      'metadata': metadata,
    };
  }

  factory LBSession.fromMap(Map<String, dynamic> map) {
    return LBSession(
      id: map['id'] as String? ?? '',
      startedAt: map['started_at'] is DateTime
          ? map['started_at'] as DateTime
          : DateTime.tryParse(map['started_at'] as String? ?? '') ?? DateTime.now(),
      endedAt: map['ended_at'] != null
          ? (map['ended_at'] is DateTime
              ? map['ended_at'] as DateTime
              : DateTime.tryParse(map['ended_at'] as String? ?? ''))
          : null,
      observationCount: (map['observation_count'] as num?)?.toInt() ?? 0,
      threatCount: (map['threat_count'] as num?)?.toInt() ?? 0,
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory LBSession.fromJson(Map<String, dynamic> json) => LBSession.fromMap(json);

  @override
  String toString() {
    return 'LBSession(id: $id, started: $startedAt, '
        'observations: $observationCount, threats: $threatCount)';
  }
}
