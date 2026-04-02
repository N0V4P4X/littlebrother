import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ServerDb {
  static final ServerDb instance = ServerDb._();
  ServerDb._();

  Database? _db;
  static const String _name = 'littlebrother_server.db';
  static const int _version = 1;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'littlebrother_server', _name);
    
    return openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Signal sources with trust
    await db.execute('''
      CREATE TABLE signal_sources (
        id            TEXT PRIMARY KEY,
        name          TEXT NOT NULL,
        source_type   TEXT NOT NULL,
        trust_weight  REAL DEFAULT 0.0,
        is_clean      INTEGER DEFAULT 1,
        enabled       INTEGER DEFAULT 1,
        first_seen    INTEGER NOT NULL,
        last_seen     INTEGER NOT NULL
      )
    ''');

    // Dirty signals (raw, unvalidated)
    await db.execute('''
      CREATE TABLE dirty_signals (
        id            TEXT PRIMARY KEY,
        source_id     TEXT REFERENCES signal_sources(id),
        signal_type   TEXT NOT NULL,
        identifier   TEXT NOT NULL,
        display_name  TEXT,
        rssi          INTEGER,
        lat           REAL,
        lon           REAL,
        metadata_json TEXT,
        ts            INTEGER NOT NULL,
        validated     INTEGER DEFAULT 0
      )
    ''');

    await db.execute('CREATE INDEX idx_dirty_source ON dirty_signals(source_id)');
    await db.execute('CREATE INDEX idx_dirty_identifier ON dirty_signals(identifier)');
    await db.execute('CREATE INDEX idx_dirty_ts ON dirty_signals(ts)');

    // Clean signals (validated)
    await db.execute('''
      CREATE TABLE clean_signals (
        id            TEXT PRIMARY KEY,
        source_id     TEXT REFERENCES signal_sources(id),
        trust_score   REAL DEFAULT 0.5,
        signal_type   TEXT NOT NULL,
        identifier   TEXT NOT NULL,
        display_name  TEXT,
        rssi          INTEGER,
        lat           REAL,
        lon           REAL,
        metadata_json TEXT,
        ts            INTEGER NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_clean_source ON clean_signals(source_id)');
    await db.execute('CREATE INDEX idx_clean_identifier ON clean_signals(identifier)');
    await db.execute('CREATE INDEX idx_clean_ts ON clean_signals(ts)');

    // Peers for LAN sync
    await db.execute('''
      CREATE TABLE peers (
        id            TEXT PRIMARY KEY,
        name          TEXT NOT NULL,
        address       TEXT NOT NULL,
        trust_level   INTEGER DEFAULT 0,
        last_sync     INTEGER,
        enabled       INTEGER DEFAULT 1
      )
    ''');

    // Key-value settings
    await db.execute('''
      CREATE TABLE settings (
        key           TEXT PRIMARY KEY,
        value         TEXT
      )
    ''');

    // Insert default sources
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.execute('''
      INSERT INTO signal_sources (id, name, source_type, trust_weight, is_clean, enabled, first_seen, last_seen)
      VALUES ('local', 'Local Device', 'local', 1.0, 1, 1, ?, ?)
    ''', [now, now]);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migrations go here
  }

  // ── Signal Sources ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSignalSources() async {
    final database = await db;
    return database.query('signal_sources', orderBy: 'last_seen DESC');
  }

  Future<Map<String, dynamic>?> getSignalSource(String id) async {
    final database = await db;
    final results = await database.query(
      'signal_sources',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> upsertSignalSource(Map<String, dynamic> source) async {
    final database = await db;
    await database.insert(
      'signal_sources',
      source,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Dirty Signals ───────────────────────────────────────────────────────

  Future<int> insertDirtySignal(Map<String, dynamic> signal) async {
    final database = await db;
    return database.insert(
      'dirty_signals',
      signal,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getDirtySignals({
    int? limit,
    int? offset,
    String? signalType,
  }) async {
    final database = await db;
    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (signalType != null) {
      where.add('signal_type = ?');
      whereArgs.add(signalType);
    }

    return database.query(
      'dirty_signals',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'ts DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<int> getDirtySignalCount() async {
    final database = await db;
    final result = await database.rawQuery('SELECT COUNT(*) as count FROM dirty_signals');
    return result.first['count'] as int;
  }

  Future<void> deleteDirtySignal(String id) async {
    final database = await db;
    await database.delete('dirty_signals', where: 'id = ?', whereArgs: [id]);
  }

  // ── Clean Signals ───────────────────────────────────────────────────────

  Future<int> insertCleanSignal(Map<String, dynamic> signal) async {
    final database = await db;
    return database.insert(
      'clean_signals',
      signal,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getCleanSignals({
    int? limit,
    int? offset,
    String? signalType,
    double? minTrust,
  }) async {
    final database = await db;
    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (signalType != null) {
      where.add('signal_type = ?');
      whereArgs.add(signalType);
    }

    if (minTrust != null) {
      where.add('trust_score >= ?');
      whereArgs.add(minTrust);
    }

    return database.query(
      'clean_signals',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'ts DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<int> getCleanSignalCount() async {
    final database = await db;
    final result = await database.rawQuery('SELECT COUNT(*) as count FROM clean_signals');
    return result.first['count'] as int;
  }

  // ── Peers ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPeers() async {
    final database = await db;
    return database.query('peers', orderBy: 'name');
  }

  Future<void> addPeer(Map<String, dynamic> peer) async {
    final database = await db;
    await database.insert(
      'peers',
      peer,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removePeer(String id) async {
    final database = await db;
    await database.delete('peers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updatePeerLastSync(String id) async {
    final database = await db;
    await database.update(
      'peers',
      {'last_sync': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Settings ────────────────────────────────────────────────────────────

  Future<String?> getSetting(String key) async {
    final database = await db;
    final results = await database.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return results.isNotEmpty ? results.first['value'] as String : null;
  }

  Future<void> setSetting(String key, String value) async {
    final database = await db;
    await database.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  Future<void> purgeOldDirtySignals(int retentionDays) async {
    final database = await db;
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch;
    
    await database.delete(
      'dirty_signals',
      where: 'ts < ? AND validated = 0',
      whereArgs: [cutoff],
    );
  }

  Future<void> close() async {
    final database = await db;
    await database.close();
    _db = null;
  }
}
