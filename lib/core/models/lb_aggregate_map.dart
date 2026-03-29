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
      _                     => 'CLEAN',
    };
  }
}

class MockCommunityData {
  static bool _testModeEnabled = false;

  static void enableTestMode() {
    assert(() {
      _testModeEnabled = true;
      return true;
    }());
  }

  static bool get isEnabled => _testModeEnabled;

  static List<TestThreat> getMockThreats() {
    final now = DateTime.now();
    return [
      TestThreat(
        id: 'TEST_STINGRAY_001',
        signalType: 'cell',
        threatType: 'stingray',
        confidence: 75,
        geohash: 'dr72h8k',
        position: LatLng(37.7749, -122.4194),
        label: '[TEST] StingRay Demo - San Francisco',
        firstReported: now.subtract(const Duration(days: 5)),
      ),
      TestThreat(
        id: 'TEST_ROGUE_AP_001',
        signalType: 'wifi',
        threatType: 'rogue_ap',
        confidence: 60,
        geohash: 'dr72h9k',
        position: LatLng(37.7751, -122.4180),
        label: '[TEST] Rogue AP Demo - Downtown',
        firstReported: now.subtract(const Duration(days: 3)),
      ),
      TestThreat(
        id: 'TEST_TRACKER_001',
        signalType: 'ble',
        threatType: 'tracker',
        confidence: 85,
        geohash: 'dr72j2m',
        position: LatLng(37.7760, -122.4150),
        label: '[TEST] BLE Tracker Demo - Market St',
        firstReported: now.subtract(const Duration(hours: 12)),
      ),
      TestThreat(
        id: 'TEST_STINGRAY_002',
        signalType: 'cell',
        threatType: 'stingray',
        confidence: 90,
        geohash: '9q5f8ve',
        position: LatLng(34.0522, -118.2437),
        label: '[TEST] StingRay Demo - Los Angeles',
        firstReported: now.subtract(const Duration(days: 7)),
      ),
      TestThreat(
        id: 'TEST_STINGRAY_003',
        signalType: 'cell',
        threatType: 'stingray',
        confidence: 45,
        geohash: 'dr72gk6',
        position: LatLng(37.8044, -122.2712),
        label: '[TEST] Low Conf Demo - Oakland',
        firstReported: now.subtract(const Duration(days: 1)),
      ),
    ];
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
  ble('BLE'),
  test('TEST');

  final String label;
  const MapLayer(this.label);
}

class TestThreat {
  final String id;
  final String signalType;
  final String threatType;
  final int confidence;
  final String geohash;
  final LatLng position;
  final String label;
  final DateTime firstReported;

  TestThreat({
    required this.id,
    required this.signalType,
    required this.threatType,
    required this.confidence,
    required this.geohash,
    required this.position,
    required this.label,
    required this.firstReported,
  });
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
    final lat = m['lat'] as double;
    final lon = m['lon'] as double;
    return CellTower(
      cellKey:         m['cell_key'] as String,
      displayName:    m['display_name'] as String? ?? '',
      pci:            m['pci'] as int? ?? -1,
      tac:            m['tac'] as int? ?? -1,
      networkType:    m['network_type'] as String? ?? '?',
      band:           m['band'] as String?,
      operator:       m['operator'] as String?,
      isServing:      (m['is_serving'] as int? ?? 0) == 1,
      position:       LatLng(lat, lon),
      observationCount: m['obs_count'] as int? ?? 1,
      worstThreat:     m['max_severity'] as int? ?? 0,
      worstThreatFlag: m['worst_flag'] as int? ?? LBThreatFlag.clean,
      rsrp:            m['rsrp'] as int? ?? -120,
      rsrq:            m['rsrq'] as int? ?? -20,
      sinr:            m['sinr'] as int? ?? -20,
      firstSeen:       DateTime.fromMillisecondsSinceEpoch(m['first_seen'] as int),
      lastSeen:        DateTime.fromMillisecondsSinceEpoch(m['last_seen'] as int),
    );
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
      bssid:            m['bssid'] as String,
      ssid:             m['ssid'] as String? ?? '',
      vendor:           m['vendor'] as String? ?? '',
      position:         LatLng(m['lat'] as double, m['lon'] as double),
      observationCount: m['obs_count'] as int? ?? 1,
      worstThreat:     (m['max_severity'] as num?)?.toInt() ?? 0,
      worstThreatFlag: (m['worst_flag'] as num?)?.toInt() ?? LBThreatFlag.clean,
      rssi:            m['rssi'] as int? ?? -100,
      channel:         (m['channel'] as num?)?.toInt(),
      security:        m['security'] as String?,
      firstSeen:       DateTime.fromMillisecondsSinceEpoch(m['first_seen'] as int),
      lastSeen:        DateTime.fromMillisecondsSinceEpoch(m['last_seen'] as int),
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
      mac:             m['mac'] as String,
      displayName:     m['display_name'] as String? ?? '',
      position:        LatLng(m['lat'] as double, m['lon'] as double),
      observationCount: m['obs_count'] as int? ?? 1,
      worstThreat:     (m['max_severity'] as num?)?.toInt() ?? 0,
      worstThreatFlag: (m['worst_flag'] as num?)?.toInt() ?? LBThreatFlag.clean,
      rssi:            m['rssi'] as int? ?? -100,
      isTracker:      (m['is_tracker'] as num?)?.toInt() == 1,
      txPower:        (m['tx_power'] as num?)?.toInt(),
      firstSeen:       DateTime.fromMillisecondsSinceEpoch(m['first_seen'] as int),
      lastSeen:        DateTime.fromMillisecondsSinceEpoch(m['last_seen'] as int),
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
