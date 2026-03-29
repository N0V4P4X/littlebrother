import 'package:flutter/material.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';

class SignalTile extends StatelessWidget {
  final LBSignal signal;
  final VoidCallback? onTap;

  const SignalTile({super.key, required this.signal, this.onTap});

  @override
  Widget build(BuildContext context) {
    final typeColor = switch (signal.signalType) {
      LBSignalType.wifi          => LBColors.wifi,
      LBSignalType.ble           => LBColors.ble,
      LBSignalType.cell          => LBColors.cell,
      LBSignalType.cellNeighbor  => LBColors.cell.withValues(alpha: 0.5),
      _                          => LBColors.dimText,
    };

    final riskColor  = LBColors.riskColor(signal.riskScore);
    final isHostile  = signal.threatFlag == LBThreatFlag.hostile;
    final isWatched  = signal.threatFlag == LBThreatFlag.watch;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: isHostile
              ? const Border(left: BorderSide(color: LBColors.red, width: 3))
              : isWatched
                  ? const Border(left: BorderSide(color: LBColors.orange, width: 3))
                  : null,
        ),
        child: Row(
          children: [
            // Type badge
            Container(
              width: 42,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                border: Border.all(color: typeColor.withValues(alpha: 0.4), width: 1),
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.center,
              child: Text(
                _typeLabel(signal.signalType),
                style: LBTextStyles.label.copyWith(color: typeColor, fontSize: 9),
              ),
            ),
            const SizedBox(width: 10),

            // Name + identifier
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    signal.displayName,
                    style: LBTextStyles.body.copyWith(
                      color: isHostile ? LBColors.red : LBColors.bodyText,
                      fontWeight: isHostile ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    signal.identifier,
                    style: LBTextStyles.label.copyWith(fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // RSSI
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${signal.rssi} dBm',
                  style: LBTextStyles.value.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 2),
                _rssiBar(signal.rssi),
              ],
            ),
            const SizedBox(width: 12),

            // Risk score
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: riskColor.withValues(alpha: 0.6), width: 1),
                color: riskColor.withValues(alpha: 0.08),
              ),
              alignment: Alignment.center,
              child: Text(
                signal.riskScore.toString(),
                style: LBTextStyles.label.copyWith(
                  color: riskColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rssiBar(int rssi) {
    final bars = switch (rssi) {
      > -50 => 4,
      > -70 => 3,
      > -85 => 2,
      _     => 1,
    };
    return Row(
      children: List.generate(4, (i) {
        final active = i < bars;
        return Container(
          width: 4,
          height: 6.0 + i * 2,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active ? LBColors.cyan : LBColors.border,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  String _typeLabel(String type) => switch (type) {
    LBSignalType.wifi          => 'WiFi',
    LBSignalType.ble           => 'BLE',
    LBSignalType.cell          => 'CELL',
    LBSignalType.cellNeighbor  => 'NBOR',
    _                          => '???',
  };
}
