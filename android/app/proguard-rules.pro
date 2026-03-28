# LittleBrother ProGuard rules

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep our platform channel handlers
-keep class art.n0v4.littlebrother.** { *; }

# SQLite / sqflite
-keep class org.sqlite.** { *; }
-keep class org.sqlite.database.** { *; }

# flutter_local_notifications
-keep class com.dexterous.** { *; }

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# flutter_blue_plus
-keep class com.boskokg.flutter_blue_plus.** { *; }

# geolocator
-keep class com.baseflow.geolocator.** { *; }

# wifi_scan
-keep class in.aabhasjindal.otpwhatever.** { *; }

# Gson / JSON (used by Flutter plugins internally)
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}
