package tv.peoplecare.remotecamera

import com.pedro.common.TimeUtils
import com.pedro.encoder.Frame
import com.pedro.encoder.input.audio.GetMicrophoneData
import com.pedro.encoder.input.sources.audio.AudioSource

/**
 * Audio source used when the microphone permission is denied or the
 * microphone cannot be opened: it produces real-time PCM silence so that the
 * stream still carries the AAC track required by Cloudflare Stream Live.
 * The UI clearly reports "microfono non disponibile".
 */
class SilenceAudioSource : AudioSource() {
    @Volatile
    private var running = false
    private var thread: Thread? = null

    override fun create(sampleRate: Int, isStereo: Boolean, echoCanceler: Boolean, noiseSuppressor: Boolean): Boolean = true

    override fun start(getMicrophoneData: GetMicrophoneData) {
        this.getMicrophoneData = getMicrophoneData
        if (running) return
        running = true
        val channels = if (isStereo) 2 else 1
        val samplesPerChunk = 1024
        val chunk = ByteArray(samplesPerChunk * channels * 2)
        val chunkNanos = samplesPerChunk * 1_000_000_000L / sampleRate.coerceAtLeast(8000)
        thread = Thread({
            var next = System.nanoTime()
            while (running) {
                this.getMicrophoneData?.inputPCMData(Frame(chunk.copyOf(), 0, chunk.size, TimeUtils.getCurrentTimeMicro()))
                next += chunkNanos
                val sleep = next - System.nanoTime()
                if (sleep > 0) {
                    try {
                        Thread.sleep(sleep / 1_000_000, (sleep % 1_000_000).toInt())
                    } catch (_: InterruptedException) {
                        break
                    }
                } else if (sleep < -chunkNanos * 10) {
                    next = System.nanoTime() // fell behind (device suspended): resync
                }
            }
        }, "PCRC-Silence").apply {
            isDaemon = true
            start()
        }
    }

    override fun stop() {
        running = false
        thread?.interrupt()
        thread = null
        getMicrophoneData = null
    }

    override fun isRunning(): Boolean = running

    override fun release() {
        stop()
    }
}
