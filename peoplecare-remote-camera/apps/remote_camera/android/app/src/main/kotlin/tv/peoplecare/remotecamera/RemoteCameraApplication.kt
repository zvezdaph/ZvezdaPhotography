package tv.peoplecare.remotecamera

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The Flutter engine is created once per process and cached: the control
 * connection to the studio (Dart) keeps running while the camera streams in
 * the background, even if the activity is destroyed.
 */
class RemoteCameraApplication : Application() {
    companion object {
        const val ENGINE_ID = "pcrc_main"
    }

    override fun onCreate() {
        super.onCreate()
        Notifications.createChannels(this)
        val engine = FlutterEngine(this)
        engine.plugins.add(CameraBridgePlugin())
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }
}
