import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as p;

class ServerConfig {
  final int httpPort;
  final List<String> corsOrigins;
  final bool mqttEnabled;
  final String mqttHost;
  final int mqttRawPort;
  final int mqttCleanPort;
  final int dirtyRetentionDays;
  final int locationRetentionDays;
  final int locationFuzzRadiusM;
  final int archiveSizeWarningMb;
  final double trustLocal;
  final double trustCrowdsourcedClean;
  final double trustCrowdsourcedDirty;
  final double trustMqtt;
  final List<PeerConfig> peers;

  ServerConfig({
    required this.httpPort,
    required this.corsOrigins,
    required this.mqttEnabled,
    required this.mqttHost,
    required this.mqttRawPort,
    required this.mqttCleanPort,
    required this.dirtyRetentionDays,
    required this.locationRetentionDays,
    required this.locationFuzzRadiusM,
    required this.archiveSizeWarningMb,
    required this.trustLocal,
    required this.trustCrowdsourcedClean,
    required this.trustCrowdsourcedDirty,
    required this.trustMqtt,
    required this.peers,
  });

  factory ServerConfig.defaults() => ServerConfig(
    httpPort: 8080,
    corsOrigins: ['*'],
    mqttEnabled: false,
    mqttHost: 'localhost',
    mqttRawPort: 1883,
    mqttCleanPort: 8883,
    dirtyRetentionDays: 7,
    locationRetentionDays: 30,
    locationFuzzRadiusM: 0,
    archiveSizeWarningMb: 1024,
    trustLocal: 1.0,
    trustCrowdsourcedClean: 0.8,
    trustCrowdsourcedDirty: 0.3,
    trustMqtt: 0.0,
    peers: [],
  );

  factory ServerConfig.fromYaml(Map yaml) {
    final server = yaml['server'] ?? {};
    final mqtt = yaml['mqtt'] ?? {};
    final database = yaml['database'] ?? {};
    final trust = yaml['trust'] ?? {};
    final trustDefaults = trust['defaults'] ?? {};

    final peers = <PeerConfig>[];
    if (yaml['peers'] != null) {
      for (final peer in yaml['peers']) {
        peers.add(PeerConfig(
          name: peer['name'] ?? 'Unnamed',
          address: peer['address'] ?? '',
          trustLevel: peer['trust_level'] ?? 0,
        ));
      }
    }

    return ServerConfig(
      httpPort: server['port'] ?? 8080,
      corsOrigins: (server['cors_origins'] as YamlList?)
          ?.map((e) => e.toString())
          .toList() ?? ['*'],
      mqttEnabled: mqtt['enabled'] ?? false,
      mqttHost: mqtt['host'] ?? 'localhost',
      mqttRawPort: mqtt['raw_port'] ?? 1883,
      mqttCleanPort: mqtt['clean_port'] ?? 8883,
      dirtyRetentionDays: database['dirty_retention_days'] ?? 7,
      locationRetentionDays: database['location_retention_days'] ?? 30,
      locationFuzzRadiusM: database['location_fuzz_radius_m'] ?? 0,
      archiveSizeWarningMb: database['archive_size_warning_mb'] ?? 1024,
      trustLocal: _parseDouble(trustDefaults['local'], 1.0),
      trustCrowdsourcedClean: _parseDouble(trustDefaults['crowdsourced_clean'], 0.8),
      trustCrowdsourcedDirty: _parseDouble(trustDefaults['crowdsourced_dirty'], 0.3),
      trustMqtt: _parseDouble(trustDefaults['mqtt'], 0.0),
      peers: peers,
    );
  }

  static double _parseDouble(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    return defaultValue;
  }

  Map<String, dynamic> toJson() => {
    'server': {
      'port': httpPort,
      'cors_origins': corsOrigins,
    },
    'mqtt': {
      'enabled': mqttEnabled,
      'host': mqttHost,
      'raw_port': mqttRawPort,
      'clean_port': mqttCleanPort,
    },
    'database': {
      'dirty_retention_days': dirtyRetentionDays,
      'location_retention_days': locationRetentionDays,
      'location_fuzz_radius_m': locationFuzzRadiusM,
      'archive_size_warning_mb': archiveSizeWarningMb,
    },
    'trust': {
      'defaults': {
        'local': trustLocal,
        'crowdsourced_clean': trustCrowdsourcedClean,
        'crowdsourced_dirty': trustCrowdsourcedDirty,
        'mqtt': trustMqtt,
      }
    },
    'peers': peers.map((p) => p.toJson()).toList(),
  };
}

class PeerConfig {
  final String name;
  final String address;
  final int trustLevel;

  PeerConfig({
    required this.name,
    required this.address,
    required this.trustLevel,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'trust_level': trustLevel,
  };
}

class ConfigLoader {
  static Future<ServerConfig> load(String configPath) async {
    final file = File(configPath);
    
    if (!await file.exists()) {
      // Try to find config.yaml in common locations
      final commonPaths = [
        p.join(p.dirname(configPath), 'config.yaml'),
        p.join(Directory.current.path, 'server', 'config.yaml'),
        p.join(Directory.current.path, 'config.yaml'),
      ];
      
      for (final path in commonPaths) {
        final f = File(path);
        if (await f.exists()) {
          return load(f.path);
        }
      }
      
      // No config found, return defaults
      return ServerConfig.defaults();
    }

    final content = await file.readAsString();
    final yaml = loadYaml(content);
    return ServerConfig.fromYaml(yaml as Map);
  }

  static Future<ServerConfig> loadOrCreate(String configPath) async {
    final file = File(configPath);
    
    if (!await file.exists()) {
      // Create default config
      final defaultConfig = ServerConfig.defaults();
      final exampleFile = File(configPath.replaceAll('config.yaml', 'config.yaml.example'));
      
      if (await exampleFile.exists()) {
        // Copy from example
        await exampleFile.copy(configPath);
        return load(configPath);
      } else {
        // Write default
        await file.create(recursive: true);
        await file.writeAsString(_defaultConfigYaml);
        return defaultConfig;
      }
    }

    return load(configPath);
  }

  static const String _defaultConfigYaml = '''
# LittleBrother Server Configuration
server:
  port: 8080
  cors_origins:
    - "*"

mqtt:
  enabled: false
  host: localhost
  raw_port: 1883
  clean_port: 8883

database:
  dirty_retention_days: 7
  location_retention_days: 30
  location_fuzz_radius_m: 0
  archive_size_warning_mb: 1024

trust:
  defaults:
    local: 1.0
    crowdsourced_clean: 0.8
    crowdsourced_dirty: 0.3
    mqtt: 0.0

peers: []
''';
}
