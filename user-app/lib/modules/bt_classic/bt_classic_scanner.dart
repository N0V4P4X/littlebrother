import 'dart:async';
import 'dart:io' show Platform, stderr, Process;
import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/core/db/oui_lookup.dart';

/// Bluetooth Classic Scanner: Scans for classic Bluetooth (BR/EDR) devices.
class BtClassicScanner {
  final _uuid = const Uuid();
  Timer? _timer;
  final _controller = StreamController<List<LBSignal>>.broadcast();
  
  Stream<List<LBSignal>> get stream => _controller.stream;
  bool get isRunning => _timer != null;

  Future<void> start(String sessionId) async {
    if (isRunning) return;
    
    // Check if we're on Linux (where we can use bluetoothctl)
    if (!Platform.isLinux) {
      stderr.write('LB_BT_CLASSIC: only supported on Linux, skipping\n');
      return;
    }
    
    stderr.write('LB_BT_CLASSIC: starting Bluetooth Classic scanner\n');
    
    // Run initial scan immediately
    await _scanOnce(sessionId);
    
    // Set up periodic timer (every 60 seconds for BT Classic)
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _scanOnce(sessionId));
    
    stderr.write('LB_BT_CLASSIC: scanner started with 60s interval\n');
  }

  Future<void> stop() async {
    stderr.write('LB_BT_CLASSIC: stopping scanner\n');
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _scanOnce(String sessionId) async {
    try {
      stderr.write('LB_BT_CLASSIC: running bluetoothctl scan\n');
      
      // Ensure adapter is powered on.
      // Do NOT enable discoverable — that would emit RF and expose the device.
      // Do NOT use 'bluetoothctl scan on' — that actively transmits inquiry packets.
      // Instead, read the adapter's cached device table (passive).
      await Process.run('bluetoothctl', ['power', 'on']);
      
      // Get list of devices from the adapter's cache (passive — no RF emission)
      final result = await Process.run('bluetoothctl', ['devices']);
      
      if (result.exitCode != 0) {
        stderr.write('LB_BT_CLASSIC: failed to get devices: ${result.stderr}\n');
        return;
      }
      
      final output = result.stdout as String;
      final lines = output.split('\n').where((l) => l.isNotEmpty).toList();
      final now = DateTime.now();
      final signals = <LBSignal>[];
      
      for (final line in lines) {
        // Format: Device AA:BB:CC:DD:EE:FF Device Name
        if (line.startsWith('Device ')) {
          try {
            final parts = line.split(' ');
            if (parts.length >= 3) {
              final mac = parts[1].toUpperCase().replaceAll(':', '');
              final name = parts.skip(2).join(' ');
              
              if (mac.isNotEmpty) {
                final vendor = OuiLookup.instance.resolve(mac);
                final isRandomized = OuiLookup.instance.isRandomized(mac);
                
                // For BT Classic, we don't have RSSI from bluetoothctl easily
                // So we'll use a default value and note it's from BT Classic
                final signal = LBSignal(
                  id: _uuid.v4(),
                  sessionId: sessionId,
                  signalType: LBSignalType.ble, // Reuse ble type for now, or could add new type
                  identifier: mac,
                  displayName: name.isNotEmpty ? name : mac,
                  rssi: -70, // Default RSSI for BT Classic when unknown
                  distanceM: _estimateDistance(-70),
                  riskScore: isRandomized ? 25 : 15, // Lower risk than LE for BT Classic
                  metadata: {
                    'bluetooth_type': 'classic',
                    'device_name': name,
                    'vendor': vendor,
                    'is_randomized_mac': isRandomized,
                    'source': 'bluetoothctl',
                    'note': 'RSSI estimated, actual unavailable from bluetoothctl',
                  },
                  timestamp: now,
                );
                signals.add(signal);
              }
            }
          } catch (e) {
            stderr.write('LB_BT_CLASSIC: error parsing line "$line": $e\n');
            continue;
          }
        }
      }
      
      if (!_controller.isClosed && signals.isNotEmpty) {
        _controller.add(signals);
        stderr.write('LB_BT_CLASSIC: emitting ${signals.length} BT Classic signals\n');
      } else {
        stderr.write('LB_BT_CLASSIC: no devices found\n');
      }
      
    } catch (e) {
      stderr.write('LB_BT_CLASSIC: scan error: $e\n');
    }
  }

  static double _estimateDistance(int rssi, {int txPower = LBPathLoss.defaultTxPowerDbm}) {
    if (rssi == 0) return -1.0;
    final exp = (txPower - rssi) / (10 * LBPathLoss.nIndoor);
    return math.pow(10, exp).toDouble();
  }

  void dispose() {
    stop();
    _controller.close();
  }
}