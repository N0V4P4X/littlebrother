import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';

class CellCapabilities {
  final bool hasPhoneStatePermission;
  final bool hasLocationPermission;
  final bool locationEnabled;
  final bool allCellInfoAvailable;
  final bool allCellInfoEmpty;
  final int androidVersion;
  final String manufacturer;
  final String model;
  final bool supportsNr;
  final String diagnosis;
  const CellCapabilities({
    required this.hasPhoneStatePermission,
    required this.hasLocationPermission,
    required this.locationEnabled,
    required this.allCellInfoAvailable,
    required this.allCellInfoEmpty,
    required this.androidVersion,
    required this.manufacturer,
    required this.model,
    required this.supportsNr,
    required this.diagnosis,
  });
  factory CellCapabilities.fromMap(Map<String, dynamic> m) => CellCapabilities(
    hasPhoneStatePermission:  m['hasPhoneStatePermission'] as bool? ?? false,
    hasLocationPermission:   m['hasLocationPermission'] as bool? ?? false,
    locationEnabled:         m['locationEnabled'] as bool? ?? false,
    allCellInfoAvailable:     m['allCellInfoAvailable'] as bool? ?? false,
    allCellInfoEmpty:        m['allCellInfoEmpty'] as bool? ?? true,
    androidVersion:          m['androidVersion'] as int? ?? 0,
    manufacturer:            m['manufacturer'] as String? ?? '',
    model:                   m['model'] as String? ?? '',
    supportsNr:              m['supportsNr'] as bool? ?? false,
    diagnosis:               m['diagnosis'] as String? ?? 'UNKNOWN',
  );
  String get diagnosisMessage {
    return switch (diagnosis) {
      'OK' => 'All systems go',
      'MISSING_PHONE_STATE_PERMISSION' => 'READ_PHONE_STATE permission denied',
      'MISSING_LOCATION_PERMISSION' => 'Location permission denied',
      'LOCATION_DISABLED' => 'Location services are disabled',
      'ALL_CELL_INFO_NOT_AVAILABLE' => 'allCellInfo API unavailable on this device',
      'ALL_CELL_INFO_EMPTY' => 'allCellInfo returned empty (possible OEM restriction)',
      _ => 'Unknown: $diagnosis',
    };
  }
  bool get isOperational => diagnosis == 'OK';
}

class CellScanner {
  final _uuid = const Uuid();
  Timer? _timer;
  final _controller = StreamController<List<LBSignal>>.broadcast();

  CellCapabilities? _lastCapabilities;
  CellCapabilities? get lastCapabilities => _lastCapabilities;
  int get consecutiveEmptyCount => 0;

  Stream<List<LBSignal>> get stream => _controller.stream;
  bool get isRunning => _timer != null;

  Future<void> start(String sessionId) async {
    if (isRunning) return;
    _timer = Timer.periodic(
      const Duration(milliseconds: LBScanInterval.cellForegroundMs),
      (_) {},
    );
    _controller.add([]);
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  int servingCellChangesPerMinute() => 0;
  int tacChangesPerMinute() => 0;
  int neighborInstabilityScore() => 0;
  int? get lastTimingAdvance => null;

  void dispose() {
    stop();
    _controller.close();
  }
}
