import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';

class LBDatabase {
  LBDatabase._();
  static final LBDatabase instance = LBDatabase._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
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
      onConfigure: (db) async {
        await db.execute('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA synchronous = NORMAL');
        await db.execute('PRAGMA foreign_keys = ON');
      },
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
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migrations go here
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
    final batch = database.batch();
    for (final s in signals) {
      batch.insert(LBDb.tObservations, s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<LBSignal>> getObservationsBySession(String sessionId) async {
    final database = await db;
    final rows = await database.query(
      LBDb.tObservations,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'ts DESC',
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

  // ── Threat Events DAO ────────────────────────────────────────────────────

  Future<int> insertThreatEvent(LBThreatEvent event) async {
    final database = await db;
    return database.insert(LBDb.tThreatEvents, event.toMap());
  }

  Future<List<LBThreatEvent>> getThreatEvents({
    bool includeDismissed = false,
    int limit = 100,
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
}
