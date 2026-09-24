package tv.peoplecare.remotecamera

import java.net.URI

/**
 * Builds the URL understood by RootEncoder from a Cloudflare endpoint.
 *
 * RootEncoder's SrtClient reads `streamid`, `passphrase` and `latency` from the
 * query string WITHOUT percent-decoding them, so values are appended raw and
 * validated to contain no URL separators.
 */
object EndpointUrls {
    private val SAFE_VALUE = Regex("^[A-Za-z0-9._~:!$'()*+,;=@/-]{1,512}$")

    fun build(endpoint: Endpoint, srtLatencyMs: Int): String = when (endpoint.protocol) {
        "srt" -> srt(endpoint, srtLatencyMs)
        "rtmps" -> rtmps(endpoint)
        "raw" -> raw(endpoint.url)
        else -> throw EngineException("invalid_endpoint", "Protocollo non supportato: ${endpoint.protocol}")
    }

    /** Test mode: a complete srt:// or rtmp(s):// URL typed by the operator. */
    private fun raw(url: String): String {
        val value = url.trim()
        val scheme = value.substringBefore("://").lowercase()
        if (scheme !in setOf("srt", "rtmp", "rtmps")) {
            throw EngineException("invalid_endpoint", "Endpoint di test: usa srt://, rtmp:// o rtmps://")
        }
        parse(value, scheme)
        return value
    }

    private fun srt(endpoint: Endpoint, latencyMs: Int): String {
        val base = endpoint.url.trim()
        val uri = parse(base, "srt")
        if (uri.port <= 0) throw EngineException("invalid_endpoint", "URL SRT senza porta")
        val streamId = endpoint.streamId?.trim().orEmpty()
        if (!SAFE_VALUE.matches(streamId)) throw EngineException("invalid_endpoint", "Stream ID SRT non valido")
        val passphrase = endpoint.passphrase?.trim().orEmpty()
        if (passphrase.isNotEmpty()) {
            // SRT (and RootEncoder) accept passphrases of 10..79 characters.
            if (passphrase.length !in 10..79 || !SAFE_VALUE.matches(passphrase)) {
                throw EngineException("invalid_endpoint", "Passphrase SRT non valida")
            }
        }
        val params = buildList {
            add("streamid=$streamId")
            if (passphrase.isNotEmpty()) add("passphrase=$passphrase")
            add("latency=${latencyMs.coerceIn(80, 8000)}")
        }
        val separator = if (base.contains('?')) "&" else "?"
        return base + separator + params.joinToString("&")
    }

    private fun rtmps(endpoint: Endpoint): String {
        val base = endpoint.url.trim()
        parse(base, "rtmps")
        val key = endpoint.streamKey?.trim().orEmpty()
        if (!SAFE_VALUE.matches(key)) throw EngineException("invalid_endpoint", "Stream key RTMPS non valida")
        return (if (base.endsWith("/")) base else "$base/") + key
    }

    private fun parse(value: String, scheme: String): URI {
        val uri = try {
            URI(value.substringBefore('?'))
        } catch (e: Exception) {
            throw EngineException("invalid_endpoint", "URL non valido")
        }
        if (!uri.scheme.equals(scheme, ignoreCase = true) || uri.host.isNullOrBlank()) {
            throw EngineException("invalid_endpoint", "URL $scheme non valido")
        }
        return uri
    }

    /** Version of the URL safe for logs: secrets replaced. */
    fun redact(url: String): String = url
        .replace(Regex("(passphrase=)[^&]*"), "$1***")
        .replace(Regex("(streamid=)[^&]*"), "$1***")
        .replace(Regex("(rtmps?://[^/]+/[^/]+/).+"), "$1***")
}
