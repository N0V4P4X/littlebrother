import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/secrets.dart';

class CellIdComponents {
  final String mcc;
  final String mnc;
  final int? lac;
  final int? tac;
  final int? cid;
  final String networkType;

  const CellIdComponents({
    required this.mcc,
    required this.mnc,
    this.lac,
    this.tac,
    this.cid,
    required this.networkType,
  });

  bool get isValid => mcc.isNotEmpty && mnc.isNotEmpty && (lac != null || tac != null) && cid != null;
}

class CellLocationResult {
  final LatLng position;
  final double? radiusMeters;
  final String source;
  final DateTime timestamp;

  const CellLocationResult({
    required this.position,
    this.radiusMeters,
    required this.source,
    required this.timestamp,
  });
}

class OpenCellIdLookup {
  final LBDatabase _db = LBDatabase.instance;
  static const String _apiBase = 'https://opencellid.org/cell/get';
  static const Duration _cacheExpiry = Duration(days: 7);

  static CellIdComponents? parseCellKey(String cellKey) {
    if (cellKey.isEmpty) return null;

    final parts = cellKey.split('-');
    if (parts.length < 4) return null;

    if (parts[0] == 'CDMA') {
      return _parseCdma(parts);
    }

    if (parts.length < 4) return null;

    final mccStr = parts[0];
    final mncStr = parts[1];

    // Validate MCC/MNC are valid positive numbers
    final mcc = int.tryParse(mccStr);
    final mnc = int.tryParse(mncStr);
    if (mcc == null || mnc == null || mcc < 100 || mcc > 999 || mnc < 0 || mnc > 999) {
      debugPrint('OpenCellIdLookup: Invalid MCC/MNC in cell key: $cellKey');
      return null;
    }

    final isNr = parts.length == 4 && parts[2].length > 4;
    final isLte = int.tryParse(parts[2]) != null && int.tryParse(parts[3]) != null;

    if (isNr || isLte) {
      final tac = int.tryParse(parts[2]);
      final ci = int.tryParse(parts[3]);
      // Validate TAC and CID are positive and within valid ranges
      if (tac == null || tac <= 0 || ci == null || ci <= 0) {
        debugPrint('OpenCellIdLookup: Invalid TAC/CID in cell key: $cellKey');
        return null;
      }
      if (isNr && ci > 68719476735) {
        debugPrint('OpenCellIdLookup: CID exceeds NR range: $cellKey');
        return null;
      }
      if (!isNr && ci > 268435455) {
        debugPrint('OpenCellIdLookup: CID exceeds LTE range: $cellKey');
        return null;
      }
      return CellIdComponents(
        mcc: mccStr,
        mnc: mncStr,
        tac: tac,
        cid: ci,
        networkType: isNr ? 'NR' : 'LTE',
      );
    }

    final lac = int.tryParse(parts[2]);
    final cid = int.tryParse(parts[3]);
    // Validate LAC and CID are positive
    if (lac == null || lac <= 0 || cid == null || cid <= 0) {
      debugPrint('OpenCellIdLookup: Invalid LAC/CID in cell key: $cellKey');
      return null;
    }
    if (cid > 65535) {
      debugPrint('OpenCellIdLookup: CID exceeds GSM range: $cellKey');
      return null;
    }
    return CellIdComponents(
      mcc: mccStr,
      mnc: mncStr,
      lac: lac,
      cid: cid,
      networkType: parts.length >= 5 ? parts[4] : 'GSM',
    );
  }

  static CellIdComponents? _parseCdma(List<String> parts) {
    if (parts.length < 5) return null;
    final mcc = int.tryParse(parts[1]);
    final mnc = int.tryParse(parts[2]);
    if (mcc == null || mcc < 100 || mcc > 999) return null;
    if (mnc == null || mnc < 0 || mnc > 32767) return null;
    final nid = int.tryParse(parts[3]);
    final bid = int.tryParse(parts[4]);
    return CellIdComponents(
      mcc: parts[1],
      mnc: parts[2],
      lac: nid,
      cid: bid,
      networkType: 'CDMA',
    );
  }

