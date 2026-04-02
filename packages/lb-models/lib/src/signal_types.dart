enum SignalType {
  wifi,
  ble,
  btClassic,
  cell,
  gps,
  unknown;

  String get displayName {
    switch (this) {
      case SignalType.wifi:
        return 'Wi-Fi';
      case SignalType.ble:
        return 'BLE';
      case SignalType.btClassic:
        return 'Bluetooth Classic';
      case SignalType.cell:
        return 'Cellular';
      case SignalType.gps:
        return 'GPS';
      case SignalType.unknown:
        return 'Unknown';
    }
  }

  String get dbValue {
    switch (this) {
      case SignalType.wifi:
        return 'wifi';
      case SignalType.ble:
        return 'ble';
      case SignalType.btClassic:
        return 'bt_classic';
      case SignalType.cell:
        return 'cell';
      case SignalType.gps:
        return 'gps';
      case SignalType.unknown:
        return 'unknown';
    }
  }

  static SignalType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'wifi':
        return SignalType.wifi;
      case 'ble':
        return SignalType.ble;
      case 'bt_classic':
      case 'btclassic':
        return SignalType.btClassic;
      case 'cell':
        return SignalType.cell;
      case 'gps':
        return SignalType.gps;
      default:
        return SignalType.unknown;
    }
  }
}

enum ThreatLevel {
  clean(0),
  watch(1),
  hostile(2);

  final int value;
  const ThreatLevel(this.value);

  String get displayName {
    switch (this) {
      case ThreatLevel.clean:
        return 'Clean';
      case ThreatLevel.watch:
        return 'Watch';
      case ThreatLevel.hostile:
        return 'Hostile';
    }
  }

  static ThreatLevel fromInt(int value) {
    switch (value) {
      case 0:
        return ThreatLevel.clean;
      case 1:
        return ThreatLevel.watch;
      case 2:
        return ThreatLevel.hostile;
      default:
        return ThreatLevel.clean;
    }
  }
}

enum ThreatType {
  stingray('Stingray Detection'),
  rogueAp('Rogue Access Point'),
  bleTracker('BLE Tracker'),
  suspiciousCell('Suspicious Cell'),
  imsiCatch('IMSI Catcher'),
  unknown('Unknown Threat');

  final String displayName;
  const ThreatType(this.displayName);

  static ThreatType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'stingray':
        return ThreatType.stingray;
      case 'rogue_ap':
      case 'rogueap':
        return ThreatType.rogueAp;
      case 'ble_tracker':
      case 'bletracker':
        return ThreatType.bleTracker;
      case 'suspicious_cell':
      case 'suspiciouscell':
        return ThreatType.suspiciousCell;
      case 'imsi_catch':
      case 'imsicatch':
        return ThreatType.imsiCatch;
      default:
        return ThreatType.unknown;
    }
  }
}

enum NetworkType {
  unknown,
  gsm,
  cdma,
  umts,
  lte,
  nr,
  lteCa;

  String get displayName {
    switch (this) {
      case NetworkType.unknown:
        return 'Unknown';
      case NetworkType.gsm:
        return 'GSM';
      case NetworkType.cdma:
        return 'CDMA';
      case NetworkType.umts:
        return 'UMTS';
      case NetworkType.lte:
        return 'LTE';
      case NetworkType.nr:
        return '5G NR';
      case NetworkType.lteCa:
        return 'LTE-A';
    }
  }

  static NetworkType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'gsm':
        return NetworkType.gsm;
      case 'cdma':
        return NetworkType.cdma;
      case 'umts':
      case 'hspa':
      case '3g':
        return NetworkType.umts;
      case 'lte':
      case '4g':
        return NetworkType.lte;
      case 'nr':
      case '5g':
        return NetworkType.nr;
      case 'lte_ca':
      case 'lteca':
        return NetworkType.lteCa;
      default:
        return NetworkType.unknown;
    }
  }
}
