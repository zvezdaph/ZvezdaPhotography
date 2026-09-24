package tv.peoplecare.remotecamera

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaCodec
import android.media.MediaRecorder
import android.net.Network
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.view.MotionEvent
import android.view.Surface
import android.view.View
import com.pedro.common.ConnectChecker
import com.pedro.common.StreamingStatsReport
import com.pedro.encoder.CodecErrorCallback
import com.pedro.encoder.input.sources.audio.AudioSource
import com.pedro.encoder.input.sources.audio.MicrophoneSource
import com.pedro.encoder.input.sources.video.Camera2Source
import com.pedro.encoder.input.video.CameraCallbacks
import com.pedro.encoder.input.video.CameraHelper
import com.pedro.encoder.utils.CodecUtil
import com.pedro.library.base.recording.RecordController
import com.pedro.library.generic.GenericStream
import com.pedro.library.util.QueueAwareBitrateAdapter
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Single owner of camera, preview, encoders, local recording and SRT/RTMPS
 * streaming (RootEncoder GenericStream). The same engine instance serves the
 * preview texture and the stream: the camera is never opened by two stacks.
 *
 * Threading: every public method posts its work on one dedicated thread;
 * results are delivered on the main thread. RootEncoder callbacks (main
 * thread) are forwarded to the same engine thread.
 */
class CameraEngine(private val context: Context) : ConnectChecker {

    companion object {
        private const val SAMPLE_RATE = 48_000
        private const val FALLBACK_SAMPLE_RATE = 44_100
        private const val SRT_FAILURES_BEFORE_FALLBACK = 3
        private const val STALL_SECONDS = 8
        private const val CONNECTING_TIMEOUT_MS = 45_000L
        private const val MIN_FREE_BYTES_FOR_RECORDING = 1_000_000_000L
        private const val DEVICE_REPORT_MS = 5_000L
        private const val SUPERVISOR_MS = 5_000L
        private const val FOCUS_VIEW_SIZE = 10_000
        private val PRESETS = mapOf(
            "low" to Triple("720p", 25, 2_000),
            "standard" to Triple("1080p", 30, 5_000),
            "high" to Triple("1080p", 30, 7_000),
        )
    }

