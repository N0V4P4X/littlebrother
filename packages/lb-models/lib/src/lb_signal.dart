import 'signal_types.dart';

class LBSignal {
  final String id;
  final String? sessionId;
  final SignalType signalType;
  final String identifier;
  final String? displayName;
  final int rssi;
  final double? lat;
  final double? lon;
  final String? geohash;
  final DateTime timestamp;
  final int threatFlag;
  final Map<String, dynamic> metadata;

  LBSignal({
    required this.id,
    this.sessionId,
    required this.signalType,
    required this.identifier,
    this.displayName,
    required this.rssi,
    this.lat,
    this.lon,
    this.geohash,
    required this.timestamp,
    this.threatFlag = 0,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? {};

  ThreatLevel get threatLevel => ThreatLevel.fromInt(threatFlag);

  bool get hasLocation => lat != null && lon != null;

  LBSignal copyWith({
    String? id,
    String? sessionId,
    SignalType? signalType,
    String? identifier,
    String? displayName,
    int? rssi,
    double? lat,
    double? lon,
    String? geohash,
    DateTime? timestamp,
    int? threatFlag,
    Map<String, dynamic>? metadata,
  }) {
    return LBSignal(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      signalType: signalType ?? this.signalType,
      identifier: identifier ?? this.identifier,
      displayName: displayName ?? this.displayName,
      rssi: rssi ?? this.rssi,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      geohash: geohash ?? this.geohash,
      timestamp: timestamp ?? this.timestamp,
      threatFlag: threatFlag ?? this.threatFlag,
      metadata: metadata ?? Map<String, dynamic>.from(this.metadata),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'signal_type': signalType.dbValue,
      'identifier': identifier,
      'display_name': displayName,
      'rssi': rssi,
      'lat': lat,
      'lon': lon,
      'geohash': geohash,
      'timestamp': timestamp.toIso8601String(),
      'threat_flag': threatFlag,
      'metadata': metadata,
    };
  }

  factory LBSignal.fromMap(Map<String, dynamic> map) {
    final metadataRaw = map['metadata'];
    Map<String, dynamic> metadata = {};
    if (metadataRaw != null) {
      if (metadataRaw is String) {
        try {
          metadata = Map<String, dynamic>.from(
            _safeJsonDecode(metadataRaw) ?? {},
          );
        } catch (_) {}
      } else if (metadataRaw is Map) {
        metadata = Map<String, dynamic>.from(metadataRaw);
      }
    }

    return LBSignal(
      id: map['id'] as String? ?? '',
      sessionId: map['session_id'] as String?,
      signalType: SignalType.fromString(map['signal_type'] as String? ?? 'unknown'),
      identifier: map['identifier'] as String? ?? '',
      displayName: map['display_name'] as String?,
      rssi: (map['rssi'] as num?)?.toInt() ?? 0,
      lat: (map['lat'] as num?)?.toDouble(),
      lon: (map['lon'] as num?)?.toDouble(),
      geohash: map['geohash'] as String?,
      timestamp: map['timestamp'] is DateTime
          ? map['timestamp'] as DateTime
          : DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
      threatFlag: (map['threat_flag'] as num?)?.toInt() ?? 0,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory LBSignal.fromJson(Map<String, dynamic> json) => LBSignal.fromMap(json);

  static Map<String, dynamic>? _safeJsonDecode(String source) {
    try {
      return source.isNotEmpty ? _parseJson(source) : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _parseJson(String source) {
    // Simple JSON parser for Map<String, dynamic>
    // Using dart:convert in actual implementation
    throw UnimplementedError('Use json.decode from dart:convert');
  }

  @override
  String toString() {
    return 'LBSignal(id: $id, type: ${signalType.displayName}, '
        'identifier: $identifier, rssi: $rssi, '
        'threat: ${threatLevel.displayName})';
  }
}

extension LBSignalJson on LBSignal {
  Map<String, dynamic> toCrowdsourceJson() {
    return {
      'id': id,
      'signal_type': signalType.dbValue,
      'identifier': identifier,
      'display_name': displayName,
      'rssi': rssi,
      'lat': lat,
      'lon': lon,
      'geohash': geohash,
      'timestamp': timestamp.toIso8601String(),
      'threat_flag': threatFlag,
    };
  }
}
