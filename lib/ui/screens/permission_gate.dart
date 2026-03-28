import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';

class PermissionGate extends StatefulWidget {
  final Widget child;
  const PermissionGate({super.key, required this.child});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool _checking = true;
  bool _granted  = false;
  Map<String, PermissionStatus> _statuses = {};

  static final _required = {
    'Location (Fine)': Permission.locationWhenInUse,
    'Location (BG)':   Permission.locationAlways,
    'BLE Scan':        Permission.bluetoothScan,
    'Nearby Devices':  Permission.nearbyWifiDevices,
    'Phone State':     Permission.phone,
  };

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final statuses = <String, PermissionStatus>{};
    for (final e in _required.entries) {
      statuses[e.key] = await e.value.status;
    }
    final allOk = statuses.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );
    if (mounted) {
      setState(() {
        _statuses = statuses;
        _granted  = allOk;
        _checking = false;
      });
    }
  }

  Future<void> _requestAll() async {
    final results = await [
      Permission.locationWhenInUse,
      Permission.locationAlways,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
      Permission.phone,
    ].request();
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: LBColors.background,
        body: Center(
          child: CircularProgressIndicator(color: LBColors.blue, strokeWidth: 1),
        ),
      );
    }
    if (_granted) return widget.child;
    return _PermissionScreen(
      statuses:   _statuses,
      onRequest:  _requestAll,
      onContinue: () => setState(() => _granted = true),
    );
  }
}

class _PermissionScreen extends StatelessWidget {
  final Map<String, PermissionStatus> statuses;
  final VoidCallback onRequest;
  final VoidCallback onContinue;

  const _PermissionScreen({
    required this.statuses,
    required this.onRequest,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final allGranted = statuses.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );

    return Scaffold(
      backgroundColor: LBColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Text(
                'LITTLEBROTHER',
                style: LBTextStyles.displayLarge.copyWith(color: LBColors.blue),
              ),
              const SizedBox(height: 4),
              Text(
                'Passive RF Intelligence',
                style: LBTextStyles.label.copyWith(letterSpacing: 1.5),
              ),
              const SizedBox(height: 32),
              Text(
                'REQUIRED PERMISSIONS',
                style: LBTextStyles.label.copyWith(color: LBColors.cyan, letterSpacing: 2),
              ),
              const SizedBox(height: 12),
              ...statuses.entries.map((e) => _PermRow(name: e.key, status: e.value)),
              const Spacer(),
              if (!allGranted)
                _LBButton(
                  label: 'GRANT PERMISSIONS',
                  color: LBColors.blue,
                  onTap: onRequest,
                )
              else
                _LBButton(
                  label: 'CONTINUE',
                  color: LBColors.green,
                  onTap: onContinue,
                ),
              const SizedBox(height: 12),
              Text(
                'Some features (cellular) require additional permissions '
                'granted automatically at runtime.',
                style: LBTextStyles.label.copyWith(fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  final String name;
  final PermissionStatus status;
  const _PermRow({required this.name, required this.status});

  @override
  Widget build(BuildContext context) {
    final granted = status == PermissionStatus.granted || status == PermissionStatus.limited;
    final color   = granted ? LBColors.green : LBColors.yellow;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            granted ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 10),
          Text(name, style: LBTextStyles.body.copyWith(fontSize: 13)),
          const Spacer(),
          Text(
            status.name.toUpperCase(),
            style: LBTextStyles.label.copyWith(color: color, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _LBButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _LBButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: LBTextStyles.body.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}
