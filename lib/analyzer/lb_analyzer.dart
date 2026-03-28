import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/models/lb_signal.dart';

/// Runs after each normalizer pass. Evaluates signals against baselines,
/// known-bad lists, and heuristic rules. Emits LBThreatEvents.
class LBAnalyzer {
  final LBDatabase _db;

  LBAnalyzer(this._db);

  /// Analyze a batch of signals from one scan cycle.
  /// Returns any threat events generated (caller persists + routes to alerts).
  Future<List<LBThreatEvent>> analyze(
    List<LBSignal> signals, {
    String? geohash,
    int? servingCellChangesPerMinute,
  }) async {
    final threats = <LBThreatEvent>[];

    final cells    = signals.where((s) => s.signalType == LBSignalType.cell).toList();
    final neighbors = signals.where((s) => s.signalType == LBSignalType.cellNeighbor).toList();
    final wifis    = signals.where((s) => s.signalType == LBSignalType.wifi).toList();
    final bles     = signals.where((s) => s.signalType == LBSignalType.ble).toList();

    // ── Stingray detection ──────────────────────────────────────────────
    final serving = cells.where((c) => c.metadata['is_serving'] == true).firstOrNull;
    if (serving != null) {
      final stingrayResult = await _analyzeStingray(
        serving: serving,
        neighbors: neighbors,
        geohash: geohash,
        changesPerMinute: servingCellChangesPerMinute ?? 0,
      );
      if (stingrayResult != null) threats.add(stingrayResult);
    }

    // ── Downgrade event ─────────────────────────────────────────────────
    final downgrade = cells.where((c) => c.identifier == 'DOWNGRADE_EVENT').firstOrNull;
    if (downgrade != null) {
      final t = _analyzeDowngrade(downgrade);
      if (t != null) threats.add(t);
    }

    // ── Rogue AP detection ──────────────────────────────────────────────
    for (final ap in wifis) {
      final rogueResult = await _analyzeRogueAp(ap, wifis);
      if (rogueResult != null) threats.add(rogueResult);
    }

    // ── BLE tracker detection ───────────────────────────────────────────
    for (final ble in bles) {
      final trackerResult = await _analyzeBleTracker(ble);
      if (trackerResult != null) threats.add(trackerResult);
    }

    return threats;
  }

  // ── Stingray heuristics ────────────────────────────────────────────────

  Future<LBThreatEvent?> _analyzeStingray({
    required LBSignal serving,
    required List<LBSignal> neighbors,
    String? geohash,
    required int changesPerMinute,
  }) async {
    final evidence = <String, dynamic>{};
    var score = 0;

    // H1 — Unknown Cell ID (weight 25)
    if (geohash != null) {
      final cellKey = serving.identifier;
      final baseline = await _db.getCellBaseline(geohash, cellKey);
      if (baseline == null) {
        evidence['unknown_cell'] = {'score': 100, 'weight': 25, 'detail': 'Cell ID never seen at this location'};
        score += 25;
      } else if ((baseline['observation_count'] as int) < 3) {
        evidence['rare_cell'] = {'score': 50, 'weight': 25, 'detail': 'Cell ID seen <3 times at this location'};
        score += 12;
      }
    }

    // H2 — Missing neighbor list (weight 10)
    if (neighbors.isEmpty) {
      evidence['no_neighbors'] = {'score': 80, 'weight': 10, 'detail': 'Serving cell reports 0 neighbors'};
      score += 8;
    } else if (neighbors.length < LBThresholds.minExpectedNeighbors) {
      evidence['few_neighbors'] = {'score': 40, 'weight': 10, 'detail': 'Only ${neighbors.length} neighbors reported'};
      score += 4;
    }

    // H3 — RSSI anomaly: serving cell much stronger than baseline (weight 20)
    if (geohash != null) {
      final baseline = await _db.getCellBaseline(geohash, serving.identifier);
      if (baseline != null) {
        final avgRssi = baseline['avg_rssi'] as double;
        final delta = serving.rssi - avgRssi;
        if (delta > LBThresholds.rssiAnomalyDb) {
          evidence['rssi_anomaly'] = {
            'score': 100, 'weight': 20,
            'detail': '${delta.toStringAsFixed(1)} dB above historical baseline',
            'observed': serving.rssi,
            'baseline': avgRssi,
          };
          score += 20;
        }
      }
    }

    // H4 — Cell ID instability (weight 3)
    if (changesPerMinute >= LBThresholds.cellIdChurnPerMinute) {
      evidence['cell_instability'] = {
        'score': 80, 'weight': 3,
        'detail': '$changesPerMinute serving cell changes in last 60s',
      };
      score += 3;
    }

    // H5 — GSM network type (highest risk — no encryption) (weight 30)
    // Note: actual downgrade is caught separately; this catches if we start on GSM
    final netType = serving.metadata['network_type_name'] as String? ?? '';
    if (netType == 'GSM') {
      evidence['gsm_network'] = {'score': 60, 'weight': 30, 'detail': 'Currently on unencrypted GSM network'};
      score += 18;
    }

    if (score < 10) return null;

    return LBThreatEvent(
      threatType: LBThreatType.stingray,
      severity:   _stingraySeverity(score),
      identifier: serving.identifier,
      evidence:   {'composite_score': score, 'heuristics': evidence},
      lat:        serving.lat,
      lon:        serving.lon,
      timestamp:  serving.timestamp,
    );
  }

