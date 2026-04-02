import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';

/// A single blip on the radar.
class RadarBlip {
  final String id;
  final String signalType;
  final int threatFlag;
  final int rssi;
  final double distanceM;
  final String label;
  final DateTime lastSeen;

  // Polar position — set by layout engine
  double angle = 0;  // radians
  double radius = 0; // normalized 0–1

  RadarBlip({
    required this.id,
    required this.signalType,
    required this.threatFlag,
    required this.rssi,
    required this.distanceM,
    required this.label,
    required this.lastSeen,
    required this.angle,
    required this.radius,
  });

  factory RadarBlip.fromSignal(LBSignal s) {
    // Deterministic angle from identifier hash
    final hash = s.identifier.codeUnits.fold(0, (a, b) => a ^ (b * 2654435761));
    final angle = (hash.abs() % 3600) / 3600.0 * 2 * math.pi;
    // Radius from distance, clamped to max 100m = edge
    final radius = (s.distanceM / 100.0).clamp(0.05, 0.92);

    return RadarBlip(
      id:         s.id,
      signalType: s.signalType,
      threatFlag: s.threatFlag,
      rssi:       s.rssi,
      distanceM:  s.distanceM,
      label:      s.displayName,
      lastSeen:   s.timestamp,
      angle:      angle,
      radius:     radius,
    );
  }

  /// Opacity decay: blips fade over 3 sweep cycles (configurable via sweepDurationS)
  double opacity(double sweepAngle, double sweepDurationS) {
    final ageSecs = DateTime.now().difference(lastSeen).inMilliseconds / 1000.0;
    final decay   = (ageSecs / (sweepDurationS * 3)).clamp(0.0, 1.0);
    return (1.0 - decay).clamp(0.1, 1.0);
  }
}

class RadarPainter extends CustomPainter {
  final double sweepAngle;       // current sweep arm angle (radians)
  final double sweepDurationS;   // seconds per full rotation
  final List<RadarBlip> blips;
  final bool threatFlash;        // triggers full-canvas red pulse
  final double flashOpacity;     // 0–1 for flash animation

  static const _ringDistances = [10.0, 30.0, 100.0]; // meters
  static const _maxDistance = 100.0;

