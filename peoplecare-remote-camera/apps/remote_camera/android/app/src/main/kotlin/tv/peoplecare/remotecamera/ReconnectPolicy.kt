package tv.peoplecare.remotecamera

import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToLong

/**
 * Exponential backoff with jitter. Same parameters as the Dart control
 * client and the Control Room (1 s, x2, max 30 s, jitter 50%).
 */
class ReconnectPolicy(
    private val initialMs: Long = 1_000,
    private val maxMs: Long = 30_000,
    private val multiplier: Double = 2.0,
    private val jitter: Double = 0.5,
    private val random: () -> Double = { Math.random() },
) {
    var attempts: Int = 0
        private set

    fun nextDelayMs(): Long {
        val base = min(maxMs.toDouble(), initialMs * multiplier.pow(attempts.toDouble()))
        attempts++
        return (base - base * jitter * random()).roundToLong()
    }

    fun reset() {
        attempts = 0
    }
}
