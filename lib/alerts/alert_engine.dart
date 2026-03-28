import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/models/lb_signal.dart';

/// Routes threat events to push notifications, UI, and OPSEC triggers.
class AlertEngine {
  final LBDatabase _db;
  final FlutterLocalNotificationsPlugin _notifs;
  final _threatController = StreamController<LBThreatEvent>.broadcast();

  Stream<LBThreatEvent> get threatStream => _threatController.stream;

  // User-configurable thresholds (defaults)
  int opsecAutoSeverity = LBSeverity.critical;
  bool opsecAutoEnabled = false;

  // Callback for OPSEC trigger (set by OpsecController)
  Future<void> Function()? onOpsecTrigger;

  // Dedup: don't re-alert same threat within cooldown window
  final _recentAlerts = <String, DateTime>{};
  static const _alertCooldown = Duration(minutes: 5);

  AlertEngine(this._db, this._notifs);

  Future<void> init() async {
    const android = AndroidInitializationSettings('@drawable/ic_notification');
    const ios     = DarwinInitializationSettings();
    await _notifs.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Create notification channels
    const channel = AndroidNotificationChannel(
      'lb_threats',
      'LittleBrother Threats',
      description: 'RF threat detection alerts',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );
    await _notifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> handleThreatEvents(List<LBThreatEvent> events) async {
    for (final event in events) {
      await _route(event);
    }
  }

  Future<void> _route(LBThreatEvent event) async {
    // Dedup
    final key = '${event.threatType}:${event.identifier}';
    final lastAlert = _recentAlerts[key];
    if (lastAlert != null &&
        DateTime.now().difference(lastAlert) < _alertCooldown) {
      return;
    }
    _recentAlerts[key] = DateTime.now();

    // Persist
    await _db.insertThreatEvent(event);

    // Broadcast to UI
    if (!_threatController.isClosed) {
      _threatController.add(event);
    }

    // Push notification if severity >= medium
    if (event.severity >= LBSeverity.medium) {
      await _pushNotification(event);
    }

    // OPSEC auto-trigger
    if (opsecAutoEnabled &&
        event.severity >= opsecAutoSeverity &&
        onOpsecTrigger != null) {
      await onOpsecTrigger!();
    }
  }

  Future<void> _pushNotification(LBThreatEvent event) async {
    final title = _notifTitle(event);
    final body  = _notifBody(event);

    await _notifs.show(
      event.hashCode.abs() % 10000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'lb_threats',
          'LittleBrother Threats',
          channelDescription: 'RF threat detection alerts',
          importance: event.severity >= LBSeverity.critical
              ? Importance.max
              : Importance.high,
          priority: Priority.high,
          color: _severityColor(event.severity),
          enableLights: true,
          ledColor: _severityColor(event.severity),
          ledOnMs: 500,
          ledOffMs: 500,
          icon: '@drawable/ic_notification',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
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
      LBThreatType.stingray   => 'Cell ${event.identifier} shows IMSI catcher signatures (score: $score)',
      LBThreatType.downgrade  => '${event.evidence['detail'] ?? 'Network type degraded'}',
      LBThreatType.rogueAp    => 'AP ${event.identifier} shows rogue access point signatures',
      LBThreatType.bleTracker => 'Device ${event.identifier} appears to be a tracking device',
      _                       => event.identifier,
    };
  }

  // Returns an Android color int
  dynamic _severityColor(int severity) => switch (severity) {
    LBSeverity.critical => const Color(0xFFFF4444),
    LBSeverity.high     => const Color(0xFFFF8C00),
    LBSeverity.medium   => const Color(0xFFFFD700),
    _                   => const Color(0xFF3B82F6),
  };

  void dispose() {
    _threatController.close();
  }
}

// Minimal Color shim for use outside widget context
class Color {
  final int value;
  const Color(this.value);
}
