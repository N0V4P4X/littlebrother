import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:littlebrother/core/db/lb_database.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/core/scan_coordinator.dart';
import 'package:littlebrother/ui/radar/radar_screen.dart';
import 'package:littlebrother/ui/screens/signal_list_screen.dart';
import 'package:littlebrother/ui/screens/threat_log_screen.dart';
import 'package:littlebrother/ui/screens/opsec_screen.dart';
import 'package:littlebrother/ui/screens/timeline_screen.dart';
import 'package:littlebrother/ui/screens/aggregate_map_screen.dart';
import 'package:littlebrother/ui/screens/permission_gate.dart';
import 'package:littlebrother/ui/theme/lb_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait + landscape, lock status bar to dark
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:            Colors.transparent,
    statusBarIconBrightness:   Brightness.light,
    systemNavigationBarColor:  LBColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize database and run migrations
  try {
    await LBDatabase.instance.db;
    debugPrint('LB_MAIN: Database initialized');
    
    // Run automatic waypoints migration if needed
    await _runWaypointsMigration();
  } catch (e) {
    debugPrint('LB_MAIN: Database init error: $e');
  }

  runApp(const LittleBrotherApp());
}

Future<void> _runWaypointsMigration() async {
  try {
    final waypointCount = await LBDatabase.instance.getWaypointCount();
    debugPrint('LB_MAIN: Current waypoint count: $waypointCount');
    
    if (waypointCount == 0) {
      debugPrint('LB_MAIN: Running waypoints migration...');
      await LBDatabase.instance.migrateObservationsToWaypoints();
      
      final newCount = await LBDatabase.instance.getWaypointCount();
      debugPrint('LB_MAIN: Migration complete - $newCount waypoints created');
      
      // Also cleanup observations without location
      await LBDatabase.instance.cleanupObservationsWithoutLocation();
      debugPrint('LB_MAIN: Cleanup complete');
    }
  } catch (e) {
    debugPrint('LB_MAIN: Migration error: $e');
  }
}

class LittleBrotherApp extends StatelessWidget {
  const LittleBrotherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LittleBrother',
      debugShowCheckedModeBanner: false,
      theme: buildLBTheme(),
      home: PermissionGate(child: const _AppShell()),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  final _coordinator = ScanCoordinator();
  int _navIndex = 0;
  bool _opsecAutoEnabled = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _coordinator.init();
    if (mounted) setState(() => _initialized = true);
    // Auto-start scanning
    await _coordinator.startScan();
    if (mounted) setState(() {});
  }

  Future<void> _toggleScan() async {
    if (_coordinator.isScanning) {
      await _coordinator.stopScan();
    } else {
      await _coordinator.startScan();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: LBColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: LBColors.blue, strokeWidth: 1),
              SizedBox(height: 16),
              Text(
                'INITIALIZING...',
                style: TextStyle(
                  fontFamily: 'Courier New',
                  color: LBColors.dimText,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: _buildBody(),
      bottomNavigationBar: _buildNav(),
    );
  }

  Widget _buildBody() {
    // Use StreamBuilder to rebuild counters on each signal batch
    return StreamBuilder(
      stream: _coordinator.signalStream,
      builder: (context, _) {
        return switch (_navIndex) {
          0 => RadarScreen(
              signalStream:       _coordinator.signalStream,
              threatStream:       _coordinator.threatStream,
              isScanning:         _coordinator.isScanning,
              onScanToggle:       _toggleScan,
              wifiCount:          _coordinator.wifiCount,
              bleCount:           _coordinator.bleCount,
              cellCount:          _coordinator.cellCount,
              threatCount:        _coordinator.threatCount,
              currentNetworkType: _coordinator.currentNetworkType,
            ),
          1 => SignalListScreen(signals: _coordinator.latestSignals),
          2 => const ThreatLogScreen(),
          3 => OpsecScreen(
              opsec:             _coordinator.opsec,
              opsecAutoEnabled:  _opsecAutoEnabled,
              onAutoToggle:      (v) {
                setState(() => _opsecAutoEnabled = v);
                _coordinator.setOpsecAutoEnabled(v);
              },
            ),
          4 => const AggregateMapScreen(),
          5 => const TimelineScreen(),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }

  Widget _buildNav() {
    return StreamBuilder<bool>(
      stream: _coordinator.wifiThrottleStream,
      initialData: _coordinator.isWifiThrottled,
      builder: (context, throttleSnap) {
        final throttled = throttleSnap.data == true;
        return StreamBuilder<LBThreatEvent>(
          stream: _coordinator.threatStream,
          builder: (context, threatSnap) {
            return BottomNavigationBar(
          currentIndex: _navIndex,
          onTap: (i) => setState(() => _navIndex = i),
          items: [
            BottomNavigationBarItem(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.radar, size: 20),
                  if (throttled)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: LBColors.yellow,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              label: 'RADAR',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.list, size: 20),
              label: 'SIGNALS',
            ),
            BottomNavigationBarItem(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.warning_amber_outlined, size: 20),
                  if (threatSnap.hasData || _coordinator.threatCount > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: LBColors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              label: 'THREATS',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.security, size: 20),
              label: 'OPSEC',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined, size: 20),
              label: 'INTEL MAP',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.timeline, size: 20),
              label: 'TIMELINE',
            ),
          ],
        );
          },
        );
      },
    );
  }
}
