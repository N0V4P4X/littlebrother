import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/secrets.dart';
import 'package:littlebrother/core/db/geohash.dart';

class CachedCell {
  final String cellKey;
  final int? mcc;
  final int? mnc;
  final int? lac;
  final int? tac;
  final int? cid;
  final String? radio;
  final String? networkType;
  final double? lat;
  final double? lon;
  final int? rangeMeters;
  final int? samples;

  CachedCell({
    required this.cellKey,
    this.mcc,
    this.mnc,
    this.lac,
    this.tac,
    this.cid,
    this.radio,
    this.networkType,
    this.lat,
    this.lon,
    this.rangeMeters,
    this.samples,
  });

  LatLng? get position => lat != null && lon != null ? LatLng(lat!, lon!) : null;
}

class SignalValidationResult {
  final bool isValid;
  final double expectedRssiMin;
  final double expectedRssiMax;
  final double observedRssi;
  final String? reason;

  SignalValidationResult({
    required this.isValid,
    required this.expectedRssiMin,
    required this.expectedRssiMax,
    required this.observedRssi,
    this.reason,
  });
}

class CellCacheService {
  final LBDatabase _db = LBDatabase.instance;
  static const String _apiBase = 'https://opencellid.org/cell/getInArea';
  
  static const int _regionPrecision = 4;
  static const int _maxCellsPerRegion = 5000;
  static const int _maxRequestsPerRegion = 10;

  Future<void> initialize() async {
    if (Secrets.privacyMode) {
      debugPrint('CellCache: Privacy mode - skipping initialization');
      return;
    }
    await _updateVisitedRegions();
    await loadCellsForVisitedRegions();
  }

  Future<void> _updateVisitedRegions() async {
    final database = await _db.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    final waypoints = await database.rawQuery('''
      SELECT DISTINCT lat, lon
      FROM ${LBDb.tDeviceWaypoints}
      WHERE lat IS NOT NULL AND lon IS NOT NULL
    ''');

    final regionMap = <String, Map<String, double>>{};
    
    for (final wp in waypoints) {
      final lat = (wp['lat'] as num).toDouble();
      final lon = (wp['lon'] as num).toDouble();
      final geohash = Geohash.encode(lat, lon, precision: _regionPrecision);
      final prefix = geohash.substring(0, _regionPrecision);
      
      if (!regionMap.containsKey(prefix)) {
        regionMap[prefix] = {
          'minLat': lat,
          'maxLat': lat,
          'minLon': lon,
          'maxLon': lon,
        };
      } else {
        final bounds = regionMap[prefix]!;
        if (lat < bounds['minLat']!) bounds['minLat'] = lat;
        if (lat > bounds['maxLat']!) bounds['maxLat'] = lat;
        if (lon < bounds['minLon']!) bounds['minLon'] = lon;
        if (lon > bounds['maxLon']!) bounds['maxLon'] = lon;
      }
    }

    await database.transaction((txn) async {
      for (final entry in regionMap.entries) {
        final bounds = entry.value;
        
        await txn.rawInsert('''
          INSERT INTO ${LBDb.tVisitedRegions} 
            (geohash_prefix, min_lat, max_lat, min_lon, max_lon, last_visited)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(geohash_prefix) DO UPDATE SET
            min_lat = excluded.min_lat,
            max_lat = excluded.max_lat,
            min_lon = excluded.min_lon,
            max_lon = excluded.max_lon,
            last_visited = excluded.last_visited
        ''', [
          entry.key,
          bounds['minLat'],
          bounds['maxLat'],
          bounds['minLon'],
          bounds['maxLon'],
          now,
        ]);
      }
    });

    debugPrint('CellCache: Updated ${regionMap.length} visited regions');
  }

