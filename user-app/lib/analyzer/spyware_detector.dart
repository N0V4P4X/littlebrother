import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/models/lb_signal.dart';

class SpywareDetector {
  final LBDatabase _db;

  bool _passiveMonitoringEnabled = false;
  Timer? _passiveMonitorTimer;

  final _findingsController = StreamController<SpywareFinding>.broadcast();
  Stream<SpywareFinding> get findingsStream => _findingsController.stream;

  final List<String> _knownPegasusDomains = [
    'free247downloads.com',
    'urlpush.net',
    'opposedarrangement.net',
    'get1tn0w.',
    'documentpro.org',
    'tahmilmilafate.com',
    'baramije.net',
    'php78mp9v.',
  ];

  SpywareDetector(this._db);

  void startPassiveMonitoring() {
    if (_passiveMonitoringEnabled) return;
    _passiveMonitoringEnabled = true;
    _passiveMonitorTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _runPassiveChecks(),
    );
    debugPrint('LB_SPYWARE: Passive monitoring started');
    _runPassiveChecks();
  }

  void stopPassiveMonitoring() {
    _passiveMonitoringEnabled = false;
    _passiveMonitorTimer?.cancel();
    _passiveMonitorTimer = null;
    debugPrint('LB_SPYWARE: Passive monitoring stopped');
  }

  Future<void> _runPassiveChecks() async {
    debugPrint('LB_SPYWARE: Running passive checks...');
    try {
      await _checkSilentSms();
    } catch (e) {
      debugPrint('LB_SPYWARE: Silent SMS check failed: $e');
    }
  }

  Future<List<SpywareFinding>> runForensicScan() async {
    final findings = <SpywareFinding>[];

    debugPrint('LB_SPYWARE: Starting forensic scan...');

    findings.addAll(await _checkSilentSms());
    findings.addAll(await _checkSmsExfiltration());

    for (final f in findings) {
      if (!_findingsController.isClosed) {
        _findingsController.add(f);
      }
      await _db.insertThreatEvent(f.toThreatEvent());
    }

    debugPrint('LB_SPYWARE: Forensic scan complete. ${findings.length} findings.');
    return findings;
  }

  Future<List<SpywareFinding>> _checkSilentSms() async {
    final findings = <SpywareFinding>[];

    try {
      final silentSms = await _db.getSilentSms();
      if (silentSms.isNotEmpty) {
        findings.add(SpywareFinding(
          type: LBThreatType.silentSms,
          severity: LBSeverity.critical,
          identifier: silentSms.length.toString(),
          detail: '${silentSms.length} hidden (class 0) SMS messages detected',
          evidence: {
            'count': silentSms.length,
            'messages': silentSms.take(5).map((m) => {
              'from': m['address'],
              'date': m['date'],
              'body_preview': (m['body'] as String?)?.substring(0, (m['body'] as String?)?.length.clamp(0, 50) ?? 0),
            }).toList(),
          },
        ));
      }
    } catch (e) {
      debugPrint('LB_SPYWARE: Silent SMS check error: $e');
    }

    return findings;
  }

  Future<List<SpywareFinding>> _checkSmsExfiltration() async {
    final findings = <SpywareFinding>[];

    try {
      final exfil = await _db.getSmsExfiltrationPatterns();
      if (exfil.isNotEmpty) {
        for (final e in exfil) {
          findings.add(SpywareFinding(
            type: LBThreatType.smsExfil,
            severity: LBSeverity.high,
            identifier: e['address'] ?? 'unknown',
            detail: '${e['count']} SMS sent to ${e['address']} - possible data exfiltration',
            evidence: {
              'count': e['count'],
              'address': e['address'],
              'recent_messages': e['recent_bodies'],
            },
          ));
        }
      }
    } catch (e) {
      debugPrint('LB_SPYWARE: SMS exfil check error: $e');
    }

    return findings;
  }

  void dispose() {
    stopPassiveMonitoring();
    _findingsController.close();
  }
}

class SpywareFinding {
  final String type;
  final int severity;
  final String identifier;
  final String detail;
  final Map<String, dynamic> evidence;
  final DateTime timestamp;

  SpywareFinding({
    required this.type,
    required this.severity,
    required this.identifier,
    required this.detail,
    Map<String, dynamic>? evidence,
    DateTime? timestamp,
  })  : evidence = evidence ?? {},
        timestamp = timestamp ?? DateTime.now();

  LBThreatEvent toThreatEvent() {
    return LBThreatEvent(
      threatType: type,
      severity: severity,
      identifier: identifier,
      evidence: {
        ...evidence,
        'detail': detail,
      },
      timestamp: timestamp,
    );
  }
}
