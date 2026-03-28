/// Pure Dart geohash encoder.
/// No external dependency — used for cell baseline bucketing (~150m at precision 7).
class Geohash {
  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Encode lat/lon to geohash string of given precision.
  static String encode(double lat, double lon, {int precision = 7}) {
    var minLat = -90.0, maxLat = 90.0;
    var minLon = -180.0, maxLon = 180.0;

    final buffer = StringBuffer();
    var bits = 0;
    var bitsTotal = 0;
    var hashValue = 0;
    var isEven = true;

    while (buffer.length < precision) {
      final mid = isEven ? (minLon + maxLon) / 2 : (minLat + maxLat) / 2;
      final val = isEven ? lon : lat;

      if (val > mid) {
        hashValue = (hashValue << 1) | 1;
        if (isEven) minLon = mid; else minLat = mid;
      } else {
        hashValue = hashValue << 1;
        if (isEven) maxLon = mid; else maxLat = mid;
      }

      isEven = !isEven;
      bits++;
      bitsTotal++;

      if (bits == 5) {
        buffer.write(_base32[hashValue]);
        bits = 0;
        hashValue = 0;
      }
    }

    return buffer.toString();
  }

  /// Decode a geohash to its center lat/lon.
  static ({double lat, double lon}) decode(String hash) {
    var minLat = -90.0, maxLat = 90.0;
    var minLon = -180.0, maxLon = 180.0;
    var isEven = true;

    for (final ch in hash.split('')) {
      final idx = _base32.indexOf(ch);
      if (idx == -1) break;
      for (var bits = 4; bits >= 0; bits--) {
        final bitVal = (idx >> bits) & 1;
        if (isEven) {
          final mid = (minLon + maxLon) / 2;
          if (bitVal == 1) minLon = mid; else maxLon = mid;
        } else {
          final mid = (minLat + maxLat) / 2;
          if (bitVal == 1) minLat = mid; else maxLat = mid;
        }
        isEven = !isEven;
      }
    }

    return (
      lat: (minLat + maxLat) / 2,
      lon: (minLon + maxLon) / 2,
    );
  }
}