  Future<void> loadCellsForVisitedRegions({bool forceRefresh = false}) async {
    if (!Secrets.hasOpenCellIdKey) {
      debugPrint('CellCache: No API key - skipping cell loading');
      return;
    }

    final database = await _db.db;
    final regions = await database.query(LBDb.tVisitedRegions);

    for (final region in regions) {
      final geohashPrefix = region['geohash_prefix'] as String;
      final minLat = region['min_lat'] as double;
      final maxLat = region['max_lat'] as double;
      final minLon = region['min_lon'] as double;
      final maxLon = region['max_lon'] as double;

      await _loadCellsForBoundingBox(
        minLat: minLat,
        maxLat: maxLat,
        minLon: minLon,
        maxLon: maxLon,
        regionKey: geohashPrefix,
      );
    }

    final cellCount = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tCachedCells}'
    )) ?? 0;
    debugPrint('CellCache: Total cached cells: $cellCount');
  }

  Future<void> _loadCellsForBoundingBox({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required String regionKey,
  }) async {
    final database = await _db.db;
    final apiKey = Secrets.effectiveApiKey;
    
    int offset = 0;
    const limit = 50;

    while (offset < _maxCellsPerRegion && (offset ~/ limit) < _maxRequestsPerRegion) {
      final queryParams = {
        'key': apiKey,
        'BBOX': '$minLat,$minLon,$maxLat,$maxLon',
        'limit': limit.toString(),
        'offset': offset.toString(),
        'format': 'json',
      };

      try {
        final uri = Uri.parse(_apiBase).replace(queryParameters: queryParams);
        final response = await http.get(uri).timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) {
          debugPrint('CellCache: API returned ${response.statusCode} for region $regionKey');
          break;
        }

        final data = jsonDecode(response.body);
        if (data is! Map || data['cells'] == null) break;

        final cells = data['cells'] as List;
        if (cells.isEmpty) break;

        await database.transaction((txn) async {
          for (final cell in cells) {
            final mcc = cell['mcc'] as int?;
            final mnc = cell['mnc'] as int?;
            final lac = cell['lac'] as int?;
            final tac = cell['tac'] as int?;
            final cid = cell['cellid'] as int?;
            
            if (mcc == null || mnc == null || cid == null) continue;

            final radio = _normalizeRadio(cell['radio'] as String?);
            final cellKey = _buildCellKey(mcc, mnc, lac, tac, cid, radio);

            await txn.rawInsert('''
              INSERT INTO ${LBDb.tCachedCells}
                (cell_key, mcc, mnc, lac, tac, cid, radio, network_type, lat, lon, range_meters, samples, last_updated)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(cell_key) DO UPDATE SET
                lat = excluded.lat,
                lon = excluded.lon,
                range_meters = excluded.range_meters,
                samples = excluded.samples,
                last_updated = excluded.last_updated
            ''', [
              cellKey,
              mcc,
              mnc,
              lac,
              tac,
              cid,
              radio,
              cell['radio'],
              (cell['lat'] as num?)?.toDouble(),
              (cell['lon'] as num?)?.toDouble(),
              cell['range'] as int?,
              cell['samples'] as int?,
              DateTime.now().millisecondsSinceEpoch,
            ]);
          }
        });

        offset += cells.length;
        if (cells.length < limit) break;

      } catch (e) {
        debugPrint('CellCache: Error loading cells for $regionKey: $e');
        break;
      }
    }

    await database.rawUpdate('''
      UPDATE ${LBDb.tVisitedRegions} SET cell_count = (
        SELECT COUNT(*) FROM ${LBDb.tCachedCells} 
        WHERE lat BETWEEN (SELECT MIN(min_lat) FROM ${LBDb.tVisitedRegions} WHERE geohash_prefix = ?)
          AND (SELECT MAX(max_lat) FROM ${LBDb.tVisitedRegions} WHERE geohash_prefix = ?)
        AND lon BETWEEN (SELECT MIN(min_lon) FROM ${LBDb.tVisitedRegions} WHERE geohash_prefix = ?)
          AND (SELECT MAX(max_lon) FROM ${LBDb.tVisitedRegions} WHERE geohash_prefix = ?)
      ) WHERE geohash_prefix = ?
    ''', [regionKey, regionKey, regionKey, regionKey, regionKey]);
  }

  String _normalizeRadio(String? radio) {
    if (radio == null) return 'UNKNOWN';
    return radio.toUpperCase();
  }

  String _buildCellKey(int mcc, int mnc, int? lac, int? tac, int cid, String radio) {
    if (radio == 'CDMA') {
      return 'CDMA-$mcc-$mnc-${lac ?? cid}';
    }
    final areaCode = tac ?? lac ?? 0;
    return '$mcc-$mnc-$areaCode-$cid';
  }

  Future<CachedCell?> findCellByKey(String cellKey) async {
    if (cellKey.isEmpty) return null;
    
    final database = await _db.db;
    final rows = await database.query(
      LBDb.tCachedCells,
      where: 'cell_key = ?',
      whereArgs: [cellKey],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    return CachedCell(
      cellKey: row['cell_key'] as String,
      mcc: row['mcc'] as int?,
      mnc: row['mnc'] as int?,
      lac: row['lac'] as int?,
      tac: row['tac'] as int?,
      cid: row['cid'] as int?,
      radio: row['radio'] as String?,
      networkType: row['network_type'] as String?,
      lat: row['lat'] as double?,
      lon: row['lon'] as double?,
      rangeMeters: row['range_meters'] as int?,
      samples: row['samples'] as int?,
    );
  }

  SignalValidationResult validateSignalStrength(CachedCell cell, int observedRssi) {
    if (cell.lat == null || cell.lon == null) {
      return SignalValidationResult(
        isValid: false,
        expectedRssiMin: -120,
        expectedRssiMax: -50,
        observedRssi: observedRssi.toDouble(),
        reason: 'No cached location',
      );
    }

    const double defaultRange = 50000;
    final rangeMeters = cell.rangeMeters ?? defaultRange;
    final rangeKm = rangeMeters / 1000.0;

    double minRssi;
    double maxRssi;

    switch (cell.radio) {
      case 'LTE':
        minRssi = _calculateRssi(rangeKm, 1800);
        maxRssi = -40;
        break;
      case 'UMTS':
        minRssi = _calculateRssi(rangeKm, 2100);
        maxRssi = -30;
        break;
      case 'GSM':
        minRssi = _calculateRssi(rangeKm, 900);
        maxRssi = -30;
        break;
      case 'NR':
        minRssi = _calculateRssi(rangeKm, 3500);
        maxRssi = -35;
        break;
      case 'CDMA':
        minRssi = _calculateRssi(rangeKm, 800);
        maxRssi = -40;
        break;
      default:
        minRssi = _calculateRssi(rangeKm, 1900);
        maxRssi = -40;
    }

    final deviation = (observedRssi - maxRssi).abs() > (minRssi - observedRssi).abs() 
        ? observedRssi - maxRssi 
        : observedRssi - minRssi;
    
    final isValid = observedRssi >= minRssi && observedRssi <= maxRssi;

    return SignalValidationResult(
      isValid: isValid,
      expectedRssiMin: minRssi,
      expectedRssiMax: maxRssi,
      observedRssi: observedRssi.toDouble(),
      reason: isValid 
          ? null 
          : 'Signal ${observedRssi}dBm outside expected range ${minRssi.toInt()}-${maxRssi.toInt()}dBm (deviation: ${deviation.toInt()}dBm)',
    );
  }

  double _calculateRssi(double distanceKm, int frequencyMhz) {
    if (distanceKm < 0.1) distanceKm = 0.1;
    
    final distanceM = distanceKm * 1000;
    final frequencyHz = frequencyMhz * 1000000;
    
    // FSPL (dB) = 20*log10(d) + 20*log10(f) + 20*log10(4π/c)
    // Simplified: 20*log10(d_m) + 20*log10(f_Hz) - 147.55
    final freeSpaceLoss = 20 * math.log(distanceM) / math.ln10
        + 20 * math.log(frequencyHz.toDouble()) / math.ln10
        - 147.55;
    
    const typicalTxPower = 23;
    
    final expectedRssi = (typicalTxPower + freeSpaceLoss).clamp(-120.0, -50.0);
    
    return expectedRssi;
  }

  Future<int> getCachedCellCount() async {
    final database = await _db.db;
    return Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tCachedCells}'
    )) ?? 0;
  }

  Future<int> getVisitedRegionCount() async {
    final database = await _db.db;
    return Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tVisitedRegions}'
    )) ?? 0;
  }
}