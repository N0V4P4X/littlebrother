import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:littlebrother/core/constants/lb_constants.dart';
import 'package:littlebrother/core/models/lb_signal.dart';

class WifiScanner {
  final _uuid = const Uuid();

  final _controller = StreamController<List<LBSignal>>.broadcast();
  final _throttleCtrl = StreamController<bool>.broadcast();

  Stream<List<LBSignal>> get stream => _controller.stream;
  Stream<bool> get throttledStream => _throttleCtrl.stream;
  bool get isRunning => false;
  bool get isThrottled => false;

  Future<void> start(String sessionId, {bool foreground = true}) async {
    _controller.add([]);
    _throttleCtrl.add(false);
  }

  Future<void> stop() async {}

  void dispose() {
    _controller.close();
    _throttleCtrl.close();
  }
}