  // ── Downgrade event ────────────────────────────────────────────────────

  LBThreatEvent? _analyzeDowngrade(LBSignal event) {
    final from = event.metadata['from'] as String? ?? '';
    final to   = event.metadata['to'] as String? ?? '';
    final isGsm = event.metadata['is_gsm_downgrade'] as bool? ?? false;

    // LTE/NR → GSM is worst case (weight 30 in composite)
    final severity = isGsm ? LBSeverity.critical : LBSeverity.high;
    final score    = isGsm ? 80 : 45;

    return LBThreatEvent(
      threatType: LBThreatType.downgrade,
      severity:   severity,
      identifier: 'DOWNGRADE_EVENT',
      evidence: {
        'composite_score': score,
        'from': from,
        'to':   to,
        'detail': 'Network downgrade from $from to $to detected',
      },
      lat:       event.lat,
      lon:       event.lon,
      timestamp: event.timestamp,
    );
  }

  // ── Rogue AP heuristics ────────────────────────────────────────────────

  Future<LBThreatEvent?> _analyzeRogueAp(
    LBSignal ap,
    List<LBSignal> allWifi,
  ) async {
    var score = 0;
    final evidence = <String, dynamic>{};

    // H1 — SSID collision (same SSID, different BSSID to known-good)
    // Compare against DB-stored devices for this SSID
    // (simplified: check if another AP in this scan has same SSID)
    final ssid = ap.metadata['ssid'] as String? ?? '';
    if (ssid.isNotEmpty) {
      final sameSSID = allWifi.where(
        (w) => w.metadata['ssid'] == ssid && w.identifier != ap.identifier
      );
      if (sameSSID.isNotEmpty) {
        score += 25;
        evidence['ssid_collision'] = {'detail': 'SSID "$ssid" seen on multiple BSSIDs'};
      }
    }

    // H2 — Open + risk score already computed in scanner
    score += ap.riskScore;
    if (ap.riskScore >= 40) {
      evidence['open_network'] = {'detail': 'Unencrypted or weak security (risk=${ap.riskScore})'};
    }

    // H3 — OUI is consumer device (not AP vendor)
    final vendor = ap.metadata['vendor'] as String? ?? '';
    if (vendor.isNotEmpty && _isConsumerDeviceVendor(vendor)) {
      score += 20;
      evidence['consumer_oui'] = {'detail': 'BSSID OUI resolves to consumer device: $vendor'};
    }

    if (score < 40) return null;

    return LBThreatEvent(
      threatType: LBThreatType.rogueAp,
      severity:   score >= 70 ? LBSeverity.high : LBSeverity.medium,
      identifier: ap.identifier,
      evidence:   {'composite_score': score, 'heuristics': evidence},
      lat:        ap.lat,
      lon:        ap.lon,
      timestamp:  ap.timestamp,
    );
  }

  bool _isConsumerDeviceVendor(String vendor) {
    final v = vendor.toLowerCase();
    // Known consumer device brands that wouldn't be an AP
    return v.contains('apple') || v.contains('samsung') || v.contains('google') ||
           v.contains('oneplus') || v.contains('xiaomi') || v.contains('huawei') ||
           v.contains('motorola') || v.contains('lg electronics');
  }

  // ── BLE Tracker heuristics ─────────────────────────────────────────────

  Future<LBThreatEvent?> _analyzeBleTracker(LBSignal ble) async {
    var score = 0;
    final evidence = <String, dynamic>{};
    final trackerType = ble.metadata['tracker_type'] as String?;

    // H1 — Known tracker signature
    if (trackerType != null) {
      score += 60;
      evidence['known_tracker'] = {'type': trackerType, 'detail': 'Matches $trackerType advertising signature'};
    }

    // H2 — Aggressive advertising interval
    final intervalMs = ble.metadata['advertising_interval_ms'] as int?;
    if (intervalMs != null && intervalMs < LBThresholds.bleAggressiveIntervalMs) {
      score += 20;
      evidence['aggressive_adv'] = {'interval_ms': intervalMs, 'detail': 'Advertising at aggressive ${intervalMs}ms interval'};
    }

    // H3 — Persistent follower: check if seen across multiple geohash locations
    // (Requires DB query — simplified for P1, full implementation in P3)

    // H4 — Unrecognized manufacturer + no services
    final vendor = ble.metadata['vendor'] as String? ?? '';
    final services = (ble.metadata['service_uuids'] as List?)?.length ?? 0;
    if (vendor.isEmpty && services == 0) {
      score += 15;
      evidence['covert_device'] = {'detail': 'No OUI match, no service UUIDs'};
    }

    if (score < 30) return null;

    return LBThreatEvent(
      threatType: LBThreatType.bleTracker,
      severity:   score >= 60 ? LBSeverity.high : LBSeverity.medium,
      identifier: ble.identifier,
      evidence:   {'composite_score': score, 'heuristics': evidence},
      lat:        ble.lat,
      lon:        ble.lon,
      timestamp:  ble.timestamp,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  int _stingraySeverity(int score) {
    if (score >= LBThresholds.stingrayCritical) return LBSeverity.critical;
    if (score >= LBThresholds.stingrayThreat)   return LBSeverity.high;
    if (score >= LBThresholds.stingrayWarning)  return LBSeverity.medium;
    return LBSeverity.low;
  }
}
