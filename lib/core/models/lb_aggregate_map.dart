import 'dart:convert';
import 'package:latlong2/latlong.dart';
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
    final geohashVal = m['geohash'];
    final geohashStr = geohashVal is String ? geohashVal : (geohashVal?.toString() ?? '');
    final gh = Geohash.decode(geohashStr);
    return AggregateCell(
      geohash:          geohashStr,
      precision:        precision,
      lat:              gh.lat,
      lon:              gh.lon,
      deviceCount:      m['device_count'] as int? ?? 0,
      observationCount: m['obs_count'] as int? ?? 0,
      worstFlag:        m['worst_flag'] as int? ?? 0,
      wifiCount:        m['wifi_count'] as int? ?? 0,
      bleCount:         m['ble_count'] as int? ?? 0,
      cellCount:        m['cell_count'] as int? ?? 0,
      mostRecent:       DateTime.fromMillisecondsSinceEpoch((m['most_recent'] as num?)?.toInt() ?? 0),
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
      _                     => 'CLEAN',
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

enum MapLayer {
  grid('GRID'),
  towers('TOWERS'),
  wifi('WIFI'),
  ble('BLE');

  final String label;
  const MapLayer(this.label);
}

class CellTower {
  final String cellKey;
  final String displayName;
  final int pci;
  final int tac;
  final String networkType;
  final String? band;
  final String? operator;
  final bool isServing;
  final LatLng position;
  final int observationCount;
  final int worstThreat;
  final int worstThreatFlag;
  final int rsrp;
  final int rsrq;
  final int sinr;
  final DateTime firstSeen;
  final DateTime lastSeen;

  const CellTower({
    required this.cellKey,
    required this.displayName,
    required this.pci,
    required this.tac,
    required this.networkType,
    this.band,
    this.operator,
    required this.isServing,
    required this.position,
    required this.observationCount,
    required this.worstThreat,
    required this.worstThreatFlag,
    required this.rsrp,
    required this.rsrq,
    required this.sinr,
    required this.firstSeen,
    required this.lastSeen,
  });

  factory CellTower.fromMap(Map<String, dynamic> m) {
    final meta = m['metadata_json'] != null ? _parseJson(m['metadata_json'] as String) : <String, dynamic>{};
    return CellTower(
      cellKey:         (m['cell_key'] as String?) ?? '',
      displayName:    (m['display_name']?.toString()) ?? '',
      pci:            (m['pci'] as num?)?.toInt() ?? (meta['pci'] as num?)?.toInt() ?? -1,
      tac:            (m['tac'] as num?)?.toInt() ?? (meta['tac'] as num?)?.toInt() ?? -1,
      networkType:    (m['network_type'] as String?) ?? meta['network_type_name'] as String? ?? meta['type'] as String? ?? '?',
      band:           (m['band'] as String?) ?? meta['band'] as String?,
      operator:       (m['operator'] as String?) ?? meta['operator'] as String?,
      isServing:      (m['is_serving'] as bool?) ?? ((meta['is_serving'] as num?)?.toInt() ?? 0) == 1,
      position:       LatLng((m['lat'] as num?)?.toDouble() ?? 0.0, (m['lon'] as num?)?.toDouble() ?? 0.0),
      observationCount: (m['obs_count'] as num?)?.toInt() ?? 1,
      worstThreat:     (m['max_severity'] as num?)?.toInt() ?? 0,
      worstThreatFlag: (m['worst_flag'] as num?)?.toInt() ?? LBThreatFlag.clean,
      rsrp:            (m['rsrp'] as num?)?.toInt() ?? (meta['rsrp'] as num?)?.toInt() ?? -120,
      rsrq:            (m['rsrq'] as num?)?.toInt() ?? (meta['rsrq'] as num?)?.toInt() ?? -20,
      sinr:            (m['sinr'] as num?)?.toInt() ?? (meta['sinr'] as num?)?.toInt() ?? -20,
      firstSeen:       DateTime.fromMillisecondsSinceEpoch((m['first_seen'] as num?)?.toInt() ?? 0),
      lastSeen:        DateTime.fromMillisecondsSinceEpoch((m['last_seen'] as num?)?.toInt() ?? 0),
    );
  }

  static Map<String, dynamic> _parseJson(String json) {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(json) as Map,
      );
    } catch (_) {
      return {};
    }
  }

  String get threatLabel {
    return switch (worstThreatFlag) {
      LBThreatFlag.watch   => 'WATCH',
      LBThreatFlag.hostile => 'HOSTILE',
      _                     => 'CLEAN',
    };
  }

  String get severityLabel {
    return switch (worstThreat) {
      LBSeverity.info     => 'INFO',
      LBSeverity.low      => 'LOW',
      LBSeverity.medium   => 'MEDIUM',
      LBSeverity.high     => 'HIGH',
      LBSeverity.critical => 'CRITICAL',
      _                    => 'CLEAN',
    };
  }
}

