import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/models/lb_signal.dart';

/// Routes threat events to push notifications, UI, and OPSEC triggers.
class AlertEngine {
  final LBDatabase _db;
  final _notifs = FlutterLocalNotificationsPlugin();
  final _threatController = StreamController<LBThreatEvent>.broadcast();

  Stream<LBThreatEvent> get threatStream => _threatController.stream;

  int opsecAutoSeverity = LBSeverity.critical;
  bool opsecAutoEnabled = false;
  Future<void> Function()? onOpsecTrigger;

  final _recentAlerts = <String, DateTime>{};
  static const _alertCooldown = Duration(minutes: 5);
  static const _maxRecentAlerts = 1000;

  void _cleanupOldAlerts() {
    final cutoff = DateTime.now().subtract(_alertCooldown * 2);
    _recentAlerts.removeWhere((_, ts) => ts.isBefore(cutoff));
    if (_recentAlerts.length > _maxRecentAlerts) {
      final sorted = _recentAlerts.keys.toList()
        ..sort((a, b) => _recentAlerts[a]!.compareTo(_recentAlerts[b]!));
      final toRemove = sorted.take(_recentAlerts.length - _maxRecentAlerts);
      _recentAlerts.removeWhere((k, _) => toRemove.contains(k));
    }
  }

  AlertEngine(this._db);

