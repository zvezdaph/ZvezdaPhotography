package tv.peoplecare.remotecamera

import android.content.Context

/** Process-wide engine: shared by the Flutter plugin and the foreground service. */
object EngineHolder {
    @Volatile
    private var engine: CameraEngine? = null

    fun get(context: Context): CameraEngine =
        engine ?: synchronized(this) {
            engine ?: CameraEngine(context.applicationContext).also { engine = it }
        }
}
