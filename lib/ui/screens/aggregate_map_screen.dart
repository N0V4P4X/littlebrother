import 'dart:async' show Timer;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/models/lb_aggregate_map.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';

String _formatDate(DateTime dt) {
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class AggregateMapScreen extends StatefulWidget {
  const AggregateMapScreen({super.key});

  @override
  State<AggregateMapScreen> createState() => _AggregateMapScreenState();
}

class _AggregateMapScreenState extends State<AggregateMapScreen> {
  final _db = LBDatabase.instance;
  final _mapController = MapController();
  bool _loading = true;
  String? _error;
  bool _loadRunning = false;
  Timer? _debounceTimer;
  String? _gpsStatus;

  MapLayer _layer = MapLayer.grid;
  bool _includeNeighbors = false;
  CellPrecision _precision = CellPrecision.standard;
  TimeRange _timeRange = TimeRange.all;
  ThreatFilter _threatFilter = ThreatFilter.all;
  
  List<AggregateCell> _gridCells = [];
  List<CellTower> _towers = [];
  List<WifiDevice> _wifiDevices = [];
  List<BleDevice> _bleDevices = [];
  List<TestThreat> _testThreats = [];
  int _maxObs = 1;
  AggregateCell? _selectedGridCell;
  CellTower? _selectedTower;
  WifiDevice? _selectedWifi;
  BleDevice? _selectedBle;
  TestThreat? _selectedTestThreat;

  List<MapLayer> get _visibleLayers => kDebugMode 
      ? MapLayer.values 
      : MapLayer.values.where((l) => l != MapLayer.test).toList();

  @override
  void initState() {
    super.initState();
    _initDbAndLoad();
  }

  Future<void> _initDbAndLoad() async {
    // Migrate any existing observations that might be missing geohash
    try {
      await _db.migrateGeohashForExistingObservations();
    } catch (e) {
      debugPrint('AggregateMap: geohash migration error (non-fatal): $e');
    }
    _load();
  }

  Future<void> _load() async {
    if (_loadRunning) return;
    if (_layer == MapLayer.test && !kDebugMode) {
      setState(() => _layer = MapLayer.grid);
      return;
    }
    _loadRunning = true;
    setState(() { _loading = true; _error = null; });
    try {
      final sinceMs = _timeRange.cutoffMs;
      final minSeverity = _threatFilter.minFlag != null ? 
          (_threatFilter == ThreatFilter.hostile ? LBSeverity.high : LBSeverity.medium) : null;

      if (_layer == MapLayer.grid) {
        await _db.rebuildAggregateCells(precision: _precision.chars);
        final raw = await _db.getAggregateCells(
          precision: _precision.chars,
          minThreatFlag: _threatFilter.minFlag,
          sinceMs: sinceMs,
          limit: 200,
        );
        final cells = raw.map((m) => AggregateCell.fromMap(m, precision: _precision.chars)).toList();
        final maxObs = cells.isEmpty ? 1 : cells.map((c) => c.observationCount).reduce(math.max);
        
        // Get GPS and observation stats for debugging
        final gpsStatus = await _db.getGpsStatus();
        final obsStats = await _db.getObservationStats();
        final waypointCount = await _db.getWaypointCount();
        final gpsStatusStr = gpsStatus['hasFreshFix'] == true 
            ? 'GPS: ✓ lat=${gpsStatus['lastPosition']?['lat']?.toStringAsFixed(4)}, lon=${gpsStatus['lastPosition']?['lon']?.toStringAsFixed(4)}'
            : 'GPS: ✗ running=${gpsStatus['isRunning']}, freshFix=${gpsStatus['hasFreshFix']}, error=${gpsStatus['lastError']}';
        final obsStatusStr = 'Data: ${obsStats['total']} obs, ${obsStats['withLatLon']} geo, $waypointCount waypoints, ${obsStats['gridCells']} cells';
        
        if (mounted) {
          setState(() {
            _gridCells = cells;
            _maxObs = maxObs;
            _loading = false;
            _gpsStatus = '$gpsStatusStr\n$obsStatusStr';
          });
        }
      } else if (_layer == MapLayer.towers) {
        final towers = await _db.getCellTowers(
          minSeverity: minSeverity,
          sinceMs: sinceMs,
          includeNeighbors: _includeNeighbors,
          limit: 500,
        );
        if (mounted) {
          setState(() {
            _towers = towers;
            _loading = false;
          });
        }
      } else if (_layer == MapLayer.wifi) {
        final wifi = await _db.getWifiDevices(
          minSeverity: minSeverity,
          sinceMs: sinceMs,
          limit: 500,
        );
        if (mounted) {
          setState(() {
            _wifiDevices = wifi;
            _loading = false;
          });
        }
      } else if (_layer == MapLayer.ble) {
        final ble = await _db.getBleDevices(
          minSeverity: minSeverity,
          sinceMs: sinceMs,
          limit: 500,
        );
        if (mounted) {
          setState(() {
            _bleDevices = ble;
            _loading = false;
          });
        }
      } else if (_layer == MapLayer.test && kDebugMode) {
        if (mounted) {
          setState(() {
            _testThreats = MockCommunityData.getMockThreats();
            _loading = false;
          });
        }
      }
    } catch (e, st) {
      debugPrint('AggregateMap load error: $e\n$st');
      if (mounted) {
        setState(() { _loading = false; _error = e.toString(); });
      }
    } finally {
      _loadRunning = false;
    }
  }

  void _debouncedLoad() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), _load);
  }

  void _onLayerChange(MapLayer layer) {
    setState(() {
      _layer = layer;
      _selectedGridCell = null;
      _selectedTower = null;
      _selectedWifi = null;
      _selectedBle = null;
      _selectedTestThreat = null;
    });
    _debouncedLoad();
  }

  void _onCellTap(AggregateCell cell) {
    setState(() => _selectedGridCell = cell);
  }

  void _onTowerTap(CellTower tower) {
    setState(() => _selectedTower = tower);
    _mapController.move(tower.position, _mapController.camera.zoom);
  }

  void _onWifiTap(WifiDevice device) {
    setState(() => _selectedWifi = device);
    _mapController.move(device.position, _mapController.camera.zoom);
  }

  void _onBleTap(BleDevice device) {
    setState(() => _selectedBle = device);
    _mapController.move(device.position, _mapController.camera.zoom);
  }

  void _onTestThreatTap(TestThreat threat) {
    setState(() => _selectedTestThreat = threat);
    _mapController.move(threat.position, _mapController.camera.zoom);
  }

  void _dismissSheet() {
    setState(() {
      _selectedGridCell = null;
      _selectedTower = null;
      _selectedWifi = null;
      _selectedBle = null;
      _selectedTestThreat = null;
    });
  }

  LatLng _getCenter() {
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
    return const LatLng(40.7128, -74.0060);
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
                _label('LAYER'),
                const SizedBox(width: 4),
                ..._visibleLayers.map((l) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _chip(
                    label: l.label,
                    selected: _layer == l,
                    onTap: () => _onLayerChange(l),
                  ),
                )),
                const SizedBox(width: 12),
                if (_layer == MapLayer.towers) ...[
                  _label('NBR'),
                  const SizedBox(width: 4),
                  _chip(
                    label: _includeNeighbors ? 'ON' : 'OFF',
                    selected: _includeNeighbors,
                    onTap: () => setState(() {
                      _includeNeighbors = !_includeNeighbors;
                      _debouncedLoad();
                    }),
                  ),
                  const SizedBox(width: 12),
                ],
                _label('TIME'),
                const SizedBox(width: 4),
                ...TimeRange.values.map((t) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _chip(
                    label: t.label,
                    selected: _timeRange == t,
                    onTap: () => setState(() {
                      _timeRange = t;
                      _debouncedLoad();
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
                      _debouncedLoad();
                    }),
                  ),
                )),
                if (_layer == MapLayer.grid) ...[
                  const SizedBox(width: 12),
                  _label('RES'),
                  const SizedBox(width: 4),
                  ...CellPrecision.values.map((p) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _chip(
                      label: p.label,
                      selected: _precision == p,
                      onTap: () => setState(() {
                        _precision = p;
                        _debouncedLoad();
                      }),
                    ),
                  )),
                ],
              ],
            ),
          ),
          if (kDebugMode && _gpsStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _gpsStatus!,
                style: LBTextStyles.label.copyWith(fontSize: 8, color: LBColors.dimText),
              ),
            ),
          if (_layer == MapLayer.grid && _gridCells.isNotEmpty ||
              _layer == MapLayer.towers && _towers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _layer == MapLayer.grid
                    ? '${_gridCells.length} cells  ·  max $_maxObs obs'
                    : '${_towers.length} towers',
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

    final isEmpty = switch (_layer) {
      MapLayer.grid => _gridCells.isEmpty,
      MapLayer.towers => _towers.isEmpty,
      MapLayer.wifi => _wifiDevices.isEmpty,
      MapLayer.ble => _bleDevices.isEmpty,
      MapLayer.test => kDebugMode ? _testThreats.isEmpty : true,
    };
    
    if (isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, color: LBColors.dimText, size: 48),
            const SizedBox(height: 12),
            Text('NO DATA', style: LBTextStyles.heading.copyWith(color: LBColors.dimText)),
            const SizedBox(height: 8),
            Text(
              switch (_layer) {
                MapLayer.grid => 'Start a scan session to populate the grid',
                MapLayer.towers => 'Start a scan session to capture towers',
                MapLayer.wifi => 'Start a scan session to capture WiFi APs',
                MapLayer.ble => 'Start a scan session to capture BLE devices',
                MapLayer.test => kDebugMode ? 'Test data layer - for development only' : '',
              },
              style: LBTextStyles.label.copyWith(color: LBColors.dimText),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        _layer == MapLayer.grid ? _buildGridView() : _buildMapView(),
        _buildLegend(),
        if (_layer == MapLayer.grid && _selectedGridCell != null)
          _buildGridBottomSheet(_selectedGridCell!),
        if (_layer == MapLayer.towers && _selectedTower != null)
          _buildTowerBottomSheet(_selectedTower!),
        if (_layer == MapLayer.wifi && _selectedWifi != null)
          _buildWifiBottomSheet(_selectedWifi!),
        if (_layer == MapLayer.ble && _selectedBle != null)
          _buildBleBottomSheet(_selectedBle!),
        if (kDebugMode && _layer == MapLayer.test && _selectedTestThreat != null)
          _buildTestBottomSheet(_selectedTestThreat!),
      ],
    );
  }

  Widget _buildGridView() {
    return LayoutBuilder(
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
                  cells: _gridCells,
                  maxObs: _maxObs,
                  selectedCell: _selectedGridCell,
                  onCellTap: _onCellTap,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapView() {
    final center = _getCenter();
    final markers = switch (_layer) {
      MapLayer.towers => _towers.map((t) => _buildTowerMarker(t)).toList(),
      MapLayer.wifi => _wifiDevices.map((w) => _buildWifiMarker(w)).toList(),
      MapLayer.ble => _bleDevices.map((b) => _buildBleMarker(b)).toList(),
      MapLayer.test => kDebugMode ? _testThreats.map((t) => _buildTestThreatMarker(t)).toList() : <Marker>[],
      MapLayer.grid => <Marker>[],
    };
    
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 14,
        onTap: (_, __) => _dismissSheet(),
      ),
      children: [
        // OpenStreetMap - primary tile provider (free, no API key)
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'art.n0v4.littlebrother',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Marker _buildTowerMarker(CellTower tower) {
    final size = (8 + math.min(tower.observationCount, 20)).toDouble();
    final threatColor = _threatColor(tower.worstThreatFlag);
    return Marker(
      point: tower.position,
      width: size + 8,
      height: size + 8,
      child: GestureDetector(
        onTap: () => _onTowerTap(tower),
        child: Container(
          decoration: BoxDecoration(
            color: threatColor.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            border: Border.all(color: threatColor, width: 2),
          ),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: threatColor.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: tower.worstThreatFlag > 0
                  ? Icon(
                      Icons.warning,
                      size: size * 0.6,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildWifiMarker(WifiDevice device) {
    final size = (8 + math.min(device.observationCount, 20)).toDouble();
    final threatColor = _threatColor(device.worstThreatFlag);
    return Marker(
      point: device.position,
      width: size + 8,
      height: size + 8,
      child: GestureDetector(
        onTap: () => _onWifiTap(device),
        child: Container(
          decoration: BoxDecoration(
            color: LBColors.blue.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            border: Border.all(color: threatColor, width: 2),
          ),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: LBColors.blue.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: device.worstThreatFlag > 0
                  ? Icon(
                      Icons.warning,
                      size: size * 0.6,
                      color: Colors.white,
                    )
                  : Icon(Icons.wifi, size: size * 0.5, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildBleMarker(BleDevice device) {
    final size = (8 + math.min(device.observationCount, 20)).toDouble();
    final threatColor = _threatColor(device.worstThreatFlag);
    final color = device.isTracker ? LBColors.red : LBColors.cyan;
    return Marker(
      point: device.position,
      width: size + 8,
      height: size + 8,
      child: GestureDetector(
        onTap: () => _onBleTap(device),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            border: Border.all(color: threatColor, width: 2),
          ),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: device.isTracker || device.worstThreatFlag > 0
                  ? Icon(
                      device.isTracker ? Icons.track_changes : Icons.warning,
                      size: size * 0.6,
                      color: Colors.white,
                    )
                  : Icon(Icons.bluetooth, size: size * 0.5, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildTestThreatMarker(TestThreat threat) {
    final size = 20.0;
    final threatColor = threat.threatType == 'stingray' ? LBColors.red 
        : threat.threatType == 'rogue_ap' ? LBColors.yellow 
        : LBColors.orange;
    return Marker(
      point: threat.position,
      width: size + 8,
      height: size + 8,
      child: GestureDetector(
        onTap: () => _onTestThreatTap(threat),
        child: Container(
          decoration: BoxDecoration(
            color: threatColor.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            border: Border.all(color: threatColor, width: 2),
          ),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: threatColor.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning, size: 12, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final double bottomOffset = ((_layer == MapLayer.grid && _selectedGridCell != null) ||
        (kDebugMode && _layer == MapLayer.test && _selectedTestThreat != null)) ? 320.0 + bottomPadding : 16.0 + bottomPadding;
    return Positioned(
      bottom: bottomOffset,
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
            if (_layer == MapLayer.grid) ...[
              Text('SIGNAL', style: LBTextStyles.label.copyWith(fontSize: 8, letterSpacing: 1.5, color: LBColors.blue)),
              const SizedBox(height: 4),
              _legendRow(LBColors.blue, 'WiFi'),
              _legendRow(LBColors.ble, 'BLE'),
              _legendRow(LBColors.orange, 'Cell'),
              const SizedBox(height: 6),
              Text('THREAT', style: LBTextStyles.label.copyWith(fontSize: 8, letterSpacing: 1.5, color: LBColors.blue)),
              const SizedBox(height: 4),
              _legendBorder(LBColors.green, 'Clean'),
              _legendBorder(LBColors.yellow, 'Watch'),
              _legendBorder(LBColors.red, 'Hostile'),
            ] else if (kDebugMode && _layer == MapLayer.test) ...[
              Text('⚠️ TEST DATA', style: LBTextStyles.label.copyWith(fontSize: 8, letterSpacing: 1.5, color: LBColors.red)),
              const SizedBox(height: 4),
              _legendBorder(LBColors.red, 'StingRay'),
              _legendBorder(LBColors.yellow, 'Rogue AP'),
              _legendBorder(LBColors.orange, 'BLE Tracker'),
              const SizedBox(height: 6),
              const Text(
                'Will be removed before release',
                style: TextStyle(fontSize: 8, color: LBColors.dimText),
              ),
            ] else ...[
              Text('THREAT', style: LBTextStyles.label.copyWith(fontSize: 8, letterSpacing: 1.5, color: LBColors.blue)),
              const SizedBox(height: 4),
              _legendBorder(LBColors.green, 'Clean'),
              _legendBorder(LBColors.yellow, 'Watch'),
              _legendBorder(LBColors.red, 'Hostile'),
            ],
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

  Widget _buildGridBottomSheet(AggregateCell cell) {
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: _CellDetailSheet(
        cell: cell,
        precision: _precision,
        onDismiss: _dismissSheet,
      ),
    );
  }

  Widget _buildTowerBottomSheet(CellTower tower) {
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: _TowerDetailSheet(
        tower: tower,
        onDismiss: _dismissSheet,
      ),
    );
  }

  Widget _buildWifiBottomSheet(WifiDevice device) {
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: _WifiDetailSheet(
        device: device,
        onDismiss: _dismissSheet,
      ),
    );
  }

  Widget _buildBleBottomSheet(BleDevice device) {
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: _BleDetailSheet(
        device: device,
        onDismiss: _dismissSheet,
      ),
    );
  }

  Widget _buildTestBottomSheet(TestThreat threat) {
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: _TestThreatDetailSheet(
        threat: threat,
        onDismiss: _dismissSheet,
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

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _mapController.dispose();
    super.dispose();
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
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _countBadge(LBColors.blue, '${widget.cell.wifiCount}', 'WiFi'),
                          const SizedBox(width: 4),
                          _countBadge(LBColors.cyan, '${widget.cell.bleCount}', 'BLE'),
                          const SizedBox(width: 4),
                          _countBadge(LBColors.orange, '${widget.cell.cellCount}', 'Cell'),
                        ],
                      ),
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

class _TowerDetailSheet extends StatelessWidget {
  final CellTower tower;
  final VoidCallback onDismiss;
  const _TowerDetailSheet({required this.tower, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final threatColor = switch (tower.worstThreatFlag) {
      LBThreatFlag.watch   => LBColors.yellow,
      LBThreatFlag.hostile => LBColors.red,
      _                    => LBColors.green,
    };

    return GestureDetector(
      onTap: () {},
      child: Container(
        height: 360,
        decoration: const BoxDecoration(
          color: LBColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          border: Border(top: BorderSide(color: LBColors.orange, width: 1.5)),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: onDismiss,
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
                        color: threatColor.withValues(alpha: 0.15),
                        border: Border.all(color: threatColor),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        tower.networkType,
                        style: LBTextStyles.label.copyWith(
                          color: threatColor,
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
                            tower.displayName.isNotEmpty 
                                ? tower.displayName 
                                : 'Cell ${tower.cellKey}',
                            style: LBTextStyles.body.copyWith(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${tower.position.latitude.toStringAsFixed(5)}, ${tower.position.longitude.toStringAsFixed(5)}',
                            style: LBTextStyles.label.copyWith(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                    if (tower.worstThreatFlag > 0)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: threatColor.withValues(alpha: 0.2),
                            border: Border.all(color: threatColor),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            tower.threatLabel,
                            style: LBTextStyles.label.copyWith(
                              color: threatColor,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: LBColors.orange.withValues(alpha: 0.1),
                        border: Border.all(color: LBColors.orange.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        tower.isServing ? 'SERV' : 'NEIGH',
                        style: LBTextStyles.label.copyWith(fontSize: 8, color: LBColors.orange),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.close, size: 16, color: LBColors.dimText),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader('IDENTIFIER'),
                    const SizedBox(height: 6),
                    _infoRow('Cell ID', tower.cellKey),
                    if (tower.pci >= 0) _infoRow('PCI', '${tower.pci}'),
                    if (tower.tac >= 0) _infoRow('TAC', '${tower.tac}'),
                    if (tower.operator != null) _infoRow('Operator', tower.operator!),
                    const SizedBox(height: 12),
                    _sectionHeader('SIGNAL'),
                    const SizedBox(height: 6),
                    _signalRow('RSRP', '${tower.rsrp} dBm', _rsrpColor(tower.rsrp)),
                    _signalRow('RSRQ', '${tower.rsrq} dB', _rsrqColor(tower.rsrq)),
                    _signalRow('SINR', '${tower.sinr} dB', _sinrColor(tower.sinr)),
                    if (tower.band != null) _infoRow('Band', tower.band!),
                    const SizedBox(height: 12),
                    _sectionHeader('STATISTICS'),
                    const SizedBox(height: 6),
                    _infoRow('Observations', '${tower.observationCount}'),
                    _infoRow('First Seen', _formatDate(tower.firstSeen)),
                    _infoRow('Last Seen', _formatDate(tower.lastSeen)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(text, style: LBTextStyles.label.copyWith(fontSize: 9, color: LBColors.blue, letterSpacing: 1.5));
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: LBTextStyles.label.copyWith(fontSize: 10, color: LBColors.dimText)),
          ),
          Expanded(
            child: Text(value, style: LBTextStyles.body.copyWith(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _signalRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: LBTextStyles.label.copyWith(fontSize: 10, color: LBColors.dimText)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              border: Border.all(color: color.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(value, style: LBTextStyles.label.copyWith(fontSize: 10, color: color)),
          ),
        ],
      ),
    );
  }

  Color _rsrpColor(int rsrp) {
    if (rsrp >= -80) return LBColors.green;
    if (rsrp >= -100) return LBColors.yellow;
    return LBColors.red;
  }

  Color _rsrqColor(int rsrq) {
    if (rsrq >= -10) return LBColors.green;
    if (rsrq >= -15) return LBColors.yellow;
    return LBColors.red;
  }

  Color _sinrColor(int sinr) {
    if (sinr >= 10) return LBColors.green;
    if (sinr >= 0) return LBColors.yellow;
    return LBColors.red;
  }
}

class _WifiDetailSheet extends StatelessWidget {
  final WifiDevice device;
  final VoidCallback onDismiss;
  const _WifiDetailSheet({required this.device, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final threatColor = switch (device.worstThreatFlag) {
      LBThreatFlag.watch   => LBColors.yellow,
      LBThreatFlag.hostile => LBColors.red,
      _                    => LBColors.green,
    };

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
              onTap: onDismiss,
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
                        color: LBColors.blue.withValues(alpha: 0.15),
                        border: Border.all(color: LBColors.blue),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'WIFI',
                        style: TextStyle(
                          color: LBColors.blue,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.ssid.isNotEmpty ? device.ssid : device.bssid,
                            style: LBTextStyles.body.copyWith(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${device.position.latitude.toStringAsFixed(5)}, ${device.position.longitude.toStringAsFixed(5)}',
                            style: LBTextStyles.label.copyWith(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                    if (device.worstThreatFlag > 0)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: threatColor.withValues(alpha: 0.2),
                            border: Border.all(color: threatColor),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            device.threatLabel,
                            style: LBTextStyles.label.copyWith(
                              color: threatColor,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    const Icon(Icons.close, size: 16, color: LBColors.dimText),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeaderWiFi('IDENTIFIER'),
                    const SizedBox(height: 6),
                    _infoRowWiFi('BSSID', device.bssid),
                    if (device.ssid.isNotEmpty) _infoRowWiFi('SSID', device.ssid),
                    if (device.vendor.isNotEmpty) _infoRowWiFi('Vendor', device.vendor),
                    const SizedBox(height: 12),
                    _sectionHeaderWiFi('SIGNAL'),
                    const SizedBox(height: 6),
                    _signalRowWiFi('RSSI', '${device.rssi} dBm', _rssiColorWifi(device.rssi)),
                    if (device.channel != null) _infoRowWiFi('Channel', '${device.channel}'),
                    if (device.security != null) _infoRowWiFi('Security', device.security!),
                    const SizedBox(height: 12),
                    _sectionHeaderWiFi('STATISTICS'),
                    const SizedBox(height: 6),
                    _infoRowWiFi('Observations', '${device.observationCount}'),
                    _infoRowWiFi('First Seen', _formatDate(device.firstSeen)),
                    _infoRowWiFi('Last Seen', _formatDate(device.lastSeen)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeaderWiFi(String text) {
    return Text(text, style: LBTextStyles.label.copyWith(fontSize: 9, color: LBColors.blue, letterSpacing: 1.5));
  }

  Widget _infoRowWiFi(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: LBTextStyles.label.copyWith(fontSize: 10, color: LBColors.dimText)),
          ),
          Expanded(
            child: Text(value, style: LBTextStyles.body.copyWith(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _signalRowWiFi(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: LBTextStyles.label.copyWith(fontSize: 10, color: LBColors.dimText)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              border: Border.all(color: color.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(value, style: LBTextStyles.label.copyWith(fontSize: 10, color: color)),
          ),
        ],
      ),
    );
  }

  Color _rssiColorWifi(int rssi) {
    if (rssi >= -50) return LBColors.green;
    if (rssi >= -70) return LBColors.yellow;
    return LBColors.red;
  }
}

class _BleDetailSheet extends StatelessWidget {
  final BleDevice device;
  final VoidCallback onDismiss;
  const _BleDetailSheet({required this.device, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final threatColor = switch (device.worstThreatFlag) {
      LBThreatFlag.watch   => LBColors.yellow,
      LBThreatFlag.hostile => LBColors.red,
      _                    => LBColors.green,
    };

    return GestureDetector(
      onTap: () {},
      child: Container(
        height: 320,
        decoration: const BoxDecoration(
          color: LBColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                      border: Border(top: BorderSide(color: LBColors.ble, width: 1.5)),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: onDismiss,
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
                        color: LBColors.ble.withValues(alpha: 0.15),
                        border: Border.all(color: LBColors.ble),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'BLE',
                        style: TextStyle(
                          color: LBColors.ble,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.displayName.isNotEmpty ? device.displayName : device.mac,
                            style: LBTextStyles.body.copyWith(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${device.position.latitude.toStringAsFixed(5)}, ${device.position.longitude.toStringAsFixed(5)}',
                            style: LBTextStyles.label.copyWith(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                    if (device.worstThreatFlag > 0)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: threatColor.withValues(alpha: 0.2),
                            border: Border.all(color: threatColor),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            device.threatLabel,
                            style: LBTextStyles.label.copyWith(
                              color: threatColor,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    if (device.isTracker)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: LBColors.red.withValues(alpha: 0.2),
                            border: Border.all(color: LBColors.red),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'TRACKER',
                            style: TextStyle(
                              color: LBColors.red,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    const Icon(Icons.close, size: 16, color: LBColors.dimText),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeaderBle('IDENTIFIER'),
                    const SizedBox(height: 6),
                    _infoRowBle('MAC', device.mac),
                    if (device.displayName.isNotEmpty) _infoRowBle('Name', device.displayName),
                    const SizedBox(height: 12),
                    _sectionHeaderBle('SIGNAL'),
                    const SizedBox(height: 6),
                    _signalRowBle('RSSI', '${device.rssi} dBm', _rssiColorBle(device.rssi)),
                    if (device.txPower != null) _infoRowBle('TX Power', '${device.txPower} dBm'),
                    const SizedBox(height: 12),
                    _sectionHeaderBle('STATISTICS'),
                    const SizedBox(height: 6),
                    _infoRowBle('Observations', '${device.observationCount}'),
                    _infoRowBle('First Seen', _formatDate(device.firstSeen)),
                    _infoRowBle('Last Seen', _formatDate(device.lastSeen)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeaderBle(String text) {
    return Text(text, style: LBTextStyles.label.copyWith(fontSize: 9, color: LBColors.ble, letterSpacing: 1.5));
  }

  Widget _infoRowBle(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: LBTextStyles.label.copyWith(fontSize: 10, color: LBColors.dimText)),
          ),
          Expanded(
            child: Text(value, style: LBTextStyles.body.copyWith(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _signalRowBle(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: LBTextStyles.label.copyWith(fontSize: 10, color: LBColors.dimText)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              border: Border.all(color: color.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(value, style: LBTextStyles.label.copyWith(fontSize: 10, color: color)),
          ),
        ],
      ),
    );
  }

  Color _rssiColorBle(int rssi) {
    if (rssi >= -50) return LBColors.green;
    if (rssi >= -70) return LBColors.yellow;
    return LBColors.red;
  }
}

class _TestThreatDetailSheet extends StatelessWidget {
  final TestThreat threat;
  final VoidCallback onDismiss;
  const _TestThreatDetailSheet({required this.threat, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final threatColor = threat.threatType == 'stingray' ? LBColors.red
        : threat.threatType == 'rogue_ap' ? LBColors.yellow
        : LBColors.orange;

    return GestureDetector(
      onTap: () {},
      child: Container(
        height: 280,
        decoration: const BoxDecoration(
          color: LBColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          border: Border(top: BorderSide(color: LBColors.red, width: 3)),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: onDismiss,
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
                        color: LBColors.red.withValues(alpha: 0.15),
                        border: Border.all(color: LBColors.red),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        '[TEST DATA]',
                        style: TextStyle(
                          color: LBColors.red,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            threat.label,
                            style: LBTextStyles.body.copyWith(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${threat.position.latitude.toStringAsFixed(5)}, ${threat.position.longitude.toStringAsFixed(5)}',
                            style: LBTextStyles.label.copyWith(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: threatColor.withValues(alpha: 0.2),
                          border: Border.all(color: threatColor),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          threat.threatType.toUpperCase(),
                          style: LBTextStyles.label.copyWith(
                            color: threatColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.close, size: 16, color: LBColors.dimText),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚠️ THIS IS TEST DATA - WILL BE REMOVED BEFORE RELEASE',
                      style: TextStyle(
                        color: LBColors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _sectionHeaderTest('SOURCE'),
                    const SizedBox(height: 6),
                    _infoRowTest('Signal Type', threat.signalType.toUpperCase()),
                    _infoRowTest('Threat Type', threat.threatType),
                    _infoRowTest('ID', threat.id),
                    const SizedBox(height: 12),
                    _sectionHeaderTest('ASSESSMENT'),
                    const SizedBox(height: 6),
                    _infoRowTest('Confidence', '${threat.confidence}%'),
                    _infoRowTest('Geohash', threat.geohash),
                    const SizedBox(height: 12),
                    _sectionHeaderTest('TIMELINE'),
                    const SizedBox(height: 6),
                    _infoRowTest('First Reported', _formatDate(threat.firstReported)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeaderTest(String text) {
    return Text(text, style: LBTextStyles.label.copyWith(fontSize: 9, color: LBColors.red, letterSpacing: 1.5));
  }

  Widget _infoRowTest(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: LBTextStyles.label.copyWith(fontSize: 10, color: LBColors.dimText)),
          ),
          Expanded(
            child: Text(value, style: LBTextStyles.body.copyWith(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
