import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/models/lb_aggregate_map.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';

class AggregateMapScreen extends StatefulWidget {
  const AggregateMapScreen({super.key});

  @override
  State<AggregateMapScreen> createState() => _AggregateMapScreenState();
}

class _AggregateMapScreenState extends State<AggregateMapScreen> {
  final _db = LBDatabase.instance;
  bool _loading = true;
  String? _error;
  List<AggregateCell> _cells = [];
  int _maxObs = 1;

  CellPrecision _precision = CellPrecision.standard;
  TimeRange _timeRange = TimeRange.all;
  ThreatFilter _threatFilter = ThreatFilter.all;
  AggregateCell? _selectedCell;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _db.rebuildAggregateCells(precision: _precision.chars);
      final raw = await _db.getAggregateCells(
        precision: _precision.chars,
        minThreatFlag: _threatFilter.minFlag,
        sinceMs: _timeRange.cutoffMs,
      );
      final cells = raw.map((m) => AggregateCell.fromMap(m, precision: _precision.chars)).toList();
      final maxObs = cells.isEmpty ? 1 : cells.map((c) => c.observationCount).reduce(math.max);
      if (mounted) {
        setState(() {
          _cells = cells.take(200).toList();
          _maxObs = maxObs;
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('AggregateMap load error: $e\n$st');
      if (mounted) {
        setState(() { _loading = false; _error = e.toString(); });
      }
    }
  }

  void _onCellTap(AggregateCell cell) {
    setState(() => _selectedCell = cell);
  }

  void _dismissSheet() {
    setState(() => _selectedCell = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LBColors.background,
      appBar: AppBar(
        title: const Text('INTEL MAP'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 18, color: LBColors.blue),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: const BoxDecoration(
        color: LBColors.surface,
        border: Border(bottom: BorderSide(color: LBColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _label('RES'),
                const SizedBox(width: 4),
                ...CellPrecision.values.map((p) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _chip(
                    label: p.label,
                    selected: _precision == p,
                    onTap: () => setState(() {
                      _precision = p;
                      _load();
                    }),
                  ),
                )),
                const SizedBox(width: 12),
                _label('TIME'),
                const SizedBox(width: 4),
                ...TimeRange.values.map((t) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _chip(
                    label: t.label,
                    selected: _timeRange == t,
                    onTap: () => setState(() {
                      _timeRange = t;
                      _load();
                    }),
                  ),
                )),
                const SizedBox(width: 12),
                _label('THREAT'),
                const SizedBox(width: 4),
                ...ThreatFilter.values.map((t) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _chip(
                    label: t.label,
                    selected: _threatFilter == t,
                    onTap: () => setState(() {
                      _threatFilter = t;
                      _load();
                    }),
                  ),
                )),
              ],
            ),
          ),
          if (_cells.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_cells.length} cells  ·  max $_maxObs obs',
                style: LBTextStyles.label.copyWith(fontSize: 9, color: LBColors.dimText),
              ),
            ),
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(s, style: LBTextStyles.label.copyWith(fontSize: 9, color: LBColors.blue, letterSpacing: 1.5)),
  );

  Widget _chip({required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? LBColors.blue.withValues(alpha: 0.2) : Colors.transparent,
          border: Border.all(color: selected ? LBColors.blue : LBColors.border),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: LBTextStyles.label.copyWith(fontSize: 10, color: selected ? LBColors.blue : LBColors.dimText),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: LBColors.blue),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: LBColors.red, size: 32),
              const SizedBox(height: 12),
              Text(_error!, style: LBTextStyles.label.copyWith(color: LBColors.red), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _load,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: LBColors.blue),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('RETRY', style: LBTextStyles.label.copyWith(color: LBColors.blue)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_cells.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, color: LBColors.dimText, size: 48),
            const SizedBox(height: 12),
            Text('NO CELLS RECORDED', style: LBTextStyles.heading.copyWith(color: LBColors.dimText)),
            const SizedBox(height: 8),
            Text(
              'Start a scan session to populate the map',
              style: LBTextStyles.label.copyWith(color: LBColors.dimText),
            ),
          ],
        ),
      );
    }
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTap: _dismissSheet,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _GridPainter(
                      cells: _cells,
                      maxObs: _maxObs,
                      selectedCell: _selectedCell,
                      onCellTap: _onCellTap,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        _buildLegend(),
        if (_selectedCell != null)
          _buildBottomSheet(_selectedCell!),
      ],
    );
  }

  Widget _buildLegend() {
    return Positioned(
      bottom: _selectedCell != null ? 320 : 16,
      left: 12,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: LBColors.surface.withValues(alpha: 0.85),
          border: Border.all(color: LBColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SIGNAL', style: LBTextStyles.label.copyWith(fontSize: 8, letterSpacing: 1.5, color: LBColors.blue)),
            const SizedBox(height: 4),
            _legendRow(LBColors.blue, 'WiFi'),
            _legendRow(LBColors.cyan, 'BLE'),
            _legendRow(LBColors.orange, 'Cell'),
            const SizedBox(height: 6),
            Text('THREAT', style: LBTextStyles.label.copyWith(fontSize: 8, letterSpacing: 1.5, color: LBColors.blue)),
            const SizedBox(height: 4),
            _legendBorder(LBColors.green, 'Clean'),
            _legendBorder(LBColors.yellow, 'Watch'),
            _legendBorder(LBColors.red, 'Hostile'),
          ],
        ),
      ),
    );
  }

  Widget _legendRow(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(label, style: LBTextStyles.label.copyWith(fontSize: 9)),
      ],
    );
  }

  Widget _legendBorder(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(label, style: LBTextStyles.label.copyWith(fontSize: 9)),
      ],
    );
  }

  Widget _buildBottomSheet(AggregateCell cell) {
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: _CellDetailSheet(
        cell: cell,
        precision: _precision,
        onDismiss: _dismissSheet,
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final List<AggregateCell> cells;
  final int maxObs;
  final AggregateCell? selectedCell;
  final void Function(AggregateCell) onCellTap;

  _GridPainter({
    required this.cells,
    required this.maxObs,
    required this.selectedCell,
    required this.onCellTap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cells.isEmpty) return;

    final padding = 24.0;
    final availableW = size.width - padding * 2;
    final availableH = size.height - padding * 2;

    double minLat = cells.map((c) => c.lat).reduce(math.min);
    double maxLat = cells.map((c) => c.lat).reduce(math.max);
    double minLon = cells.map((c) => c.lon).reduce(math.min);
    double maxLon = cells.map((c) => c.lon).reduce(math.max);

    if ((maxLat - minLat).abs() < 0.0001) { maxLat = minLat + 0.001; }
    if ((maxLon - minLon).abs() < 0.0001) { maxLon = minLon + 0.001; }

    final rangeLat = maxLat - minLat;
    final rangeLon = maxLon - minLon;
    final aspectRatio = rangeLon / rangeLat;

    double gridW, gridH;
    if (aspectRatio > availableW / availableH) {
      gridW = availableW;
      gridH = availableW / aspectRatio;
    } else {
      gridH = availableH;
      gridW = availableH * aspectRatio;
    }

    final cols = math.max(2, (math.sqrt(cells.length * (gridW / gridH))).ceil());
    final rows = (cells.length / cols).ceil();
    final cellSize = math.min(gridW / cols, gridH / rows);

    final offsetX = padding + (availableW - gridW) / 2;
    final offsetY = padding + (availableH - gridH) / 2;

    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final col = i % cols;
      final row = i ~/ cols;
      final x = offsetX + col * cellSize;
      final y = offsetY + row * cellSize;

      final rect = Rect.fromLTWH(x + 2, y + 2, cellSize - 4, cellSize - 4);
      final density = cell.observationCount / maxObs;
      final fillColor = _typeColor(cell.dominantType).withValues(alpha: 0.15 + density * 0.6);

      final borderPaint = Paint()
        ..color = _threatColor(cell.worstFlag)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell.worstFlag > 0 ? 1.5 : 0.8;

      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;

      final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rRect, fillPaint);
      canvas.drawRRect(rRect, borderPaint);

      if (selectedCell?.geohash == cell.geohash) {
        canvas.drawRRect(
          rRect,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      if (cell.deviceCount > 1) {
        final dotPaint = Paint()..color = _threatColor(cell.worstFlag);
        canvas.drawCircle(Offset(rect.right - 5, rect.top + 5), 2.5, dotPaint);
      }
    }
  }

  Color _typeColor(String type) {
    return switch (type) {
      LBSignalType.wifi => LBColors.blue,
      LBSignalType.ble  => LBColors.cyan,
      _                 => LBColors.orange,
    };
  }

  Color _threatColor(int flag) {
    return switch (flag) {
      LBThreatFlag.watch   => LBColors.yellow,
      LBThreatFlag.hostile => LBColors.red,
      _                    => LBColors.green,
    };
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.cells != cells ||
      old.maxObs != maxObs ||
      old.selectedCell != selectedCell;
}

class _CellDetailSheet extends StatefulWidget {
  final AggregateCell cell;
  final CellPrecision precision;
  final VoidCallback onDismiss;
  const _CellDetailSheet({required this.cell, required this.precision, required this.onDismiss});

  @override
  State<_CellDetailSheet> createState() => _CellDetailSheetState();
}

class _CellDetailSheetState extends State<_CellDetailSheet> {
  List<DeviceProfile> _devices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await LBDatabase.instance.getDevicesAtCell(
        widget.cell.geohash,
        precision: widget.precision.chars,
      );
      if (mounted) {
        setState(() {
          _devices = raw.map((m) => DeviceProfile(
            identifier:       m['identifier'] as String,
            displayName:      m['display_name'] as String,
            signalType:       m['signal_type'] as String,
            vendor:           (m['vendor'] as String?) ?? '',
            observationCount: m['obs_count'] as int,
            cellCount:        m['cell_count'] as int,
            worstThreatFlag: m['worst_flag'] as int? ?? 0,
            firstSeen:        DateTime.fromMillisecondsSinceEpoch(m['first_seen'] as int),
            lastSeen:         DateTime.fromMillisecondsSinceEpoch(m['last_seen'] as int),
          )).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('CellDetail load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        height: 320,
        decoration: const BoxDecoration(
          color: LBColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          border: Border(top: BorderSide(color: LBColors.blue, width: 1.5)),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: widget.onDismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: LBColors.border)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _threatColor(widget.cell.worstFlag).withValues(alpha: 0.15),
                        border: Border.all(color: _threatColor(widget.cell.worstFlag)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        widget.cell.geohash,
                        style: LBTextStyles.label.copyWith(
                          color: _threatColor(widget.cell.worstFlag),
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.cell.lat.toStringAsFixed(5)}, ${widget.cell.lon.toStringAsFixed(5)}',
                            style: LBTextStyles.label.copyWith(fontSize: 9),
                          ),
                          Text(
                            '${widget.cell.observationCount} obs · ${widget.cell.deviceCount} devices',
                            style: LBTextStyles.label.copyWith(fontSize: 9, color: LBColors.dimText),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _countBadge(LBColors.blue, '${widget.cell.wifiCount}', 'WiFi'),
                        const SizedBox(width: 4),
                        _countBadge(LBColors.cyan, '${widget.cell.bleCount}', 'BLE'),
                        const SizedBox(width: 4),
                        _countBadge(LBColors.orange, '${widget.cell.cellCount}', 'Cell'),
                      ],
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.close, size: 16, color: LBColors.dimText),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: LBColors.blue))
                  : _devices.isEmpty
                      ? Center(child: Text('NO DEVICES', style: LBTextStyles.label.copyWith(color: LBColors.dimText)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _devices.length,
                          itemBuilder: (_, i) => _DeviceRow(profile: _devices[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countBadge(Color color, String count, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        '$count $label',
        style: LBTextStyles.label.copyWith(fontSize: 8, color: color),
      ),
    );
  }

  Color _threatColor(int flag) {
    return switch (flag) {
      LBThreatFlag.watch   => LBColors.yellow,
      LBThreatFlag.hostile => LBColors.red,
      _                    => LBColors.green,
    };
  }
}

class _DeviceRow extends StatelessWidget {
  final DeviceProfile profile;
  const _DeviceRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    final threatColor = switch (profile.worstThreatFlag) {
      LBThreatFlag.watch   => LBColors.yellow,
      LBThreatFlag.hostile => LBColors.red,
      _                    => LBColors.green,
    };
    final typeColor = switch (profile.signalType) {
      LBSignalType.wifi => LBColors.blue,
      LBSignalType.ble  => LBColors.cyan,
      _                  => LBColors.orange,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: threatColor, width: 2),
          bottom: const BorderSide(color: LBColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              border: Border.all(color: typeColor.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.center,
            child: Text(
              _typeLabel(profile.signalType),
              style: LBTextStyles.label.copyWith(fontSize: 8, color: typeColor),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName.isEmpty ? profile.identifier : profile.displayName,
                  style: LBTextStyles.body.copyWith(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  profile.identifier,
                  style: LBTextStyles.label.copyWith(fontSize: 9),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: profile.isMobile
                  ? LBColors.yellow.withValues(alpha: 0.1)
                  : LBColors.dimText.withValues(alpha: 0.1),
              border: Border.all(
                color: profile.isMobile
                    ? LBColors.yellow.withValues(alpha: 0.4)
                    : LBColors.dimText.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              profile.isMobile ? 'MOBILE' : 'STATIC',
              style: LBTextStyles.label.copyWith(
                fontSize: 8,
                color: profile.isMobile ? LBColors.yellow : LBColors.dimText,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${profile.observationCount}x',
                style: LBTextStyles.label.copyWith(fontSize: 10, color: LBColors.bodyText),
              ),
              Text(
                _fmtTime(profile.lastSeen),
                style: LBTextStyles.label.copyWith(fontSize: 8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _typeLabel(String type) {
    return switch (type) {
      LBSignalType.wifi => 'WIFI',
      LBSignalType.ble  => 'BLE',
      _                 => 'CELL',
    };
  }

  String _fmtTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
