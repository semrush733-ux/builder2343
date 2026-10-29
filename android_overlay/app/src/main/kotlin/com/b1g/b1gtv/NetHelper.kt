package com.b1g.b1gtv

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * Settings › Network: what the TV is connected to, the Wi-Fi networks around it, and joining one.
 *
 * Android 9 and older let an app join a Wi-Fi network for the whole TV, so that happens right here.
 * From Android 10 only the system may do that: the app then opens the TV's Wi-Fi page.
 * Network names and the scan list need the location permission (an Android rule for Wi-Fi scans).
 */
class NetHelper(private val activity: Activity) {

    companion object {
        const val PERMISSION_REQUEST = 4721
    }

    private val wifi: WifiManager?
        get() = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager

    fun hasLocation(): Boolean =
        ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    fun requestLocation() {
        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), PERMISSION_REQUEST)
    }

    private fun clean(ssid: String?): String {
        val s = (ssid ?: "").trim().removePrefix("\"").removeSuffix("\"")
        return if (s == "<unknown ssid>") "" else s
    }

    private fun ipAddress(): String {
        try {
            for (nif in NetworkInterface.getNetworkInterfaces()) {
                if (!nif.isUp || nif.isLoopback) continue
                for (addr in nif.inetAddresses) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) return addr.hostAddress ?: ""
                }
            }
        } catch (_: Exception) {
        }
        return ""
    }

    @Suppress("DEPRECATION")
    fun info(): Map<String, Any?> {
        val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        var type = "none"
        if (cm != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val caps = cm.getNetworkCapabilities(cm.activeNetwork)
                if (caps != null) {
                    type = when {
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                        else -> "other"
                    }
                }
            } else {
                val ni = cm.activeNetworkInfo
                if (ni != null && ni.isConnected) {
                    type = when (ni.type) {
                        ConnectivityManager.TYPE_ETHERNET -> "ethernet"
                        ConnectivityManager.TYPE_WIFI -> "wifi"
                        else -> "other"
                    }
                }
            }
        }
        val out = HashMap<String, Any?>()
        out["type"] = type
        out["ip"] = ipAddress()
        out["canJoin"] = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
        out["location"] = hasLocation()
        val w = wifi
        if (w != null && type == "wifi") {
            val ci = w.connectionInfo
            if (ci != null) {
                out["ssid"] = clean(ci.ssid)
                out["rssi"] = ci.rssi
                out["level"] = WifiManager.calculateSignalLevel(ci.rssi, 5)
                out["linkMbps"] = ci.linkSpeed
                out["frequency"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) ci.frequency else 0
            }
        }
        out["wifiOn"] = w?.isWifiEnabled ?: false
        return out
    }

    @Suppress("DEPRECATION")
    fun scan(): Map<String, Any?> {
        if (!hasLocation()) return mapOf("permission" to false, "list" to emptyList<Any>())
        val w = wifi ?: return mapOf("permission" to true, "list" to emptyList<Any>())
        try {
            w.startScan()
        } catch (_: Exception) {
        }
        val best = HashMap<String, Map<String, Any?>>()
        for (r in w.scanResults ?: emptyList()) {
            val ssid = clean(r.SSID)
            if (ssid.isEmpty()) continue
            val caps = r.capabilities ?: ""
            val entry = mapOf(
                "ssid" to ssid,
                "rssi" to r.level,
                "level" to WifiManager.calculateSignalLevel(r.level, 5),
                "secured" to (caps.contains("WEP") || caps.contains("PSK") || caps.contains("EAP") || caps.contains("SAE")),
                "band" to (if (r.frequency > 4900) "5 GHz" else "2.4 GHz"),
            )
            val old = best[ssid]
            if (old == null || (old["rssi"] as Int) < r.level) best[ssid] = entry
        }
        val list = best.values.sortedByDescending { it["rssi"] as Int }
        return mapOf("permission" to true, "list" to list)
    }

    /** Joins a network (Android 9 and older). Returns "joining", "settings" (newer Android) or "failed". */
    @Suppress("DEPRECATION")
    fun join(ssid: String, password: String, secured: Boolean): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            openSettings()
            return "settings"
        }
        val w = wifi ?: return "failed"
        return try {
            if (!w.isWifiEnabled) w.isWifiEnabled = true
            val conf = WifiConfiguration()
            conf.SSID = "\"" + ssid + "\""
            if (secured) {
                conf.preSharedKey = "\"" + password + "\""
            } else {
                conf.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
            }
            var id = w.addNetwork(conf)
            if (id == -1) {
                // Already saved on the TV: use that entry.
                id = w.configuredNetworks?.firstOrNull { clean(it.SSID) == ssid }?.networkId ?: -1
            }
            if (id == -1) return "failed"
            w.disconnect()
            val ok = w.enableNetwork(id, true)
            w.reconnect()
            if (ok) "joining" else "failed"
        } catch (_: Exception) {
            "failed"
        }
    }

    fun openSettings() {
        try {
            val i = Intent(Settings.ACTION_WIFI_SETTINGS)
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(i)
        } catch (_: Exception) {
            try {
                val i = Intent(Settings.ACTION_SETTINGS)
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(i)
            } catch (_: Exception) {
            }
        }
    }
}
