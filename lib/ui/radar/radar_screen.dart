import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/ui/radar/radar_painter.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';

class RadarScreen extends StatefulWidget {
  final Stream<List<LBSignal>> signalStream;
  final Stream<LBThreatEvent> threatStream;
  final VoidCallback? onScanToggle;
  final bool isScanning;
  final int wifiCount;
  final int bleCount;
  final int cellCount;
  final int threatCount;
  final String currentNetworkType;

  const RadarScreen({
    super.key,
    required this.signalStream,
    required this.threatStream,
    required this.isScanning,
    this.onScanToggle,
    this.wifiCount = 0,
    this.bleCount = 0,
    this.cellCount = 0,
    this.threatCount = 0,
    this.currentNetworkType = '---',
  });

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen>
    with TickerProviderStateMixin {

  // Sweep animation
  late AnimationController _sweepCtrl;
  late Animation<double> _sweepAnim;

  // Threat flash animation
  late AnimationController _flashCtrl;
  late Animation<double> _flashAnim;

  // Blip map: identifier → RadarBlip
  final _blips = <String, RadarBlip>{};

  StreamSubscription<List<LBSignal>>? _signalSub;
  StreamSubscription<LBThreatEvent>? _threatSub;

  static const _sweepDurationS = 4.0;

  @override
  void initState() {
    super.initState();

    _sweepCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_sweepDurationS * 1000).round()),
    )..repeat();

    _sweepAnim = Tween<double>(begin: 0, end: 2 * math.pi)
        .animate(_sweepCtrl);

    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _flashAnim = Tween<double>(begin: 0, end: 1)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_flashCtrl);

    _signalSub = widget.signalStream.listen(_onSignals);
    _threatSub = widget.threatStream.listen(_onThreat);
  }

  @override
  void didUpdateWidget(RadarScreen old) {
    super.didUpdateWidget(old);
    if (old.signalStream != widget.signalStream) {
      _signalSub?.cancel();
      _signalSub = widget.signalStream.listen(_onSignals);
    }
    if (old.threatStream != widget.threatStream) {
      _threatSub?.cancel();
      _threatSub = widget.threatStream.listen(_onThreat);
    }
  }

  void _onSignals(List<LBSignal> signals) {
    if (!mounted) return;
    setState(() {
      for (final s in signals) {
        if (s.identifier == 'DOWNGRADE_EVENT') continue;
        _blips[s.identifier] = RadarBlip.fromSignal(s);
      }
      // Prune stale blips (not seen in 3 sweep cycles)
      final cutoff = DateTime.now().subtract(
        Duration(seconds: (_sweepDurationS * 3).round()),
      );
      _blips.removeWhere((_, b) => b.lastSeen.isBefore(cutoff));
    });
  }

  void _onThreat(LBThreatEvent event) {
    if (!mounted) return;
    if (event.severity >= LBSeverity.critical) {
      _flashCtrl.forward(from: 0).then((_) => _flashCtrl.reverse());
    }
  }

  @override
  void dispose() {
    _sweepCtrl.dispose();
    _flashCtrl.dispose();
    _signalSub?.cancel();
    _threatSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LBColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildRadar()),
            _buildBottomCounters(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LBColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            'LITTLEBROTHER',
            style: LBTextStyles.heading.copyWith(color: LBColors.blue, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Text('v0.1.0', style: LBTextStyles.label),
          const Spacer(),
          // Network type indicator
          _networkTypeBadge(),
          const SizedBox(width: 12),
          // Scan toggle
          GestureDetector(
            onTap: widget.onScanToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.isScanning
                    ? LBColors.green.withValues(alpha: 0.15)
                    : LBColors.surface,
                border: Border.all(
                  color: widget.isScanning ? LBColors.green : LBColors.border,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isScanning ? LBColors.green : LBColors.dimText,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isScanning ? 'SCANNING' : 'PAUSED',
                    style: LBTextStyles.label.copyWith(
                      color: widget.isScanning ? LBColors.green : LBColors.dimText,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkTypeBadge() {
    final type = widget.currentNetworkType;
    final color = switch (type) {
      'NR'     => LBColors.green,
      'LTE'    => LBColors.cyan,
      'UMTS'   => LBColors.yellow,
      'GSM'    => LBColors.red,
      _        => LBColors.dimText,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        type,
        style: LBTextStyles.label.copyWith(color: color, fontSize: 10),
      ),
    );
  }

  Widget _buildRadar() {
    return AnimatedBuilder(
      animation: Listenable.merge([_sweepAnim, _flashAnim]),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = math.min(constraints.maxWidth, constraints.maxHeight);
            return Center(
              child: SizedBox(
                width: size,
                height: size,
                child: CustomPaint(
                  painter: RadarPainter(
                    sweepAngle:    _sweepAnim.value,
                    sweepDurationS: _sweepDurationS,
                    blips:         _blips.values.toList(),
                    threatFlash:   _flashCtrl.isAnimating,
                    flashOpacity:  _flashAnim.value,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBottomCounters() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: LBColors.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _counter('Wi-Fi', widget.wifiCount, LBColors.wifi),
          _vdiv(),
          _counter('BLE', widget.bleCount, LBColors.ble),
          _vdiv(),
          _counter('CELL', widget.cellCount, LBColors.cell),
          _vdiv(),
          _counter('THREATS', widget.threatCount, LBColors.red, highlight: widget.threatCount > 0),
        ],
      ),
    );
  }

  Widget _counter(String label, int count, Color color, {bool highlight = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          count.toString().padLeft(3, '0'),
          style: LBTextStyles.displayMedium.copyWith(
            color: highlight ? LBColors.red : color,
            fontSize: 18,
          ),
        ),
        Text(label, style: LBTextStyles.label.copyWith(fontSize: 9)),
      ],
    );
  }

  Widget _vdiv() => Container(
    width: 1,
    height: 32,
    color: LBColors.border,
  );
}
