package com.b1g.b1gtv

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.StringReader
import java.util.concurrent.Executors

/**
 * Settings › VPN: runs a WireGuard tunnel for the whole TV from a configuration the customer
 * brings (from their VPN provider, the website or a link). Uses the official WireGuard library.
 *
 * Android asks the customer once to allow the VPN ("connection request"); after that the app can
 * switch it on and off by itself.
 */
class VpnHelper(private val activity: Activity) {

    companion object {
        const val PERMISSION_REQUEST = 4731
    }

    private val backend by lazy { GoBackend(activity.applicationContext) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: (() -> Unit)? = null
    private var pendingResult: MethodChannel.Result? = null

    private val tunnel = object : Tunnel {
        override fun getName(): String = "cloudplayer"
        override fun onStateChange(newState: Tunnel.State) {}
    }

    /** Checks a configuration without starting it. Returns "" when fine, else the reason. */
    fun check(text: String): String = try {
        Config.parse(BufferedReader(StringReader(text)))
        ""
    } catch (e: Exception) {
        e.message ?: "This is not a WireGuard configuration."
    }

    fun state(): String = try {
        if (backend.getState(tunnel) == Tunnel.State.UP) "up" else "down"
    } catch (e: Exception) {
        "down"
    }

    fun up(text: String, result: MethodChannel.Result) {
        val config = try {
            Config.parse(BufferedReader(StringReader(text)))
        } catch (e: Exception) {
            result.success(mapOf("ok" to false, "error" to (e.message ?: "This is not a WireGuard configuration.")))
            return
        }
        val start = {
            worker.execute {
                val r: Map<String, Any?> = try {
                    backend.setState(tunnel, Tunnel.State.UP, config)
                    mapOf("ok" to true)
                } catch (e: Exception) {
                    mapOf("ok" to false, "error" to (e.message ?: e.javaClass.simpleName))
                }
                main.post { result.success(r) }
            }
        }
        // First time: Android shows its own "allow VPN connection" question.
        val ask: Intent? = try { android.net.VpnService.prepare(activity) } catch (e: Exception) { null }
        if (ask != null) {
            pending = start
            pendingResult = result
            @Suppress("DEPRECATION")
            activity.startActivityForResult(ask, PERMISSION_REQUEST)
        } else {
            start()
        }
    }

    /** Called from MainActivity.onActivityResult for the VPN question. */
    fun onPermission(granted: Boolean) {
        val go = pending
        val r = pendingResult
        pending = null
        pendingResult = null
        if (granted && go != null) {
            go()
        } else {
            r?.success(mapOf("ok" to false, "error" to "The VPN was not allowed on this TV."))
        }
    }

    fun down(result: MethodChannel.Result) {
        worker.execute {
            val r: Map<String, Any?> = try {
                backend.setState(tunnel, Tunnel.State.DOWN, null)
                mapOf("ok" to true)
            } catch (e: Exception) {
                mapOf("ok" to false, "error" to (e.message ?: e.javaClass.simpleName))
            }
            main.post { result.success(r) }
        }
    }
}
