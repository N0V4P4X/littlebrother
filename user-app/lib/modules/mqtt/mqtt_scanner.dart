import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';

/// MQTT Scanner: Subscribes to an MQTT broker for external signal data.
class MqttScanner {
  final _uuid = const Uuid();
  MqttServerClient? _client;
  final _controller = StreamController<List<LBSignal>>.broadcast();
    
   // Configuration
   final String _brokerUrl;
   final int _port;
   final String _username;
   final String _password;
   final String _clientId;
   final List<String> _topics; // Topics to subscribe to
   
   // Connection state
   bool _isConnected = false;
   
   MqttScanner({
     required String brokerUrl,
     int port = 8883,
     String username = '',
     String password = '',
     String? clientId,
     List<String>? topics,
   })  : _brokerUrl = brokerUrl,
         _port = port,
         _username = username,
         _password = password,
         _clientId = clientId ?? 'littlebrother_${const Uuid().v4()}',
         _topics = topics ?? ['lb/signals/#'];
   
   Stream<List<LBSignal>> get stream => _controller.stream;
   bool get isRunning => _isConnected;
   
   Future<void> start(String sessionId) async {
     if (_isConnected) return;
     
     stderr.write('LB_MQTT: connecting to broker $_brokerUrl:$_port\n');
     
     _client = MqttServerClient(_brokerUrl, _clientId);
     _client!.port = _port;
     _client!.keepAlivePeriod = 20;
     _client!.secure = _port == 8883;
     if (_client!.secure) {
       _client!.securityContext = SecurityContext.defaultContext;
     }
     _client!.logging(on: false);
     
     // Authentication
     if (_username.isNotEmpty) {
       final connMess = MqttConnectMessage()
           .withClientIdentifier(_clientId)
           .withWillQos(MqttQos.atLeastOnce)
           .startClean()
           .withWillTopic('lb/status')
           .withWillMessage('offline')
           .authenticateAs(_username, _password);
       _client!.connectionMessage = connMess;
     } else {
       _client!.connectionMessage = MqttConnectMessage()
           .withClientIdentifier(_clientId)
           .startClean();
     }
     
     // Connection handler - assign available callbacks
     _client!.onConnected = _onConnected;
     _client!.onDisconnected = _onDisconnected;
     _client!.onSubscribed = _onSubscribed;
     
     try {
       await _client!.connect();
     } catch (e) {
       stderr.write('LB_MQTT: connection error: $e\n');
       rethrow;
     }
   }
   
   void _onConnected() {
     _isConnected = true;
     stderr.write('LB_MQTT: connected to broker\n');
     
     // Subscribe to topics
     for (final topic in _topics) {
       _client!.subscribe(topic, MqttQos.atLeastOnce);
       stderr.write('LB_MQTT: subscribed to topic: $topic\n');
     }
     
     // Set up message handler
     _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage>>? c) {
       if (c != null && c.isNotEmpty) {
         final recvMsg = c[0].payload as MqttPublishMessage;
         final payload = MqttPublishPayload.bytesToStringAsString(recvMsg.payload.message);
         _handleMessage(payload);
       }
     });
   }
   
   void _onDisconnected() {
     _isConnected = false;
     stderr.write('LB_MQTT: disconnected from broker\n');
   }
   
    void _onSubscribed(String topic) {
      stderr.write('LB_MQTT: subscribed to $topic\n');
    }
    
    void _handleMessage(String payload) {
     try {
       // Expecting JSON payload with signal data
       final jsonData = jsonDecode(payload);
       
       // Handle both single signal and array of signals
       final List<dynamic> signalsJson = jsonData is List ? jsonData : [jsonData];
       final signals = <LBSignal>[];
       final now = DateTime.now();
       
       for (final signalJson in signalsJson) {
         final signal = _parseSignal(signalJson, now);
         if (signal != null) {
           signals.add(signal);
         }
       }
       
       if (signals.isNotEmpty) {
         stderr.write('LB_MQTT: received ${signals.length} signals from broker\n');
         if (!_controller.isClosed) {
           _controller.add(signals);
         }
       }
     } catch (e) {
       stderr.write('LB_MQTT: failed to parse message: $e\n');
     }
   }
   
   LBSignal? _parseSignal(dynamic json, DateTime now) {
     try {
       // Required fields
        final String sessionId = (json['sessionId'] as String?) ?? '';
        final String identifier = (json['identifier'] as String?) ?? '';
        final String signalTypeStr = (json['signalType'] as String?) ?? '';
       
       if (sessionId.isEmpty || identifier.isEmpty || signalTypeStr.isEmpty) {
         return null;
       }
       
        // Map signalType string to enum values from constants
        final String signalTypeLower = signalTypeStr.toLowerCase();
        String signalType;
        if (signalTypeLower == LBSignalType.wifi) {
          signalType = LBSignalType.wifi;
        } else if (signalTypeLower == LBSignalType.ble) {
          signalType = LBSignalType.ble;
        } else if (signalTypeLower == LBSignalType.cell) {
          signalType = LBSignalType.cell;
        } else if (signalTypeLower == LBSignalType.cellNeighbor) {
          signalType = LBSignalType.cellNeighbor;
        } else {
          signalType = LBSignalType.wifi;
        }
       
        final String displayName = (json['displayName'] as String?) ?? identifier;
        final int rssi = (json['rssi'] as num?)?.toInt() ?? -100;
       final double distanceM = (json['distanceM'] as num?)?.toDouble() ?? _estimateDistance(rssi);
       final int riskScore = (json['riskScore'] as num?)?.toInt() ?? 0;
       
       // Metadata - preserve all extra fields
       final Map<String, dynamic> metadata = Map<String, dynamic>.from(json['metadata'] ?? {});
       // Add MQTT-specific metadata
       metadata['mqtt_received'] = true;
        metadata['mqtt_timestamp'] = (json['timestamp'] as String?) ?? now.toIso8601String();
       
        return LBSignal(
          id: (json['id'] as String?) ?? _uuid.v4(),
          sessionId: sessionId,
          signalType: signalType,
          identifier: identifier,
          displayName: displayName,
          rssi: rssi,
          distanceM: distanceM,
          riskScore: riskScore.clamp(0, 100),
          metadata: metadata,
          timestamp: DateTime.tryParse((json['timestamp'] as String?) ?? now.toIso8601String()) ?? now,
        );
     } catch (e) {
       stderr.write('LB_MQTT: error parsing signal: $e\n');
       return null;
     }
   }
   
    double _estimateDistance(int rssi, {int txPower = LBPathLoss.defaultTxPowerDbm}) {
      if (rssi == 0) return -1.0;
      final exp = (txPower - rssi) / (10 * LBPathLoss.nIndoor);
      return math.pow(10, exp).toDouble();
    }
   
   Future<void> stop() async {
     if (!_isConnected) return;
     
     stderr.write('LB_MQTT: disconnecting from broker\n');
     _isConnected = false;
     _client?.disconnect();
     _client = null;
   }
   
   void dispose() {
     stop();
     _controller.close();
   }
}