  Future<void> init() async {
    const android = AndroidInitializationSettings('ic_notification');
    const ios     = DarwinInitializationSettings();
    await _notifs.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    await _notifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'lb_threats',
            'LittleBrother Threats',
            description: 'RF threat detection alerts',
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
          ),
        );
  }

  Future<void> handleThreatEvents(List<LBThreatEvent> events) async {
    for (final event in events) {
      await _route(event);
    }
  }

  Future<void> _route(LBThreatEvent event) async {
    _cleanupOldAlerts();
    final key = '${event.threatType}:${event.identifier}';
    final lastAlert = _recentAlerts[key];
    if (lastAlert != null &&
        DateTime.now().difference(lastAlert) < _alertCooldown) {
      return;
    }
    _recentAlerts[key] = DateTime.now();

    await _db.insertThreatEvent(event);

    if (!_threatController.isClosed) {
      _threatController.add(event);
    }

    if (event.severity >= LBSeverity.medium) {
      await _pushNotification(event);
    }

    if (opsecAutoEnabled &&
        event.severity >= opsecAutoSeverity &&
        onOpsecTrigger != null) {
      await onOpsecTrigger!();
    }
  }

  Future<void> _pushNotification(LBThreatEvent event) async {
    final isCritical = event.severity >= LBSeverity.critical;
    final ledColor   = _severityColor(event.severity);

    ByteArrayAndroidBitmap? largeIcon;
    try {
      final bytes = await rootBundle.load('assets/icons/ic_notification.png');
      final buffer = bytes.buffer.asUint8List();
      largeIcon = ByteArrayAndroidBitmap.fromBase64String(base64Encode(buffer));
    } catch (e) {
      debugPrint('LB_ALERT failed to load large icon asset: $e');
    }

    final androidDetails = AndroidNotificationDetails(
      'lb_threats',
      'LittleBrother Threats',
      channelDescription: 'RF threat detection alerts',
      importance: isCritical ? Importance.max : Importance.high,
      priority: Priority.high,
      color: ledColor,
      enableLights: true,
      ledColor: ledColor,
      ledOnMs: 500,
      ledOffMs: 500,
      icon: 'ic_notification',
      largeIcon: largeIcon,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );

    try {
      await _notifs.show(
        event.hashCode.abs() % 10000,
        _notifTitle(event),
        getNotificationBody(event),
        NotificationDetails(android: androidDetails, iOS: iosDetails),
      );
    } catch (e) {
      debugPrint('LB_ALERT notification failed (non-fatal): $e');
    }
  }

  String _notifTitle(LBThreatEvent event) {
    final prefix = switch (event.severity) {
      LBSeverity.critical => '⛔ CRITICAL',
      LBSeverity.high     => '🔴 THREAT',
      LBSeverity.medium   => '🟠 WARNING',
      _                   => '🟡 ALERT',
    };
    return switch (event.threatType) {
      LBThreatType.stingray    => '$prefix — IMSI Catcher Detected',
      LBThreatType.downgrade   => '$prefix — Network Downgrade',
      LBThreatType.rogueAp     => _rogueApTitle(event, prefix),
      LBThreatType.bleTracker  => _bleTrackerTitle(event, prefix),
      LBThreatType.silentSms   => '$prefix — Silent SMS Detected',
      LBThreatType.smsExfil    => '$prefix — SMS Exfiltration Detected',
      LBThreatType.dnsAnomaly  => '$prefix — Suspicious DNS Query',
      LBThreatType.deviceComp  => '$prefix — Device May Be Compromised',
      LBThreatType.processAnom => '$prefix — Suspicious Process',
      LBThreatType.deauthStorm => '$prefix — Deauth Attack Detected',
      _                        => '$prefix — ${event.threatType}',
    };
  }

  String _bleTrackerTitle(LBThreatEvent event, String prefix) {
    final heuristics = event.evidence['heuristics'] as Map<String, dynamic>?;
    final knownTracker = heuristics?['known_tracker'] as Map<String, dynamic>?;
    final trackerType = knownTracker?['type'] as String?;
    
    if (trackerType != null) {
      return '$prefix — $trackerType Detected';
    }
    
    final persistent = heuristics?['persistent_follower'] as Map<String, dynamic>?;
    if (persistent != null) {
      return '$prefix — Tracking Device Following You';
    }
    
    return '$prefix — BLE Tracker Detected';
  }

  String _rogueApTitle(LBThreatEvent event, String prefix) {
    final heuristics = event.evidence['heuristics'] as Map<String, dynamic>?;
    
    if (heuristics?['evil_twin'] != null) {
      return '$prefix — Evil Twin Detected';
    }
    if (heuristics?['privacy_risk'] != null) {
      final riskType = heuristics!['privacy_risk'] as Map<String, dynamic>;
      return '$prefix — ${riskType['type']} Detected';
    }
    if (heuristics?['spoofed_home'] != null) {
      return '$prefix — Spoofed Home Network';
    }
    if (heuristics?['karma_detection'] != null) {
      return '$prefix — Karma Probe Response';
    }
    
    return '$prefix — Rogue Access Point';
  }

  String getNotificationBody(LBThreatEvent event) {
    final score = event.evidence['composite_score'];
    return switch (event.threatType) {
      LBThreatType.stingray    => 'Cell ${event.identifier} — IMSI catcher signatures (score: $score)',
      LBThreatType.downgrade   => '${event.evidence['detail'] ?? 'Network type degraded'}',
      LBThreatType.rogueAp     => _rogueApBody(event),
      LBThreatType.bleTracker  => _bleTrackerBody(event),
      LBThreatType.silentSms   => 'Hidden class 0 SMS from ${event.identifier}',
      LBThreatType.smsExfil    => '${event.evidence['count'] ?? 'Multiple'} SMS sent to unknown recipient',
      LBThreatType.dnsAnomaly  => 'Query to ${event.identifier} matches known malware domain',
      LBThreatType.deviceComp  => event.evidence['detail'] ?? 'Security compromise indicators detected',
      LBThreatType.processAnom => 'Suspicious process: ${event.identifier}',
      LBThreatType.deauthStorm => '${event.evidence['detail'] ?? 'Wireless deauthentication attack detected'}',
      _                        => event.identifier,
    };
  }

  String _rogueApBody(LBThreatEvent event) {
    final heuristics = event.evidence['heuristics'] as Map<String, dynamic>? ?? {};
    final score = event.evidence['composite_score'];
    final parts = <String>[];
    
    if (heuristics['evil_twin'] != null) {
      final et = heuristics['evil_twin'] as Map<String, dynamic>;
      parts.add('Evil twin: ${et['count'] ?? 1} APs with same SSID');
    }
    if (heuristics['privacy_risk'] != null) {
      final pr = heuristics['privacy_risk'] as Map<String, dynamic>;
      parts.add('${pr['type']}: ${pr['detail'] ?? 'Known privacy risk'}');
    }
    if (heuristics['spoofed_home'] != null) {
      parts.add('Spoofed home network pattern');
    }
    if (heuristics['consumer_oui'] != null) {
      parts.add('Consumer device as AP');
    }
    if (heuristics['open_network'] != null) {
      parts.add('Open/unencrypted network');
    }
    
    if (parts.isEmpty) {
      return 'AP ${event.identifier} - rogue AP (score: $score)';
    }
    
    return parts.join(' • ');
  }

  String _bleTrackerBody(LBThreatEvent event) {
    final heuristics = event.evidence['heuristics'] as Map<String, dynamic>? ?? {};
    final knownTracker = heuristics['known_tracker'] as Map<String, dynamic>?;
    final trackerType = knownTracker?['type'] as String?;
    final persistent = heuristics['persistent_follower'] as Map<String, dynamic>?;
    final closeProx = heuristics['close_proximity'] as Map<String, dynamic>?;
    
    final parts = <String>[];
    
    if (trackerType != null) {
      parts.add('Known tracker type: $trackerType');
    }
    
    if (persistent != null) {
      final geohashCount = persistent['geohash_count'] ?? 0;
      parts.add('Seen at $geohashCount locations');
    }
    
    if (closeProx != null) {
      parts.add('Very close proximity (${closeProx['distance_m']}m)');
    }
    
    if (parts.isEmpty) {
      final sc = event.evidence['composite_score'];
      return 'Unknown BLE tracker detected - score: $sc';
    }
    
    return parts.join(' • ');
  }

  Color _severityColor(int severity) => switch (severity) {
    LBSeverity.critical => const Color(0xFFFF4444),
    LBSeverity.high     => const Color(0xFFFF8C00),
    LBSeverity.medium   => const Color(0xFFFFD700),
    _                   => const Color(0xFF3B82F6),
  };

  void dispose() {
    _threatController.close();
  }
}
