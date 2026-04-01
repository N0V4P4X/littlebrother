import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_aggregate_map.dart';

class LBMapView extends StatefulWidget {
  final LatLng? initialCenter;
  final double initialZoom;
  final List<Marker> markers;
  final List<AggregateCell> gridCells;
  final int gridPrecision;
  final Function(LatLng)? onTap;
  final Function(AggregateCell)? onCellTap;
  final Function(LatLng, double)? onPositionChanged;
  final bool showLocationButton;
  final LatLng? currentLocation;
  final MapController? mapController;
  final int tileProviderIndex;
  final bool enableClustering;
  final int clusterZoomThreshold;

  const LBMapView({
    super.key,
    this.initialCenter,
    this.initialZoom = 14.0,
    this.markers = const [],
    this.gridCells = const [],
    this.gridPrecision = 7,
    this.onTap,
    this.onCellTap,
    this.onPositionChanged,
    this.showLocationButton = false,
    this.currentLocation,
    this.mapController,
    this.tileProviderIndex = 1,
    this.enableClustering = false,
    this.clusterZoomThreshold = 15,
  });

  @override
  State<LBMapView> createState() => _LBMapViewState();
}

class _LBMapViewState extends State<LBMapView> {
  late final MapController _mapController;
  int _currentProvider = 1; // Default to CartoDB Voyager (more reliable)
  int _errorCount = 0;
  bool _tilesLoaded = false;
  bool _loadingTiles = true;

