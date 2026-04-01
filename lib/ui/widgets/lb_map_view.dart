import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class LBMapView extends StatefulWidget {
  final LatLng? initialCenter;
  final double initialZoom;
  final List<Marker> markers;
  final Function(LatLng)? onTap;
  final Function(LatLng, double)? onPositionChanged;
  final bool showLocationButton;
  final LatLng? currentLocation;
  final MapController? mapController;
  final int tileProviderIndex;

  const LBMapView({
    super.key,
    this.initialCenter,
    this.initialZoom = 14.0,
    this.markers = const [],
    this.onTap,
    this.onPositionChanged,
    this.showLocationButton = false,
    this.currentLocation,
    this.mapController,
    this.tileProviderIndex = 1,
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
                MarkerLayer(markers: widget.markers),
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