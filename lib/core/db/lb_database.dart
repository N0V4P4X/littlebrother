import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/db/geohash.dart';
import 'package:littlebrother/core/models/lb_aggregate_map.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/modules/gps/gps_tracker.dart';

class LBDatabase {
  LBDatabase._();
  static final LBDatabase instance = LBDatabase._();

  Database? _db;
  Completer<Database>? _dbCompleter;

  Future<Database> get db async {
    if (_db != null) return _db!;
    if (_dbCompleter != null) return _dbCompleter!.future;
    _dbCompleter = Completer<Database>();
    try {
      _db = await _open();
      _dbCompleter!.complete(_db);
    } catch (e) {
      _dbCompleter!.completeError(e);
      _dbCompleter = null;
      rethrow;
    }
    return _db!;
  }

  // ── Schema ───────────────────────────────────────────────────────────────

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, LBDb.name);

    return openDatabase(
      path,
      version: LBDb.version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${LBDb.tSessions} (
        id                TEXT PRIMARY KEY,
        started_at        INTEGER NOT NULL,
        ended_at          INTEGER,
        observation_count INTEGER NOT NULL DEFAULT 0,
        threat_count      INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LBDb.tObservations} (
        id            TEXT PRIMARY KEY,
        session_id    TEXT NOT NULL,
        signal_type   TEXT NOT NULL,
        identifier    TEXT NOT NULL,
        display_name  TEXT NOT NULL,
        rssi          INTEGER NOT NULL,
        distance_m    REAL NOT NULL,
        risk_score    INTEGER NOT NULL,
        lat           REAL,
        lon           REAL,
        metadata_json TEXT NOT NULL,
        ts            INTEGER NOT NULL,
        threat_flag   INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES ${LBDb.tSessions}(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_obs_identifier ON ${LBDb.tObservations}(identifier, ts);
    ''');
    await db.execute('''
      CREATE INDEX idx_obs_session ON ${LBDb.tObservations}(session_id);
    ''');
    await db.execute('''
      CREATE INDEX idx_obs_type ON ${LBDb.tObservations}(signal_type, ts);
    ''');

    await db.execute('''
      CREATE TABLE ${LBDb.tKnownDevices} (
        identifier         TEXT PRIMARY KEY,
        signal_type        TEXT NOT NULL,
        display_name       TEXT NOT NULL,
        vendor             TEXT NOT NULL DEFAULT '',
        first_seen         INTEGER NOT NULL,
        last_seen          INTEGER NOT NULL,
        observation_count  INTEGER NOT NULL DEFAULT 1,
        threat_flag        INTEGER NOT NULL DEFAULT 0,
        notes              TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_known_flag ON ${LBDb.tKnownDevices}(threat_flag);
    ''');

    await db.execute('''
      CREATE TABLE ${LBDb.tCellBaseline} (
        geohash              TEXT NOT NULL,
        cell_key             TEXT NOT NULL,
        network_type         TEXT NOT NULL,
        avg_rssi             REAL NOT NULL,
        first_seen           INTEGER NOT NULL,
        observation_count    INTEGER NOT NULL DEFAULT 1,
        opencellid_verified  INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (geohash, cell_key)
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LBDb.tThreatEvents} (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        threat_type   TEXT NOT NULL,
        severity      INTEGER NOT NULL,
        identifier    TEXT NOT NULL,
        evidence_json TEXT NOT NULL,
        lat           REAL,
        lon           REAL,
        ts            INTEGER NOT NULL,
        dismissed     INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_threats_ts ON ${LBDb.tThreatEvents}(ts DESC);
    ''');
    await db.execute('''
      CREATE INDEX idx_threats_dismissed ON ${LBDb.tThreatEvents}(dismissed, severity);
    ''');

    await db.execute('''
      CREATE TABLE ${LBDb.tAggregateCells} (
        geohash       TEXT NOT NULL,
        precision     INTEGER NOT NULL DEFAULT 7,
        device_count  INTEGER NOT NULL DEFAULT 0,
        obs_count     INTEGER NOT NULL DEFAULT 0,
        worst_flag    INTEGER NOT NULL DEFAULT 0,
        wifi_count    INTEGER NOT NULL DEFAULT 0,
        ble_count     INTEGER NOT NULL DEFAULT 0,
        cell_count    INTEGER NOT NULL DEFAULT 0,
        most_recent   INTEGER NOT NULL,
        PRIMARY KEY (geohash, precision)
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LBDb.tDeviceWaypoints} (
        identifier    TEXT PRIMARY KEY,
        signal_type   TEXT NOT NULL,
        display_name  TEXT,
        lat           REAL NOT NULL,
        lon           REAL NOT NULL,
        accuracy_m    REAL,
        rssi_avg      REAL,
        rssi_count    INTEGER DEFAULT 0,
        rssi_min      INTEGER,
        rssi_max      INTEGER,
        first_seen    INTEGER NOT NULL,
        last_seen     INTEGER NOT NULL,
        obs_count     INTEGER DEFAULT 1,
        threat_flag   INTEGER DEFAULT 0,
        vendor        TEXT,
        metadata_json TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_waypoints_type ON ${LBDb.tDeviceWaypoints}(signal_type);
    ''');
    await db.execute('''
      CREATE INDEX idx_waypoints_location ON ${LBDb.tDeviceWaypoints}(lat, lon);
    ''');

    try {
      await db.execute('PRAGMA foreign_keys = ON');
    } catch (_) {
      // PRAGMA may not be supported on all SQLite builds
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE ${LBDb.tAggregateCells} (
          geohash       TEXT NOT NULL,
          precision     INTEGER NOT NULL DEFAULT 7,
          device_count  INTEGER NOT NULL DEFAULT 0,
          obs_count     INTEGER NOT NULL DEFAULT 0,
          worst_flag    INTEGER NOT NULL DEFAULT 0,
          wifi_count    INTEGER NOT NULL DEFAULT 0,
          ble_count     INTEGER NOT NULL DEFAULT 0,
          cell_count    INTEGER NOT NULL DEFAULT 0,
          most_recent   INTEGER NOT NULL,
          PRIMARY KEY (geohash, precision)
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE ${LBDb.tObservations} ADD COLUMN geohash TEXT');
      await db.execute('CREATE INDEX idx_obs_geohash ON ${LBDb.tObservations}(geohash)');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE ${LBDb.tDeviceWaypoints} (
          identifier    TEXT PRIMARY KEY,
          signal_type   TEXT NOT NULL,
          display_name  TEXT,
          lat           REAL NOT NULL,
          lon           REAL NOT NULL,
          accuracy_m    REAL,
          rssi_avg      REAL,
          rssi_count    INTEGER DEFAULT 0,
          rssi_min      INTEGER,
          rssi_max      INTEGER,
          first_seen    INTEGER NOT NULL,
          last_seen     INTEGER NOT NULL,
          obs_count     INTEGER DEFAULT 1,
          threat_flag   INTEGER DEFAULT 0,
          vendor        TEXT,
          metadata_json TEXT
        )
      ''');
      await db.execute('''
        CREATE INDEX idx_waypoints_type ON ${LBDb.tDeviceWaypoints}(signal_type);
      ''');
      await db.execute('''
        CREATE INDEX idx_waypoints_location ON ${LBDb.tDeviceWaypoints}(lat, lon);
      ''');
    }
  }

  // ── Session DAO ──────────────────────────────────────────────────────────

  Future<void> insertSession(LBSession session) async {
    final database = await db;
    await database.insert(LBDb.tSessions, session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSession(LBSession session) async {
    final database = await db;
    await database.update(
      LBDb.tSessions,
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<List<LBSession>> getSessions({int limit = 50}) async {
    final database = await db;
    final rows = await database.query(
      LBDb.tSessions,
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(LBSession.fromMap).toList();
  }

  // ── Observation DAO ──────────────────────────────────────────────────────

  Future<void> insertObservationBatch(List<LBSignal> signals) async {
    if (signals.isEmpty) return;
    final database = await db;
    await database.transaction((txn) async {
      try {
        final batch = txn.batch();
        
        for (final s in signals) {
          final map = s.toMap();
          if (s.lat != null && s.lon != null) {
            map['geohash'] = Geohash.encode(s.lat!, s.lon!, precision: 7);
          }
          
          // Upsert device_waypoints table for fast map queries
          if (s.lat != null && s.lon != null) {
            final now = s.timestamp.millisecondsSinceEpoch;
            final vendor = s.metadata['vendor'] as String?;
            final rssi = s.rssi;
            
            batch.rawInsert('''
              INSERT INTO ${LBDb.tDeviceWaypoints} (
                identifier, signal_type, display_name, lat, lon,
                accuracy_m, rssi_avg, rssi_count, rssi_min, rssi_max,
                first_seen, last_seen, obs_count, threat_flag, vendor, metadata_json
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(identifier) DO UPDATE SET
                lat = excluded.lat,
                lon = excluded.lon,
                rssi_avg = CASE 
                  WHEN ${LBDb.tDeviceWaypoints}.rssi_count > 0 THEN (${LBDb.tDeviceWaypoints}.rssi_avg * ${LBDb.tDeviceWaypoints}.rssi_count + excluded.rssi_avg * excluded.rssi_count) / (${LBDb.tDeviceWaypoints}.rssi_count + excluded.rssi_count)
                  ELSE excluded.rssi_avg
                END,
                rssi_count = ${LBDb.tDeviceWaypoints}.rssi_count + excluded.rssi_count,
                rssi_min = MIN(${LBDb.tDeviceWaypoints}.rssi_min, excluded.rssi_min),
                rssi_max = MAX(${LBDb.tDeviceWaypoints}.rssi_max, excluded.rssi_max),
                last_seen = MAX(${LBDb.tDeviceWaypoints}.last_seen, excluded.last_seen),
                obs_count = ${LBDb.tDeviceWaypoints}.obs_count + excluded.obs_count,
                threat_flag = MAX(${LBDb.tDeviceWaypoints}.threat_flag, excluded.threat_flag),
                metadata_json = excluded.metadata_json
            ''', [
              s.identifier, s.signalType, s.displayName, s.lat, s.lon,
              null, rssi, 1, rssi, rssi,
              now, now, 1, s.threatFlag, vendor, jsonEncode(s.metadata),
            ]);
          }
          
          // Still insert into observations for history/timeline
          batch.insert(LBDb.tObservations, map,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      } catch (e) {
        debugPrint('LB_DB insertObservationBatch error: $e');
        rethrow;
      }
    });
  }

  Future<List<LBSignal>> getObservationsBySession(String sessionId, {int? limit, int? offset}) async {
    final database = await db;
    final rows = await database.query(
      LBDb.tObservations,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'ts DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(LBSignal.fromMap).toList();
  }

  Future<List<LBSignal>> getRecentByType(String signalType, {int limitMs = 60000}) async {
    final database = await db;
    final since = DateTime.now().millisecondsSinceEpoch - limitMs;
    final rows = await database.query(
      LBDb.tObservations,
      where: 'signal_type = ? AND ts >= ?',
      whereArgs: [signalType, since],
      orderBy: 'ts DESC',
    );
    return rows.map(LBSignal.fromMap).toList();
  }

  Future<List<LBSignal>> getRssiHistory(String identifier, {int limit = 100}) async {
    final database = await db;
    final rows = await database.query(
      LBDb.tObservations,
      columns: ['ts', 'rssi', 'distance_m', 'lat', 'lon'],
      where: 'identifier = ?',
      whereArgs: [identifier],
      orderBy: 'ts DESC',
      limit: limit,
    );
    // Minimal reconstruction for graphing
    return rows.map((m) => LBSignal(
      id: '',
      sessionId: '',
      signalType: '',
      identifier: identifier,
      displayName: '',
      rssi: m['rssi'] as int,
      distanceM: (m['distance_m'] as num).toDouble(),
      riskScore: 0,
      lat: m['lat'] != null ? (m['lat'] as num).toDouble() : null,
      lon: m['lon'] != null ? (m['lon'] as num).toDouble() : null,
      metadata: {},
      timestamp: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
    )).toList();
  }

  Future<void> purgeOlderThan(Duration age) async {
    final database = await db;
    final cutoff = DateTime.now().subtract(age).millisecondsSinceEpoch;
    await database.delete(
      LBDb.tObservations,
      where: 'ts < ?',
      whereArgs: [cutoff],
    );
  }

  // ── Known Devices DAO ────────────────────────────────────────────────────

  Future<void> upsertKnownDevice(LBSignal signal, String vendor) async {
    final database = await db;
    final now = signal.timestamp.millisecondsSinceEpoch;
    await database.rawInsert('''
      INSERT INTO ${LBDb.tKnownDevices}
        (identifier, signal_type, display_name, vendor, first_seen, last_seen, observation_count, threat_flag)
      VALUES (?, ?, ?, ?, ?, ?, 1, ?)
      ON CONFLICT(identifier) DO UPDATE SET
        display_name       = excluded.display_name,
        vendor             = CASE WHEN vendor = '' THEN excluded.vendor ELSE vendor END,
        last_seen          = excluded.last_seen,
        observation_count  = observation_count + 1
    ''', [
      signal.identifier,
      signal.signalType,
      signal.displayName,
      vendor,
      now, now,
      signal.threatFlag,
    ]);
  }

  Future<Map<String, int>> getKnownDeviceThreatFlags(List<String> identifiers) async {
    if (identifiers.isEmpty) return {};
    final database = await db;
    final placeholders = identifiers.map((_) => '?').join(',');
    final rows = await database.rawQuery(
      'SELECT identifier, threat_flag FROM ${LBDb.tKnownDevices} WHERE identifier IN ($placeholders)',
      identifiers,
    );
    return {for (final r in rows) r['identifier'] as String: r['threat_flag'] as int};
  }

  Future<void> setThreatFlag(String identifier, int flag, {String notes = ''}) async {
    final database = await db;
    await database.update(
      LBDb.tKnownDevices,
      {'threat_flag': flag, 'notes': notes},
      where: 'identifier = ?',
      whereArgs: [identifier],
    );
  }

  // ── Cell Baseline DAO ────────────────────────────────────────────────────

  Future<void> upsertCellBaseline({
    required String geohash,
    required String cellKey,
    required String networkType,
    required int rssi,
  }) async {
    final database = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.rawInsert('''
      INSERT INTO ${LBDb.tCellBaseline}
        (geohash, cell_key, network_type, avg_rssi, first_seen, observation_count)
      VALUES (?, ?, ?, ?, ?, 1)
      ON CONFLICT(geohash, cell_key) DO UPDATE SET
        avg_rssi          = (avg_rssi * observation_count + excluded.avg_rssi) / (observation_count + 1),
        observation_count = observation_count + 1,
        network_type      = excluded.network_type
    ''', [geohash, cellKey, networkType, rssi.toDouble(), now]);
  }

  Future<Map<String, dynamic>?> getCellBaseline(String geohash, String cellKey) async {
    final database = await db;
    final rows = await database.query(
      LBDb.tCellBaseline,
      where: 'geohash = ? AND cell_key = ?',
      whereArgs: [geohash, cellKey],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getCellsAtGeohash(String geohash) async {
    final database = await db;
    return database.query(
      LBDb.tCellBaseline,
      where: 'geohash = ?',
      whereArgs: [geohash],
    );
  }

  Future<List<CellTower>> getCellTowers({
    int? minSeverity,
    int? sinceMs,
    bool includeNeighbors = false,
    int limit = 500,
  }) async {
    final database = await db;
    
    final conditions = <String>["signal_type = 'cell'"];
    final args = <dynamic>[];
    
    if (includeNeighbors) {
      conditions.clear();
      conditions.add("signal_type IN ('cell', 'cell_neighbor')");
    }
    
    if (sinceMs != null) {
      conditions.add('last_seen >= ?');
      args.add(sinceMs);
    }

    final where = conditions.join(' AND ');

    final rows = await database.rawQuery('''
      SELECT 
        identifier as cell_key,
        display_name,
        metadata_json,
        rssi_avg as avg_rssi,
        rssi_max as rssi,
        obs_count,
        first_seen,
        last_seen,
        lat,
        lon,
        threat_flag as worst_flag,
        0 as max_severity
      FROM ${LBDb.tDeviceWaypoints}
      WHERE $where
      ORDER BY obs_count DESC
      LIMIT ?
    ''', [...args, limit]);

    return rows.map((row) {
      final meta = row['metadata_json'] != null 
          ? _parseJson(row['metadata_json'] as String)
          : <String, dynamic>{};
      
      return CellTower(
        cellKey:         (row['cell_key'] as String?) ?? '',
        displayName:     row['display_name']?.toString() ?? '',
        pci:             (meta['pci'] as num?)?.toInt() ?? -1,
        tac:             (meta['tac'] as num?)?.toInt() ?? -1,
        networkType:     meta['network_type_name'] as String? ?? 
                         (meta['type'] as String?) ?? '?',
        band:            meta['band'] as String?,
        operator:        meta['operator'] as String?,
        isServing:       (meta['is_serving'] as bool?) ?? false,
        position:         LatLng((row['lat'] as num?)?.toDouble() ?? 0.0, (row['lon'] as num?)?.toDouble() ?? 0.0),
        observationCount: (row['obs_count'] as num?)?.toInt() ?? 0,
        worstThreat:     (row['max_severity'] as num?)?.toInt() ?? 0,
        worstThreatFlag: (row['worst_flag'] as num?)?.toInt() ?? 0,
        rsrp:            (meta['rsrp'] as num?)?.toInt() ?? -120,
        rsrq:            (meta['rsrq'] as num?)?.toInt() ?? -20,
        sinr:            (meta['sinr'] as num?)?.toInt() ?? -20,
        firstSeen:       DateTime.fromMillisecondsSinceEpoch((row['first_seen'] as num?)?.toInt() ?? 0),
        lastSeen:        DateTime.fromMillisecondsSinceEpoch((row['last_seen'] as num?)?.toInt() ?? 0),
      );
    }).toList();
  }

  Map<String, dynamic> _parseJson(String json) {
    try {
      return Map<String, dynamic>.from(
        const JsonDecoder().convert(json) as Map,
      );
    } catch (_) {
      return {};
    }
  }

  Future<List<WifiDevice>> getWifiDevices({
    int? minSeverity,
    int? sinceMs,
    int limit = 500,
  }) async {
    final database = await db;
    
    final conditions = <String>["signal_type = 'wifi'"];
    final args = <dynamic>[];
    
    if (sinceMs != null) {
      conditions.add('last_seen >= ?');
      args.add(sinceMs);
    }

    final where = conditions.join(' AND ');

    final rows = await database.rawQuery('''
      SELECT 
        identifier as bssid,
        display_name as ssid,
        metadata_json,
        rssi_avg as avg_rssi,
        rssi_max as rssi,
        obs_count,
        first_seen,
        last_seen,
        lat,
        lon,
        threat_flag as worst_flag,
        0 as max_severity,
        vendor
      FROM ${LBDb.tDeviceWaypoints}
      WHERE $where
      ORDER BY obs_count DESC
      LIMIT ?
    ''', [...args, limit]);

    return rows.map((row) {
      final meta = row['metadata_json'] != null 
          ? _parseJson(row['metadata_json'] as String)
          : <String, dynamic>{};
      
      return WifiDevice(
        bssid:            (row['bssid'] as String?) ?? '',
        ssid:             row['ssid']?.toString() ?? '',
        vendor:           (row['vendor'] as String?) ?? meta['vendor'] as String? ?? '',
        position:         LatLng((row['lat'] as num?)?.toDouble() ?? 0.0, (row['lon'] as num?)?.toDouble() ?? 0.0),
        observationCount: (row['obs_count'] as num?)?.toInt() ?? 0,
        worstThreat:     (row['max_severity'] as num?)?.toInt() ?? 0,
        worstThreatFlag: (row['worst_flag'] as num?)?.toInt() ?? 0,
        rssi:            (row['rssi'] as num?)?.toInt() ?? -100,
        channel:         (meta['channel'] as num?)?.toInt(),
        security:        meta['capabilities'] as String?,
        firstSeen:       DateTime.fromMillisecondsSinceEpoch((row['first_seen'] as num?)?.toInt() ?? 0),
        lastSeen:        DateTime.fromMillisecondsSinceEpoch((row['last_seen'] as num?)?.toInt() ?? 0),
      );
    }).toList();
  }

  Future<List<BleDevice>> getBleDevices({
    int? minSeverity,
    int? sinceMs,
    int limit = 500,
  }) async {
    final database = await db;
    
    final conditions = <String>["signal_type = 'ble'"];
    final args = <dynamic>[];
    
    if (sinceMs != null) {
      conditions.add('last_seen >= ?');
      args.add(sinceMs);
    }

    final where = conditions.join(' AND ');

    final rows = await database.rawQuery('''
      SELECT 
        identifier as mac,
        display_name,
        metadata_json,
        rssi_avg as avg_rssi,
        rssi_max as rssi,
        obs_count,
        first_seen,
        last_seen,
        lat,
        lon,
        threat_flag as worst_flag,
        0 as max_severity
      FROM ${LBDb.tDeviceWaypoints}
      WHERE $where
      ORDER BY obs_count DESC
      LIMIT ?
    ''', [...args, limit]);

    return rows.map((row) {
      final meta = row['metadata_json'] != null 
          ? _parseJson(row['metadata_json'] as String)
          : <String, dynamic>{};
      
      return BleDevice(
        mac:              (row['mac'] as String?) ?? '',
        displayName:      row['display_name']?.toString() ?? '',
        position:         LatLng((row['lat'] as num?)?.toDouble() ?? 0.0, (row['lon'] as num?)?.toDouble() ?? 0.0),
        observationCount: (row['obs_count'] as num?)?.toInt() ?? 0,
        worstThreat:     (row['max_severity'] as num?)?.toInt() ?? 0,
        worstThreatFlag: (row['worst_flag'] as num?)?.toInt() ?? 0,
        rssi:            (row['rssi'] as num?)?.toInt() ?? -100,
        isTracker:       meta['is_tracker'] as bool? ?? false,
        txPower:         (meta['tx_power'] as num?)?.toInt(),
        firstSeen:       DateTime.fromMillisecondsSinceEpoch((row['first_seen'] as num?)?.toInt() ?? 0),
        lastSeen:        DateTime.fromMillisecondsSinceEpoch((row['last_seen'] as num?)?.toInt() ?? 0),
      );
    }).toList();
  }

  // ── Threat Events DAO ────────────────────────────────────────────────────

  Future<int> insertThreatEvent(LBThreatEvent event) async {
    final database = await db;
    return database.insert(LBDb.tThreatEvents, event.toMap());
  }

  Future<List<LBThreatEvent>> getThreatEvents({
    bool includeDismissed = false,
    int limit = 100,
    int? offset,
    int? minSeverity,
  }) async {
    final database = await db;
    final conditions = <String>[];
    final args = <dynamic>[];
    if (!includeDismissed) {
      conditions.add('dismissed = 0');
    }
    if (minSeverity != null) {
      conditions.add('severity >= ?');
      args.add(minSeverity);
    }
    final where = conditions.isEmpty ? null : conditions.join(' AND ');
    final rows = await database.query(
      LBDb.tThreatEvents,
      where: where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'ts DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(LBThreatEvent.fromMap).toList();
  }

  Future<void> dismissThreatEvent(int id) async {
    final database = await db;
    await database.update(
      LBDb.tThreatEvents,
      {'dismissed': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Aggregate Map DAO ───────────────────────────────────────────────────

  static int? _lastRebuildMs;
  static const _rebuildIntervalMs = 5 * 60 * 1000; // 5 minutes

  Future<void> migrateGeohashForExistingObservations() async {
    final database = await db;
    
    // First try: update records that already have geohash in metadata JSON
    final countFromMeta = await database.rawUpdate('''
      UPDATE ${LBDb.tObservations}
      SET geohash = SUBSTR(metadata_json, INSTR(metadata_json, '"geohash":"') + 11, 7)
      WHERE geohash IS NULL
        AND lat IS NOT NULL
        AND lon IS NOT NULL
        AND metadata_json LIKE '%geohash%'
    ''');
    debugPrint('LB_DB: Migrated $countFromMeta observations from metadata JSON');

    // Second: compute geohash from lat/lon for records without it
    final missingCount = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tObservations} WHERE geohash IS NULL AND lat IS NOT NULL AND lon IS NOT NULL'
    )) ?? 0;
    
    if (missingCount > 0) {
      debugPrint('LB_DB: Need to compute geohash for $missingCount observations');
      // This would require reading all records and updating - expensive but necessary
      // For now, we'll let the rebuildAggregateCells handle this via the fallback SQL
    }
  }

  Future<void> rebuildAggregateCells({int precision = 7, bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && _lastRebuildMs != null && (now - _lastRebuildMs!) < _rebuildIntervalMs) {
      return;
    }
    _lastRebuildMs = now;
    
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        LBDb.tAggregateCells,
        where: 'precision = ?',
        whereArgs: [precision],
      );

      await txn.rawInsert('''
        INSERT INTO ${LBDb.tAggregateCells}
          (geohash, precision, device_count, obs_count, worst_flag,
           wifi_count, ble_count, cell_count, most_recent)
        SELECT
          COALESCE(
            o.geohash,
            CASE 
              WHEN INSTR(o.metadata_json, '"geohash":"') > 0 THEN SUBSTR(o.metadata_json, INSTR(o.metadata_json, '"geohash":"') + 11, $precision)
              WHEN INSTR(o.metadata_json, '"geohash": "') > 0 THEN SUBSTR(o.metadata_json, INSTR(o.metadata_json, '"geohash": "') + 12, $precision)
              ELSE NULL
            END
          ) AS geohash,
          $precision AS p,
          COUNT(DISTINCT o.identifier) AS device_count,
          COUNT(*) AS obs_count,
          MAX(o.threat_flag) AS worst_flag,
          SUM(CASE WHEN o.signal_type = 'wifi' THEN 1 ELSE 0 END) AS wifi_count,
          SUM(CASE WHEN o.signal_type = 'ble' THEN 1 ELSE 0 END) AS ble_count,
          SUM(CASE WHEN o.signal_type IN ('cell','cell_neighbor') THEN 1 ELSE 0 END) AS cell_count,
          MAX(o.ts) AS most_recent
        FROM ${LBDb.tObservations} o
        WHERE (o.lat IS NOT NULL AND o.lon IS NOT NULL)
           OR (o.geohash IS NOT NULL)
           OR (o.metadata_json LIKE '%geohash%')
        GROUP BY p, geohash
      ''');
    });
    
    // Log statistics for debugging
    final totalObs = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tObservations}'
    )) ?? 0;
    final withLatLon = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tObservations} WHERE lat IS NOT NULL AND lon IS NOT NULL'
    )) ?? 0;
    final withGeohash = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tObservations} WHERE geohash IS NOT NULL'
    )) ?? 0;
    final gridCells = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tAggregateCells} WHERE precision = ?', [precision]
    )) ?? 0;
    
    debugPrint('LB_DB: Rebuild complete - $totalObs total obs, $withLatLon with lat/lon, $withGeohash with geohash, $gridCells grid cells');
  }

  Future<List<Map<String, dynamic>>> getAggregateCells({
    int precision = 7,
    int? minObs,
    int? minThreatFlag,
    int? sinceMs,
    int? limit,
    int? offset,
  }) async {
    final database = await db;
    final conditions = <String>['precision = ?'];
    final args = <dynamic>[precision];

    if (minObs != null) {
      conditions.add('obs_count >= ?');
      args.add(minObs);
    }
    if (sinceMs != null) {
      conditions.add('most_recent >= ?');
      args.add(sinceMs);
    }
    if (minThreatFlag != null) {
      conditions.add('worst_flag >= ?');
      args.add(minThreatFlag);
    }

    final rows = await database.query(
      LBDb.tAggregateCells,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'obs_count DESC',
      limit: limit,
      offset: offset,
    );

    return rows;
  }

  Future<List<Map<String, dynamic>>> getDevicesAtCell(String geohash, {int precision = 7}) async {
    final database = await db;
    return database.rawQuery('''
      SELECT
        o.identifier,
        o.display_name,
        o.signal_type,
        k.vendor,
        COUNT(*) AS obs_count,
        COUNT(DISTINCT SUBSTR(o.geohash, 1, $precision)) AS cell_count,
        MAX(o.threat_flag) AS worst_flag,
        MIN(o.ts) AS first_seen,
        MAX(o.ts) AS last_seen
      FROM ${LBDb.tObservations} o
      LEFT JOIN ${LBDb.tKnownDevices} k ON k.identifier = o.identifier
      WHERE o.geohash IS NOT NULL AND SUBSTR(o.geohash, 1, $precision) = SUBSTR(?, 1, $precision)
      GROUP BY o.identifier
      ORDER BY obs_count DESC
    ''', [geohash]);
  }

  // ── Stats ────────────────────────────────────────────────────────────────

  Future<Map<String, int>> getSessionStats(String sessionId) async {
    final database = await db;
    final result = await database.rawQuery('''
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN signal_type = 'wifi' THEN 1 ELSE 0 END) as wifi,
        SUM(CASE WHEN signal_type = 'ble' THEN 1 ELSE 0 END) as ble,
        SUM(CASE WHEN signal_type IN ('cell','cell_neighbor') THEN 1 ELSE 0 END) as cell,
        SUM(CASE WHEN threat_flag > 0 THEN 1 ELSE 0 END) as threats
      FROM ${LBDb.tObservations}
      WHERE session_id = ?
    ''', [sessionId]);
    final row = result.first;
    return {
      'total':   row['total'] as int? ?? 0,
      'wifi':    row['wifi'] as int? ?? 0,
      'ble':     row['ble'] as int? ?? 0,
      'cell':    row['cell'] as int? ?? 0,
      'threats': row['threats'] as int? ?? 0,
    };
  }

  Future<void> close() async {
    final database = await db;
    await database.close();
    _db = null;
  }

  Future<Map<String, dynamic>> getGpsStatus() async {
    final gps = GpsTracker.instance;
    return {
      'isRunning': gps.isRunning,
      'hasFreshFix': gps.hasFreshFix,
      'lastPosition': gps.lastPosition != null 
          ? {'lat': gps.lastPosition!.latitude, 'lon': gps.lastPosition!.longitude}
          : null,
      'lastError': gps.lastError,
    };
  }

  Future<Map<String, int>> getObservationStats() async {
    final database = await db;
    final total = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tObservations}'
    )) ?? 0;
    final withLatLon = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tObservations} WHERE lat IS NOT NULL AND lon IS NOT NULL'
    )) ?? 0;
    final withGeohash = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tObservations} WHERE geohash IS NOT NULL'
    )) ?? 0;
    final gridCells = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tAggregateCells}'
    )) ?? 0;
    
    return {
      'total': total,
      'withLatLon': withLatLon,
      'withGeohash': withGeohash,
      'gridCells': gridCells,
    };
  }

  // ── Device Waypoints DAO ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getWaypoints({
    String? signalType,
    int? sinceMs,
    int? minObsCount,
    int? threatFlag,
    int limit = 500,
  }) async {
    final database = await db;
    final conditions = <String>[];
    final args = <dynamic>[];

    if (signalType != null) {
      conditions.add('signal_type = ?');
      args.add(signalType);
    }
    if (sinceMs != null) {
      conditions.add('last_seen >= ?');
      args.add(sinceMs);
    }
    if (minObsCount != null) {
      conditions.add('obs_count >= ?');
      args.add(minObsCount);
    }
    if (threatFlag != null) {
      conditions.add('threat_flag >= ?');
      args.add(threatFlag);
    }

    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    return database.rawQuery('''
      SELECT * FROM ${LBDb.tDeviceWaypoints}
      $where
      ORDER BY obs_count DESC
      LIMIT ?
    ''', [...args, limit]);
  }

  Future<int> getWaypointCount() async {
    final database = await db;
    return Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tDeviceWaypoints}'
    )) ?? 0;
  }

  Future<int> getWaypointCountByType(String signalType) async {
    final database = await db;
    return Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM ${LBDb.tDeviceWaypoints} WHERE signal_type = ?',
      [signalType]
    )) ?? 0;
  }

  Future<void> deleteAllWaypoints() async {
    final database = await db;
    await database.delete(LBDb.tDeviceWaypoints);
  }

  Future<void> migrateObservationsToWaypoints() async {
    final database = await db;
    
    // Get observations with location data and aggregate by identifier
    await database.rawInsert('''
      INSERT OR IGNORE INTO ${LBDb.tDeviceWaypoints} (
        identifier, signal_type, display_name, lat, lon,
        rssi_avg, rssi_count, rssi_min, rssi_max,
        first_seen, last_seen, obs_count, threat_flag, vendor, metadata_json
      )
      SELECT 
        o.identifier,
        o.signal_type,
        MAX(o.display_name) as display_name,
        MAX(o.lat) as lat,
        MAX(o.lon) as lon,
        AVG(CAST(o.rssi AS REAL)) as rssi_avg,
        COUNT(*) as rssi_count,
        MIN(o.rssi) as rssi_min,
        MAX(o.rssi) as rssi_max,
        MIN(o.ts) as first_seen,
        MAX(o.ts) as last_seen,
        COUNT(*) as obs_count,
        MAX(o.threat_flag) as threat_flag,
        '' as vendor,
        MAX(o.metadata_json) as metadata_json
      FROM ${LBDb.tObservations} o
      WHERE o.lat IS NOT NULL AND o.lon IS NOT NULL
      GROUP BY o.identifier, o.signal_type
    ''');
    
    debugPrint('LB_DB: Migrated observations to waypoints');
  }

  Future<void> cleanupObservationsWithoutLocation() async {
    final database = await db;
    final deleted = await database.delete(
      LBDb.tObservations,
      where: 'lat IS NULL AND lon IS NULL AND (geohash IS NULL OR geohash = "")',
    );
    debugPrint('LB_DB: Cleaned up $deleted observations without location');
  }
}
