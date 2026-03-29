import 'package:littlebrother/core/wake_lock_stub.dart'
    if (dart.library.io) 'package:littlebrother/core/wake_lock_android.dart'
    if (dart.library.ffi) 'package:littlebrother/core/wake_lock_linux.dart';

export 'package:littlebrother/core/wake_lock_stub.dart'
    if (dart.library.io) 'package:littlebrother/core/wake_lock_android.dart'
    if (dart.library.ffi) 'package:littlebrother/core/wake_lock_linux.dart';
