import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';

class ThreatLogScreen extends StatefulWidget {
  const ThreatLogScreen({super.key});

  @override
  State<ThreatLogScreen> createState() => _ThreatLogScreenState();
}

class _ThreatLogScreenState extends State<ThreatLogScreen> {
  List<LBThreatEvent> _events = [];
  bool _loading = true;
  bool _showDismissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final events = await LBDatabase.instance.getThreatEvents(
      includeDismissed: _showDismissed,
      limit: 200,
    );
    if (mounted) setState(() { _events = events; _loading = false; });
  }

  Future<void> _dismiss(int id) async {
    await LBDatabase.instance.dismissThreatEvent(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LBColors.background,
      appBar: AppBar(
        title: const Text('THREAT LOG'),
        actions: [
          IconButton(
            icon: Icon(
              _showDismissed ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: LBColors.blue,
            ),
            onPressed: () {
              setState(() => _showDismissed = !_showDismissed);
              _load();
            },
            tooltip: _showDismissed ? 'Hide dismissed' : 'Show dismissed',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18, color: LBColors.blue),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: LBColors.blue))
          : _events.isEmpty
              ? Center(
                  child: Text(
                    'NO THREATS RECORDED',
                    style: LBTextStyles.label.copyWith(letterSpacing: 2),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) => _ThreatCard(
                    event: _events[i],
                    onDismiss: _events[i].id != null && !_events[i].dismissed
                        ? () => _dismiss(_events[i].id!)
                        : null,
                  ),
                ),
    );
  }
}

class _ThreatCard extends StatelessWidget {
  final LBThreatEvent event;
  final VoidCallback? onDismiss;

  const _ThreatCard({required this.event, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final color = LBColors.severity(event.severity);
    final score = event.evidence['composite_score'];
    final fmt   = DateFormat('HH:mm:ss  dd MMM');

    return Container(
      decoration: BoxDecoration(
        color: LBColors.surface,
        border: Border(left: BorderSide(color: color, width: 3)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(3),
          bottomRight: Radius.circular(3),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        iconColor: LBColors.dimText,
        collapsedIconColor: LBColors.dimText,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                border: Border.all(color: color.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                event.severityLabel,
                style: LBTextStyles.label.copyWith(color: color, fontSize: 9),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _typeLabel(event.threatType),
                style: LBTextStyles.body.copyWith(
                  color: event.dismissed ? LBColors.dimText : LBColors.bodyText,
                ),
              ),
            ),
            if (score != null)
              Text(
                'score: $score',
                style: LBTextStyles.label.copyWith(fontSize: 10),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${event.identifier}  ·  ${fmt.format(event.timestamp)}',
            style: LBTextStyles.label.copyWith(fontSize: 10),
          ),
        ),
        children: [
          _EvidenceTable(evidence: event.evidence),
          if (onDismiss != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: LBColors.dimText,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  side: const BorderSide(color: LBColors.border),
                ),
                child: Text(
                  'DISMISS',
                  style: LBTextStyles.label.copyWith(fontSize: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _typeLabel(String type) => switch (type) {
    LBThreatType.stingray    => 'IMSI CATCHER / STINGRAY',
    LBThreatType.downgrade   => 'NETWORK DOWNGRADE',
    LBThreatType.rogueAp     => 'ROGUE ACCESS POINT',
    LBThreatType.bleTracker  => 'BLE TRACKER',
    LBThreatType.watchlist   => 'WATCHLIST HIT',
    LBThreatType.silentSms   => 'SILENT SMS',
    LBThreatType.smsExfil    => 'SMS EXFILTRATION',
    LBThreatType.dnsAnomaly  => 'DNS ANOMALY',
    LBThreatType.deviceComp  => 'DEVICE COMPROMISED',
    LBThreatType.processAnom => 'PROCESS ANOMALY',
    LBThreatType.deauthStorm => 'DEAUTH ATTACK',
    _                       => type.toUpperCase(),
  };
}

class _EvidenceTable extends StatelessWidget {
  final Map<String, dynamic> evidence;
  const _EvidenceTable({required this.evidence});

  @override
  Widget build(BuildContext context) {
    final heuristics = evidence['heuristics'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 12, color: LBColors.border),
        ...heuristics.entries.map((e) {
          final val = e.value as Map<String, dynamic>?;
          final detail = val?['detail'] as String? ?? '';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('▸ ', style: LBTextStyles.label.copyWith(color: LBColors.blue)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.key.toUpperCase().replaceAll('_', ' '),
                        style: LBTextStyles.label.copyWith(color: LBColors.cyan, fontSize: 10),
                      ),
                      if (detail.isNotEmpty)
                        Text(detail, style: LBTextStyles.label.copyWith(fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        if (heuristics.isEmpty)
          Text(
            evidence.toString(),
            style: LBTextStyles.label.copyWith(fontSize: 10),
          ),
      ],
    );
  }
}
