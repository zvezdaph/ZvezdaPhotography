package tv.peoplecare.remotecamera

import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.util.Size

/**
 * Reads the real capabilities of the phone (Camera2 characteristics and
 * MediaCodec H.264 encoder limits). Only what is reported here is enabled in
 * the app and in the Control Room.
 */
class CapabilityProbe(private val context: Context) {

    data class FacingCaps(
        val cameraId: String,
        val sensorOrientation: Int,
        val zoomMin: Float,
        val zoomMax: Float,
        val torch: Boolean,
        val autofocus: Boolean,
        val focusPoint: Boolean,
        val exposureMin: Int,
        val exposureMax: Int,
        val exposureStep: Double,
        val fps: Map<String, List<Int>>,
        val resolutions: List<String>,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "available" to true,
            "zoom" to mapOf("supported" to (zoomMax > zoomMin + 0.01f), "min" to zoomMin.toDouble(), "max" to zoomMax.toDouble()),
            "torch" to torch,
            "autofocus" to autofocus,
            "focusPoint" to focusPoint,
            "exposure" to mapOf(
                "supported" to (exposureMax > exposureMin),
                "min" to exposureMin,
                "max" to exposureMax,
                "step" to exposureStep,
            ),
            "fps" to fps,
        )
    }

    private val manager = context.getSystemService(CameraManager::class.java)

    fun probe(): Map<String, FacingCaps> {
        val result = HashMap<String, FacingCaps>()
        val cameraManager = manager ?: return result
        val ids = try {
            cameraManager.cameraIdList
        } catch (e: Exception) {
            EngineEvents.log("error", "Impossibile elencare le camere: ${e.message}", "camera_unavailable")
            return result
        }
        for (id in ids) {
            val ch = try {
                cameraManager.getCameraCharacteristics(id)
            } catch (_: Exception) {
                continue
            }
            val facing = when (ch.get(CameraCharacteristics.LENS_FACING)) {
                CameraMetadata.LENS_FACING_FRONT -> "front"
                CameraMetadata.LENS_FACING_BACK -> "back"
                else -> null
            } ?: continue
            // RootEncoder opens the first camera id of each facing: probe the same one.
            if (result.containsKey(facing)) continue
            result[facing] = probeCamera(id, ch)
        }
        return result
    }

    private fun probeCamera(id: String, ch: CameraCharacteristics): FacingCaps {
        val level = ch.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL) ?: CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY
        var zoomMin = 1f
        var zoomMax = ch.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && level != CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY) {
            ch.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)?.let {
                zoomMin = it.lower
                zoomMax = it.upper
            }
        }
        val afModes = ch.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)?.toList() ?: emptyList()
        val autofocus = afModes.contains(CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO) ||
            afModes.contains(CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_PICTURE) ||
            afModes.contains(CameraMetadata.CONTROL_AF_MODE_AUTO)
        val maxAfRegions = ch.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AF) ?: 0
        val aeRange = ch.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
        val aeStep = ch.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_STEP)
        val map = ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val outputSizes = map?.getOutputSizes(SurfaceTexture::class.java)?.toList() ?: emptyList()
        val fpsRanges = ch.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)?.toList() ?: emptyList()

        val resolutions = mutableListOf<String>()
        val fps = LinkedHashMap<String, List<Int>>()
        for ((label, size) in listOf("720p" to Size(1280, 720), "1080p" to Size(1920, 1080))) {
            if (!cameraSupportsSize(level, outputSizes, size)) continue
            // Maximum frame rate the sensor sustains at this size.
            val minFrameNanos = try {
                map?.getOutputMinFrameDuration(SurfaceTexture::class.java, pickSize(outputSizes, size)) ?: 0L
            } catch (_: Exception) {
                0L
            }
            val sensorMaxFps = if (minFrameNanos > 0) (1e9 / minFrameNanos).toInt() else 30
            val cameraMax = fpsRanges.filter { it.upper <= sensorMaxFps }.maxOfOrNull { it.upper } ?: 30
            val supported = listOf(25, 30, 50, 60).filter { f ->
                f <= cameraMax && encoderSupports(size.width, size.height, f)
            }
            if (supported.isNotEmpty()) {
                resolutions.add(label)
                fps[label] = supported
            }
        }
        return FacingCaps(
            cameraId = id,
            sensorOrientation = ch.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90,
            zoomMin = zoomMin,
            zoomMax = zoomMax,
            torch = ch.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true,
            autofocus = autofocus,
            focusPoint = maxAfRegions > 0 && afModes.contains(CameraMetadata.CONTROL_AF_MODE_AUTO),
            exposureMin = aeRange?.lower ?: 0,
            exposureMax = aeRange?.upper ?: 0,
            exposureStep = aeStep?.toDouble() ?: 0.0,
            fps = fps,
            resolutions = resolutions,
        )
    }

    /** Same rule RootEncoder applies when initializing Camera2Source. */
    private fun cameraSupportsSize(level: Int, sizes: List<Size>, size: Size): Boolean {
        if (sizes.isEmpty()) return false
        return if (level == CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY) {
            sizes.contains(size)
        } else {
            val maxW = sizes.maxOf { it.width }
            val maxH = sizes.maxOf { it.height }
            size.width <= maxW && size.height <= maxH
        }
    }

    private fun pickSize(sizes: List<Size>, wanted: Size): Size =
        sizes.firstOrNull { it == wanted }
            ?: sizes.filter { it.width >= wanted.width && it.height >= wanted.height }.minByOrNull { it.width * it.height }
            ?: wanted

    companion object {
        private var encoderCache: List<MediaCodecInfo.VideoCapabilities>? = null

        private fun avcEncoders(): List<MediaCodecInfo.VideoCapabilities> {
            encoderCache?.let { return it }
            val list = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .filter { it.isEncoder && it.supportedTypes.any { t -> t.equals(MediaFormat.MIMETYPE_VIDEO_AVC, ignoreCase = true) } }
                .mapNotNull { info ->
                    try {
                        info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).videoCapabilities
                    } catch (_: Exception) {
                        null
                    }
                }
            encoderCache = list
            return list
        }

        /** True when at least one H.264 encoder supports size and frame rate. */
        fun encoderSupports(width: Int, height: Int, fps: Int): Boolean =
            avcEncoders().any { caps ->
                try {
                    caps.areSizeAndRateSupported(width, height, fps.toDouble()) ||
                        caps.areSizeAndRateSupported(height, width, fps.toDouble())
                } catch (_: Exception) {
                    false
                }
            }

        fun maxEncoderBitrateKbps(): Int =
            (avcEncoders().maxOfOrNull { it.bitrateRange.upper } ?: 20_000_000) / 1000
    }
}
