package art.n0v4.littlebrother

import android.content.Context
import android.os.PowerManager

class WakeLockHandler(context: Context) {
    private val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val wakeLock: PowerManager.WakeLock = pm.newWakeLock(
        PowerManager.PARTIAL_WAKE_LOCK,
        "LittleBrother::ScanWakeLock"
    )

    fun acquire() {
        if (!wakeLock.isHeld) {
            wakeLock.acquire(30 * 60 * 1000L) // max 30 min per acquire
        }
    }

    fun release() {
        if (wakeLock.isHeld) wakeLock.release()
    }
}
