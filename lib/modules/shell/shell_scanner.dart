import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';
import 'package:littlebrother/core/db/oui_lookup.dart';

/// Shell Scanner: Executes user-defined commands and parses output as signals.
class ShellScanner {
  Timer? _timer;
  final _controller = StreamController<List<LBSignal>>.broadcast();
  
  // Configuration for shell commands to run
  final List<_ShellCommandConfig> _commands = [
    // Example: ARP table scanner for local network devices
    _ShellCommandConfig(
      name: 'arp-scan',
      command: ['arp', '-a'],
      parser: _parseArpOutput,
      interval: Duration(seconds: 30),
    ),
    // Example: WiFi interface details (if available)
    _ShellCommandConfig(
      name: 'iwlist-scan',
      command: ['iwlist', 'scan'],
      parser: _parseIwlistOutput,
      interval: Duration(seconds: 60),
      // Only run on Linux wireless interfaces
      condition: () => Platform.isLinux && File('/proc/net/wireless').existsSync(),
    ),
  ];
  
  Stream<List<LBSignal>> get stream => _controller.stream;
  bool get isRunning => _timer != null;

  Future<void> start(String sessionId) async {
    if (isRunning) return;
    
    stderr.write('LB_SHELL: starting shell scanner\n');
    
    // Run initial scan immediately
    await _runAllCommands(sessionId);
    
      // Set up periodic timer for recurring scans
    // Use the shortest interval among all commands, or default to 30s
    final intervals = _commands.where((c) => c.condition == null || c.condition!()).map((c) => c.interval).toList();
    Duration minInterval = const Duration(seconds: 30);
    if (intervals.isNotEmpty) {
      minInterval = intervals.reduce((a, b) => a.compareTo(b) < 0 ? a : b);
    }
    _timer = Timer.periodic(minInterval, (_) => _runAllCommands(sessionId));
    
    stderr.write('LB_SHELL: shell scanner started with ${minInterval.inSeconds}s interval\n');
  }

