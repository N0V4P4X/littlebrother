import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';

const _nativePerms = MethodChannel('art.n0v4.littlebrother/permissions');

class PermissionGate extends StatelessWidget {
  final Widget child;
  const PermissionGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return _NonAndroidGate(child: child);
    }
    return _AndroidPermissionGate(child: child);
  }
}

class _NonAndroidGate extends StatefulWidget {
  final Widget child;
  const _NonAndroidGate({required this.child});

  @override
  State<_NonAndroidGate> createState() => _NonAndroidGateState();
}

class _NonAndroidGateState extends State<_NonAndroidGate> {
  bool _accepted = false;

  String get _platformName {
    if (Platform.isIOS)     return 'iOS';
    if (Platform.isMacOS)   return 'macOS';
    if (Platform.isLinux)   return 'Linux';
    if (Platform.isWindows) return 'Windows';
    return 'this platform';
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted) return widget.child;
    return Scaffold(
      backgroundColor: LBColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text('LITTLEBROTHER',
                  style: LBTextStyles.displayLarge.copyWith(color: LBColors.blue)),
              const SizedBox(height: 4),
              Text('Passive RF Intelligence',
                  style: LBTextStyles.label.copyWith(letterSpacing: 1.5)),
              const SizedBox(height: 32),
              Text('PLATFORM NOTICE',
                  style: LBTextStyles.label.copyWith(
                      color: LBColors.cyan, letterSpacing: 2, fontSize: 11)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: LBColors.blue.withAlpha(20),
                  border: Border.all(color: LBColors.blue.withAlpha(80)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: LBColors.blue, size: 16),
                        const SizedBox(width: 8),
                        Text('Running on $_platformName',
                            style: LBTextStyles.body.copyWith(fontSize: 12, color: LBColors.blue)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'LittleBrother is built for Android. '
                      'Wi-Fi (${Platform.isLinux ? 'nmcli' : Platform.isMacOS ? 'networksetup' : 'limited'}) and BLE scanning are available. '
                      'Cellular, GPS, and OPSEC features require an Android device.',
                      style: LBTextStyles.body.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _InfoCard(
                text: 'Some features are disabled on $_platformName. '
                    'For full RF intelligence, use the Android app.',
                color: LBColors.orange,
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _accepted = true),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: LBColors.blue.withAlpha(25),
                    border: Border.all(color: LBColors.blue),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: Text('CONTINUE',
                      style: LBTextStyles.body.copyWith(
                          color: LBColors.blue, fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AndroidPermissionGate extends StatefulWidget {
  final Widget child;
  const _AndroidPermissionGate({required this.child});

  @override
  State<_AndroidPermissionGate> createState() => _AndroidPermissionGateState();
}

class _AndroidPermissionGateState extends State<_AndroidPermissionGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _skipped = false;
  Map<String, _PermInfo> _perms = {};

  static final _permDefs = [
    _PermDef('Location',            Permission.locationWhenInUse, optional: false),
    _PermDef('Background Location', Permission.locationAlways,    optional: false, nativeMethod: 'requestBackgroundLocation'),
    _PermDef('BLE Scan',            Permission.bluetoothScan,     optional: false),
    _PermDef('Phone State',         Permission.phone,             optional: false),
    _PermDef('Nearby Wi-Fi',        Permission.nearbyWifiDevices, optional: false,  nativeMethod: 'requestNearbyWifi'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAll();
  }

  Future<void> _checkAll() async {
    setState(() => _checking = true);
    final map = <String, _PermInfo>{};
    for (final def in _permDefs) {
      final status = await def.permission.status;
      debugPrint('LB_PERM [${def.label}] = $status');
      map[def.label] = _PermInfo(def: def, status: status);
    }
    if (mounted) setState(() { _perms = map; _checking = false; });
  }

  bool get _requiredGranted => _permDefs
      .where((d) => !d.optional)
      .every((d) => _perms[d.label]?.granted == true);

  Future<void> _requestOne(_PermInfo info) async {
    debugPrint('LB_PERM tapped: ${info.def.label} status=${info.status}');

    if (info.status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }

    // Background location: ensure foreground granted first
    if (info.def.label == 'Background Location') {
      final fg = _perms['Location'];
      if (fg == null || !fg.granted) {
        _showSnack('Grant "Location" first, then tap Background Location.');
        return;
      }
    }

    // Use native channel if defined — bypasses permission_handler Samsung quirk
    if (info.def.nativeMethod != null) {
      debugPrint('LB_PERM using native channel: ${info.def.nativeMethod}');
      try {
        final result = await _nativePerms.invokeMethod<String>(info.def.nativeMethod!);
        debugPrint('LB_PERM native result: $result');
      } on PlatformException catch (e) {
        debugPrint('LB_PERM native error: $e');
      }
    } else {
      final result = await info.def.permission.request();
      debugPrint('LB_PERM handler result: $result');
    }

    await _checkAll();
  }

  Future<void> _requestAll() async {
    // Phase 1 — standard permissions via permission_handler (batch safe)
    await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.phone,
    ].request();
    await _checkAll();

    // Phase 2 — background location via native channel (must follow fg location)
    if (_perms['Location']?.granted == true) {
      try {
        await _nativePerms.invokeMethod('requestBackgroundLocation');
      } on PlatformException catch (e) {
        debugPrint('LB_PERM bg location native error: $e');
      }
      // Re-check before proceeding so pendingResult is cleared
      await _checkAll();
    }

    // Phase 3 — nearby wifi via native channel (sequential — one pending at a time)
    try {
      await _nativePerms.invokeMethod('requestNearbyWifi');
    } on PlatformException catch (e) {
      debugPrint('LB_PERM nearby wifi native error: $e');
    }

    await _checkAll();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: LBTextStyles.body.copyWith(fontSize: 12)),
      backgroundColor: LBColors.surface,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: LBColors.background,
        body: Center(child: CircularProgressIndicator(
            color: LBColors.blue, strokeWidth: 1)),
      );
    }

    if (_requiredGranted || _skipped) return widget.child;

    final anyBlocked = _perms.values
        .any((i) => !i.def.optional && i.status.isPermanentlyDenied);

    return Scaffold(
      backgroundColor: LBColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text('LITTLEBROTHER',
                  style: LBTextStyles.displayLarge.copyWith(color: LBColors.blue)),
              const SizedBox(height: 4),
              Text('Passive RF Intelligence',
                  style: LBTextStyles.label.copyWith(letterSpacing: 1.5)),
              const SizedBox(height: 32),
              Text('PERMISSIONS',
                  style: LBTextStyles.label.copyWith(
                      color: LBColors.cyan, letterSpacing: 2, fontSize: 11)),
              const SizedBox(height: 4),
              Text('Tap any row to request individually.',
                  style: LBTextStyles.label.copyWith(fontSize: 10)),
              const SizedBox(height: 12),

              ..._permDefs.map((def) {
                final info = _perms[def.label];
                if (info == null) return const SizedBox.shrink();
                return _PermRow(info: info, onTap: () => _requestOne(info));
              }),

              const SizedBox(height: 12),

              // Raw status debug panel
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: LBColors.surface,
                  border: Border.all(color: LBColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RAW STATUS',
                        style: LBTextStyles.label.copyWith(
                            color: LBColors.blue, fontSize: 9, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    ..._perms.entries.map((e) => Text(
                          '${e.key}: ${e.value.status}',
                          style: LBTextStyles.label.copyWith(fontSize: 10),
                        )),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              if (anyBlocked)
                _InfoCard(
                    text: 'Permissions permanently blocked — tap to open Settings.',
                    color: LBColors.orange)
              else
                _InfoCard(
                    text: 'Grant Location first, then Background Location.',
                    color: LBColors.blue),

              const Spacer(),
              _LBButton(label: 'GRANT ALL', color: LBColors.blue, onTap: _requestAll),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _skipped = true),  // proceed with reduced capability
                  child: Text('SKIP — REDUCED CAPABILITY',
                      style: LBTextStyles.label.copyWith(
                          color: LBColors.dimText, fontSize: 10)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Types ────────────────────────────────────────────────────────────────────

class _PermDef {
  final String label;
  final Permission permission;
  final bool optional;
  final String? nativeMethod;
  const _PermDef(this.label, this.permission,
      {required this.optional, this.nativeMethod});
}

class _PermInfo {
  final _PermDef def;
  final PermissionStatus status;
  const _PermInfo({required this.def, required this.status});
  bool get granted =>
      status == PermissionStatus.granted || status == PermissionStatus.limited;
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _PermRow extends StatelessWidget {
  final _PermInfo info;
  final VoidCallback onTap;
  const _PermRow({required this.info, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final granted  = info.granted;
    final blocked  = info.status.isPermanentlyDenied;
    final optional = info.def.optional;

    final Color color = granted ? LBColors.green
        : blocked              ? LBColors.red
        : optional             ? LBColors.dimText
        :                        LBColors.yellow;

    final String badge = granted ? 'GRANTED'
        : blocked                ? 'BLOCKED — TAP FOR SETTINGS'
        : optional               ? 'OPTIONAL — TAP'
        :                          'TAP TO GRANT';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
              color: color.withValues(alpha: 0.06),
            ),
            child: Row(
              children: [
                Icon(
                  granted ? Icons.check_circle_outline
                      : blocked ? Icons.block
                      : Icons.touch_app_outlined,
                  color: color, size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(info.def.label,
                    style: LBTextStyles.body.copyWith(fontSize: 13))),
                Text(badge, style: LBTextStyles.label.copyWith(
                    color: color, fontSize: 9)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: color, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;
  final Color color;
  const _InfoCard({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06),
      border: Border(left: BorderSide(color: color, width: 2)),
      borderRadius: const BorderRadius.only(
          topRight: Radius.circular(3), bottomRight: Radius.circular(3)),
    ),
    child: Text(text, style: LBTextStyles.body.copyWith(fontSize: 12)),
  );
}

class _LBButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _LBButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(label, style: LBTextStyles.body.copyWith(
          color: color, fontWeight: FontWeight.bold, letterSpacing: 2)),
    ),
  );
}
