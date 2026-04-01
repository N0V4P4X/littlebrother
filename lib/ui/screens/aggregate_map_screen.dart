import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/models/lb_aggregate_map.dart';
import 'package:littlebrother/modules/gps/gps_tracker.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';
import 'package:littlebrother/ui/widgets/lb_map_view.dart';

class AggregateMapScreen extends StatefulWidget {
  const AggregateMapScreen({super.key});

  @override
  State<AggregateMapScreen> createState() => _AggregateMapScreenState();
}

class _AggregateMapScreenState extends State<AggregateMapScreen> {
  final _db = LBDatabase.instance;
  bool _loading = true;
  String? _error;
  bool _loadRunning = false;

  MapLayer _layer = MapLayer.grid;
  TimeRange _timeRange = TimeRange.all;
  ThreatFilter _threatFilter = ThreatFilter.all;
  int _tileProviderIndex = 1; // Default to CartoDB Voyager
  int _gridPrecision = 7; // Default precision (150m)

  List<AggregateCell> _gridCells = [];
  List<CellTower> _towers = [];
  List<WifiDevice> _wifiDevices = [];
  List<BleDevice> _bleDevices = [];
  LatLng? _currentLocation;

  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    try {
      await _db.migrateGeohashForExistingObservations();
    } catch (e) {
      debugPrint('AggregateMap: geohash migration error (non-fatal): $e');
    }
    _load();
    _startGpsUpdates();
  }

  void _startGpsUpdates() {
    final gps = GpsTracker.instance;
    if (gps.hasFreshFix && gps.lastPosition != null) {
      setState(() {
        _currentLocation = LatLng(
          gps.lastPosition!.latitude,
          gps.lastPosition!.longitude,
        );
      });
    }
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && gps.hasFreshFix && gps.lastPosition != null) {
        setState(() {
          _currentLocation = LatLng(
            gps.lastPosition!.latitude,
            gps.lastPosition!.longitude,
          );
        });
      }
    });
  }

  Future<void> _load() async {
    if (_loadRunning) return;
    _loadRunning = true;
    setState(() => _loading = true);

    try {
      final sinceMs = _timeRange.cutoffMs;

      if (_layer == MapLayer.grid) {
        await _db.rebuildAggregateCells(precision: _gridPrecision);
        final cells = await _db.getAggregateCells(
          precision: _gridPrecision,
          minThreatFlag: _threatFilter.minFlag,
          sinceMs: sinceMs,
          limit: 200,
        );
        final cellObjects = cells.map((m) => AggregateCell.fromMap(m, precision: _gridPrecision)).toList();
        final maxObs = cells.isEmpty ? 1 : cells.map((c) => c['obs_count'] as int? ?? 1).reduce((a, b) => a > b ? a : b);
        setState(() {
          _gridCells = cellObjects;
          _maxObs = maxObs;
          _loading = false;
        });
        debugPrint('AggregateMap: loaded ${_gridCells.length} grid cells');
      } else if (_layer == MapLayer.towers) {
        final towers = await _db.getCellTowers(
          minSeverity: _threatFilter.minFlag != null ? LBSeverity.medium : null,
          sinceMs: sinceMs,
          limit: 500,
        );
        setState(() {
          _towers = towers;
          _loading = false;
        });
        debugPrint('AggregateMap: loaded ${_towers.length} towers');
        for (final t in towers) {
          debugPrint('  Tower: ${t.cellKey} lat=${t.position.latitude.toStringAsFixed(5)} lon=${t.position.longitude.toStringAsFixed(5)}');
        }
      } else if (_layer == MapLayer.wifi) {
        final wifi = await _db.getWifiDevices(
          minSeverity: _threatFilter.minFlag != null ? LBSeverity.medium : null,
          sinceMs: sinceMs,
          limit: 500,
        );
        setState(() {
          _wifiDevices = wifi;
          _loading = false;
        });
        debugPrint('AggregateMap: loaded ${_wifiDevices.length} WiFi devices');
      } else if (_layer == MapLayer.ble) {
        final ble = await _db.getBleDevices(
          minSeverity: _threatFilter.minFlag != null ? LBSeverity.medium : null,
          sinceMs: sinceMs,
          limit: 500,
        );
        setState(() {
          _bleDevices = ble;
          _loading = false;
        });
        debugPrint('AggregateMap: loaded ${_bleDevices.length} BLE devices');
        for (final b in ble) {
          debugPrint('  BLE: ${b.mac} lat=${b.position.latitude.toStringAsFixed(5)} lon=${b.position.longitude.toStringAsFixed(5)}');
        }
      }
    } catch (e, st) {
      debugPrint('AggregateMap load error: $e\n$st');
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    } finally {
      _loadRunning = false;
    }
  }

  int _maxObs = 1;

  void _onLayerChange(MapLayer layer) {
    setState(() => _layer = layer);
    _load();
  }

  void _onFilterChange() {
    _load();
  }

  void _changePrecision(int precision) {
    setState(() {
      _gridPrecision = precision;
    });
    _load();
  }

  LatLng _getMapCenter() {
    if (_layer == MapLayer.grid && _gridCells.isNotEmpty) {
      final lats = _gridCells.map((c) => c.lat);
      final lons = _gridCells.map((c) => c.lon);
      return LatLng(
        (lats.reduce(math.min) + lats.reduce(math.max)) / 2,
        (lons.reduce(math.min) + lons.reduce(math.max)) / 2,
      );
    } else if (_layer == MapLayer.towers && _towers.isNotEmpty) {
      final lats = _towers.map((t) => t.position.latitude);
      final lons = _towers.map((t) => t.position.longitude);
      return LatLng(
        (lats.reduce(math.min) + lats.reduce(math.max)) / 2,
        (lons.reduce(math.min) + lons.reduce(math.max)) / 2,
      );
    } else if (_layer == MapLayer.wifi && _wifiDevices.isNotEmpty) {
      final lats = _wifiDevices.map((d) => d.position.latitude);
      final lons = _wifiDevices.map((d) => d.position.longitude);
      return LatLng(
        (lats.reduce(math.min) + lats.reduce(math.max)) / 2,
        (lons.reduce(math.min) + lons.reduce(math.max)) / 2,
      );
    } else if (_layer == MapLayer.ble && _bleDevices.isNotEmpty) {
      final lats = _bleDevices.map((d) => d.position.latitude);
      final lons = _bleDevices.map((d) => d.position.longitude);
      return LatLng(
        (lats.reduce(math.min) + lats.reduce(math.max)) / 2,
        (lons.reduce(math.min) + lons.reduce(math.max)) / 2,
      );
    }
    return _currentLocation ?? const LatLng(37.7749, -122.4194);
  }

  List<Marker> _getMarkers() {
    switch (_layer) {
      case MapLayer.grid:
        return [];
      case MapLayer.towers:
        return _towers.map((t) => _buildTowerMarker(t)).toList();
      case MapLayer.wifi:
        return _wifiDevices.map((w) => _buildWifiMarker(w)).toList();
      case MapLayer.ble:
        return _bleDevices.map((b) => _buildBleMarker(b)).toList();
    }
  }

  Marker _buildTowerMarker(CellTower tower) {
    final size = (8 + math.min(tower.observationCount, 20)).toDouble();
    final color = _threatColor(tower.worstThreatFlag);
    return Marker(
      point: tower.position,
      width: size + 12,
      height: size + 12,
      child: GestureDetector(
        onTap: () => _showTowerDetail(tower),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: tower.worstThreatFlag > 0
                  ? Icon(Icons.warning, size: size * 0.5, color: Colors.white)
                  : const Icon(Icons.cell_tower, size: 12, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildWifiMarker(WifiDevice wifi) {
    final size = (8 + math.min(wifi.observationCount, 20)).toDouble();
    final color = LBColors.blue;
    return Marker(
      point: wifi.position,
      width: size + 12,
      height: size + 12,
      child: GestureDetector(
        onTap: () => _showWifiDetail(wifi),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi, size: 10, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildBleMarker(BleDevice ble) {
    final size = (8 + math.min(ble.observationCount, 20)).toDouble();
    final color = ble.isTracker ? LBColors.red : LBColors.cyan;
    return Marker(
      point: ble.position,
      width: size + 12,
      height: size + 12,
      child: GestureDetector(
        onTap: () => _showBleDetail(ble),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: Icon(
                ble.isTracker ? Icons.track_changes : Icons.bluetooth,
                size: 10,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _threatColor(int flag) {
    return switch (flag) {
      LBThreatFlag.watch => LBColors.yellow,
      LBThreatFlag.hostile => LBColors.red,
      _ => LBColors.green,
    };
  }

  void _showTowerDetail(CellTower tower) {
    showModalBottomSheet(
      context: context,
      backgroundColor: LBColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cell Tower: ${tower.cellKey}', style: LBTextStyles.heading),
            const SizedBox(height: 8),
            Text('Type: ${tower.networkType}', style: LBTextStyles.body),
            Text('Band: ${tower.band ?? "Unknown"}', style: LBTextStyles.body),
            Text('PCI: ${tower.pci}', style: LBTextStyles.body),
            Text('Operator: ${tower.operator ?? "Unknown"}', style: LBTextStyles.body),
            Text('Observations: ${tower.observationCount}', style: LBTextStyles.body),
            Text('Position: ${tower.position.latitude.toStringAsFixed(5)}, ${tower.position.longitude.toStringAsFixed(5)}', style: LBTextStyles.label),
          ],
        ),
      ),
    );
  }

  void _showWifiDetail(WifiDevice wifi) {
    showModalBottomSheet(
      context: context,
      backgroundColor: LBColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WiFi: ${wifi.ssid.isEmpty ? "[hidden]" : wifi.ssid}', style: LBTextStyles.heading),
            const SizedBox(height: 8),
            Text('BSSID: ${wifi.bssid}', style: LBTextStyles.body),
            Text('Vendor: ${wifi.vendor}', style: LBTextStyles.body),
            Text('Channel: ${wifi.channel ?? "Unknown"}', style: LBTextStyles.body),
            Text('Security: ${wifi.security ?? "Unknown"}', style: LBTextStyles.body),
            Text('Observations: ${wifi.observationCount}', style: LBTextStyles.body),
          ],
        ),
      ),
    );
  }

  void _showBleDetail(BleDevice ble) {
    showModalBottomSheet(
      context: context,
      backgroundColor: LBColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BLE: ${ble.displayName.isEmpty ? ble.mac : ble.displayName}', style: LBTextStyles.heading),
            const SizedBox(height: 8),
            Text('MAC: ${ble.mac}', style: LBTextStyles.body),
            Text('RSSI: ${ble.rssi} dBm', style: LBTextStyles.body),
            Text('Tracker: ${ble.isTracker ? "Yes" : "No"}', style: LBTextStyles.body),
            Text('Observations: ${ble.observationCount}', style: LBTextStyles.body),
          ],
        ),
      ),
    );
  }

  void _fitAllMarkers() {
    final markers = _getMarkers();
    if (markers.isEmpty) return;

    final points = markers.map((m) => m.point).toList();
    
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLon = points.first.longitude;
    double maxLon = points.first.longitude;
    
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    
    final bounds = LatLngBounds(
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LBColors.background,
      appBar: AppBar(
        title: const Text('INTEL MAP'),
        backgroundColor: LBColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.fit_screen),
            onPressed: _fitAllMarkers,
            tooltip: 'Fit all markers',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: LBColors.blue))
                : _error != null
                    ? Center(child: Text('Error: $_error', style: LBTextStyles.body))
                    : LBMapView(
                        initialCenter: _getMapCenter(),
                        initialZoom: 14,
                        markers: _getMarkers(),
                        gridCells: _gridCells,
                        gridPrecision: _gridPrecision,
                        showLocationButton: _currentLocation != null,
                        currentLocation: _currentLocation,
                        tileProviderIndex: _tileProviderIndex,
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: LBColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildLabel('LAYER'),
            const SizedBox(width: 4),
            ...MapLayer.values.map((l) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildChip(
                label: l.label,
                selected: _layer == l,
                onTap: () => _onLayerChange(l),
              ),
            )),
            const SizedBox(width: 12),
            _buildLabel('TIME'),
            const SizedBox(width: 4),
            ...TimeRange.values.map((t) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildChip(
                label: t.label,
                selected: _timeRange == t,
                onTap: () => setState(() {
                  _timeRange = t;
                  _onFilterChange();
                }),
              ),
            )),
            const SizedBox(width: 12),
            _buildLabel('THREAT'),
            const SizedBox(width: 4),
            ...ThreatFilter.values.map((t) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildChip(
                label: t.label,
                selected: _threatFilter == t,
                onTap: () => setState(() {
                  _threatFilter = t;
                  _onFilterChange();
                }),
              ),
            )),
            if (_layer == MapLayer.grid) ...[
              const SizedBox(width: 12),
              _buildLabel('GRID'),
              const SizedBox(width: 4),
              _buildChip(label: '7 (150m)', selected: _gridPrecision == 7, onTap: () => _changePrecision(7)),
              _buildChip(label: '6 (1km)', selected: _gridPrecision == 6, onTap: () => _changePrecision(6)),
              _buildChip(label: '8 (38m)', selected: _gridPrecision == 8, onTap: () => _changePrecision(8)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text, style: LBTextStyles.label.copyWith(fontSize: 10, color: LBColors.dimText));
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? LBColors.blue.withValues(alpha: 0.2) : Colors.transparent,
          border: Border.all(
            color: selected ? LBColors.blue : LBColors.border,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: LBTextStyles.label.copyWith(
            fontSize: 11,
            color: selected ? LBColors.blue : LBColors.dimText,
          ),
        ),
      ),
    );
  }
}