package com.follow.clash

import client.Mobile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge that boots the vendor Rust core (libprotocolabs_mobile.so) and hands FlClash
 * the port of its local HTTP proxy.
 *
 * Boot order mirrors what the vendor app does on Android:
 *   startup(appDir) -> setApiServers -> setAccessToken -> setSystemDnsServers
 *   -> setPhysicalInterface -> setTagAndMode -> startHttpServer()
 *
 * startHttpServer() returns the port directly (int), so no port sniffing is needed.
 * The core proxies independently of the VPN slot, which lets mihomo chain it as an
 * upstream HTTP proxy without fighting over the tun device.
 */
object EfanBridge {
    private const val CHANNEL = "efan/core"
    private var channel: MethodChannel? = null
    @Volatile
    private var port: Int = 0

    fun attach(messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(Mobile.ensureLoaded())
                "boot" -> {
                    try {
                        val appDir = call.argument<String>("appDir") ?: ""
                        val apiServers = call.argument<String>("apiServers") ?: ""
                        val token = call.argument<String>("token") ?: ""
                        val tag = call.argument<String>("tag") ?: ""
                        val mode = call.argument<String>("mode") ?: "rule"
                        result.success(boot(appDir, apiServers, token, tag, mode))
                    } catch (t: Throwable) {
                        result.error("boot_failed", t.message, null)
                    }
                }
                "stop" -> {
                    runCatching { Mobile.instance.stop() }
                    port = 0
                    result.success(true)
                }
                "port" -> result.success(port)
                "appData" -> result.success(runCatching { Mobile.instance.getCachedAppData() }.getOrNull())
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun boot(appDir: String, apiServers: String, token: String, tag: String, mode: String): Map<String, Any?> {
        val steps = linkedMapOf<String, Any?>()
        val m = Mobile.instance
        // 1) core must be initialised before any setter is accepted
        steps["startup"] = runCatching { m.startup(appDir); "ok" }.getOrElse { "err:$it" }
        steps["appDir"] = runCatching { m.setAppDirectory(appDir); "ok" }.getOrElse { "err:$it" }
        // 2) credentials
        steps["apiServersIn"] = apiServers
        if (apiServers.isNotEmpty()) {
            steps["apiServers"] = runCatching { m.setApiServers(apiServers).toString() }.getOrElse { "err:$it" }
        }
        if (token.isNotEmpty()) {
            steps["accessToken"] = runCatching { m.setAccessToken(token).toString() }.getOrElse { "err:$it" }
        }
        // 3) app data is fetched asynchronously: poll until it lands
        var data = ""
        for (i in 0 until 25) {
            data = runCatching { m.forceGetAppData() }.getOrElse { "" }
            if (data.length > 120 && !data.contains("fetching")) break
            Thread.sleep(1000)
        }
        for (path in listOf("/v1/app/data", "/v1/user/appdata", "/v1/user/app-data", "/v1/appdata", "/v1/subscribe")) {
            steps["req$path"] = runCatching { m.request(path, "", "").take(140) }.getOrElse { "err:$it" }
        }
        steps["getAppData"] = runCatching { m.getAppData().take(140) }.getOrElse { "err:$it" }
        steps["headers"] = runCatching { m.getRequestHeaders().take(160) }.getOrElse { "err:$it" }
        steps["appDataLen"] = data.length
        steps["appDataHead"] = data.take(200)
        // 4) pick a node and bring the local proxy up
        if (tag.isNotEmpty()) {
            steps["tagAndMode"] = runCatching { m.setTagAndMode(tag, mode).toString() }.getOrElse { "err:$it" }
        }
        steps["port"] = runCatching { m.startHttpServer() }.getOrElse { -1 }
        port = (steps["port"] as? Int) ?: 0
        return steps
    }
}
