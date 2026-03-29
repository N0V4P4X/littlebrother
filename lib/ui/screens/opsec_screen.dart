import 'package:flutter/material.dart';
import 'package:littlebrother/opsec/opsec_controller.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';

class OpsecScreen extends StatefulWidget {
  final OpsecController opsec;
  final bool opsecAutoEnabled;
  final ValueChanged<bool> onAutoToggle;

  const OpsecScreen({
    super.key,
    required this.opsec,
    required this.opsecAutoEnabled,
    required this.onAutoToggle,
  });

  @override
  State<OpsecScreen> createState() => _OpsecScreenState();
}

class _OpsecScreenState extends State<OpsecScreen> {
  String? _lastAction;
  bool _busy = false;

  Future<void> _killRf() async {
    setState(() { _busy = true; _lastAction = null; });
    final result = await widget.opsec.killRf();
    if (mounted) setState(() { _busy = false; _lastAction = result; });
  }

  Future<void> _restoreRf() async {
    setState(() { _busy = true; _lastAction = null; });
    final result = await widget.opsec.restoreRf();
    if (mounted) setState(() { _busy = false; _lastAction = result; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LBColors.background,
      appBar: AppBar(title: const Text('OPSEC')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('RF KILL CONTROLS'),
          const SizedBox(height: 8),
          _InfoCard(
            text: widget.opsec.canKillRf
                ? 'WRITE_SETTINGS granted — airplane mode available.'
                : 'WRITE_SETTINGS not granted. RF kill will attempt Wi-Fi disable only.\nGrant via Settings → Apps → LittleBrother → Permissions.',
            color: widget.opsec.canKillRf ? LBColors.green : LBColors.yellow,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'KILL RF',
                  sublabel: 'Airplane mode / disable radios',
                  color: LBColors.red,
                  busy: _busy,
                  onTap: _killRf,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'RESTORE RF',
                  sublabel: 'Re-enable radios',
                  color: LBColors.green,
                  busy: _busy,
                  onTap: _restoreRf,
                ),
              ),
            ],
          ),
          if (_lastAction != null) ...[
            const SizedBox(height: 8),
            _InfoCard(text: _lastAction!, color: LBColors.cyan),
          ],
          const SizedBox(height: 24),

          _sectionHeader('AUTOMATION'),
          const SizedBox(height: 8),
          _ToggleRow(
            label: 'Auto RF Kill on CRITICAL Threat',
            sublabel: 'Automatically triggers RF kill when a CRITICAL severity event is detected',
            value: widget.opsecAutoEnabled,
            onChanged: widget.onAutoToggle,
            activeColor: LBColors.red,
          ),
          const SizedBox(height: 24),

          _sectionHeader('PASSIVE MODE'),
          const SizedBox(height: 8),
          _InfoCard(
            text: 'LittleBrother operates in passive receive-only mode. '
                  'No signals are transmitted, injected, or jammed. '
                  'Active jamming or spoofing is illegal under 18 U.S.C. § 1362 and FCC Part 97.',
            color: LBColors.blue,
          ),
          const SizedBox(height: 24),

          if (!widget.opsec.canKillRf) ...[
            _sectionHeader('PERMISSIONS'),
            const SizedBox(height: 8),
            _ActionButton(
              label: 'REQUEST WRITE_SETTINGS',
              sublabel: 'Required for airplane mode control',
              color: LBColors.blue,
              busy: false,
              onTap: widget.opsec.requestWriteSettingsPermission,
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Text(
    title,
    style: LBTextStyles.label.copyWith(
      color: LBColors.blue,
      fontSize: 11,
      letterSpacing: 2,
    ),
  );
}

class _InfoCard extends StatelessWidget {
  final String text;
  final Color color;
  const _InfoCard({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        border: Border(left: BorderSide(color: color, width: 2)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(3),
          bottomRight: Radius.circular(3),
        ),
      ),
      child: Text(text, style: LBTextStyles.body.copyWith(fontSize: 12)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;
  final bool busy;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.busy,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          border: Border.all(color: color.withOpacity(0.5), width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            if (busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: color, strokeWidth: 1.5),
              )
            else
              Text(
                label,
                style: LBTextStyles.body.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              sublabel,
              style: LBTextStyles.label.copyWith(fontSize: 9),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  const _ToggleRow({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.onChanged,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: LBColors.surface,
        border: Border.all(color: LBColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: LBTextStyles.body.copyWith(fontSize: 12)),
                const SizedBox(height: 2),
                Text(sublabel, style: LBTextStyles.label.copyWith(fontSize: 10)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: activeColor,
            trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? activeColor.withOpacity(0.3)
                  : LBColors.border,
            ),
          ),
        ],
      ),
    );
  }
}