  Future<CellLocationResult?> lookupCell(String cellKey, {bool forceRefresh = false}) async {
    if (!Secrets.hasOpenCellIdKey) {
      debugPrint('OpenCellIdLookup: No API key configured');
      return null;
    }

    final components = parseCellKey(cellKey);
    if (components == null || !components.isValid) {
      debugPrint('OpenCellIdLookup: Invalid cell key: $cellKey');
      return null;
    }

    if (!forceRefresh) {
      final cached = await _getCachedLocation(cellKey);
      if (cached != null) return cached;
    }

    try {
      final result = await _queryOpenCellId(components);
      if (result != null) {
        await _cacheLocation(cellKey, result);
      }
      return result;
    } catch (e) {
      debugPrint('OpenCellIdLookup error: $e');
      return null;
    }
  }

  Future<CellLocationResult?> _queryOpenCellId(CellIdComponents c) async {
    final apiKey = Secrets.effectiveApiKey;
    
    final radio = c.networkType.toUpperCase();
    final radioType = radio == 'NR' ? 'NR' : 
                      radio == 'LTE' ? 'LTE' : 
                      radio == 'CDMA' ? 'CDMA' : 
                      radio == 'UMTS' ? 'UMTS' : 'GSM';
    
    final queryParams = {
      'key': apiKey,
      'mcc': c.mcc,
      'mnc': c.mnc,
      'cellid': c.cid.toString(),
      'radio': radioType,
      if (c.lac != null) 'lac': c.lac.toString(),
      if (c.tac != null) 'tac': c.tac.toString(),
      'format': 'json',
    };

    final uri = Uri.parse(_apiBase).replace(queryParameters: queryParams);
    debugPrint('OpenCellIdLookup: Requesting cell lookup (key redacted)');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      debugPrint('OpenCellIdLookup: API returned ${response.statusCode}: ${response.body}');
      return null;
    }

    final data = jsonDecode(response.body);
    if (data is! Map || data.isEmpty) return null;

    final lat = data['lat'];
    final lon = data['lon'];
    if (lat == null || lon == null) return null;

    return CellLocationResult(
      position: LatLng(
        (lat as num).toDouble(),
        (lon as num).toDouble(),
      ),
      radiusMeters: (data['range'] as num?)?.toDouble(),
      source: 'opencellid',
      timestamp: DateTime.now(),
    );
  }

  Future<void> _cacheLocation(String cellKey, CellLocationResult result) async {
    final database = await _db.db;
    await database.rawInsert('''
      INSERT OR REPLACE INTO cell_id_cache (cell_key, lat, lon, radius, source, timestamp)
      VALUES (?, ?, ?, ?, ?, ?)
    ''', [
      cellKey,
      result.position.latitude,
      result.position.longitude,
      result.radiusMeters,
      result.source,
      result.timestamp.millisecondsSinceEpoch,
    ]);
  }

  Future<CellLocationResult?> _getCachedLocation(String cellKey) async {
    final database = await _db.db;
    final rows = await database.query(
      'cell_id_cache',
      where: 'cell_key = ?',
      whereArgs: [cellKey],
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int);
    
    if (DateTime.now().difference(timestamp) > _cacheExpiry) {
      return null;
    }

    return CellLocationResult(
      position: LatLng(row['lat'] as double, row['lon'] as double),
      radiusMeters: row['radius'] as double?,
      source: row['source'] as String,
      timestamp: timestamp,
    );
  }

  /// Table is created by DB migration v5. This method is kept for backward
  /// compatibility only and will be removed in a future release.
  @Deprecated('Table created by DB migration v5')
  Future<void> createCacheTable() async {
    final database = await _db.db;
    await database.execute('''
      CREATE TABLE IF NOT EXISTS cell_id_cache (
        cell_key TEXT PRIMARY KEY,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        radius REAL,
        source TEXT,
        timestamp INTEGER
      )
    ''');
  }
}
