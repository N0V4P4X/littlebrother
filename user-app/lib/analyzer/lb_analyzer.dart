import 'package:flutter/foundation.dart' show debugPrint;
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/data/known_wifi_networks.dart';
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
    int? tacChangesPerMinute,
    int? neighborInstabilityScore,
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
        servingChangesPerMinute: servingCellChangesPerMinute ?? 0,
        tacChangesPerMinute: tacChangesPerMinute ?? 0,
        neighborInstability: neighborInstabilityScore ?? 0,
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
    required int servingChangesPerMinute,
    required int tacChangesPerMinute,
    required int neighborInstability,
  }) async {
    final evidence = <String, dynamic>{};
    var score = 0;

    // Fetch baseline once and reuse for both H1 and H3
    Map<String, dynamic>? baseline;
    if (geohash != null) {
      baseline = await _db.getCellBaseline(geohash, serving.identifier);
    }

    // H1 — Unknown Cell ID (weight 25)
    if (geohash != null) {
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

    // H4 — Serving Cell ID instability (weight 25 — bumped from 3)
    // A StingRay forces handovers to maintain the illusion; natural handover is slower
    if (servingChangesPerMinute >= LBThresholds.cellIdChurnPerMinute) {
      evidence['cell_instability'] = {
        'score': 80, 'weight': 25,
        'detail': '$servingChangesPerMinute serving cell changes in last 60s',
      };
      score += 25;
    }

    // H5 — GSM network type (highest risk — no encryption) (weight 30)
    // Note: actual downgrade is caught separately; this catches if we start on GSM
    final netType = serving.metadata['network_type_name'] as String? ?? '';
    if (netType == 'GSM') {
      evidence['gsm_network'] = {'score': 60, 'weight': 30, 'detail': 'Currently on unencrypted GSM network'};
      score += 18;
    }

    // H6 — Timing Advance anomaly (weight 20)
    // StingRays in close range show anomalous TA values (unusually small = very close)
    // Natural cells at street level: TA 0-10. A StingRay nearby: TA 0-3
    final ta = serving.metadata['timing_advance'] as int?;
    if (ta != null && ta >= 0 && ta <= 3) {
      // Very low TA with no corresponding proximity explanation
      final rsrp = serving.metadata['rsrp'] as int? ?? -100;
      if (rsrp > -85) { // Strong signal + very low TA = suspiciously close
        evidence['ta_anomaly'] = {
          'score': 90, 'weight': 20,
          'detail': 'TA=$ta with strong signal (RSRP=$rsrp dBm) — device appears very close',
          'timing_advance': ta,
          'rsrp': rsrp,
        };
        score += 20;
      }
    }

    // H7 — Neighbor list stability (weight 20)
    // A StingRay typically suppresses or mimics the real neighbor list
    if (neighborInstability >= 70) {
      final detail = neighborInstability >= 90
          ? 'Neighbor list is perfectly static — likely being suppressed'
          : 'Neighbor list is suspiciously consistent across scans';
      evidence['neighbor_stability'] = {
        'score': neighborInstability, 'weight': 20,
        'detail': detail,
        'instability_score': neighborInstability,
      };
      score += 20;
    }

    // H8 — TAC/LAC churn (weight 15)
    // A StingRay that impersonates multiple cells may cause rapid TAC changes
    if (tacChangesPerMinute >= 3) {
      evidence['tac_churn'] = {
        'score': 75, 'weight': 15,
        'detail': '$tacChangesPerMinute TAC changes in last 60s — area tracking area is unstable',
      };
      score += 15;
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
    final ssid = ap.metadata['ssid'] as String? ?? '';

    // H1 — SSID collision (evil twin detection)
    // Same SSID, different BSSID - could be legitimate AP or evil twin
    if (ssid.isNotEmpty) {
      final sameSSID = allWifi.where(
        (w) => w.metadata['ssid'] == ssid && w.identifier != ap.identifier
      ).toList();
      
      if (sameSSID.isNotEmpty) {
        // Check if they're on different channels (more likely to be real)
        final thisChannel = ap.metadata['channel'] as int? ?? 0;
        final sameChannel = sameSSID.any((w) => w.metadata['channel'] == thisChannel);
        
        if (sameChannel) {
          score += 40;
          evidence['evil_twin'] = {
            'detail': 'SSID "$ssid" on same channel from multiple BSSIDs - potential evil twin',
            'count': sameSSID.length,
            'channel': thisChannel,
          };
        } else {
          score += 15;
          evidence['ssid_collision'] = {'detail': 'SSID "$ssid" seen on multiple BSSIDs'};
        }
      }
    }

    // H2 — Known privacy-breaking networks (captive portals, honeypots)
    final privacyRisk = KnownPrivacyAps.checkSsid(ssid);
    if (privacyRisk != PrivacyRisk.none) {
      final riskPoints = privacyRisk == PrivacyRisk.honeypot ? 35 : 20;
      score += riskPoints;
      evidence['privacy_risk'] = {
        'type': KnownPrivacyAps.riskName(privacyRisk),
        'detail': 'Known ${KnownPrivacyAps.riskName(privacyRisk)} - $ssid',
      };
    }

    // H3 — Likely spoofed home network
    if (KnownPrivacyAps.isLikelySpoofedHome(ssid)) {
      score += 25;
      evidence['spoofed_home'] = {
        'detail': 'SSID "$ssid" matches commonly spoofed home network patterns',
      };
    }

    // H4 — Open network with no security
    score += ap.riskScore;
    if (ap.riskScore >= 40) {
      evidence['open_network'] = {'detail': 'Unencrypted or weak security (risk=${ap.riskScore})'};
    }

    // H5 — OUI is consumer device (not AP vendor)
    final vendor = ap.metadata['vendor'] as String? ?? '';
    if (vendor.isNotEmpty && _isConsumerDeviceVendor(vendor)) {
      score += 20;
      evidence['consumer_oui'] = {'detail': 'BSSID OUI resolves to consumer device: $vendor'};
    }

    // H6 — Hidden network (blank SSID) with strong signal
    if (ssid.isEmpty && ap.rssi > -60) {
      score += 15;
      evidence['hidden_ssid'] = {'detail': 'Hidden SSID with strong signal (-${ap.rssi} dBm)'};
    }

    // H7 — Unusual channel for area
    final channel = ap.metadata['channel'] as int? ?? 0;
    if (channel >= 12 && channel <= 14) {
      score += 10;
      evidence['unusual_channel'] = {'detail': '2.4GHz channel $channel (unusual region?)'};
    }

    // H8 — Karma probe response detection
    // An AP that responds to any probe request (including for non-existent SSIDs)
    // is likely running karma/mana attack. We detect this by checking for
    // a very high number of unique SSIDs seen in a short time from same BSSID
    // (This would require tracking across sessions - marking as future enhancement)
    evidence['karma_detection'] = {
      'detail': 'Multi-SSID probe response detection (requires historical analysis)',
      'note': 'Enable probe request logging for full karma detection',
    };

    if (score < 40) return null;

    return LBThreatEvent(
      threatType: LBThreatType.rogueAp,
      severity:   _rogueApSeverity(score),
      identifier: ap.identifier,
      evidence:   {'composite_score': score, 'heuristics': evidence},
      lat:        ap.lat,
      lon:        ap.lon,
      timestamp:  ap.timestamp,
    );
  }

  int _rogueApSeverity(int score) {
    if (score >= 80) return LBSeverity.critical;
    if (score >= 60) return LBSeverity.high;
    if (score >= 40) return LBSeverity.medium;
    return LBSeverity.low;
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

    // H1 — Known tracker signature (AirTag, SmartTag, Tile, etc.)
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
    try {
      final crossSession = await _db.getCrossSessionTrackers(
        minGeohashCount: 2,
        sinceMs: DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch,
      );
      final thisDevice = crossSession.where((d) => d['identifier'] == ble.identifier).firstOrNull;
      if (thisDevice != null) {
        final geohashCount = thisDevice['geohash_count'] as int? ?? 0;
        final obsCount = thisDevice['total_observations'] as int? ?? 0;
        if (geohashCount >= 2) {
          score += 50;
          evidence['persistent_follower'] = {
            'geohash_count': geohashCount,
            'observation_count': obsCount,
            'detail': 'Device seen at $geohashCount different locations - possible tracking',
          };
        }
      }
    } catch (e) {
      debugPrint('LB_ANALYZER: Cross-session tracker check failed: $e');
    }

    // H4 — Unrecognized manufacturer + no services (potentially covert)
    final vendor = ble.metadata['vendor'] as String? ?? '';
    final services = (ble.metadata['service_uuids'] as List?)?.length ?? 0;
    if (vendor.isEmpty && services == 0) {
      score += 15;
      evidence['covert_device'] = {'detail': 'No OUI match, no service UUIDs - possibly hidden tracker'};
    }

    // H5 — Very close distance + sustained presence
    final distanceM = ble.distanceM;
    if (distanceM != null && distanceM < 2.0) {
      score += 25;
      evidence['close_proximity'] = {'distance_m': distanceM, 'detail': 'Device within 2m - very close proximity'};
    }

    // H6 — Random MAC with unknown vendor (typical of AirTags)
    final isRandomized = ble.metadata['is_randomized_mac'] as bool? ?? false;
    if (isRandomized && vendor.isEmpty && trackerType == null) {
      score += 20;
      evidence['randomized_unknown'] = {'detail': 'Randomized MAC with no vendor info - potential AirTag-like device'};
    }

    if (score < 30) return null;

    return LBThreatEvent(
      threatType: LBThreatType.bleTracker,
      severity:   _bleTrackerSeverity(score),
      identifier: ble.identifier,
      evidence:   {'composite_score': score, 'heuristics': evidence},
      lat:        ble.lat,
      lon:        ble.lon,
      timestamp:  ble.timestamp,
    );
  }

  int _bleTrackerSeverity(int score) {
    if (score >= 80) return LBSeverity.critical;
    if (score >= 60) return LBSeverity.high;
    if (score >= 40) return LBSeverity.medium;
    return LBSeverity.low;
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  int _stingraySeverity(int score) {
    if (score >= LBThresholds.stingrayCritical) return LBSeverity.critical;
    if (score >= LBThresholds.stingrayThreat)   return LBSeverity.high;
    if (score >= LBThresholds.stingrayWarning)  return LBSeverity.medium;
    return LBSeverity.low;
  }
}
