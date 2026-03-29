package art.n0v4.littlebrother

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class PermissionChannelHandler(private val activity: Activity)
    : PluginRegistry.RequestPermissionsResultListener {

    companion object {
        const val CHANNEL = "art.n0v4.littlebrother/permissions"
        const val REQ_BACKGROUND_LOCATION = 1001
        const val REQ_NEARBY_WIFI         = 1002
    }

    // Map of requestCode → pending MethodChannel.Result so concurrent
    // permission requests don't clobber each other.
    private val pendingResults = mutableMapOf<Int, MethodChannel.Result>()

    fun checkAndRequest(permission: String, requestCode: Int, result: MethodChannel.Result) {
        val status = ContextCompat.checkSelfPermission(activity, permission)
        if (status == PackageManager.PERMISSION_GRANTED) {
            result.success("granted")
            return
        }
        // Store result callback keyed by requestCode
        pendingResults[requestCode] = result
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            ActivityCompat.requestPermissions(activity, arrayOf(permission), requestCode)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        val result = pendingResults.remove(requestCode) ?: return false

        val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED

        result.success(if (granted) "granted" else "denied")
        return true
    }
}