    private val executor = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "PCRC-Engine").apply { priority = Thread.NORM_PRIORITY + 1 }
    }
    private val main = Handler(Looper.getMainLooper())
    private val probe = CapabilityProbe(context)
    private val deviceMonitor = DeviceMonitor(context)
    private val networkMonitor = NetworkMonitor(context) { previous, current ->
        executor.execute { onNetworkChanged(previous, current) }
    }

    /** Notified (main thread) on every state change: used by StreamingService. */
    @Volatile
    var stateListener: ((Map<String, Any?>) -> Unit)? = null

    private var caps: Map<String, CapabilityProbe.FacingCaps> = emptyMap()
    private var stream: GenericStream? = null
    private var camera: Camera2Source? = null
    private var microphone: MicrophoneSource? = null
    private var micAvailable = false
    private var initialized = false

    private var settings = VideoSettings.DEFAULT
    private var cameraStatus = "off"
    private var streamStatus = "idle"
    private var desiredStreaming = false
    private var paused = false
    private var userVideoEnabled = true
    private var userAudioEnabled = true
    private var torch = false
    private var autofocus = false
    private var exposure = 0
    private var zoom = 1f
    private var facing = "back"
    private var recording = false
    private var recordingFile: File? = null
    private var lastError: EngineError? = null
    private val recentErrors = ArrayDeque<EngineError>()

    private var request: StreamRequest? = null
    private var activeEndpoint: Endpoint? = null
    private var fallbackActive = false
    private var connectedOnce = false
    private var consecutiveFailures = 0
    private var reconnects = 0
    private var sessionStartedAt = 0L
    private var connectedAt = 0L
    private var connectingSince = 0L
    private var retryPending = false
    private var expectedDisconnects = 0
    private val policy = ReconnectPolicy()
    private var restartFuture: ScheduledFuture<*>? = null
    private var supervisorFuture: ScheduledFuture<*>? = null
    private var deviceFuture: ScheduledFuture<*>? = null
    private var focusView: View? = null
    private var bitrateAdapter: QueueAwareBitrateAdapter? = null
    private var currentVideoKbps = 0
    private var fps = 0
    private var zeroBytesSeconds = 0

    private var previewSurface: Surface? = null
    private var previewWidth = 0
    private var previewHeight = 0
    private var activityVisible = false
    private var displayRotationDegrees = 90
    private var lastNetworkId: Int? = null

    // ---------------------------------------------------------------------
    // Threading helpers
    // ---------------------------------------------------------------------

    private fun <T> submit(callback: (Result<T>) -> Unit, block: () -> T) {
        executor.execute {
            val result = try {
                Result.success(block())
            } catch (e: EngineException) {
                Result.failure(e)
            } catch (e: IllegalArgumentException) {
                Result.failure(EngineException("invalid_argument", e.message ?: "Parametro non valido"))
            } catch (e: IllegalStateException) {
                Result.failure(EngineException("invalid_state", e.message ?: "Stato non valido"))
            } catch (e: Exception) {
                Result.failure(EngineException("engine_error", e.message ?: e.javaClass.simpleName))
            }
            main.post { callback(result) }
        }
    }

    private fun requireStream(): GenericStream =
        stream ?: throw EngineException("not_initialized", "Camera non inizializzata")

    private fun requireCamera(): Camera2Source =
        camera ?: throw EngineException("not_initialized", "Camera non inizializzata")

    private fun hasPermission(permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    // ---------------------------------------------------------------------
    // Lifecycle
    // ---------------------------------------------------------------------

    fun initialize(requested: VideoSettings, callback: (Result<Map<String, Any?>>) -> Unit) = submit(callback) {
        if (!hasPermission(Manifest.permission.CAMERA)) {
            throw EngineException("camera_permission", "Permesso fotocamera negato")
        }
        if (!initialized) {
            cameraStatus = "starting"
            emitState()
            caps = probe.probe()
            if (caps.isEmpty()) {
                cameraStatus = "error"
                recordError("camera_unavailable", "Nessuna fotocamera disponibile")
                throw EngineException("camera_unavailable", "Nessuna fotocamera disponibile")
            }
            facing = if (caps.containsKey("back")) "back" else "front"
            val cam = Camera2Source(context)
            if (facing == "front") cam.switchCamera()
            cam.setCameraCallback(cameraCallbacks)
            camera = cam
            micAvailable = hasPermission(Manifest.permission.RECORD_AUDIO)
            val audio: AudioSource = if (micAvailable) {
                MicrophoneSource(MediaRecorder.AudioSource.CAMCORDER).also { microphone = it }
            } else {
                recordError("microphone_denied", "Permesso microfono negato: viene trasmesso audio silenzioso")
                SilenceAudioSource()
            }
            val generic = GenericStream(context, this, cam, audio)
            generic.getGlInterface().autoHandleOrientation = activityVisible
            generic.setFpsListener { value -> executor.execute { fps = value } }
            generic.setEncoderErrorCallback(codecErrorCallback)
            generic.getStreamClient().setReTries(Int.MAX_VALUE)
            stream = generic
            settings = sanitizeSettings(requested)
            prepareEncoders()
            networkMonitor.start()
            scheduleDeviceReports()
            initialized = true
            cameraStatus = "ready"
            main.post { focusView = View(context).apply { layout(0, 0, FOCUS_VIEW_SIZE, FOCUS_VIEW_SIZE) } }
            EngineEvents.log("info", "Camera pronta: ${settings.resolutionLabel} ${settings.fps} fps")
        } else if (!micAvailable && hasPermission(Manifest.permission.RECORD_AUDIO)) {
            // The microphone permission was granted after start: switch from silence to the real microphone.
            val mic = MicrophoneSource(MediaRecorder.AudioSource.CAMCORDER)
            try {
                requireStream().changeAudioSource(mic)
                microphone = mic
                micAvailable = true
                applyMute()
                EngineEvents.log("info", "Microfono attivato")
            } catch (e: Exception) {
                recordError("microphone_unavailable", "Microfono non attivabile: ${e.message}")
            }
        }
        emitCapabilities()
        emitState()
        mapOf("capabilities" to capabilitiesMap(), "state" to stateMap())
    }

    /** Stops everything and releases the camera (the app was closed from the UI). */
    fun shutdown(callback: (Result<Unit>) -> Unit) = submit(callback) {
        desiredStreaming = false
        restartFuture?.cancel(false)
        supervisorFuture?.cancel(false)
        deviceFuture?.cancel(false)
        networkMonitor.stop()
        stream?.let { s ->
            if (s.isRecording) s.stopRecord()
            if (s.isStreaming) {
                expectedDisconnects++
                s.stopStream()
            }
            if (s.isOnPreview) s.stopPreview()
            s.release()
        }
        stream = null
        camera = null
        microphone = null
        initialized = false
        cameraStatus = "off"
        streamStatus = "idle"
        recording = false
        emitState()
    }

    fun setActivityVisible(visible: Boolean, rotationDegrees: Int) {
        executor.execute {
            activityVisible = visible
            if (visible) displayRotationDegrees = rotationDegrees
            // While the UI is hidden the orientation is frozen (the phone may be locked in portrait).
            stream?.getGlInterface()?.autoHandleOrientation = visible
        }
    }

    // ---------------------------------------------------------------------
    // Preview (Flutter texture)
    // ---------------------------------------------------------------------

    fun attachPreview(surface: Surface, width: Int, height: Int, callback: (Result<Unit>) -> Unit) = submit(callback) {
        val s = requireStream()
        previewSurface = surface
        previewWidth = width
        previewHeight = height
        if (!surface.isValid) throw EngineException("preview_surface", "Superficie di anteprima non valida")
        if (s.isOnPreview) s.stopPreview()
        s.startPreview(surface, width, height)
        applyManualOrientationIfHidden()
        refreshCameraControls()
        emitState()
    }

    /**
     * Stops rendering into the preview surface and waits (bounded) for it on the
     * engine thread. Used when Flutter is about to destroy the texture surface.
     * Must not be called from the engine thread.
     */
    fun detachPreviewBlocking(timeoutMs: Long) {
        val latch = CountDownLatch(1)
        executor.execute {
            try {
                previewSurface = null
                stream?.let { if (it.isOnPreview) it.stopPreview() }
            } catch (_: Exception) {
            } finally {
                latch.countDown()
            }
            emitState()
        }
        latch.await(timeoutMs, TimeUnit.MILLISECONDS)
    }

    fun detachPreview(callback: (Result<Unit>) -> Unit) = submit(callback) {
        previewSurface = null
        stream?.let { if (it.isOnPreview) it.stopPreview() }
        emitState()
    }

    // ---------------------------------------------------------------------
    // Streaming
    // ---------------------------------------------------------------------

    fun startStream(req: StreamRequest, callback: (Result<Map<String, Any?>>) -> Unit) = submit(callback) {
        val s = requireStream()
        if (desiredStreaming) throw EngineException("already_streaming", "La trasmissione è già attiva")
        // Validate endpoints before touching the encoders.
        EndpointUrls.build(req.primary, req.srtLatencyMs)
        req.fallback?.let { EndpointUrls.build(it, req.srtLatencyMs) }
        request = req
        activeEndpoint = req.primary
        fallbackActive = false
        desiredStreaming = true
        paused = false
        applyMute()
        reconnects = 0
        consecutiveFailures = 0
        connectedOnce = false
        policy.reset()
        sessionStartedAt = System.currentTimeMillis()
        connectedAt = 0L
        lastError = null
        connectToActiveEndpoint(s)
        startSupervisor()
        mapOf("protocol" to (activeEndpoint?.protocol ?: "srt"))
    }

    fun stopStream(callback: (Result<Unit>) -> Unit) = submit(callback) { stopStreamInternal("Stop richiesto") }

    private fun stopStreamInternal(reason: String) {
        desiredStreaming = false
        restartFuture?.cancel(false)
        restartFuture = null
        supervisorFuture?.cancel(false)
        supervisorFuture = null
        retryPending = false
        paused = false
        applyMute()
        val s = stream
        if (s != null && s.isStreaming) {
            streamStatus = "stopping"
            emitState()
            expectedDisconnects++
            s.stopStream()
        }
        bitrateAdapter = null
        streamStatus = "idle"
        connectedAt = 0L
        sessionStartedAt = 0L
        EngineEvents.log("info", "Trasmissione fermata ($reason)")
        emitState()
    }

    /** Fast reconnection of the transport; encoders and camera keep running. */
    fun reconnect(callback: (Result<Unit>) -> Unit) = submit(callback) {
        if (!desiredStreaming) throw EngineException("not_streaming", "Nessuna trasmissione attiva")
        scheduleFullRestart(200, "Riconnessione richiesta")
    }

    /** Stop + start of the whole transmission (new SRT session). */
    fun restartStream(callback: (Result<Unit>) -> Unit) = submit(callback) {
        if (!desiredStreaming) throw EngineException("not_streaming", "Nessuna trasmissione attiva")
        scheduleFullRestart(500, "Riavvio richiesto")
    }

    private fun connectToActiveEndpoint(s: GenericStream) {
        val endpoint = activeEndpoint ?: return
        val req = request ?: return
        val url = EndpointUrls.build(endpoint, req.srtLatencyMs)
        streamStatus = if (connectedOnce) "reconnecting" else "connecting"
        connectingSince = SystemClock.elapsedRealtime()
        retryPending = true
        emitState()
        if (settings.bitrateMode == "auto") {
            val total = (settings.videoBitrateKbps + settings.audioBitrateKbps) * 1000
            bitrateAdapter = QueueAwareBitrateAdapter(total, total / 5) { bitrate ->
                executor.execute { applyVideoBitrate((bitrate / 1000) - settings.audioBitrateKbps) }
            }
        } else {
            bitrateAdapter = null
        }
        currentVideoKbps = settings.videoBitrateKbps
        EngineEvents.log("info", "Connessione ${endpoint.protocol.uppercase()} a ${EndpointUrls.redact(url)}")
        s.getStreamClient().setReTries(Int.MAX_VALUE)
        s.startStream(url)
        applyManualOrientationIfHidden()
    }

    private fun scheduleFullRestart(delayMs: Long, reason: String) {
        restartFuture?.cancel(false)
        retryPending = true
        val s = stream ?: return
        if (s.isStreaming) {
            expectedDisconnects++
            s.stopStream()
        }
        streamStatus = "reconnecting"
        emitState()
        EngineEvents.log("warning", "$reason: nuovo tentativo tra ${delayMs} ms")
        restartFuture = executor.schedule({
            restartFuture = null
            val current = stream
            if (desiredStreaming && current != null && !current.isStreaming) {
                try {
                    connectToActiveEndpoint(current)
                } catch (e: Exception) {
                    recordError("start_failed", e.message ?: "Avvio fallito")
                    scheduleFullRestart(policy.nextDelayMs(), "Avvio fallito")
                }
            }
        }, delayMs, TimeUnit.MILLISECONDS)
    }

    /**
     * Guarantees progress while the operator wants to be live: if no connection
     * is established within CONNECTING_TIMEOUT_MS (e.g. a retry got lost), a
     * clean restart of the transport is scheduled.
     */
    private fun startSupervisor() {
        supervisorFuture?.cancel(false)
        supervisorFuture = executor.scheduleWithFixedDelay({
            if (!desiredStreaming) return@scheduleWithFixedDelay
            val waiting = streamStatus == "connecting" || streamStatus == "reconnecting"
            val elapsed = SystemClock.elapsedRealtime() - connectingSince
            if (waiting && restartFuture == null && elapsed > CONNECTING_TIMEOUT_MS) {
                recordError("connect_timeout", "Nessuna connessione dopo ${elapsed / 1000} s")
                scheduleFullRestart(policy.nextDelayMs(), "Connessione non riuscita")
            }
        }, SUPERVISOR_MS, SUPERVISOR_MS, TimeUnit.MILLISECONDS)
    }

    private fun onNetworkChanged(previous: Network?, current: Network?) {
        val id = current?.hashCode()
        val changed = lastNetworkId != null && id != lastNetworkId
        lastNetworkId = id
        EngineEvents.emit("network", networkMonitor.info.toMap())
        if (current == null) {
            if (desiredStreaming) {
                recordError("network_lost", "Rete persa: in attesa di una nuova connessione")
                streamStatus = "reconnecting"
                emitState()
            }
            return
        }
        if (desiredStreaming && (changed || previous == null)) {
            EngineEvents.log("warning", "Rete cambiata (${networkMonitor.info.type}): riconnessione immediata")
            policy.reset()
            scheduleFullRestart(300, "Cambio rete")
        }
    }

    // ConnectChecker (called by RootEncoder on the main thread) ---------------

    override fun onConnectionStarted(url: String) {
        executor.execute {
            retryPending = false
            connectingSince = SystemClock.elapsedRealtime()
        }
    }

    override fun onConnectionSuccess() {
        executor.execute {
            if (!desiredStreaming) return@execute
            if (connectedOnce) reconnects++
            connectedOnce = true
            consecutiveFailures = 0
            retryPending = false
            zeroBytesSeconds = 0
            policy.reset()
            connectedAt = System.currentTimeMillis()
            streamStatus = "live"
            stream?.getStreamClient()?.setReTries(Int.MAX_VALUE)
            bitrateAdapter?.reset()
            stream?.requestKeyframe()
            EngineEvents.log("info", "LIVE via ${activeEndpoint?.protocol?.uppercase()}${if (fallbackActive) " (fallback)" else ""}")
            emitState()
        }
    }

    override fun onConnectionFailed(reason: String) {
        executor.execute { handleFailure(reason) }
    }

    override fun onDisconnect() {
        executor.execute {
            if (expectedDisconnects > 0) {
                expectedDisconnects--
                return@execute
            }
            if (desiredStreaming) handleFailure("Disconnesso")
        }
    }

    override fun onAuthError() {
        executor.execute { handleFailure("Autenticazione rifiutata dal server") }
    }

    override fun onAuthSuccess() {}

    override fun onStreamingStats(report: StreamingStatsReport) {
        executor.execute { handleStats(report) }
    }

    private fun handleFailure(reason: String) {
        if (!desiredStreaming) return
        // A retry is already scheduled: duplicated callbacks of the same failure are ignored.
        if (retryPending) return
        val s = stream ?: return
        consecutiveFailures++
        recordError(if (connectedOnce) "stream_disconnected" else "connect_failed", reason)
        val req = request
        val endpoint = activeEndpoint
        if (req != null && endpoint?.protocol == "srt" && !connectedOnce && req.autoFallback && req.fallback != null &&
            consecutiveFailures >= SRT_FAILURES_BEFORE_FALLBACK
        ) {
            EngineEvents.log("warning", "SRT non raggiungibile dopo $consecutiveFailures tentativi: passo a RTMPS (fallback)")
            activeEndpoint = req.fallback
            fallbackActive = true
            consecutiveFailures = 0
            policy.reset()
            scheduleFullRestart(500, "Fallback RTMPS")
            return
        }
        val delay = policy.nextDelayMs()
        streamStatus = "reconnecting"
        emitState()
        retryPending = true
        val retried = try {
            s.getStreamClient().reTry(delay, reason)
        } catch (_: Exception) {
            false
        }
        if (retried) {
            EngineEvents.log("warning", "Riconnessione tra ${delay} ms (tentativo ${policy.attempts}): $reason")
        } else {
            scheduleFullRestart(delay, reason)
        }
    }

    private fun handleStats(report: StreamingStatsReport) {
        if (!desiredStreaming) return
        bitrateAdapter?.onStreamingStats(report)
        if (streamStatus == "live") {
            zeroBytesSeconds = if (report.bytesOutPerSecond <= 0) zeroBytesSeconds + 1 else 0
            if (zeroBytesSeconds >= STALL_SECONDS) {
                zeroBytesSeconds = 0
                recordError("stream_stalled", "Nessun dato inviato da $STALL_SECONDS s")
                scheduleFullRestart(500, "Flusso bloccato")
                return
            }
        }
        EngineEvents.emit(
            "stats",
            mapOf(
                "bitrateKbps" to report.smoothedBitrate / 1000.0,
                "uploadKbps" to report.bytesOutPerSecond * 8 / 1000.0,
                "queuePercent" to report.queueCongestionPercent.toDouble(),
                "throughput" to report.throughput.name.lowercase(),
                "fps" to fps,
                "targetVideoKbps" to currentVideoKbps,
            ),
        )
    }

    // ---------------------------------------------------------------------
    // Pause / video / audio
    // ---------------------------------------------------------------------

    fun pause(callback: (Result<Unit>) -> Unit) = submit(callback) {
        if (!desiredStreaming) throw EngineException("not_streaming", "Nessuna trasmissione attiva")
        paused = true
        applyMute()
        EngineEvents.log("info", "PAUSA: video nero e audio muto, sessione SRT mantenuta")
        emitState()
    }

    fun resume(callback: (Result<Unit>) -> Unit) = submit(callback) {
        paused = false
        applyMute()
        stream?.requestKeyframe()
        EngineEvents.log("info", "Ripresa della trasmissione")
        emitState()
    }

    fun setVideoEnabled(enabled: Boolean, callback: (Result<Unit>) -> Unit) = submit(callback) {
        userVideoEnabled = enabled
        applyMute()
        emitState()
    }

    fun setAudioEnabled(enabled: Boolean, callback: (Result<Unit>) -> Unit) = submit(callback) {
        if (enabled && !micAvailable) {
            throw EngineException("microphone_unavailable", "Microfono non disponibile (permesso negato)")
        }
        userAudioEnabled = enabled
        applyMute()
        emitState()
    }

    /** Video/audio are muted in the encoders, the SRT/RTMPS session stays open. */
    private fun applyMute() {
        val s = stream ?: return
        val gl = s.getGlInterface()
        if (userVideoEnabled && !paused) gl.unMuteVideo() else gl.muteVideo()
        microphone?.let { if (userAudioEnabled && !paused) it.unMute() else it.mute() }
    }

    // ---------------------------------------------------------------------
    // Camera controls
    // ---------------------------------------------------------------------

    fun switchCamera(target: String, callback: (Result<Map<String, Any?>>) -> Unit) = submit(callback) {
        val cam = requireCamera()
        if (target != "front" && target != "back") throw EngineException("invalid_argument", "Camera sconosciuta")
        if (target == facing) return@submit mapOf("facing" to facing)
        val targetCaps = caps[target] ?: throw EngineException("unsupported", "Camera ${if (target == "front") "frontale" else "posteriore"} non presente")
        if (!targetCaps.resolutions.contains(settings.resolutionLabel)) {
            throw EngineException("unsupported", "La camera ${if (target == "front") "frontale" else "posteriore"} non supporta ${settings.resolutionLabel}")
        }
        if (targetCaps.fps[settings.resolutionLabel]?.contains(settings.fps) != true) {
            throw EngineException("unsupported", "La camera richiesta non supporta ${settings.fps} fps a ${settings.resolutionLabel}")
        }
        cam.switchCamera()
        facing = if (cam.getCameraFacing() == CameraHelper.Facing.FRONT) "front" else "back"
        torch = false
        zoom = 1f
        exposure = 0
        refreshCameraControls()
        emitCapabilities()
        emitState()
        mapOf("facing" to facing)
    }

    fun setZoom(level: Double, callback: (Result<Map<String, Any?>>) -> Unit) = submit(callback) {
        val cam = requireCamera()
        val c = caps[facing] ?: throw EngineException("unsupported", "Zoom non supportato")
        if (c.zoomMax <= c.zoomMin + 0.01f) throw EngineException("unsupported", "Zoom non supportato")
        if (!cam.isRunning()) throw EngineException("camera_off", "La camera non è attiva")
        val value = level.toFloat().coerceIn(c.zoomMin, c.zoomMax)
        cam.setZoom(value)
        zoom = cam.getZoom()
        emitState()
        mapOf("zoom" to zoom.toDouble())
    }

    fun zoomBy(step: Double, callback: (Result<Map<String, Any?>>) -> Unit) {
        executor.execute {
            val target = zoom + step
            setZoom(target, callback)
        }
    }

    fun setTorch(enabled: Boolean, callback: (Result<Map<String, Any?>>) -> Unit) = submit(callback) {
        val cam = requireCamera()
        if (enabled) {
            if (caps[facing]?.torch != true) throw EngineException("unsupported", "Torcia non disponibile su questa camera")
            if (!cam.isRunning()) throw EngineException("camera_off", "La camera non è attiva")
            try {
                cam.enableLantern()
            } catch (e: Exception) {
                throw EngineException("torch_failed", "Torcia non attivabile: ${e.message}")
            }
        } else {
            cam.disableLantern()
        }
        torch = cam.isLanternEnabled()
        emitState()
        mapOf("torch" to torch)
    }

    fun setAutoFocus(enabled: Boolean, callback: (Result<Map<String, Any?>>) -> Unit) = submit(callback) {
        val cam = requireCamera()
        if (caps[facing]?.autofocus != true) throw EngineException("unsupported", "Autofocus non supportato")
        if (!cam.isRunning()) throw EngineException("camera_off", "La camera non è attiva")
        val ok = if (enabled) cam.enableAutoFocus() else cam.disableAutoFocus()
        if (!ok && enabled) throw EngineException("autofocus_failed", "Autofocus non attivato")
        autofocus = cam.isAutoFocusEnabled()
        emitState()
        mapOf("autofocus" to autofocus)
    }

    /**
     * Focus on a point of the transmitted frame (x, y in 0..1). The point is
     * converted to sensor coordinates and applied with RootEncoder's
     * tap-to-focus (AF regions + AF trigger).
     */
    fun focusAt(x: Double, y: Double, callback: (Result<Map<String, Any?>>) -> Unit) = submit(callback) {
        val cam = requireCamera()
        val c = caps[facing] ?: throw EngineException("unsupported", "Focus point non supportato")
        if (!c.focusPoint) throw EngineException("unsupported", "Focus point non supportato da questa camera")
        if (!cam.isRunning()) throw EngineException("camera_off", "La camera non è attiva")
        val rotation = FocusMapper.sensorToFrameRotation(c.sensorOrientation, displayRotationDegrees, facing == "front")
        val point = FocusMapper.frameToSensor(x.toFloat(), y.toFloat(), rotation, mirrored = false)
        // RootEncoder maps event coordinates proportionally to the view size onto the sensor array.
        val view = focusView ?: throw EngineException("not_initialized", "Focus non pronto")
        val size = FOCUS_VIEW_SIZE
        val now = SystemClock.uptimeMillis()
        val event = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, point.x * size, point.y * size, 0)
        val ok = try {
            cam.tapToFocus(view, event)
        } finally {
            event.recycle()
        }
        if (!ok) throw EngineException("focus_failed", "Messa a fuoco non riuscita")
        autofocus = true
        emitState()
        mapOf("x" to x, "y" to y)
    }

    fun setExposure(index: Int, callback: (Result<Map<String, Any?>>) -> Unit) = submit(callback) {
        val cam = requireCamera()
        val c = caps[facing] ?: throw EngineException("unsupported", "Esposizione non supportata")
        if (c.exposureMax <= c.exposureMin) throw EngineException("unsupported", "Esposizione non regolabile")
        if (!cam.isRunning()) throw EngineException("camera_off", "La camera non è attiva")
        cam.setExposure(index.coerceIn(c.exposureMin, c.exposureMax))
        exposure = cam.getExposure()
        emitState()
        mapOf("exposure" to exposure, "ev" to exposure * c.exposureStep)
    }

    private fun refreshCameraControls() {
        val cam = camera ?: return
        if (!cam.isRunning()) return
        zoom = cam.getZoom().takeIf { it > 0f } ?: 1f
        torch = cam.isLanternEnabled()
        autofocus = cam.isAutoFocusEnabled()
        if (!autofocus && caps[facing]?.autofocus == true) {
            autofocus = cam.enableAutoFocus()
        }
        exposure = cam.getExposure()
    }

    // ---------------------------------------------------------------------
    // Settings (resolution, fps, bitrate)
    // ---------------------------------------------------------------------

    fun applySettings(requested: VideoSettings, callback: (Result<Map<String, Any?>>) -> Unit) = submit(callback) {
        val s = requireStream()
        val next = sanitizeSettings(requested)
        val needsPrepare = next.width != settings.width || next.height != settings.height || next.fps != settings.fps ||
            next.portrait != settings.portrait || next.keyframeIntervalSec != settings.keyframeIntervalSec ||
            next.audioBitrateKbps != settings.audioBitrateKbps
        val onlyBitrate = !needsPrepare
        if (onlyBitrate) {
            settings = next
            applyBitrateMode()
            emitState()
            return@submit mapOf("restarted" to false)
        }
        val wasStreaming = desiredStreaming
        val wasRecording = s.isRecording
        val surface = previewSurface
        if (wasRecording) stopRecordingInternal()
        if (s.isStreaming) {
            expectedDisconnects++
            s.stopStream()
        }
        restartFuture?.cancel(false)
        restartFuture = null
        if (s.isOnPreview) s.stopPreview()
        settings = next
        prepareEncoders()
        if (surface != null && surface.isValid) {
            s.startPreview(surface, previewWidth, previewHeight)
        }
        if (wasStreaming) {
            connectedOnce = false
            connectToActiveEndpoint(s)
        }
        if (wasRecording) startRecordingInternal()
        applyMute()
        refreshCameraControls()
        EngineEvents.log("info", "Formato applicato: ${settings.resolutionLabel} ${settings.fps} fps ${settings.videoBitrateKbps} kbps")
        emitCapabilities()
        emitState()
        mapOf("restarted" to wasStreaming)
    }

    fun setBitrate(mode: String, kbps: Int?, callback: (Result<Map<String, Any?>>) -> Unit) = submit(callback) {
        if (mode != "auto" && mode != "manual") throw EngineException("invalid_argument", "Modalità bitrate non valida")
        val value = (kbps ?: settings.videoBitrateKbps).coerceIn(300, maxBitrateKbps())
        settings = settings.copy(bitrateMode = mode, videoBitrateKbps = value)
        applyBitrateMode()
        emitState()
        mapOf("mode" to mode, "kbps" to value)
    }

    fun applyPreset(name: String, callback: (Result<Map<String, Any?>>) -> Unit) {
        val preset = PRESETS[name]
        if (preset == null) {
            main.post { callback(Result.failure(EngineException("invalid_argument", "Preset sconosciuto"))) }
            return
        }
        executor.execute {
            val (resolution, wantedFps, kbps) = preset
            val facingCaps = caps[facing]
            val supportedFps = facingCaps?.fps?.get(resolution) ?: emptyList()
            // Standard/High prefer 30 fps, fall back to 25 when 30 is not available.
            val fpsValue = when {
                supportedFps.contains(wantedFps) -> wantedFps
                supportedFps.contains(25) -> 25
                supportedFps.isNotEmpty() -> supportedFps.first()
                else -> wantedFps
            }
            val (w, h) = if (resolution == "720p") 1280 to 720 else 1920 to 1080
            applySettings(settings.copy(width = w, height = h, fps = fpsValue, videoBitrateKbps = kbps), callback)
        }
    }

    private fun applyBitrateMode() {
        val s = stream ?: return
        if (settings.bitrateMode == "manual") {
            bitrateAdapter = null
            applyVideoBitrate(settings.videoBitrateKbps)
        } else if (desiredStreaming && bitrateAdapter == null) {
            val total = (settings.videoBitrateKbps + settings.audioBitrateKbps) * 1000
            bitrateAdapter = QueueAwareBitrateAdapter(total, total / 5) { bitrate ->
                executor.execute { applyVideoBitrate((bitrate / 1000) - settings.audioBitrateKbps) }
            }
            applyVideoBitrate(settings.videoBitrateKbps)
        } else {
            applyVideoBitrate(settings.videoBitrateKbps)
        }
        if (s.isStreaming) s.requestKeyframe()
    }

    private fun applyVideoBitrate(kbps: Int) {
        val value = kbps.coerceIn(300, maxBitrateKbps())
        currentVideoKbps = value
        stream?.setVideoBitrateOnFly(value * 1000)
    }

    private fun maxBitrateKbps(): Int = minOf(20_000, CapabilityProbe.maxEncoderBitrateKbps())

    /** Only values supported by the hardware are applied (never forced). */
    private fun sanitizeSettings(requested: VideoSettings): VideoSettings {
        val facingCaps = caps[facing] ?: return requested
        var result = requested
        if (!facingCaps.resolutions.contains(result.resolutionLabel)) {
            val fallback = facingCaps.resolutions.lastOrNull() ?: throw EngineException("unsupported", "Nessuna risoluzione supportata")
            EngineEvents.log("warning", "${result.resolutionLabel} non supportata: uso $fallback")
            result = if (fallback == "720p") result.copy(width = 1280, height = 720) else result.copy(width = 1920, height = 1080)
        }
        val fpsList = facingCaps.fps[result.resolutionLabel] ?: emptyList()
        if (!fpsList.contains(result.fps)) {
            val fallbackFps = fpsList.filter { it <= result.fps }.maxOrNull() ?: fpsList.firstOrNull() ?: 30
            EngineEvents.log("warning", "${result.fps} fps non supportati a ${result.resolutionLabel}: uso $fallbackFps")
            result = result.copy(fps = fallbackFps)
        }
        return result.copy(videoBitrateKbps = result.videoBitrateKbps.coerceIn(300, maxBitrateKbps()))
    }

    private fun prepareEncoders() {
        val s = requireStream()
        val rotation = if (settings.portrait) 90 else 0
        val videoOk = try {
            s.prepareVideo(
                settings.width,
                settings.height,
                settings.videoBitrateKbps * 1000,
                settings.fps,
                settings.keyframeIntervalSec,
                rotation,
            )
        } catch (e: IllegalArgumentException) {
            throw EngineException("unsupported", "Configurazione video non supportata: ${e.message}")
        }
        if (!videoOk) throw EngineException("encoder_failure", "Encoder H.264 non inizializzato")
        currentVideoKbps = settings.videoBitrateKbps
        val audioBitrate = settings.audioBitrateKbps * 1000
        val audioOk = listOf(SAMPLE_RATE to true, FALLBACK_SAMPLE_RATE to true, FALLBACK_SAMPLE_RATE to false).any { (rate, stereo) ->
            try {
                s.prepareAudio(rate, stereo, audioBitrate)
            } catch (_: IllegalArgumentException) {
                false
            }
        }
        if (!audioOk) throw EngineException("encoder_failure", "Encoder AAC non inizializzato")
    }

    // ---------------------------------------------------------------------
    // Local MP4 backup recording
    // ---------------------------------------------------------------------

    fun recordingDirectory(): File? = context.getExternalFilesDir(Environment.DIRECTORY_MOVIES)?.let { File(it, "PeopleCare") }

    fun setRecording(enabled: Boolean, cameraLabel: String?, callback: (Result<Map<String, Any?>>) -> Unit) = submit(callback) {
        if (enabled) {
            val file = startRecordingInternal(cameraLabel)
            mapOf("recording" to true, "file" to file.name, "freeBytes" to deviceMonitor.freeBytes(recordingDirectory()))
        } else {
            val file = stopRecordingInternal()
            mapOf("recording" to false, "file" to file?.name)
        }
    }

    private var recordingLabel: String? = null

    private fun startRecordingInternal(cameraLabel: String? = recordingLabel): File {
        val s = requireStream()
        if (s.isRecording) return recordingFile ?: throw EngineException("invalid_state", "Registrazione già attiva")
        val dir = recordingDirectory() ?: throw EngineException("storage_unavailable", "Memoria non disponibile")
        if (!dir.exists() && !dir.mkdirs()) throw EngineException("storage_unavailable", "Cartella registrazioni non creata")
        val free = deviceMonitor.freeBytes(dir) ?: 0L
        if (free < MIN_FREE_BYTES_FOR_RECORDING) {
            throw EngineException("storage_low", "Spazio insufficiente: ${free / 1_000_000} MB liberi (minimo 1000 MB)")
        }
        recordingLabel = cameraLabel
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val prefix = (cameraLabel ?: "CAM").replace(Regex("[^A-Za-z0-9]+"), "_").trim('_').ifEmpty { "CAM" }
        val file = File(dir, "${prefix}_$stamp.mp4")
        s.startRecord(file.absolutePath, listener = recordListener)
        recordingFile = file
        recording = true
        applyManualOrientationIfHidden()
        EngineEvents.log("info", "Registrazione backup avviata: ${file.name}")
        emitState()
        return file
    }

    private fun stopRecordingInternal(): File? {
        val s = stream ?: return null
        val file = recordingFile
        if (s.isRecording) s.stopRecord()
        recording = false
        recordingFile = null
        emitState()
        if (file != null) {
            EngineEvents.log("info", "Registrazione salvata: ${file.name}")
            executor.execute { exportToGallery(file) }
        }
        return file
    }

    private val recordListener = object : RecordController.Listener {
        override fun onStatusChange(status: RecordController.Status) {
            executor.execute {
                if (status == RecordController.Status.STOPPED && recording) {
                    recording = false
                    emitState()
                }
            }
        }

        override fun onError(e: Exception?) {
            executor.execute {
                recordError("recording_error", "Errore registrazione: ${e?.message ?: "sconosciuto"}")
                recording = false
                emitState()
            }
        }
    }

    /** Copies the finished MP4 in Movies/PeopleCare (MediaStore, Android 10+, no permission). */
    private fun exportToGallery(file: File) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !file.exists() || file.length() == 0L) return
        try {
            val resolver = context.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, file.name)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/PeopleCare")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values) ?: return
            resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out, 1 shl 20) } }
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            file.delete()
            EngineEvents.log("info", "Registrazione esportata in Movies/PeopleCare/${file.name}")
        } catch (e: Exception) {
            EngineEvents.log("warning", "Registrazione conservata nella memoria dell'app (${file.name}): ${e.message}")
        }
    }

    // ---------------------------------------------------------------------
    // Errors from camera and encoders
    // ---------------------------------------------------------------------

    private val cameraCallbacks = object : CameraCallbacks {
        override fun onCameraChanged(facing: CameraHelper.Facing) {
            executor.execute {
                this@CameraEngine.facing = if (facing == CameraHelper.Facing.FRONT) "front" else "back"
                emitState()
            }
        }

        override fun onCameraError(error: String) {
            executor.execute {
                cameraStatus = "error"
                recordError("camera_error", error)
                emitState()
                executor.schedule({ reopenCamera() }, 2, TimeUnit.SECONDS)
            }
        }

        override fun onCameraOpened() {
            executor.execute {
                if (cameraStatus != "ready") {
                    cameraStatus = "ready"
                    emitState()
                }
            }
        }

        override fun onCameraDisconnected() {
            executor.execute {
                cameraStatus = "error"
                recordError("camera_disconnected", "Fotocamera occupata da un'altra app o disconnessa")
                emitState()
                executor.schedule({ reopenCamera() }, 3, TimeUnit.SECONDS)
            }
        }
    }

    private fun reopenCamera() {
        val cam = camera ?: return
        val s = stream ?: return
        if (!(s.isStreaming || s.isRecording || s.isOnPreview)) {
            // Nothing needs the camera now: it will be opened on the next start.
            cameraStatus = "ready"
            emitState()
            return
        }
        if (cam.restart()) {
            EngineEvents.log("info", "Riapertura della fotocamera")
        } else {
            recordError("camera_unavailable", "Impossibile riaprire la fotocamera")
        }
    }

    private val codecErrorCallback = object : CodecErrorCallback {
        override fun onCodecError(type: CodecUtil.CodecTypeError, e: MediaCodec.CodecException) {
            executor.execute {
                recordError("encoder_failure", "Errore encoder ${type.name}: ${e.diagnosticInfo}")
                val s = stream ?: return@execute
                val reset = if (type.name.contains("AUDIO", ignoreCase = true)) s.resetAudioEncoder() else s.resetVideoEncoder()
                if (!reset && desiredStreaming) scheduleFullRestart(1000, "Encoder in errore")
            }
        }
    }

    private fun recordError(code: String, message: String) {
        val error = EngineError(code, message)
        lastError = error
        recentErrors.addLast(error)
        while (recentErrors.size > 10) recentErrors.removeFirst()
        EngineEvents.log(if (code.startsWith("camera") || code.contains("fail")) "error" else "warning", message, code)
    }

    // ---------------------------------------------------------------------
    // Orientation while the UI is hidden
    // ---------------------------------------------------------------------

    /**
     * When the GL renderer (re)starts while the activity is hidden, RootEncoder
     * cannot read the UI orientation: apply the last visible one, using the
     * same mapping as RootEncoder's SensorRotationManager.
     */
    private fun applyManualOrientationIfHidden() {
        if (activityVisible) return
        val gl = stream?.getGlInterface() ?: return
        val cameraOrientation = when (displayRotationDegrees) {
            0 -> 90
            90 -> 0
            180 -> 270
            270 -> 180
            else -> 0
        }
        val ui = if (cameraOrientation == 0) 270 else cameraOrientation - 90
        gl.setCameraOrientation(ui)
        gl.setIsPortrait(ui == 0 || ui == 180)
    }

    // ---------------------------------------------------------------------
    // State and telemetry
    // ---------------------------------------------------------------------

    fun getState(callback: (Result<Map<String, Any?>>) -> Unit) = submit(callback) {
        mapOf("capabilities" to capabilitiesMap(), "state" to stateMap(), "device" to deviceMap())
    }

    private fun scheduleDeviceReports() {
        deviceFuture?.cancel(false)
        deviceFuture = executor.scheduleWithFixedDelay({
            try {
                EngineEvents.emit("device", deviceMap())
            } catch (_: Exception) {
            }
        }, 0, DEVICE_REPORT_MS, TimeUnit.MILLISECONDS)
    }

    private fun deviceMap(): Map<String, Any?> =
        deviceMonitor.snapshot(recordingDirectory()) + mapOf("network" to networkMonitor.info.toMap())

    private fun capabilitiesMap(): Map<String, Any?> {
        val facings = caps.mapValues { it.value.toMap() }
        val resolutions = caps[facing]?.resolutions ?: emptyList()
        return mapOf(
            "facings" to facings,
            "resolutions" to resolutions,
            "recording" to (recordingDirectory() != null),
            "protocols" to listOf("srt", "rtmps"),
            "maxBitrateKbps" to maxBitrateKbps(),
            "microphone" to micAvailable,
        )
    }

    private fun emitCapabilities() {
        EngineEvents.emit("capabilities", capabilitiesMap())
    }

    private fun stateMap(): Map<String, Any?> {
        val s = stream
        val now = System.currentTimeMillis()
        val encoderWidth = if (settings.portrait) settings.height else settings.width
        val encoderHeight = if (settings.portrait) settings.width else settings.height
        return mapOf(
            "cameraStatus" to cameraStatus,
            "streamStatus" to streamStatus,
            "paused" to paused,
            "facing" to facing,
            "zoom" to zoom.toDouble(),
            "torch" to torch,
            "autofocus" to autofocus,
            "exposure" to exposure,
            "videoEnabled" to userVideoEnabled,
            "audioEnabled" to (userAudioEnabled && micAvailable),
            "microphoneAvailable" to micAvailable,
            "recording" to (recording && s?.isRecording == true),
            "recordingFile" to recordingFile?.name,
            "resolution" to settings.resolutionLabel,
            "width" to encoderWidth,
            "height" to encoderHeight,
            "fps" to settings.fps,
            "bitrateMode" to settings.bitrateMode,
            "targetBitrateKbps" to settings.videoBitrateKbps,
            "currentVideoKbps" to currentVideoKbps,
            "audioBitrateKbps" to settings.audioBitrateKbps,
            "protocol" to protocolLabel(),
            "testEndpoint" to (activeEndpoint?.protocol == "raw"),
            "fallbackActive" to fallbackActive,
            "orientation" to if (settings.portrait) "portrait" else "landscape",
            "preview" to (s?.isOnPreview == true),
            "reconnects" to reconnects,
            "reconnectAttempt" to policy.attempts,
            "sessionStartedAt" to sessionStartedAt.takeIf { it > 0 },
            "connectedAt" to connectedAt.takeIf { it > 0 },
            "uptimeSec" to if (sessionStartedAt > 0 && connectedOnce) (now - sessionStartedAt) / 1000 else 0,
            "lastError" to lastError?.toMap(),
            "recentErrors" to recentErrors.map { it.toMap() },
        )
    }

    private fun protocolLabel(): String {
        val endpoint = activeEndpoint ?: request?.primary ?: return "srt"
        return if (endpoint.protocol == "raw") {
            if (endpoint.url.trim().lowercase().startsWith("srt")) "srt" else "rtmps"
        } else {
            endpoint.protocol
        }
    }

    private fun emitState() {
        val state = stateMap()
        EngineEvents.emit("state", state)
        val listener = stateListener ?: return
        main.post { listener(state) }
    }
}
