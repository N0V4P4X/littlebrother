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
        _notifBody(event),
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
      LBThreatType.stingray   => '$prefix — IMSI Catcher Detected',
      LBThreatType.downgrade  => '$prefix — Network Downgrade',
      LBThreatType.rogueAp    => '$prefix — Rogue Access Point',
      LBThreatType.bleTracker => '$prefix — BLE Tracker Detected',
      _                       => '$prefix — ${event.threatType}',
    };
  }

  String _notifBody(LBThreatEvent event) {
    final score = event.evidence['composite_score'];
    return switch (event.threatType) {
      LBThreatType.stingray   => 'Cell ${event.identifier} — IMSI catcher signatures (score: $score)',
      LBThreatType.downgrade  => '${event.evidence['detail'] ?? 'Network type degraded'}',
      LBThreatType.rogueAp    => 'AP ${event.identifier} — rogue AP signatures',
      LBThreatType.bleTracker => 'Device ${event.identifier} — tracking device detected',
      _                       => event.identifier,
    };
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