  Future<void> stop() async {
    stderr.write('LB_SHELL: stopping shell scanner\n');
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _runAllCommands(String sessionId) async {
    final now = DateTime.now();
    final signals = <LBSignal>[];
    
    for (final config in _commands) {
      // Check if command should run based on condition
      if (config.condition != null && !config.condition!()) {
        continue;
      }
      
      try {
        stderr.write('LB_SHELL: running command "${config.name}"\n');
        final result = await Process.run(config.command.first, config.command.skip(1).toList());
        
        if (result.exitCode == 0) {
          final parsed = config.parser(result.stdout as String, sessionId, now);
          if (parsed.isNotEmpty) {
            signals.addAll(parsed);
            stderr.write('LB_SHELL: "${config.name}" produced ${parsed.length} signals\n');
          }
        } else {
          stderr.write('LB_SHELL: "${config.name}" failed with exit code ${result.exitCode}: ${result.stderr}\n');
        }
      } catch (e) {
        stderr.write('LB_SHELL: "${config.name}" error: $e\n');
      }
    }
    
    if (!_controller.isClosed && signals.isNotEmpty) {
      _controller.add(signals);
      stderr.write('LB_SHELL: emitting ${signals.length} total signals\n');
    }
  }

  // Parse arp -a output for local network devices
  static List<LBSignal> _parseArpOutput(String output, String sessionId, DateTime now) {
    final signals = <LBSignal>[];
    final lines = output.split('\n');
    final uuid = Uuid();
    
    for (final line in lines) {
      // Typical arp -a output: ? (192.168.1.1) at aa:bb:cc:dd:ee:ff [ether] on eth0
      if (line.contains('at ') && line.contains('[ether]')) {
        try {
          String? ipAddr;
          String? macAddr;
          
          // Extract IP address (between parentheses)
          final ipMatch = RegExp(r'\(([^)]+)\)').firstMatch(line);
          if (ipMatch != null) {
            ipAddr = ipMatch.group(1) ?? '';
          }
          
          // Extract MAC address (after "at ")
          final atIndex = line.indexOf('at ');
          if (atIndex != -1) {
            final afterAt = line.substring(atIndex + 3);
            final macMatch = RegExp(r'([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})').firstMatch(afterAt);
            if (macMatch != null) {
              macAddr = macMatch.group(0) ?? '';
            }
          }
          
          if (macAddr != null) {
            final cleanMac = macAddr.replaceAll(':', '').replaceAll('-', '').toUpperCase();
            final vendor = OuiLookup.instance.resolve(cleanMac);
            final isRandomized = OuiLookup.instance.isRandomized(cleanMac);
            
            final signal = LBSignal(
              id: uuid.v4(),
              sessionId: sessionId,
              signalType: LBSignalType.wifi, // Treat as network device
              identifier: cleanMac,
              displayName: vendor.isNotEmpty ? vendor : '$ipAddr ($cleanMac)',
              rssi: -50, // Default RSSI for local network devices
              distanceM: 1.0, // Assume local network
              riskScore: isRandomized ? 30 : 10, // Slightly higher risk for randomized MACs
              metadata: {
                'ip_address': ipAddr ?? 'unknown',
                'mac_address': cleanMac,
                'vendor': vendor,
                'is_randomized_mac': isRandomized,
                'source': 'arp-scan',
              },
              timestamp: now,
            );
            signals.add(signal);
          }
        } catch (e) {
          // Skip malformed lines
          continue;
        }
      }
    }
    return signals;
  }

  // Parse iwlist scan output for detailed WiFi info
  static List<LBSignal> _parseIwlistOutput(String output, String sessionId, DateTime now) {
    final signals = <LBSignal>[];
    final uuid = Uuid();
    
    // Split by "Cell" entries
    final cells = output.split('Cell ');
    for (final cell in cells.skip(1)) { // Skip first empty split
      try {
        String? ssid;
        String? bssid;
        int? signal;
        int? frequency;
        String? encryption;
        String? quality;
        
        // Extract ESSID (SSID)
          final essidMatch = RegExp(r'ESSID:"([^"]*)"').firstMatch(cell);
          if (essidMatch != null) {
            ssid = essidMatch.group(1);
          }
          
          // Extract Address (BSSID)
          final addressMatch = RegExp(r'Address: ([0-9A-Fa-f:]{17})').firstMatch(cell);
          if (addressMatch != null) {
            bssid = addressMatch.group(1)?.toUpperCase();
          }
          
          // Extract Signal level
          final signalMatch = RegExp(r'Signal level=(-?\d+) dBm').firstMatch(cell);
          if (signalMatch != null) {
            signal = int.tryParse(signalMatch.group(1)!);
          }
          
          // Extract Frequency
          final freqMatch = RegExp(r'Frequency:([^ ]+) GHz').firstMatch(cell);
          if (freqMatch != null) {
            final freqStr = freqMatch.group(1)!;
            frequency = (double.parse(freqStr) * 1000).round(); // Convert GHz to MHz
          }
          
          // Extract Encryption key
          final encMatch = RegExp(r'Encryption key:(on|off)').firstMatch(cell);
          if (encMatch != null) {
            encryption = encMatch.group(1)!;
          }
          
          // Extract Quality
          final qualMatch = RegExp(r'Quality=([0-9]+)/([0-9]+)').firstMatch(cell);
          if (qualMatch != null) {
            quality = '${qualMatch.group(1)}/${qualMatch.group(2)}';
          }
        
        if (bssid != null && signal != null) {
          final cleanBssid = bssid.replaceAll(':', '');
          final vendor = OuiLookup.instance.resolve(cleanBssid);
          final isRandomized = OuiLookup.instance.isRandomized(cleanBssid);
          
          final sigVal = signal;
          
          var riskScore = 0;
          if (encryption == 'off') {
            riskScore += 40; // Open network
          } else if (encryption == 'on') {
            riskScore += 10; // Encrypted
          }
          if (sigVal > -50) riskScore += 20; // Strong signal
          riskScore = riskScore.clamp(0, 100);
          
          final signalObj = LBSignal(
            id: uuid.v4(),
            sessionId: sessionId,
            signalType: LBSignalType.wifi,
            identifier: cleanBssid,
            displayName: ssid?.isNotEmpty == true ? ssid! : '[hidden] ($cleanBssid)',
            rssi: sigVal,
            distanceM: _estimateDistance(sigVal),
            riskScore: riskScore,
            metadata: {
              'ssid': ssid ?? '',
              'bssid': cleanBssid,
              'frequency_mhz': frequency,
              'encryption': encryption,
              'quality': quality,
              'vendor': vendor,
              'is_randomized_mac': isRandomized,
              'source': 'iwlist-scan',
            },
            timestamp: now,
          );
          signals.add(signalObj);
        }
      } catch (e) {
        // Skip malformed cells
        continue;
      }
    }
    return signals;
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

/// Configuration for a shell command to be executed by the ShellScanner
class _ShellCommandConfig {
  final String name;
  final List<String> command;
  final List<LBSignal> Function(String output, String sessionId, DateTime now) parser;
  final Duration interval;
  final bool Function()? condition;

  const _ShellCommandConfig({
    required this.name,
    required this.command,
    required this.parser,
    required this.interval,
    this.condition,
  });
}