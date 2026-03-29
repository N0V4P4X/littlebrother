import 'package:littlebrother/opsec/opsec_controller_stub.dart'
    if (dart.library.io) 'package:littlebrother/opsec/opsec_controller_android.dart'
    if (dart.library.ffi) 'package:littlebrother/opsec/opsec_controller_linux.dart';

export 'package:littlebrother/opsec/opsec_controller_stub.dart'
    if (dart.library.io) 'package:littlebrother/opsec/opsec_controller_android.dart'
    if (dart.library.ffi) 'package:littlebrother/opsec/opsec_controller_linux.dart';
