import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:littlebrother/core/db/geohash.dart';

class GpsTracker {
  GpsTracker._();
  static final GpsTracker instance = GpsTracker._();
  
  StreamSubscription<Position>? _sub;
  Position? _lastPosition;
  DateTime? _lastFixTime;
  bool _isRunning = false;
  String? _lastError;

  Position? get lastPosition => _lastPosition;
  DateTime? get lastFixTime => _lastFixTime;
  bool get isRunning => _isRunning;
  String? get lastError => _lastError;

  /// Returns true if the last GPS fix is fresh enough to trust.
  /// Uses 120 second threshold to account for GPS startup delays.
  bool get hasFreshFix {
    final lastFix = _lastFixTime;
    if (lastFix == null) return false;
    final ageMs = DateTime.now().difference(lastFix).inMilliseconds;
    return ageMs < 120000; // 2 minutes
  }

  String? get currentGeohash {
    if (_lastPosition == null) return null;
    return Geohash.encode(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      precision: 7,
    );
  }

  Future<bool> start() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _lastError = 'Permission denied: $permission';
      debugPrint('GPS_TRACKER: Permission denied - $permission');
      return false;
    }

    debugPrint('GPS_TRACKER: Starting location stream');
    _isRunning = true;

    // Get immediate position as backup
    _requestImmediatePosition();

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // Get all updates
      ),
    ).listen((pos) {
      _lastPosition = pos;
      _lastFixTime = DateTime.now();
      debugPrint('GPS_TRACKER: New position - lat: ${pos.latitude}, lon: ${pos.longitude}, accuracy: ${pos.accuracy}m');
    }, onError: (e) {
      _lastError = e.toString();
      debugPrint('GPS_TRACKER: Error - $e');
    });

    return true;
  }

  Future<void> _requestImmediatePosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _lastPosition = pos;
      _lastFixTime = DateTime.now();
      debugPrint('GPS_TRACKER: Immediate position - lat: ${pos.latitude}, lon: ${pos.longitude}, accuracy: ${pos.accuracy}m');
    } catch (e) {
      debugPrint('GPS_TRACKER: Immediate position failed: $e');
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _isRunning = false;
    debugPrint('GPS_TRACKER: Stopped');
  }

  void dispose() {
    stop();
  }
}
