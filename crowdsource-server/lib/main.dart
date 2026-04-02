import 'dart:io';
import 'package:path/path.dart' as p;
import 'config.dart';
import 'http_server.dart';
import 'db/server_db.dart';

void main(List<String> args) async {
  print('╔═══════════════════════════════════════════════════════════╗');
  print('║           LittleBrother Server v0.1.0                      ║');
  print('║           LAN Control Panel & Crowdsource Hub              ║');
  print('╚═══════════════════════════════════════════════════════════╝');
  print('');

  // Find config
  final configPath = _findConfigPath();
  print('Config: $configPath');
  
  final config = await ConfigLoader.loadOrCreate(configPath);
  print('Server port: ${config.httpPort}');
  print('MQTT enabled: ${config.mqttEnabled}');
  print('');

  // Initialize database
  print('Initializing database...');
  await ServerDb.instance.db;
  print('Database ready');
  print('');

  // Start HTTP server
  print('Starting HTTP server...');
  final server = HttpServer(config);
  await server.start();
  print('');

  print('═══════════════════════════════════════════════════════════════');
  print('LittleBrother Server is running');
  print('');
  print('Dashboard: http://localhost:${config.httpPort}');
  print('API:       http://localhost:${config.httpPort}/api');
  print('');
  print('Press Ctrl+C to stop');
  print('═══════════════════════════════════════════════════════════════');

  // Keep running - wait for SIGINT
  await Future<void>.delayed(Duration(days: 365));
  
  print('');
  print('Shutting down...');
  await ServerDb.instance.close();
  print('Done');
}

String _findConfigPath() {
  // Check for config in various locations
  final candidates = [
    p.join(Directory.current.path, 'server', 'config.yaml'),
    p.join(Directory.current.path, 'config.yaml'),
    p.join(Platform.environment['HOME'] ?? '', '.littlebrother', 'server.yaml'),
    p.join(Directory.current.path, '..', 'littlebrother_server', 'config.yaml'),
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) {
      return path;
    }
  }

  // Return first candidate as default
  return candidates.first;
}
