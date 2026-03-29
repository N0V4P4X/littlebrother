import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:littlebrother/core/db/geohash.dart';

class GpsTracker {
  StreamSubscription<Position>? _sub;
  Position? _lastPosition;
  DateTime? _lastFixTime;

  Position? get lastPosition => _lastPosition;
  DateTime? get lastFixTime => _lastFixTime;

  /// Returns true if the last GPS fix is fresh enough to trust.
  bool get hasFreshFix {
    final lastFix = _lastFixTime;
    if (lastFix == null) return false;
    return DateTime.now().difference(lastFix).inMilliseconds < 30000;
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
      return false;
    }

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // update every 5m of movement
      ),
    ).listen((pos) {
      _lastPosition = pos;
      _lastFixTime = DateTime.now();
    });

    return true;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    stop();
  }
}