  RadarPainter({
    required this.sweepAngle,
    required this.sweepDurationS,
    required this.blips,
    this.threatFlash = false,
    this.flashOpacity = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = math.min(cx, cy) * 0.92;

    _drawBackground(canvas, size, cx, cy, r);
    _drawGrid(canvas, cx, cy, r);
    _drawRings(canvas, cx, cy, r);
    _drawCompass(canvas, cx, cy, r);
    _drawSweepTrail(canvas, cx, cy, r);
    _drawSweepArm(canvas, cx, cy, r);
    _drawBlips(canvas, cx, cy, r);
    if (threatFlash && flashOpacity > 0) {
      _drawThreatFlash(canvas, size);
    }
  }

  void _drawBackground(Canvas canvas, Size size, double cx, double cy, double r) {
    // Outer clip circle
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)));

    // Background fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = LBColors.background,
    );

    // Subtle radial gradient from center
    final gradient = RadialGradient(
      colors: [
        LBColors.blueDim.withValues(alpha: 0.25),
        LBColors.background.withValues(alpha: 0),
      ],
      stops: const [0, 1],
    );
    canvas.drawOval(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      Paint()
        ..shader = gradient.createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
        ),
    );

    // Border ring
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = LBColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawGrid(Canvas canvas, double cx, double cy, double r) {
    final paint = Paint()
      ..color = LBColors.blue.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    // 8 radial spokes
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)),
        paint,
      );
    }
  }

  void _drawRings(Canvas canvas, double cx, double cy, double r) {
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (final dist in _ringDistances) {
      final ringR = (dist / _maxDistance) * r;
      ringPaint.color = LBColors.blue.withValues(alpha: 0.18);
      canvas.drawCircle(Offset(cx, cy), ringR, ringPaint);

      // Distance label
      _drawText(
        canvas,
        '${dist.toInt()}m',
        Offset(cx + ringR + 4, cy - 8),
        LBColors.blue.withValues(alpha: 0.5),
        9,
      );
    }
  }

  void _drawCompass(Canvas canvas, double cx, double cy, double r) {
    const labels = ['N', 'E', 'S', 'W'];
    const angles = [
      -math.pi / 2,
      0.0,
      math.pi / 2,
      math.pi,
    ];
    final offset = r + 14.0;
    for (var i = 0; i < 4; i++) {
      final x = cx + offset * math.cos(angles[i]);
      final y = cy + offset * math.sin(angles[i]);
      _drawText(canvas, labels[i], Offset(x - 5, y - 7),
          LBColors.blue.withValues(alpha: 0.4), 10);
    }
  }

  void _drawSweepTrail(Canvas canvas, double cx, double cy, double r) {
    // Fading arc trailing 90° behind sweep arm
    const trailArc = math.pi / 2;
    const steps    = 30;

    for (var i = 0; i < steps; i++) {
      final frac    = i / steps;
      final alpha   = (1.0 - frac) * 0.35;
      final startA  = sweepAngle - trailArc * frac;
      final sweepA  = trailArc / steps;

      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startA - sweepA,
        sweepA,
        false,
        Paint()
          ..color = LBColors.blue.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r,
      );
    }
  }

  void _drawSweepArm(Canvas canvas, double cx, double cy, double r) {
    canvas.drawLine(
      Offset(cx, cy),
      Offset(
        cx + r * math.cos(sweepAngle),
        cy + r * math.sin(sweepAngle),
      ),
      Paint()
        ..color = LBColors.blue.withValues(alpha: 0.9)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    // Bright tip
    canvas.drawCircle(
      Offset(
        cx + r * math.cos(sweepAngle),
        cy + r * math.sin(sweepAngle),
      ),
      2.5,
      Paint()..color = LBColors.cyan,
    );
  }

  void _drawBlips(Canvas canvas, double cx, double cy, double r) {
    for (final blip in blips) {
      final opacity = blip.opacity(sweepAngle, sweepDurationS);
      final color   = LBColors.blipColor(blip.signalType, blip.threatFlag)
          .withValues(alpha: opacity);

      final bx = cx + blip.radius * r * math.cos(blip.angle);
      final by = cy + blip.radius * r * math.sin(blip.angle);

      // Blip size scales with RSSI strength (-100 dBm = small, -30 = large)
      final blipR = _blipRadius(blip.rssi);

      // Outer glow
      canvas.drawCircle(
        Offset(bx, by),
        blipR * 2.5,
        Paint()..color = color.withValues(alpha: opacity * 0.15),
      );

      // Main dot
      canvas.drawCircle(
        Offset(bx, by),
        blipR,
        Paint()..color = color,
      );

      // Hostile blips get a ring
      if (blip.threatFlag == 2) {
        canvas.drawCircle(
          Offset(bx, by),
          blipR + 4,
          Paint()
            ..color = LBColors.red.withValues(alpha: opacity * 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
  }

  void _drawThreatFlash(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = LBColors.red.withValues(alpha: flashOpacity * 0.3),
    );
    // Pulsing border
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color = LBColors.red.withValues(alpha: flashOpacity * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  double _blipRadius(int rssi) {
    // Map RSSI -100…-30 dBm → radius 3…8 px
    final clamped = rssi.clamp(-100, -30);
    final norm    = (clamped + 100) / 70.0; // 0=weak, 1=strong
    return 3.0 + norm * 5.0;
  }

  static final Map<String, TextPainter> _textPainterCache = {};

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize,
  ) {
    final cacheKey = '$text|$color|$fontSize';
    final tp = _textPainterCache.putIfAbsent(cacheKey, () {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Courier New',
            color: color,
            fontSize: fontSize,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(RadarPainter old) {
    if (old.sweepAngle != sweepAngle) return true;
    if (old.flashOpacity != flashOpacity) return true;
    if (old.blips.length != blips.length) return true;
    // Check if any blip content changed (threat flag, rssi, position)
    for (var i = 0; i < blips.length; i++) {
      final a = old.blips[i], b = blips[i];
      if (a.id != b.id || a.threatFlag != b.threatFlag ||
          a.rssi != b.rssi || a.angle != b.angle || a.radius != b.radius) {
        return true;
      }
    }
    return false;
  }
}
