/* <<LICENSEINJECTOR:HEADER:START>> */
/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 N0V4-N3XU5
 */
/* <<LICENSEINJECTOR:HEADER:END>> */

package art.n0v4.littlebrother

import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL_CELL    = "art.n0v4.littlebrother/cell"
        const val CHANNEL_OPSEC   = "art.n0v4.littlebrother/opsec"
        const val CHANNEL_WAKE    = "art.n0v4.littlebrother/wake"
        const val CHANNEL_PERMS   = "art.n0v4.littlebrother/permissions"
    }

    private lateinit var permHandler: PermissionChannelHandler

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        permHandler = PermissionChannelHandler(this)
        flutterEngine.plugins.add(object : io.flutter.embedding.engine.plugins.FlutterPlugin {
            override fun onAttachedToEngine(binding: io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding) {}
            override fun onDetachedFromEngine(binding: io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding) {}
        })

        // ── Permission channel ────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_PERMS)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestBackgroundLocation" -> permHandler.checkAndRequest(
                        android.Manifest.permission.ACCESS_BACKGROUND_LOCATION,
                        PermissionChannelHandler.REQ_BACKGROUND_LOCATION,
                        result
                    )
                    "requestNearbyWifi" -> permHandler.checkAndRequest(
                        android.Manifest.permission.NEARBY_WIFI_DEVICES,
                        PermissionChannelHandler.REQ_NEARBY_WIFI,
                        result
                    )
                    else -> result.notImplemented()
                }
            }

        // ── Cell channel ──────────────────────────────────────────────────
        val cellHandler = CellChannelHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_CELL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAllCellInfo"         -> cellHandler.getAllCellInfo(result)
                    "getServiceState"        -> cellHandler.getServiceState(result)
                    "getCellCapabilities"    -> cellHandler.getCellCapabilities(result)
                    "getPhysicalChannels"    -> cellHandler.getPhysicalChannels(result)
                    else                     -> result.notImplemented()
                }
            }

        // ── OPSEC channel ─────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_OPSEC)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAirplaneMode" -> {
                        val enable = call.argument<Boolean>("enable") ?: false
                        setAirplaneMode(enable, result)
                    }
                    "setWifiEnabled" -> {
                        val enable = call.argument<Boolean>("enable") ?: false
                        setWifiEnabled(enable, result)
                    }
                    "canWriteSettings" -> {
                        result.success(Settings.System.canWrite(this))
                    }
                    "requestWriteSettings" -> {
                        val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Wake channel ──────────────────────────────────────────────────
        val wakeHandler = WakeLockHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_WAKE)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> { wakeHandler.acquire(); result.success(null) }
                    "release" -> { wakeHandler.release(); result.success(null) }
                    else      -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun setAirplaneMode(enable: Boolean, result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!Settings.System.canWrite(this)) {
                    result.error("NO_PERMISSION", "WRITE_SETTINGS not granted", null)
                    return
                }
            }
            Settings.Global.putInt(
                contentResolver,
                Settings.Global.AIRPLANE_MODE_ON,
                if (enable) 1 else 0
            )
            val intent = Intent(Intent.ACTION_AIRPLANE_MODE_CHANGED)
            intent.putExtra("state", enable)
            sendBroadcast(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("OPSEC_ERROR", e.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun setWifiEnabled(enable: Boolean, result: MethodChannel.Result) {
        try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // API 29+: can't programmatically toggle; open panel instead
                val intent = Intent(Settings.Panel.ACTION_WIFI)
                startActivity(intent)
                result.success(false) // false = user must confirm
            } else {
                wifiManager.isWifiEnabled = enable
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("WIFI_ERROR", e.message, null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::permHandler.isInitialized) {
            permHandler.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}
