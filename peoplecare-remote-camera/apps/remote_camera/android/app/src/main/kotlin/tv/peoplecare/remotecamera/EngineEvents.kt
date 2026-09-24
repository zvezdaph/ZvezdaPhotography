package tv.peoplecare.remotecamera

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Delivers engine events to Dart through the EventChannel. Events are always
 * posted on the main thread (required by the Flutter embedding). When Dart is
 * not listening, events are dropped: Dart asks for a full state on subscribe.
 */
object EngineEvents {
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: EventChannel.EventSink? = null

    fun attach(sink: EventChannel.EventSink?) {
        main.post { this.sink = sink }
    }

    fun emit(type: String, payload: Map<String, Any?>) {
        val event = HashMap<String, Any?>(payload.size + 1)
        event.putAll(payload)
        event["type"] = type
        if (Looper.myLooper() == Looper.getMainLooper()) {
            sink?.success(event)
        } else {
            main.post { sink?.success(event) }
        }
    }

    fun log(level: String, message: String, code: String? = null) {
        emit("log", mapOf("level" to level, "message" to message, "code" to code, "ts" to System.currentTimeMillis()))
    }
}
