package tv.peoplecare.remotecamera

/** Video/audio encoder settings requested by the Dart side. */
data class VideoSettings(
    val width: Int,
    val height: Int,
    val fps: Int,
    val videoBitrateKbps: Int,
    val audioBitrateKbps: Int,
    val bitrateMode: String,
    val keyframeIntervalSec: Int,
    val portrait: Boolean,
) {
    val resolutionLabel: String get() = if (height >= 1080) "1080p" else "720p"

    companion object {
        val DEFAULT = VideoSettings(
            width = 1920,
            height = 1080,
            fps = 30,
            videoBitrateKbps = 5000,
            audioBitrateKbps = 128,
            bitrateMode = "auto",
            keyframeIntervalSec = 2,
            portrait = false,
        )

        fun fromMap(map: Map<*, *>?, fallback: VideoSettings = DEFAULT): VideoSettings {
            if (map == null) return fallback
            val resolution = map["resolution"] as? String
            val (w, h) = when (resolution) {
                "720p" -> 1280 to 720
                "1080p" -> 1920 to 1080
                else -> fallback.width to fallback.height
            }
            return VideoSettings(
                width = w,
                height = h,
                fps = (map["fps"] as? Number)?.toInt()?.takeIf { it in listOf(25, 30, 50, 60) } ?: fallback.fps,
                videoBitrateKbps = (map["videoBitrateKbps"] as? Number)?.toInt()?.coerceIn(300, 20_000) ?: fallback.videoBitrateKbps,
                audioBitrateKbps = (map["audioBitrateKbps"] as? Number)?.toInt()?.coerceIn(32, 320) ?: fallback.audioBitrateKbps,
                bitrateMode = (map["bitrateMode"] as? String)?.takeIf { it == "auto" || it == "manual" } ?: fallback.bitrateMode,
                keyframeIntervalSec = (map["keyframeIntervalSec"] as? Number)?.toInt()?.coerceIn(1, 8) ?: fallback.keyframeIntervalSec,
                portrait = (map["orientation"] as? String)?.let { it == "portrait" } ?: fallback.portrait,
            )
        }
    }
}

/** One ingest endpoint (SRT or RTMPS) of a Cloudflare live input. */
data class Endpoint(
    val protocol: String,
    val url: String,
    val streamId: String?,
    val passphrase: String?,
    val streamKey: String?,
) {
    companion object {
        fun fromMap(map: Map<*, *>?): Endpoint? {
            if (map == null) return null
            val protocol = map["protocol"] as? String ?: return null
            val url = map["url"] as? String ?: return null
            // "raw" = full URL typed by the operator in the diagnostics test mode.
            if (protocol != "srt" && protocol != "rtmps" && protocol != "raw") return null
            return Endpoint(
                protocol = protocol,
                url = url,
                streamId = map["streamId"] as? String,
                passphrase = map["passphrase"] as? String,
                streamKey = map["streamKey"] as? String,
            )
        }
    }
}

data class StreamRequest(
    val primary: Endpoint,
    val fallback: Endpoint?,
    val autoFallback: Boolean,
    val srtLatencyMs: Int,
)

data class EngineError(val code: String, val message: String, val ts: Long = System.currentTimeMillis()) {
    fun toMap(): Map<String, Any> = mapOf("code" to code, "message" to message, "ts" to ts)
}

/** Result of an engine operation, returned to Dart and used in the command ACK. */
class EngineException(val code: String, message: String) : Exception(message)