class WifiDevice {
  final String bssid;
  final String ssid;
  final String vendor;
  final LatLng position;
  final int observationCount;
  final int worstThreat;
  final int worstThreatFlag;
  final int rssi;
  final int? channel;
  final String? security;
  final DateTime firstSeen;
  final DateTime lastSeen;

  const WifiDevice({
    required this.bssid,
    required this.ssid,
    required this.vendor,
    required this.position,
    required this.observationCount,
    required this.worstThreat,
    required this.worstThreatFlag,
    required this.rssi,
    this.channel,
    this.security,
    required this.firstSeen,
    required this.lastSeen,
  });

  factory WifiDevice.fromMap(Map<String, dynamic> m) {
    return WifiDevice(
      bssid:            (m['bssid'] as String?) ?? '',
      ssid:             (m['ssid'] as String?) ?? '',
      vendor:           (m['vendor'] as String?) ?? '',
      position:         LatLng((m['lat'] as num?)?.toDouble() ?? 0.0, (m['lon'] as num?)?.toDouble() ?? 0.0),
      observationCount: (m['obs_count'] as num?)?.toInt() ?? 1,
      worstThreat:     (m['max_severity'] as num?)?.toInt() ?? 0,
      worstThreatFlag: (m['worst_flag'] as num?)?.toInt() ?? LBThreatFlag.clean,
      rssi:            (m['rssi'] as num?)?.toInt() ?? -100,
      channel:         (m['channel'] as num?)?.toInt(),
      security:        m['security'] as String?,
      firstSeen:       DateTime.fromMillisecondsSinceEpoch((m['first_seen'] as num?)?.toInt() ?? 0),
      lastSeen:        DateTime.fromMillisecondsSinceEpoch((m['last_seen'] as num?)?.toInt() ?? 0),
    );
  }

  String get threatLabel {
    return switch (worstThreatFlag) {
      LBThreatFlag.watch   => 'WATCH',
      LBThreatFlag.hostile => 'HOSTILE',
      _                     => 'CLEAN',
    };
  }
}

class BleDevice {
  final String mac;
  final String displayName;
  final LatLng position;
  final int observationCount;
  final int worstThreat;
  final int worstThreatFlag;
  final int rssi;
  final bool isTracker;
  final int? txPower;
  final DateTime firstSeen;
  final DateTime lastSeen;

  const BleDevice({
    required this.mac,
    required this.displayName,
    required this.position,
    required this.observationCount,
    required this.worstThreat,
    required this.worstThreatFlag,
    required this.rssi,
    required this.isTracker,
    this.txPower,
    required this.firstSeen,
    required this.lastSeen,
  });

  factory BleDevice.fromMap(Map<String, dynamic> m) {
    return BleDevice(
      mac:             (m['mac'] as String?) ?? '',
      displayName:     (m['display_name'] as String?) ?? '',
      position:        LatLng((m['lat'] as num?)?.toDouble() ?? 0.0, (m['lon'] as num?)?.toDouble() ?? 0.0),
      observationCount: (m['obs_count'] as num?)?.toInt() ?? 1,
      worstThreat:     (m['max_severity'] as num?)?.toInt() ?? 0,
      worstThreatFlag: (m['worst_flag'] as num?)?.toInt() ?? LBThreatFlag.clean,
      rssi:            (m['rssi'] as num?)?.toInt() ?? -100,
      isTracker:      (m['is_tracker'] as num?)?.toInt() == 1,
      txPower:        (m['tx_power'] as num?)?.toInt(),
      firstSeen:       DateTime.fromMillisecondsSinceEpoch((m['first_seen'] as num?)?.toInt() ?? 0),
      lastSeen:        DateTime.fromMillisecondsSinceEpoch((m['last_seen'] as num?)?.toInt() ?? 0),
    );
  }

  String get threatLabel {
    return switch (worstThreatFlag) {
      LBThreatFlag.watch   => 'WATCH',
      LBThreatFlag.hostile => 'HOSTILE',
      _                     => 'CLEAN',
    };
  }
}
