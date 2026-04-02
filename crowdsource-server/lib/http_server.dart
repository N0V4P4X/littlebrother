import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import '../db/server_db.dart';
import '../config.dart';

class HttpServer {
  final ServerDb _db = ServerDb.instance;
  final ServerConfig _config;
  final _uuid = const Uuid();
  
  HttpServer(this._config);

  Future<void> start() async {
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(_router);

    final server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      _config.httpPort,
      shared: true,
    );

    print('HTTP Server started on http://${server.address.host}:${server.port}');
  }

  Middleware _corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await innerHandler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
  };

  Router get _router => Router()
    // ── Status ─────────────────────────────────────────────────────────────
    ..get('/api/status', _handleStatus)
    
    // ── Scan Control ─────────────────────────────────────────────────────
    ..post('/api/scan/start', _handleScanStart)
    ..post('/api/scan/stop', _handleScanStop)
    
    // ── Crowdsource ────────────────────────────────────────────────────────
    ..get('/api/crowdsource', _handleCrowdsourceGet)
    ..post('/api/crowdsource/enable', _handleCrowdsourceEnable)
    ..post('/api/crowdsource/disable', _handleCrowdsourceDisable)
    ..get('/api/crowdsource/dirty', _handleDirtySignals)
    ..post('/api/crowdsource/validate/<id>', _handleValidateSignal)
    ..post('/api/crowdsource/reject/<id>', _handleRejectSignal)
    
    // ── Peers ─────────────────────────────────────────────────────────────
    ..get('/api/peers', _handlePeersGet)
    ..post('/api/peers/add', _handlePeersAdd)
    ..post('/api/peers/remove/<id>', _handlePeersRemove)
    ..post('/api/peers/sync/<id>', _handlePeersSync)
    
    // ── Settings ─────────────────────────────────────────────────────────
    ..get('/api/settings', _handleSettingsGet)
    ..post('/api/settings', _handleSettingsSet)
    
    // ── Database ───────────────────────────────────────────────────────
    ..get('/api/db/stats', _handleDbStats)
    
    // ── Web UI ───────────────────────────────────────────────────────────
    ..get('/', _serveDashboard);

  // ── Status ─────────────────────────────────────────────────────────────

  Future<Response> _handleStatus(Request req) async {
    final dirtyCount = await _db.getDirtySignalCount();
    final cleanCount = await _db.getCleanSignalCount();
    final sources = await _db.getSignalSources();
    
    return Response.ok(jsonEncode({
      'status': 'running',
      'mqtt_enabled': _config.mqttEnabled,
      'port': _config.httpPort,
      'dirty_signals': dirtyCount,
      'clean_signals': cleanCount,
      'sources': sources.length,
    }));
  }

  // ── Scan Control ─────────────────────────────────────────────────────

  Future<Response> _handleScanStart(Request req) async {
    // This would connect to the LittleBrother app via some IPC
    // For now, just acknowledge
    return Response.ok(jsonEncode({'status': 'ok', 'message': 'Scan start requested (IPC not implemented)'}));
  }

  Future<Response> _handleScanStop(Request req) async {
    return Response.ok(jsonEncode({'status': 'ok', 'message': 'Scan stop requested (IPC not implemented)'}));
  }

  // ── Crowdsource ───────────────────────────────────────────────────────

  Future<Response> _handleCrowdsourceGet(Request req) async {
    final sources = await _db.getSignalSources();
    final dirtyCount = await _db.getDirtySignalCount();
    final cleanCount = await _db.getCleanSignalCount();
    
    return Response.ok(jsonEncode({
      'mqtt_enabled': _config.mqttEnabled,
      'mqtt_host': _config.mqttHost,
      'sources': sources,
      'dirty_count': dirtyCount,
      'clean_count': cleanCount,
    }));
  }

  Future<Response> _handleCrowdsourceEnable(Request req) async {
    // Would enable MQTT subscriber
    return Response.ok(jsonEncode({'status': 'ok', 'message': 'MQTT enable requested'}));
  }

  Future<Response> _handleCrowdsourceDisable(Request req) async {
    return Response.ok(jsonEncode({'status': 'ok', 'message': 'MQTT disable requested'}));
  }

  Future<Response> _handleDirtySignals(Request req) async {
    final limit = int.tryParse(req.url.queryParameters['limit'] ?? '50');
    final offset = int.tryParse(req.url.queryParameters['offset'] ?? '0');
    final signalType = req.url.queryParameters['type'];
    
    final signals = await _db.getDirtySignals(
      limit: limit,
      offset: offset,
      signalType: signalType,
    );
    
    return Response.ok(jsonEncode(signals));
  }

  Future<Response> _handleValidateSignal(Request req, String id) async {
    // Move from dirty to clean
    final signals = await _db.getDirtySignals(limit: 1);
    final signal = signals.where((s) => s['id'] == id).firstOrNull;
    
    if (signal == null) {
      return Response.notFound(jsonEncode({'error': 'Signal not found'}));
    }
    
    // Insert to clean
    await _db.insertCleanSignal({
      ...signal,
      'trust_score': _config.trustCrowdsourcedClean,
    });
    
    // Remove from dirty
    await _db.deleteDirtySignal(id);
    
    return Response.ok(jsonEncode({'status': 'ok', 'id': id}));
  }

  Future<Response> _handleRejectSignal(Request req, String id) async {
    await _db.deleteDirtySignal(id);
    return Response.ok(jsonEncode({'status': 'ok', 'id': id}));
  }

  // ── Peers ───────────────────────────────────────────────────────────────

  Future<Response> _handlePeersGet(Request req) async {
    final peers = await _db.getPeers();
    return Response.ok(jsonEncode(peers));
  }

  Future<Response> _handlePeersAdd(Request req) async {
    final body = jsonDecode(await req.readAsString());
    
    await _db.addPeer({
      'id': _uuid.v4(),
      'name': body['name'] ?? 'Unnamed',
      'address': body['address'] ?? '',
      'trust_level': body['trust_level'] ?? 0,
      'enabled': 1,
    });
    
    return Response.ok(jsonEncode({'status': 'ok'}));
  }

  Future<Response> _handlePeersRemove(Request req, String id) async {
    await _db.removePeer(id);
    return Response.ok(jsonEncode({'status': 'ok'}));
  }

  Future<Response> _handlePeersSync(Request req, String id) async {
    // Would initiate sync with peer
    await _db.updatePeerLastSync(id);
    return Response.ok(jsonEncode({'status': 'ok', 'message': 'Sync with peer initiated'}));
  }

  // ── Settings ───────────────────────────────────────────────────────────

  Future<Response> _handleSettingsGet(Request req) async {
    return Response.ok(jsonEncode(_config.toJson()));
  }

  Future<Response> _handleSettingsSet(Request req) async {
    // Would save to config - for now just acknowledge
    return Response.ok(jsonEncode({'status': 'ok', 'message': 'Settings update requested'}));
  }

  // ── Database ───────────────────────────────────────────────────────────

  Future<Response> _handleDbStats(Request req) async {
    final dirtyCount = await _db.getDirtySignalCount();
    final cleanCount = await _db.getCleanSignalCount();
    final sources = await _db.getSignalSources();
    final peers = await _db.getPeers();
    
    return Response.ok(jsonEncode({
      'dirty_signals': dirtyCount,
      'clean_signals': cleanCount,
      'sources': sources.length,
      'peers': peers.length,
    }));
  }

  // ── Web UI ───────────────────────────────────────────────────────────

  Future<Response> _serveDashboard(Request req) async {
    final html = _dashboardHtml;
    return Response.ok(html, headers: {'Content-Type': 'text/html'});
  }

  static const String _dashboardHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>LittleBrother Server</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { 
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #0d1117; color: #c9d1d9; min-height: 100vh;
    }
    .header {
      background: #161b22; padding: 1rem 2rem; border-bottom: 1px solid #30363d;
      display: flex; justify-content: space-between; align-items: center;
    }
    .header h1 { font-size: 1.25rem; color: #58a6ff; }
    .status-badge {
      padding: 0.25rem 0.75rem; border-radius: 999px; font-size: 0.75rem;
      background: #238636; color: white;
    }
    .container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1.5rem; }
    .card {
      background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 1.5rem;
    }
    .card h2 { font-size: 1rem; margin-bottom: 1rem; color: #8b949e; }
    .stat { font-size: 2rem; font-weight: 600; color: #58a6ff; }
    .stat-label { font-size: 0.75rem; color: #8b949e; margin-top: 0.25rem; }
    .btn {
      background: #238636; color: white; border: none; padding: 0.5rem 1rem;
      border-radius: 6px; cursor: pointer; font-size: 0.875rem;
    }
    .btn:hover { background: #2ea043; }
    .btn-secondary { background: #30363d; }
    .btn-secondary:hover { background: #3d444d; }
    .btn-danger { background: #da3633; }
    .btn-danger:hover { background: #f85149; }
    .input {
      background: #0d1117; border: 1px solid #30363d; color: #c9d1d9;
      padding: 0.5rem; border-radius: 6px; width: 100%; margin-bottom: 0.5rem;
    }
    table { width: 100%; border-collapse: collapse; }
    th, td { text-align: left; padding: 0.75rem; border-bottom: 1px solid #30363d; }
    th { color: #8b949e; font-weight: 500; font-size: 0.75rem; text-transform: uppercase; }
    .nav { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; }
    .nav-btn {
      background: transparent; border: 1px solid #30363d; color: #8b949e;
      padding: 0.5rem 1rem; border-radius: 6px; cursor: pointer;
    }
    .nav-btn.active { background: #30363d; color: #c9d1d9; }
    .section { display: none; }
    .section.active { display: block; }
    .empty { color: #8b949e; text-align: center; padding: 2rem; }
  </style>
</head>
<body>
  <div class="header">
    <h1>LittleBrother Server</h1>
    <span class="status-badge">Online</span>
  </div>
  
  <div class="container">
    <div class="nav">
      <button class="nav-btn active" onclick="showSection('status')">Status</button>
      <button class="nav-btn" onclick="showSection('crowdsource')">Crowdsource</button>
      <button class="nav-btn" onclick="showSection('peers')">Peers</button>
      <button class="nav-btn" onclick="showSection('settings')">Settings</button>
    </div>
    
    <div id="status" class="section active">
      <div class="grid">
        <div class="card">
          <h2>Dirty Signals</h2>
          <div class="stat" id="dirty-count">-</div>
          <div class="stat-label">Unvalidated</div>
        </div>
        <div class="card">
          <h2>Clean Signals</h2>
          <div class="stat" id="clean-count">-</div>
          <div class="stat-label">Validated</div>
        </div>
        <div class="card">
          <h2>Sources</h2>
          <div class="stat" id="sources-count">-</div>
          <div class="stat-label">Connected</div>
        </div>
        <div class="card">
          <h2>Peers</h2>
          <div class="stat" id="peers-count">-</div>
          <div class="stat-label">Trusted Peers</div>
        </div>
      </div>
    </div>
    
    <div id="crowdsource" class="section">
      <div class="card">
        <h2>MQTT Configuration</h2>
        <p style="color: #8b949e; margin-bottom: 1rem;">
          Connect to a local Mosquitto broker to receive crowdsourced signal data.
        </p>
        <button class="btn" onclick="enableMqtt()">Enable MQTT</button>
        <button class="btn btn-secondary" onclick="disableMqtt()">Disable MQTT</button>
      </div>
      <div class="card" style="margin-top: 1.5rem;">
        <h2>Unvalidated Signals</h2>
        <div id="dirty-signals">
          <p class="empty">No unvalidated signals</p>
        </div>
      </div>
    </div>
    
    <div id="peers" class="section">
      <div class="card">
        <h2>Add Peer</h2>
        <input type="text" class="input" id="peer-name" placeholder="Name (e.g. Home Base)">
        <input type="text" class="input" id="peer-address" placeholder="Address (e.g. 192.168.1.100:8080)">
        <button class="btn" onclick="addPeer()">Add Peer</button>
      </div>
      <div class="card" style="margin-top: 1.5rem;">
        <h2>Connected Peers</h2>
        <div id="peers-list">
          <p class="empty">No peers configured</p>
        </div>
      </div>
    </div>
    
    <div id="settings" class="section">
      <div class="card">
        <h2>Server Settings</h2>
        <p style="color: #8b949e;">Configuration coming soon...</p>
      </div>
    </div>
  </div>

  <script>
    const API = '';
    
    function showSection(id) {
      document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
      document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
      document.getElementById(id).classList.add('active');
      event.target.classList.add('active');
    }
    
    async function fetchStatus() {
      const res = await fetch(API + '/api/status');
      const data = await res.json();
      document.getElementById('dirty-count').textContent = data.dirty_signals;
      document.getElementById('clean-count').textContent = data.clean_signals;
      document.getElementById('sources-count').textContent = data.sources;
    }
    
    async function fetchDbStats() {
      const res = await fetch(API + '/api/db/stats');
      const data = await res.json();
      document.getElementById('peers-count').textContent = data.peers;
    }
    
    async function fetchCrowdsource() {
      const res = await fetch(API + '/api/crowdsource');
      const data = await res.json();
      
      const signalsRes = await fetch(API + '/api/crowdsource/dirty?limit=20');
      const signals = await signalsRes.json();
      
      const container = document.getElementById('dirty-signals');
      if (signals.length === 0) {
        container.innerHTML = '<p class="empty">No unvalidated signals</p>';
      } else {
        let html = '<table><thead><tr><th>Type</th><th>Identifier</th><th>RSSI</th><th>Actions</th></tr></thead><tbody>';
        for (const s of signals) {
          html += '<tr>';
          html += '<td>' + s.signal_type + '</td>';
          html += '<td>' + (s.display_name || s.identifier) + '</td>';
          html += '<td>' + s.rssi + '</td>';
          html += '<td>';
          html += '<button class="btn" onclick="validateSignal(\\'' + s.id + '\\')">Validate</button> ';
          html += '<button class="btn btn-danger" onclick="rejectSignal(\\'' + s.id + '\\')">Reject</button>';
          html += '</td></tr>';
        }
        html += '</tbody></table>';
        container.innerHTML = html;
      }
    }
    
    async function fetchPeers() {
      const res = await fetch(API + '/api/peers');
      const peers = await res.json();
      
      const container = document.getElementById('peers-list');
      if (peers.length === 0) {
        container.innerHTML = '<p class="empty">No peers configured</p>';
      } else {
        let html = '<table><thead><tr><th>Name</th><th>Address</th><th>Trust</th><th>Actions</th></tr></thead><tbody>';
        for (const p of peers) {
          html += '<tr>';
          html += '<td>' + p.name + '</td>';
          html += '<td>' + p.address + '</td>';
          html += '<td>' + (p.trust_level ? 'Trusted' : 'Untrusted') + '</td>';
          html += '<td>';
          html += '<button class="btn btn-secondary" onclick="syncPeer(\\'' + p.id + '\\')">Sync</button> ';
          html += '<button class="btn btn-danger" onclick="removePeer(\\'' + p.id + '\\')">Remove</button>';
          html += '</td></tr>';
        }
        html += '</tbody></table>';
        container.innerHTML = html;
      }
    }
    
    async function enableMqtt() {
      await fetch(API + '/api/crowdsource/enable', { method: 'POST' });
      fetchCrowdsource();
    }
    
    async function disableMqtt() {
      await fetch(API + '/api/crowdsource/disable', { method: 'POST' });
      fetchCrowdsource();
    }
    
    async function validateSignal(id) {
      await fetch(API + '/api/crowdsource/validate/' + id, { method: 'POST' });
      fetchCrowdsource();
      fetchStatus();
    }
    
    async function rejectSignal(id) {
      await fetch(API + '/api/crowdsource/reject/' + id, { method: 'POST' });
      fetchCrowdsource();
    }
    
    async function addPeer() {
      const name = document.getElementById('peer-name').value;
      const address = document.getElementById('peer-address').value;
      if (!name || !address) return;
      
      await fetch(API + '/api/peers/add', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({name, address})
      });
      
      document.getElementById('peer-name').value = '';
      document.getElementById('peer-address').value = '';
      fetchPeers();
    }
    
    async function removePeer(id) {
      await fetch(API + '/api/peers/remove/' + id, { method: 'POST' });
      fetchPeers();
    }
    
    async function syncPeer(id) {
      await fetch(API + '/api/peers/sync/' + id, { method: 'POST' });
      fetchPeers();
    }
    
    // Initialize
    fetchStatus();
    fetchDbStats();
    fetchCrowdsource();
    fetchPeers();
    
    // Refresh every 10 seconds
    setInterval(() => {
      fetchStatus();
      fetchDbStats();
    }, 10000);
  </script>
</body>
</html>
''';
}
