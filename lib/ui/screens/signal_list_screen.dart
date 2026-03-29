import 'package:flutter/material.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';
import 'package:littlebrother/ui/widgets/signal_tile.dart';

class SignalListScreen extends StatefulWidget {
  final List<LBSignal> signals;

  const SignalListScreen({super.key, required this.signals});

  @override
  State<SignalListScreen> createState() => _SignalListScreenState();
}

class _SignalListScreenState extends State<SignalListScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabs;
  final _sortNotifier = ValueNotifier<String>('rssi');
  List<LBSignal>? _cachedSignals;
  String? _cachedSortBy;

  final _tabTypes = [
    (label: 'ALL',  type: null),
    (label: 'Wi-Fi', type: LBSignalType.wifi),
    (label: 'BLE',   type: LBSignalType.ble),
    (label: 'CELL',  type: LBSignalType.cell),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabTypes.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _sortNotifier.dispose();
    super.dispose();
  }

  List<LBSignal> _filtered(String? type) {
    final sortBy = _sortNotifier.value;
    if (_cachedSignals == null || _cachedSortBy != sortBy) {
      _cachedSortBy = sortBy;
      var list = widget.signals.where((s) => s.identifier != 'DOWNGRADE_EVENT').toList();
      switch (sortBy) {
        case 'rssi': list.sort((a, b) => b.rssi.compareTo(a.rssi));
        case 'risk': list.sort((a, b) => b.riskScore.compareTo(a.riskScore));
        case 'name': list.sort((a, b) => a.displayName.compareTo(b.displayName));
      }
      _cachedSignals = list;
    }
    return type == null
        ? _cachedSignals!
        : _cachedSignals!.where((s) => s.signalType == type).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LBColors.background,
      appBar: AppBar(
        title: const Text('SIGNALS'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, size: 18, color: LBColors.blue),
            color: LBColors.surface,
            onSelected: (v) {
              _sortNotifier.value = v;
              _cachedSignals = null;
            },
            itemBuilder: (_) => [
              _menuItem('rssi', 'Sort by RSSI'),
              _menuItem('risk', 'Sort by Risk'),
              _menuItem('name', 'Sort by Name'),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: LBColors.cyan,
          unselectedLabelColor: LBColors.dimText,
          indicatorColor: LBColors.blue,
          labelStyle: LBTextStyles.label.copyWith(fontSize: 11, letterSpacing: 1),
          tabs: _tabTypes
              .map((t) => Tab(
                    text: t.label,
                    height: 36,
                  ))
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: _tabTypes
            .map((t) => _buildList(_filtered(t.type)))
            .toList(),
      ),
    );
  }

  Widget _buildList(List<LBSignal> signals) {
    if (signals.isEmpty) {
      return Center(
        child: Text(
          'NO SIGNALS',
          style: LBTextStyles.label.copyWith(letterSpacing: 2),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: signals.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, thickness: 1, color: LBColors.border),
      itemBuilder: (ctx, i) => SignalTile(signal: signals[i]),
    );
  }

  PopupMenuItem<String> _menuItem(String value, String label) =>
      PopupMenuItem(
        value: value,
        child: Text(label, style: LBTextStyles.body),
      );
}
