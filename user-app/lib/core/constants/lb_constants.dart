/// LittleBrother — global constants
library;

class LBChannels {
  static const cell  = 'art.n0v4.littlebrother/cell';
  static const opsec = 'art.n0v4.littlebrother/opsec';
  static const wake  = 'art.n0v4.littlebrother/wake';
}

class LBDb {
  static const name            = 'lbscan.db'; // matches README adb pull instructions
  static const version         = 6;
  static const tObservations   = 'observations';
  static const tKnownDevices   = 'known_devices';
  static const tCellBaseline   = 'cell_baseline';
  static const tThreatEvents   = 'threat_events';
  static const tSessions       = 'sessions';
  static const tAggregateCells = 'aggregate_cells';
  static const tDeviceWaypoints = 'device_waypoints';
  static const tCachedCells     = 'cached_cells';
  static const tVisitedRegions = 'visited_regions';
}

class LBSignalType {
  static const wifi        = 'wifi';
  static const ble         = 'ble';
  static const cell        = 'cell';
  static const cellNeighbor = 'cell_neighbor';
}

class SignalPoint {
  final double lat;
  final double lon;
  final DateTime timestamp;
  final int rssi;
  final String signalType;

  const SignalPoint({
    required this.lat,
    required this.lon,
    required this.timestamp,
    required this.rssi,
    required this.signalType,
  });
}

class LBThreatType {
  static const stingray     = 'stingray';
  static const rogueAp      = 'rogue_ap';
  static const bleTracker   = 'ble_tracker';
  static const downgrade   = 'downgrade';
  static const watchlist   = 'watchlist_hit';
  static const silentSms   = 'silent_sms';
  static const smsExfil    = 'sms_exfiltration';
  static const dnsAnomaly  = 'dns_anomaly';
  static const deviceComp  = 'device_compromised';
  static const processAnom = 'process_anomaly';
  static const deauthStorm = 'deauth_storm';
}

class LBThreatFlag {
  static const clean   = 0;
  static const watch   = 1;
  static const hostile = 2;
}

class LBSeverity {
  static const info     = 1;
  static const low      = 2;
  static const medium   = 3;
  static const high     = 4;
  static const critical = 5;
}

class LBScanInterval {
  static const wifiForegroundMs   = 10000;
  static const wifiBackgroundMs   = 30000;
  static const bleForegroundMs    = 5000;
  static const cellForegroundMs   = 5000;
  static const gpsMaxAgeMs        = 30000;
}

class LBPathLoss {
  /// Free-space path loss exponent
  static const nOutdoor = 2.0;
  /// Indoor path loss exponent  
  static const nIndoor  = 2.7;
  /// Default TX power assumption (dBm) when not provided by AP
  static const defaultTxPowerDbm = -59;
}

class LBThresholds {
  /// Composite stingray score → alert levels
  static const stingrayWarning  = 40;
  static const stingrayThreat   = 65;
  static const stingrayCritical = 85;

  /// OPSEC auto-trigger severity
  static const opsecAutoSeverity = LBSeverity.critical;

  /// RSSI anomaly: dB above baseline to flag
  static const rssiAnomalyDb = 15;

  /// BLE: advertising interval below this (ms) is flagged aggressive
  static const bleAggressiveIntervalMs = 100;

  /// Cell: changes per 60s to flag instability
  static const cellIdChurnPerMinute = 3;

  /// Neighbor count: below this in urban area is suspicious
  static const minExpectedNeighbors = 3;
}

class LBGeohash {
  /// 7 chars ≈ 150m precision — used for cell baseline grouping
  static const precisionLevel = 7;
}
