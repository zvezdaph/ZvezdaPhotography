package tv.peoplecare.remotecamera

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities

/**
 * Observes the default network. A change of default network (Wi-Fi <-> 4G/5G)
 * invalidates the SRT session (UDP source address changes), so the engine
 * reconnects immediately instead of waiting for a timeout.
 */
class NetworkMonitor(context: Context, private val onChange: (previous: Network?, current: Network?) -> Unit) {
    data class Info(
        val type: String,
        val metered: Boolean,
        val validated: Boolean,
        val uplinkKbps: Int?,
        val downlinkKbps: Int?,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "type" to type,
            "metered" to metered,
            "validated" to validated,
            "uplinkKbps" to uplinkKbps,
            "downlinkKbps" to downlinkKbps,
        )
    }

    private val connectivity = context.getSystemService(ConnectivityManager::class.java)

    @Volatile
    var current: Network? = null
        private set

    @Volatile
    var info: Info = Info("none", metered = false, validated = false, uplinkKbps = null, downlinkKbps = null)
        private set

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            val previous = current
            current = network
            refresh(network, connectivity?.getNetworkCapabilities(network))
            if (previous != network) onChange(previous, network)
        }

        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            if (network == current) refresh(network, caps)
        }

        override fun onLost(network: Network) {
            if (network == current) {
                current = null
                info = Info("none", metered = false, validated = false, uplinkKbps = null, downlinkKbps = null)
                onChange(network, null)
            }
        }
    }

    private var registered = false

    fun start() {
        if (registered || connectivity == null) return
        try {
            connectivity.registerDefaultNetworkCallback(callback)
            registered = true
        } catch (e: RuntimeException) {
            EngineEvents.log("warning", "Monitoraggio rete non disponibile: ${e.message}", "network_monitor")
        }
    }

    fun stop() {
        if (!registered) return
        try {
            connectivity?.unregisterNetworkCallback(callback)
        } catch (_: RuntimeException) {
        }
        registered = false
    }

    private fun refresh(network: Network, caps: NetworkCapabilities?) {
        if (caps == null) return
        val type = when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "other"
        }
        info = Info(
            type = type,
            metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED),
            validated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
            // Estimates provided by the platform, 0 means unknown.
            uplinkKbps = caps.linkUpstreamBandwidthKbps.takeIf { it > 0 },
            downlinkKbps = caps.linkDownstreamBandwidthKbps.takeIf { it > 0 },
        )
        EngineEvents.emit("network", info.toMap() + ("networkId" to network.hashCode()))
    }
}
