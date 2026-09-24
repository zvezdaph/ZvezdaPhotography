package tv.peoplecare.remotecamera

import android.Manifest
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Foreground service that keeps the camera usable while the app is in the
 * background or the phone is locked (Android 9+ requires it for camera and
 * microphone access; Android 14+ requires the camera/microphone service types).
 * It is started while the app is visible ("camera armed") and holds CPU and
 * Wi-Fi locks only while live or recording.
 */
class StreamingService : Service() {

    companion object {
        const val ACTION_ARM = "tv.peoplecare.remotecamera.ARM"
        const val ACTION_STOP_STREAM = "tv.peoplecare.remotecamera.STOP_STREAM"
        const val ACTION_DISARM = "tv.peoplecare.remotecamera.DISARM"

        @Volatile
        var running = false
            private set

        fun arm(context: Context) {
            val intent = Intent(context, StreamingService::class.java).setAction(ACTION_ARM)
            context.startForegroundService(intent)
        }

        fun disarm(context: Context) {
            if (!running) return
            context.startService(Intent(context, StreamingService::class.java).setAction(ACTION_DISARM))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var lastNotificationKey = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Notifications.createChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISARM -> {
                shutdownService()
                return START_NOT_STICKY
            }
            ACTION_STOP_STREAM -> {
                EngineHolder.get(this).stopStream { }
                EngineEvents.log("warning", "Trasmissione fermata dalla notifica")
            }
        }
        if (!goForeground()) return START_NOT_STICKY
        running = true
        EngineHolder.get(this).stateListener = { state -> onEngineState(state) }
        return START_NOT_STICKY
    }

    private fun goForeground(): Boolean {
        val notification = Notifications.build(this, "PeopleCare Remote Camera", "Camera pronta per la regia", live = false)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var types = 0
                if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                    types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                }
                if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                    types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                if (types == 0) {
                    EngineEvents.log("error", "Permesso fotocamera mancante: servizio non avviato", "camera_permission")
                    stopSelf()
                    return false
                }
                startForeground(Notifications.NOTIFICATION_ID, notification, types)
            } else {
                startForeground(Notifications.NOTIFICATION_ID, notification)
            }
            true
        } catch (e: Exception) {
            // Android 12+: ForegroundServiceStartNotAllowedException when started from background.
            EngineEvents.log("error", "Servizio in primo piano non avviato: ${e.message}", "foreground_service")
            stopSelf()
            false
        }
    }

    private fun onEngineState(state: Map<String, Any?>) {
        val status = state["streamStatus"] as? String ?: "idle"
        val paused = state["paused"] == true
        val recording = state["recording"] == true
        val active = status == "live" || status == "connecting" || status == "reconnecting" || recording
        if (active) acquireLocks() else releaseLocks()
        val (title, text) = when {
            status == "live" && paused -> "IN PAUSA" to "Sessione attiva, video e audio sospesi"
            status == "live" -> "● LIVE" to "In onda via ${(state["protocol"] as? String ?: "srt").uppercase()}"
            status == "reconnecting" -> "RICONNESSIONE" to "Rete instabile, riconnessione automatica in corso"
            status == "connecting" -> "CONNESSIONE" to "Connessione a Cloudflare Stream"
            status == "error" -> "ERRORE" to ((state["lastError"] as? Map<*, *>)?.get("message") as? String ?: "Errore trasmissione")
            recording -> "REGISTRAZIONE" to "Registrazione backup in corso"
            else -> "PeopleCare Remote Camera" to "Camera pronta per la regia"
        }
        val key = "$title|$text"
        if (key == lastNotificationKey) return
        lastNotificationKey = key
        getSystemService(NotificationManager::class.java)?.notify(
            Notifications.NOTIFICATION_ID,
            Notifications.build(this, title, text, live = status == "live" || status == "reconnecting"),
        )
    }

    private fun acquireLocks() {
        if (wakeLock?.isHeld != true) {
            val power = getSystemService(PowerManager::class.java)
            wakeLock = power?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "PeopleCare:live")?.apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        if (wifiLock?.isHeld != true) {
            val wifi = applicationContext.getSystemService(WifiManager::class.java)
            @Suppress("DEPRECATION")
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
            wifiLock = wifi?.createWifiLock(mode, "PeopleCare:live")?.apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseLocks() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        wifiLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The app was swiped away: keep an ongoing transmission alive, otherwise release the camera.
        val engine = EngineHolder.get(this)
        engine.getState { result ->
            val state = result.getOrNull()?.get("state") as? Map<*, *>
            val status = state?.get("streamStatus") as? String
            val recording = state?.get("recording") == true
            if (status == "idle" || status == "error" || status == null) {
                if (!recording) shutdownService()
            }
        }
        super.onTaskRemoved(rootIntent)
    }

    private fun shutdownService() {
        EngineHolder.get(this).shutdown { }
        releaseLocks()
        running = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        releaseLocks()
        running = false
        EngineHolder.get(this).stateListener = null
        super.onDestroy()
    }
}