  static const _tileProviders = [
    ('OpenStreetMap', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
    ('CartoDB Voyager', 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png'),
    ('CartoDB Dark', 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'),
    ('OpenTopoMap', 'https://tile.opentopomap.org/{z}/{x}/{y}.png'),
  ];

  @override
  void initState() {
    super.initState();
    _currentProvider = widget.tileProviderIndex;
    _mapController = widget.mapController ?? MapController();
    debugPrint('LBMapView init with provider: ${_tileProviders[_currentProvider].$1}');
  }

  @override
  void didUpdateWidget(LBMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tileProviderIndex != oldWidget.tileProviderIndex) {
      setState(() {
        _currentProvider = widget.tileProviderIndex;
        _errorCount = 0;
        _loadingTiles = true;
      });
    }
  }

  @override
  void dispose() {
    if (widget.mapController == null) {
      _mapController.dispose();
    }
    super.dispose();
  }

  void _centerOnLocation() {
    if (widget.currentLocation != null) {
      _mapController.move(widget.currentLocation!, 16.0);
    }
  }

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    _errorCount++;
    debugPrint('LBMapView tile error #$_errorCount: $error');
    
    setState(() {
      _loadingTiles = false;
    });
    
    // Switch provider after 3 persistent errors
    if (_errorCount > 3 && _currentProvider < _tileProviders.length - 1) {
      setState(() {
        _currentProvider++;
        _errorCount = 0;
        _loadingTiles = true;
      });
      debugPrint('LBMapView: switched to ${_tileProviders[_currentProvider].$1}');
    }
  }

  void _onTileLoad() {
    debugPrint('LBMapView: tiles loaded successfully');
    setState(() {
      _tilesLoaded = true;
      _loadingTiles = false;
    });
  }

  void _cycleProvider() {
    setState(() {
      _currentProvider = (_currentProvider + 1) % _tileProviders.length;
      _errorCount = 0;
      _loadingTiles = true;
      _tilesLoaded = false;
    });
    debugPrint('LBMapView: manual switch to ${_tileProviders[_currentProvider].$1}');
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.initialCenter ?? const LatLng(37.7749, -122.4194);
    final currentTile = _tileProviders[_currentProvider];

    debugPrint('LBMapView building with provider: ${currentTile.$1}, url: ${currentTile.$2}');

    return Container(
      color: const Color(0xFF1A1A2E),
      child: Stack(
        children: [
          // Map with explicit constraints
          SizedBox.expand(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: widget.initialZoom,
                backgroundColor: const Color(0xFF1A1A2E),
                onTap: (tapPosition, point) {
                  widget.onTap?.call(point);
                },
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture && widget.onPositionChanged != null) {
                    widget.onPositionChanged!(position.center, position.zoom);
                  }
                },
                onMapReady: () {
                  debugPrint('LBMapView: map ready');
                  setState(() {
                    _loadingTiles = false;
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: currentTile.$2,
                  userAgentPackageName: 'art.n0v4.littlebrother',
                  errorTileCallback: _onTileError,
                  maxZoom: 19,
                ),
                if (widget.gridCells.isNotEmpty)
                  PolygonLayer(
                    polygons: _buildGridPolygons(),
                  ),
                MarkerLayer(markers: widget.enableClustering ? _buildClusteredMarkers() : widget.markers),
              ],
            ),
          ),
          // Loading indicator
          if (_loadingTiles)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: ColoredBox(
                color: Color(0xFF1A1A2E),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF00D9FF)),
                      SizedBox(height: 16),
                      Text(
                        'Loading map tiles...',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Tile provider indicator
          Positioned(
            left: 16,
            top: 16,
            child: GestureDetector(
              onTap: _cycleProvider,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF00D9FF).withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _tilesLoaded ? Icons.map : Icons.map_outlined,
                      size: 14,
                      color: _tilesLoaded ? Color(0xFF00FF88) : Color(0xFF00D9FF),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentTile.$1,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.swap_horiz, size: 14, color: Colors.white54),
                  ],
                ),
              ),
            ),
          ),
          // Error indicator
          if (_errorCount > 0 && !_loadingTiles)
            Positioned(
              left: 16,
              top: 50,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Tile errors: $_errorCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          // Location button
          if (widget.showLocationButton)
            Positioned(
              right: 16,
              bottom: 100,
              child: FloatingActionButton.small(
                heroTag: 'location',
                onPressed: _centerOnLocation,
                backgroundColor: const Color(0xFF1E1E2E),
                child: const Icon(Icons.my_location, color: Color(0xFF00D9FF)),
              ),
            ),
          // Center on markers button
          if (widget.markers.isNotEmpty)
            Positioned(
              right: 16,
              bottom: 150,
              child: FloatingActionButton.small(
                heroTag: 'fit',
                onPressed: () {
                  if (widget.markers.isNotEmpty) {
                    final points = widget.markers.map((m) => m.point).toList();
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
                    _mapController.fitCamera(
                      CameraFit.bounds(
                        bounds: LatLngBounds(
                          LatLng(minLat, minLon),
                          LatLng(maxLat, maxLon),
                        ),
                        padding: const EdgeInsets.all(50),
                      ),
                    );
                  }
                },
                backgroundColor: const Color(0xFF1E1E2E),
                child: const Icon(Icons.fit_screen, color: Color(0xFF00D9FF)),
              ),
              ),
        ],
      ),
    );
  }

  List<Polygon> _buildGridPolygons() {
    final cells = widget.gridCells;
    if (cells.isEmpty) return [];

    int maxObs = 1;
    for (final cell in cells) {
      if (cell.observationCount > maxObs) maxObs = cell.observationCount;
    }

    return cells.map((cell) {
      final density = cell.observationCount / maxObs;
      final alpha = (0.15 + density * 0.6).clamp(0.15, 0.75);
      final fillColor = _cellFillColor(cell.dominantType, alpha);
      final borderColor = _threatBorderColor(cell.worstFlag);

      // Get polygon points from geohash bounds
      final points = _geohashToPolygon(cell.geohash);

      return Polygon(
        points: points,
        color: fillColor,
        borderColor: borderColor,
        borderStrokeWidth: cell.worstFlag > 0 ? 2.0 : 1.0,
      );
    }).toList();
  }

  Color _cellFillColor(String dominantType, double alpha) {
    final baseColor = switch (dominantType) {
      LBSignalType.wifi => const Color(0xFF00D9FF),  // cyan
      LBSignalType.ble  => const Color(0xFFFF6B6B), // coral
      _                  => const Color(0xFFFFB347), // orange
    };
    return baseColor.withValues(alpha: alpha);
  }

  Color _threatBorderColor(int flag) {
    return switch (flag) {
      LBThreatFlag.watch   => const Color(0xFFFFD93D),   // yellow
      LBThreatFlag.hostile => const Color(0xFFFF4757), // red
      _                    => const Color(0xFF00FF88), // green
    };
  }

  List<LatLng> _geohashToPolygon(String geohash) {
    // Decode geohash to get center, then compute bounds
    final decoded = _decodeGeohash(geohash);
    final bounds = _geohashBounds(geohash);
    
    // Return 4 corners of the geohash cell
    return [
      LatLng(bounds['minLat']!, bounds['minLon']!),
      LatLng(bounds['maxLat']!, bounds['minLon']!),
      LatLng(bounds['maxLat']!, bounds['maxLon']!),
      LatLng(bounds['minLat']!, bounds['maxLon']!),
    ];
  }

  Map<String, double> _geohashBounds(String geohash) {
    // Standard geohash decode
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    var minLat = -90.0, maxLat = 90.0;
    var minLon = -180.0, maxLon = 180.0;
    var isEven = true;

    for (final ch in geohash.split('')) {
      final idx = base32.indexOf(ch.toLowerCase());
      if (idx == -1) break;
      
      for (var bits = 4; bits >= 0; bits--) {
        final bitVal = (idx >> bits) & 1;
        if (isEven) {
          final mid = (minLon + maxLon) / 2;
          if (bitVal == 1) { minLon = mid; } else { maxLon = mid; }
        } else {
          final mid = (minLat + maxLat) / 2;
          if (bitVal == 1) { minLat = mid; } else { maxLat = mid; }
        }
        isEven = !isEven;
      }
    }

    return {
      'minLat': minLat,
      'maxLat': maxLat,
      'minLon': minLon,
      'maxLon': maxLon,
    };
  }

  ({double lat, double lon}) _decodeGeohash(String geohash) {
    final bounds = _geohashBounds(geohash);
    return (
      lat: (bounds['minLat']! + bounds['maxLat']!) / 2,
      lon: (bounds['minLon']! + bounds['maxLon']!) / 2,
    );
  }

  List<Marker> _buildClusteredMarkers() {
    if (!widget.enableClustering || widget.markers.isEmpty) {
      return widget.markers;
    }

    final zoom = _mapController.camera.zoom;
    final useClusters = zoom < widget.clusterZoomThreshold;

    if (!useClusters) {
      return widget.markers;
    }

    // Grid-based clustering
    final clusterRadius = 0.002; // ~200m at mid latitudes
    final clusters = <String, List<Marker>>{};
    final clustered = <Marker>[];

    for (final marker in widget.markers) {
      final key = '${(marker.point.latitude / clusterRadius).floor()}_${(marker.point.longitude / clusterRadius).floor()}';
      clusters.putIfAbsent(key, () => []).add(marker);
    }

    for (final entry in clusters.entries) {
      final markersInCluster = entry.value;
      if (markersInCluster.length == 1) {
        clustered.add(markersInCluster.first);
      } else {
        // Create cluster marker
        final centerLat = markersInCluster.map((m) => m.point.latitude).reduce((a, b) => a + b) / markersInCluster.length;
        final centerLon = markersInCluster.map((m) => m.point.longitude).reduce((a, b) => a + b) / markersInCluster.length;
        final count = markersInCluster.length;

        clustered.add(Marker(
          point: LatLng(centerLat, centerLon),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () {
              // Zoom in to show individual markers
              _mapController.move(LatLng(centerLat, centerLon), zoom + 2);
            },
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF00D9FF).withValues(alpha: 0.8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ));
      }
    }

    return clustered;
  }

  void moveTo(LatLng point, {double? zoom}) {
    _mapController.move(point, zoom ?? _mapController.camera.zoom);
  }

  void zoomIn() {
    _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
  }

  void zoomOut() {
    _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
  }
}