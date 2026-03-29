import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<LBSession> _sessions = [];
  List<LBThreatEvent> _recentThreats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = LBDatabase.instance;
      final sessions = await db.getSessions(limit: 50);
      final threats = await db.getThreatEvents(limit: 100);
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _recentThreats = threats;
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('LB_TIMELINE load error: $e\n$st');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _exportSession(LBSession session) async {
    final db = LBDatabase.instance;
    final observations = await db.getObservationsBySession(session.id);
    
    final buffer = StringBuffer();
    buffer.writeln('Type,Identifier,Display Name,RSSI,dBm,Distance m,Risk Score,Lat,Lon,Timestamp');
    
    for (final o in observations) {
      buffer.writeln([
        o.signalType,
        o.identifier,
        '"${o.displayName.replaceAll('"', '""')}"',
        o.rssi,
        o.rssi,
        o.distanceM.toStringAsFixed(2),
        o.riskScore,
        o.lat?.toStringAsFixed(6) ?? '',
        o.lon?.toStringAsFixed(6) ?? '',
        o.timestamp.toIso8601String(),
      ].join(','));
    }
    
    final dir = await getTemporaryDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(session.startedAt);
    final file = File('${dir.path}/littlebrother_session_$ts.csv');
    await file.writeAsString(buffer.toString());
    
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'LittleBrother Session Export'),
      );
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _exportThreats() async {
    if (_recentThreats.isEmpty) return;
    
    final buffer = StringBuffer();
    buffer.writeln('Type,Severity,Identifier,Lat,Lon,Timestamp,Evidence');
    
    for (final t in _recentThreats) {
      buffer.writeln([
        t.threatType,
        t.severityLabel,
        '"${t.identifier}"',
        t.lat?.toStringAsFixed(6) ?? '',
        t.lon?.toStringAsFixed(6) ?? '',
        t.timestamp.toIso8601String(),
        '"${t.evidence.toString().replaceAll('"', '""')}"',
      ].join(','));
    }
    
    final dir = await getTemporaryDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/littlebrother_threats_$ts.csv');
    await file.writeAsString(buffer.toString());
    
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'LittleBrother Threat Export'),
      );
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LBColors.background,
      appBar: AppBar(
        title: const Text('INTEL TIMELINE'),
        actions: [
          if (_recentThreats.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download, size: 18, color: LBColors.blue),
              onPressed: _exportThreats,
              tooltip: 'Export threats',
            ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18, color: LBColors.blue),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: LBColors.blue))
          : CustomScrollView(
              slivers: [
                if (_recentThreats.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('RECENT THREATS', style: LBTextStyles.heading),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _recentThreats.length.clamp(0, 20),
                        itemBuilder: (_, i) => _ThreatMini(event: _recentThreats[i]),
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Text('SESSION HISTORY', style: LBTextStyles.heading),
                  ),
                ),
                if (_sessions.isEmpty)
                  const SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'NO SESSIONS RECORDED',
                        style: TextStyle(
                          fontFamily: 'Courier New',
                          color: LBColors.dimText,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _SessionCard(
                        session: _sessions[i],
                        onExport: () => _exportSession(_sessions[i]),
                      ),
                      childCount: _sessions.length,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
    );
  }
}

class _ThreatMini extends StatelessWidget {
  final LBThreatEvent event;
  const _ThreatMini({required this.event});

  @override
  Widget build(BuildContext context) {
    final color = LBColors.severity(event.severity);
    final fmt = DateFormat('HH:mm');
    
    return Container(
      width: 100,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LBColors.surface,
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              event.severityLabel,
              style: LBTextStyles.label.copyWith(color: color, fontSize: 9),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _typeLabel(event.threatType),
            style: LBTextStyles.label.copyWith(fontSize: 10, color: LBColors.bodyText),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Text(
            fmt.format(event.timestamp),
            style: LBTextStyles.label.copyWith(fontSize: 9),
          ),
        ],
      ),
    );
  }

  String _typeLabel(String type) => switch (type) {
    'stingray' => 'STINGRAY',
    'downgrade' => 'DOWNGRADE',
    'rogue_ap' => 'ROGUE AP',
    'ble_tracker' => 'BLE TRACKER',
    _ => type.toUpperCase(),
  };
}

class _SessionCard extends StatelessWidget {
  final LBSession session;
  final VoidCallback onExport;
  
  const _SessionCard({required this.session, required this.onExport});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy');
    final timeFmt = DateFormat('HH:mm:ss');
    final duration = session.endedAt
        ?.difference(session.startedAt);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: LBColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LBColors.border),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        iconColor: LBColors.dimText,
        collapsedIconColor: LBColors.dimText,
        title: Row(
          children: [
            Expanded(
              child: Text(
                fmt.format(session.startedAt),
                style: LBTextStyles.body.copyWith(color: LBColors.cyan),
              ),
            ),
            Text(
              timeFmt.format(session.startedAt),
              style: LBTextStyles.label,
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              _StatChip(
                icon: Icons.radar,
                value: '${session.observationCount}',
                color: LBColors.blue,
              ),
              const SizedBox(width: 12),
              _StatChip(
                icon: Icons.warning,
                value: '${session.threatCount}',
                color: session.threatCount > 0 ? LBColors.red : LBColors.dimText,
              ),
              const SizedBox(width: 12),
              if (duration != null)
                Text(
                  _formatDuration(duration),
                  style: LBTextStyles.label,
                ),
            ],
          ),
        ),
        children: [
          const Divider(height: 16, color: LBColors.border),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.download, size: 14),
                label: const Text('EXPORT CSV'),
                style: TextButton.styleFrom(
                  foregroundColor: LBColors.cyan,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _StatChip({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(value, style: LBTextStyles.label.copyWith(color: color)),
      ],
    );
  }
}
