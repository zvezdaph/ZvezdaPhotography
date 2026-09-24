package tv.peoplecare.remotecamera

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry

/**
 * Bridge between Dart and the native camera engine:
 *  - MethodChannel "tv.peoplecare.remotecamera/engine" for commands,
 *  - EventChannel "tv.peoplecare.remotecamera/events" for state/telemetry,
 *  - a Flutter texture (SurfaceProducer) for the preview rendered by the engine.
 */
class CameraBridgePlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        const val METHOD_CHANNEL = "tv.peoplecare.remotecamera/engine"
        const val EVENT_CHANNEL = "tv.peoplecare.remotecamera/events"
        private const val PERMISSION_REQUEST = 4271
    }

    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var textures: TextureRegistry
    private var activityBinding: ActivityPluginBinding? = null
    private var producer: TextureRegistry.SurfaceProducer? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    private val engine: CameraEngine get() = EngineHolder.get(context)
    private val activity: Activity? get() = activityBinding?.activity

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) {}
        override fun onDisplayRemoved(displayId: Int) {}
        override fun onDisplayChanged(displayId: Int) {
            val a = activity as? MainActivity ?: return
            engine.setActivityVisible(true, a.displayRotationDegrees())
        }
    }

    // ------------------------------------------------------------------ FlutterPlugin

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textures = binding.textureRegistry
        methods = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methods.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        EngineEvents.attach(null)
        producer?.release()
        producer = null
    }

    // ------------------------------------------------------------------ ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        context.getSystemService(DisplayManager::class.java)?.registerDisplayListener(displayListener, main)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        context.getSystemService(DisplayManager::class.java)?.unregisterDisplayListener(displayListener)
    }

    // ------------------------------------------------------------------ EventChannel

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        EngineEvents.attach(sink)
    }

    override fun onCancel(arguments: Any?) {
        EngineEvents.attach(null)
    }

    // ------------------------------------------------------------------ Methods

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            dispatch(call, result)
        } catch (e: EngineException) {
            result.error(e.code, e.message, null)
        } catch (e: Exception) {
            result.error("bridge_error", e.message ?: e.javaClass.simpleName, null)
        }
    }

    private fun <T> reply(result: MethodChannel.Result): (Result<T>) -> Unit = { outcome ->
        outcome.fold(
            onSuccess = { value -> result.success(if (value is Unit) null else value) },
            onFailure = { error ->
                val code = (error as? EngineException)?.code ?: "engine_error"
                result.error(code, error.message ?: code, null)
            },
        )
    }

    private fun MethodCall.bool(name: String): Boolean =
        argument<Boolean>(name) ?: throw EngineException("invalid_argument", "Argomento mancante: $name")

    private fun MethodCall.double(name: String): Double =
        (argument<Any>(name) as? Number)?.toDouble() ?: throw EngineException("invalid_argument", "Argomento mancante: $name")

    private fun dispatch(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deviceInfo" -> result.success(deviceInfo())
            "permissionStatus" -> result.success(permissionStatus())
            "requestPermissions" -> requestPermissions(result)
            "openAppSettings" -> {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                result.success(null)
            }
            "initialize" -> {
                if (!granted(Manifest.permission.CAMERA)) throw EngineException("camera_permission", "Permesso fotocamera negato")
                // Arm the foreground service while the app is visible: camera and
                // microphone stay usable when the phone is locked or the app is in background.
                if (activity != null) StreamingService.arm(context)
                engine.initialize(VideoSettings.fromMap(call.argument("settings")), reply(result))
            }
            "attachPreview" -> attachPreview(call, result)
            "detachPreview" -> {
                producer?.let { p ->
                    engine.detachPreview { }
                    p.release()
                }
                producer = null
                result.success(null)
            }
            "startStream" -> {
                val primary = Endpoint.fromMap(call.argument("primary")) ?: throw EngineException("invalid_endpoint", "Endpoint mancante")
                val request = StreamRequest(
                    primary = primary,
                    fallback = Endpoint.fromMap(call.argument("fallback")),
                    autoFallback = call.argument<Boolean>("autoFallback") ?: true,
                    srtLatencyMs = (call.argument<Any>("srtLatencyMs") as? Number)?.toInt() ?: 500,
                )
                engine.startStream(request, reply(result))
            }
            "stopStream" -> engine.stopStream(reply(result))
            "pause" -> engine.pause(reply(result))
            "resume" -> engine.resume(reply(result))
            "reconnect" -> engine.reconnect(reply(result))
            "restartStream" -> engine.restartStream(reply(result))
            "setVideoEnabled" -> engine.setVideoEnabled(call.bool("enabled"), reply(result))
            "setAudioEnabled" -> engine.setAudioEnabled(call.bool("enabled"), reply(result))
            "switchCamera" -> engine.switchCamera(call.argument<String>("facing") ?: "back", reply(result))
            "setZoom" -> engine.setZoom(call.double("zoom"), reply(result))
            "zoomBy" -> engine.zoomBy(call.double("step"), reply(result))
            "setTorch" -> engine.setTorch(call.bool("enabled"), reply(result))
            "setAutoFocus" -> engine.setAutoFocus(call.bool("enabled"), reply(result))
            "focusAt" -> engine.focusAt(call.double("x"), call.double("y"), reply(result))
            "setExposure" -> engine.setExposure(call.double("index").toInt(), reply(result))
            "applySettings" -> engine.applySettings(VideoSettings.fromMap(call.argument("settings")), reply(result))
            "setBitrate" -> engine.setBitrate(
                call.argument<String>("mode") ?: "auto",
                (call.argument<Any>("kbps") as? Number)?.toInt(),
                reply(result),
            )
            "applyPreset" -> engine.applyPreset(call.argument<String>("preset") ?: "standard", reply(result))
            "setRecording" -> engine.setRecording(call.bool("enabled"), call.argument<String>("label"), reply(result))
            "getState" -> engine.getState(reply(result))
            "setKeepScreenOn" -> {
                val enabled = call.bool("enabled")
                activity?.window?.let { w ->
                    if (enabled) w.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else w.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(activity != null)
            }
            "setScreenBrightness" -> {
                // -1 restores the system brightness; 0.01..1 overrides it for this window only.
                val value = call.double("value").toFloat()
                activity?.window?.let { w ->
                    val params = w.attributes
                    params.screenBrightness = if (value < 0f) WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE else value.coerceIn(0.01f, 1f)
                    w.attributes = params
                }
                result.success(activity != null)
            }
            "setOrientationLock" -> {
                val portrait = call.argument<String>("orientation") == "portrait"
                activity?.requestedOrientation =
                    if (portrait) ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT else ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                result.success(activity != null)
            }
            "shutdown" -> {
                producer?.release()
                producer = null
                engine.shutdown { outcome ->
                    StreamingService.disarm(context)
                    reply<Unit>(result)(outcome)
                }
            }
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------------ Preview texture

    private fun attachPreview(call: MethodCall, result: MethodChannel.Result) {
        val width = (call.argument<Any>("width") as? Number)?.toInt() ?: 1920
        val height = (call.argument<Any>("height") as? Number)?.toInt() ?: 1080
        val p = producer ?: textures.createSurfaceProducer(TextureRegistry.SurfaceLifecycle.resetInBackground).also { created ->
            producer = created
            created.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceAvailable() {
                    val current = producer ?: return
                    engine.attachPreview(current.surface, current.width, current.height) { }
                }

                override fun onSurfaceCleanup() {
                    // The surface is destroyed right after this call: stop drawing into it synchronously.
                    engine.detachPreviewBlocking(1500)
                }
            })
        }
        p.setSize(width, height)
        engine.attachPreview(p.surface, width, height) { outcome ->
            outcome.fold(
                onSuccess = { result.success(mapOf("textureId" to p.id(), "width" to width, "height" to height)) },
                onFailure = { error -> result.error((error as? EngineException)?.code ?: "preview_error", error.message, null) },
            )
        }
    }

    // ------------------------------------------------------------------ Permissions

    private fun granted(permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun permissionStatus(): Map<String, Any?> = mapOf(
        "camera" to granted(Manifest.permission.CAMERA),
        "microphone" to granted(Manifest.permission.RECORD_AUDIO),
        "notifications" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || granted(Manifest.permission.POST_NOTIFICATIONS)),
    )

    private fun requestPermissions(result: MethodChannel.Result) {
        val a = activity
        if (a == null) {
            result.success(permissionStatus())
            return
        }
        val wanted = mutableListOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) wanted.add(Manifest.permission.POST_NOTIFICATIONS)
        val missing = wanted.filter { !granted(it) }
        if (missing.isEmpty()) {
            result.success(permissionStatus())
            return
        }
        pendingPermissionResult?.success(permissionStatus())
        pendingPermissionResult = result
        a.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        pendingPermissionResult?.success(permissionStatus())
        pendingPermissionResult = null
        return true
    }

    private fun deviceInfo(): Map<String, Any?> {
        val packageInfo = try {
            context.packageManager.getPackageInfo(context.packageName, 0)
        } catch (_: Exception) {
            null
        }
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "androidVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "appVersion" to (packageInfo?.versionName ?: "?"),
            "debug" to BuildConfig.DEBUG,
            "recordingDir" to EngineHolder.get(context).recordingDirectory()?.absolutePath,
        )
    }
}
