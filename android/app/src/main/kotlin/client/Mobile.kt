package client

/**
 * JNI surface of the vendor tunnel core (libprotocolabs_mobile.so).
 *
 * The native exports are named Java_client_Mobile_<method>, so this class must keep
 * the package `client` and the name `Mobile`. Signatures below were recovered from
 * the vendor APK's classes.dex (Lclient/Mobile;) — every method takes/returns only
 * String, int or boolean, which is why this bridge is small.
 */
class Mobile private constructor() {

    companion object {
        @Volatile
        private var loaded = false

        @Synchronized
        fun ensureLoaded(): Boolean {
            if (loaded) return true
            return try {
                System.loadLibrary("protocolabs_mobile")
                loaded = true
                true
            } catch (t: Throwable) {
                false
            }
        }

        val instance: Mobile by lazy {
            ensureLoaded()
            Mobile()
        }
    }

    // lifecycle
    external fun startup(dir: String)
    external fun stop(): String
    external fun disconnect(): String
    external fun onSleep(): String
    external fun onWake(): String
    external fun onNetworkChange(): String

    // config
    external fun setAppDirectory(dir: String)
    external fun setApiServers(servers: String): String
    external fun setAccessToken(token: String): String
    external fun setTagAndMode(tag: String, mode: String): String
    external fun setSystemDnsServers(servers: String): String
    external fun setPhysicalInterface(name: String): String
    external fun setAllowIPv6(allow: Boolean): String
    external fun setFp(fp: String): String
    external fun setDebug(debug: Boolean)
    external fun setDirectDomains(domains: String): String
    external fun setDirectIPs(ips: String): String
    external fun setProxyDomains(domains: String): String
    external fun setProxyIPs(ips: String): String

    // data plane
    external fun connect(tunFd: Int): String
    external fun startHttpServer(): Int
    external fun restartHttpServer(): Int
    external fun getTunnelFileDescriptor(): Int
    external fun getTunnelNetworkSettings(): String

    // app data
    external fun getAppData(): String
    external fun getCachedAppData(): String
    external fun forceGetAppData(): String
    external fun getTagAndMode(): String
    external fun request(req: String, headers: String, body: String): String
    // diagnostics / extra surface recovered from the dex
    external fun getRequestHeaders(): String
    external fun probeServerLatency(tag: String): String
    external fun readCrashLog(): String
    external fun readMemorySummary(): String
    external fun listMemDumps(): String
    external fun dumpMemorySnapshot(): String
    external fun clearMemDumps()
    external fun enableMemDumpOnGrowth(limit: Int)
    external fun enableMemDumpPeriodic(seconds: Int)
    external fun setMemoryLimit(enable: Boolean)
    external fun setFcmToken(token: String): String

}
