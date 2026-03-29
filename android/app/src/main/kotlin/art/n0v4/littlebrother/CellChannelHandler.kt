/* <<LICENSEINJECTOR:HEADER:START>> */
/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 N0V4-N3XU5
 */
/* <<LICENSEINJECTOR:HEADER:END>> */

package art.n0v4.littlebrother

import android.content.Context
import android.os.Build
import android.telephony.*
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodChannel

class CellChannelHandler(private val context: Context) {

    private val telephonyManager: TelephonyManager by lazy {
        context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
    }

    private val locationManager: android.location.LocationManager by lazy {
        context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
    }

    fun getAllCellInfo(result: MethodChannel.Result) {
        try {
            val cells = telephonyManager.allCellInfo ?: run {
                result.success(emptyList<Map<String, Any>>())
                return
            }
            val output = cells.mapNotNull { parseCellInfo(it) }
            result.success(output)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "READ_PHONE_STATE required", null)
        } catch (e: Exception) {
            result.error("CELL_ERROR", e.message, null)
        }
    }

    fun getServiceState(result: MethodChannel.Result) {
        try {
            val state = mutableMapOf<String, Any>()
            state["dataNetworkType"] = telephonyManager.dataNetworkType
            state["voiceNetworkType"] = telephonyManager.voiceNetworkType
            state["networkTypeName"] = networkTypeName(telephonyManager.dataNetworkType)
            state["isRoaming"] = telephonyManager.isNetworkRoaming
            state["operatorName"] = telephonyManager.networkOperatorName ?: ""
            state["operator"] = telephonyManager.networkOperator ?: ""

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                state["signalStrength"] = parseSignalStrength(telephonyManager.signalStrength)
            }
            result.success(state)
        } catch (e: Exception) {
            result.error("SERVICE_STATE_ERROR", e.message, null)
        }
    }

    fun getCellCapabilities(result: MethodChannel.Result) {
        val caps = mutableMapOf<String, Any>()
        val readPhoneState = context.checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE)
        val fineLocation = context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION)
        val coarseLocation = context.checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION)
        val hasLocationPermission = fineLocation == android.content.pm.PackageManager.PERMISSION_GRANTED ||
                                    coarseLocation == android.content.pm.PackageManager.PERMISSION_GRANTED
        val hasPhoneStatePermission = readPhoneState == android.content.pm.PackageManager.PERMISSION_GRANTED

        val locationEnabled = try {
            locationManager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) ||
            locationManager.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)
        } catch (e: Exception) { false }

        val allCellInfoAvailable = try {
            val test = telephonyManager.allCellInfo
            test != null
        } catch (e: SecurityException) { false }

        val allCellInfoEmpty = try {
            val test = telephonyManager.allCellInfo
            test == null || test.isEmpty()
        } catch (e: Exception) { true }

        caps["hasPhoneStatePermission"] = hasPhoneStatePermission
        caps["hasLocationPermission"] = hasLocationPermission
        caps["locationEnabled"] = locationEnabled
        caps["allCellInfoAvailable"] = allCellInfoAvailable
        caps["allCellInfoEmpty"] = allCellInfoEmpty
        caps["androidVersion"] = Build.VERSION.SDK_INT
        caps["manufacturer"] = Build.MANUFACTURER
        caps["model"] = Build.MODEL
        caps["supportsNr"] = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

        val diagnosis = when {
            !hasPhoneStatePermission -> "MISSING_PHONE_STATE_PERMISSION"
            !hasLocationPermission -> "MISSING_LOCATION_PERMISSION"
            !locationEnabled -> "LOCATION_DISABLED"
            !allCellInfoAvailable -> "ALL_CELL_INFO_NOT_AVAILABLE"
            allCellInfoEmpty -> "ALL_CELL_INFO_EMPTY"
            else -> "OK"
        }
        caps["diagnosis"] = diagnosis

        result.success(caps)
    }

    fun getPhysicalChannels(result: MethodChannel.Result) {
        result.success(emptyList<Map<String, Any>>())
    }

    // ── Cell info parsers ──────────────────────────────────────────────────

    private fun parseCellInfo(cell: CellInfo): Map<String, Any>? {
        val base = mutableMapOf<String, Any>(
            "isServing"     to cell.isRegistered,
            "timestampNanos" to cell.timeStamp,
        )

        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && cell is CellInfoNr -> parseNr(cell, base)
            cell is CellInfoLte  -> parseLte(cell, base)
            cell is CellInfoWcdma -> parseWcdma(cell, base)
            cell is CellInfoGsm  -> parseGsm(cell, base)
            cell is CellInfoCdma -> parseCdma(cell, base)
            else -> null
        }
    }

    private fun parseLte(cell: CellInfoLte, base: MutableMap<String, Any>): Map<String, Any> {
        val id = cell.cellIdentity
        val sig = cell.cellSignalStrength

        base["type"] = "LTE"
        base["mcc"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mccString ?: "" else id.mcc.toString()
        base["mnc"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mncString ?: "" else id.mnc.toString()
        base["tac"] = id.tac
        base["ci"] = id.ci       // Cell Identity (28-bit)
        base["pci"] = id.pci     // Physical Cell ID (0–503)
        base["earfcn"] = id.earfcn
        base["bandwidth"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) id.bandwidth else -1
        base["rssi"] = sig.rssi
        base["rsrp"] = sig.rsrp  // Reference Signal Received Power (dBm)
        base["rsrq"] = sig.rsrq  // Reference Signal Received Quality (dB)
        base["rssnr"] = sig.rssnr
        base["cqi"] = sig.cqi
        base["timingAdvance"] = sig.timingAdvance
        base["level"] = sig.level
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            base["band"] = id.bands.firstOrNull() ?: -1
        }
        // Composite cell ID for DB keying
        base["cellKey"] = "${base["mcc"]}-${base["mnc"]}-${base["tac"]}-${base["ci"]}"
        return base
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun parseNr(cell: CellInfoNr, base: MutableMap<String, Any>): Map<String, Any> {
        val id = cell.cellIdentity as CellIdentityNr
        val sig = cell.cellSignalStrength as CellSignalStrengthNr

        base["type"] = "NR"
        base["mcc"] = id.mccString ?: ""
        base["mnc"] = id.mncString ?: ""
        base["tac"] = id.tac
        base["nci"] = id.nci    // NR Cell Identity (36-bit)
        base["pci"] = id.pci
        base["arfcn"] = id.nrarfcn
        base["ssRsrp"] = sig.ssRsrp
        base["ssRsrq"] = sig.ssRsrq
        base["ssSinr"] = sig.ssSinr
        base["csiRsrp"] = sig.csiRsrp
        base["csiRsrq"] = sig.csiRsrq
        base["level"] = sig.level
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            base["band"] = id.bands.firstOrNull() ?: -1
        }
        base["cellKey"] = "${base["mcc"]}-${base["mnc"]}-${base["tac"]}-${base["nci"]}"
        return base
    }

    private fun parseWcdma(cell: CellInfoWcdma, base: MutableMap<String, Any>): Map<String, Any> {
        val id = cell.cellIdentity
        val sig = cell.cellSignalStrength

        base["type"] = "UMTS"
        base["mcc"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mccString ?: "" else id.mcc.toString()
        base["mnc"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mncString ?: "" else id.mnc.toString()
        base["lac"] = id.lac
        base["cid"] = id.cid
        base["psc"] = id.psc   // Primary Scrambling Code
        base["uarfcn"] = id.uarfcn
        base["rssi"] = sig.dbm
        base["level"] = sig.level
        base["cellKey"] = "${base["mcc"]}-${base["mnc"]}-${base["lac"]}-${base["cid"]}"
        return base
    }

    private fun parseGsm(cell: CellInfoGsm, base: MutableMap<String, Any>): Map<String, Any> {
        val id = cell.cellIdentity
        val sig = cell.cellSignalStrength

        base["type"] = "GSM"
        base["mcc"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mccString ?: "" else id.mcc.toString()
        base["mnc"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mncString ?: "" else id.mnc.toString()
        base["lac"] = id.lac
        base["cid"] = id.cid
        base["arfcn"] = id.arfcn
        base["bsic"] = id.bsic  // Base Station Identity Code
        base["rssi"] = sig.dbm
        base["bitErrorRate"] = sig.bitErrorRate
        base["level"] = sig.level
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            base["timingAdvance"] = sig.timingAdvance
        }
        base["cellKey"] = "${base["mcc"]}-${base["mnc"]}-${base["lac"]}-${base["cid"]}"
        return base
    }

    private fun parseCdma(cell: CellInfoCdma, base: MutableMap<String, Any>): Map<String, Any> {
        val id = cell.cellIdentity
        val sig = cell.cellSignalStrength

        base["type"] = "CDMA"
        base["networkId"] = id.networkId
        base["systemId"] = id.systemId
        base["basestationId"] = id.basestationId
        base["cdmaDbm"] = sig.cdmaDbm
        base["cdmaEcio"] = sig.cdmaEcio
        base["evdoDbm"] = sig.evdoDbm
        base["level"] = sig.level
        base["cellKey"] = "CDMA-${base["systemId"]}-${base["networkId"]}-${base["basestationId"]}"
        return base
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun parseSignalStrength(sig: SignalStrength?): Map<String, Any> {
        if (sig == null) return emptyMap()
            return mapOf(
                "level" to sig.level,
                "dbm" to sig.getCellSignalStrengths().firstOrNull()?.dbm.let { it ?: -1 }
            )
    }

    private fun networkTypeName(type: Int): String = when (type) {
        TelephonyManager.NETWORK_TYPE_NR      -> "NR"
        TelephonyManager.NETWORK_TYPE_LTE     -> "LTE"
        TelephonyManager.NETWORK_TYPE_HSPAP,
        TelephonyManager.NETWORK_TYPE_HSPA,
        TelephonyManager.NETWORK_TYPE_HSDPA,
        TelephonyManager.NETWORK_TYPE_HSUPA,
        TelephonyManager.NETWORK_TYPE_UMTS    -> "UMTS"
        TelephonyManager.NETWORK_TYPE_EDGE,
        TelephonyManager.NETWORK_TYPE_GPRS,
        TelephonyManager.NETWORK_TYPE_GSM     -> "GSM"
        TelephonyManager.NETWORK_TYPE_CDMA,
        TelephonyManager.NETWORK_TYPE_1xRTT,
        TelephonyManager.NETWORK_TYPE_EVDO_0,
        TelephonyManager.NETWORK_TYPE_EVDO_A,
        TelephonyManager.NETWORK_TYPE_EVDO_B  -> "CDMA"
        TelephonyManager.NETWORK_TYPE_UNKNOWN -> "UNKNOWN"
        else                                  -> "OTHER($type)"
    }
}
