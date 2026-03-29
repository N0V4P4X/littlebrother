import 'package:littlebrother/core/db/geohash.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';

class AggregateCell {
  final String geohash;
  final int precision;
  final double lat;
  final double lon;
  final int deviceCount;
  final int observationCount;
  final int worstFlag;
  final int wifiCount;
  final int bleCount;
  final int cellCount;
  final DateTime mostRecent;

  AggregateCell({
    required this.geohash,
    required this.precision,
    required this.lat,
    required this.lon,
    required this.deviceCount,
    required this.observationCount,
    required this.worstFlag,
    required this.wifiCount,
    required this.bleCount,
    required this.cellCount,
    required this.mostRecent,
  });

  factory AggregateCell.fromMap(Map<String, dynamic> m, {int precision = LBGeohash.precisionLevel}) {
    final gh = Geohash.decode(m['geohash'] as String);
    return AggregateCell(
      geohash:          m['geohash'] as String,
      precision:        precision,
      lat:              gh.lat,
      lon:              gh.lon,
      deviceCount:      m['device_count'] as int? ?? 0,
      observationCount: m['obs_count'] as int? ?? 0,
      worstFlag:        m['worst_flag'] as int? ?? 0,
      wifiCount:        m['wifi_count'] as int? ?? 0,
      bleCount:         m['ble_count'] as int? ?? 0,
      cellCount:        m['cell_count'] as int? ?? 0,
      mostRecent:       DateTime.fromMillisecondsSinceEpoch(m['most_recent'] as int),
    );
  }

  String get dominantType {
    if (wifiCount >= bleCount && wifiCount >= cellCount) return LBSignalType.wifi;
    if (bleCount >= cellCount) return LBSignalType.ble;
    return LBSignalType.cell;
  }

  int get dominantCount {
    return switch (dominantType) {
      LBSignalType.wifi => wifiCount,
      LBSignalType.ble  => bleCount,
      _                  => cellCount,
    };
  }
}

class DeviceProfile {
  final String identifier;
  final String displayName;
  final String signalType;
  final String vendor;
  final int observationCount;
  final int cellCount;
  final int worstThreatFlag;
  final DateTime firstSeen;
  final DateTime lastSeen;

  const DeviceProfile({
    required this.identifier,
    required this.displayName,
    required this.signalType,
    required this.vendor,
    required this.observationCount,
    required this.cellCount,
    required this.worstThreatFlag,
    required this.firstSeen,
    required this.lastSeen,
  });

  bool get isMobile => cellCount > 1;

  bool get isStationary => cellCount == 1;

  String get threatLabel {
    return switch (worstThreatFlag) {
      LBThreatFlag.watch   => 'WATCH',
      LBThreatFlag.hostile => 'HOSTILE',
      _                    => 'CLEAN',
    };
  }
}

enum CellPrecision {
  coarse(6, '1.2 km'),
  standard(7, '150 m'),
  fine(8, '38 m');

  final int chars;
  final String label;
  const CellPrecision(this.chars, this.label);
}

enum TimeRange {
  day1('24h', Duration(days: 1)),
  days7('7d', Duration(days: 7)),
  days30('30d', Duration(days: 30)),
  all('ALL', null);

  final String label;
  final Duration? duration;
  const TimeRange(this.label, this.duration);

  int? get cutoffMs {
    if (duration == null) return null;
    return DateTime.now().subtract(duration!).millisecondsSinceEpoch;
  }
}

enum ThreatFilter {
  all('ALL'),
  watch('WATCH'),
  hostile('HOSTILE');

  final String label;
  const ThreatFilter(this.label);

  int? get minFlag {
    return switch (this) {
      ThreatFilter.all     => null,
      ThreatFilter.watch   => LBThreatFlag.watch,
      ThreatFilter.hostile => LBThreatFlag.hostile,
    };
  }
}
