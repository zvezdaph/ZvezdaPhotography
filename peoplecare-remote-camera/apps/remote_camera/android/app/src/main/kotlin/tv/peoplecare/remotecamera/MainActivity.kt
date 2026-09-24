package tv.peoplecare.remotecamera

import android.os.Build
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun getCachedEngineId(): String = RemoteCameraApplication.ENGINE_ID

    // The engine outlives the activity (background streaming, control connection).
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onResume() {
        super.onResume()
        EngineHolder.get(this).setActivityVisible(true, displayRotationDegrees())
    }

    override fun onPause() {
        EngineHolder.get(this).setActivityVisible(false, displayRotationDegrees())
        super.onPause()
    }

    fun displayRotationDegrees(): Int {
        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display?.rotation ?: Surface.ROTATION_90
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.rotation
        }
        return when (rotation) {
            Surface.ROTATION_0 -> 0
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 90
        }
    }
}
