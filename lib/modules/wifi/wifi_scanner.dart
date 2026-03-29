// ignore: UNUSED_IMPORT
import 'package:littlebrother/modules/wifi/wifi_scanner_stub.dart'
    if (dart.library.io) 'package:littlebrother/modules/wifi/wifi_scanner_android.dart'
    if (dart.library.io_ffi) 'package:littlebrother/modules/wifi/wifi_scanner_linux.dart';

export 'package:littlebrother/modules/wifi/wifi_scanner_stub.dart'
    if (dart.library.io) 'package:littlebrother/modules/wifi/wifi_scanner_android.dart'
    if (dart.library.io_ffi) 'package:littlebrother/modules/wifi/wifi_scanner_linux.dart';
