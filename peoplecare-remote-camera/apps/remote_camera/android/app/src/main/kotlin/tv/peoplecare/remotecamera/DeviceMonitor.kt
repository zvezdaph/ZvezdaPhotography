package tv.peoplecare.remotecamera

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import java.io.File

/** Battery, temperature and storage readings, using only non-invasive public APIs. */
class DeviceMonitor(private val context: Context) {
    fun snapshot(recordingDir: File?): Map<String, Any?> {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val tempTenths = battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE) ?: Int.MIN_VALUE
        val percent = if (level >= 0 && scale > 0) level * 100.0 / scale else null
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        val temperature = if (tempTenths != Int.MIN_VALUE && tempTenths > -400) tempTenths / 10.0 else null
        return mapOf(
            "batteryPercent" to percent,
            "charging" to charging,
            "temperatureC" to temperature,
            "thermal" to thermalStatus(),
            "storageFreeBytes" to freeBytes(recordingDir),
        )
    }

    fun freeBytes(dir: File?): Long? {
        val target = dir ?: return null
        return try {
            if (!target.exists()) target.mkdirs()
            StatFs(target.absolutePath).availableBytes
        } catch (_: Exception) {
            null
        }
    }

    private fun thermalStatus(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val power = context.getSystemService(PowerManager::class.java) ?: return null
        return when (power.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> "none"
            PowerManager.THERMAL_STATUS_LIGHT -> "light"
            PowerManager.THERMAL_STATUS_MODERATE -> "moderate"
            PowerManager.THERMAL_STATUS_SEVERE -> "severe"
            PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
            PowerManager.THERMAL_STATUS_EMERGENCY -> "emergency"
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "shutdown"
            else -> null
        }
    }
}
