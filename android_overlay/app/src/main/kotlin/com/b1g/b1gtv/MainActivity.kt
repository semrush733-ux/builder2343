package com.b1g.b1gtv

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.core.content.FileProvider
import java.io.File
import java.net.NetworkInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The app draws its own focus highlight; Android's outline around the whole screen is not wanted.
        hideSystemFocusOutline(window.decorView)
    }

    private fun hideSystemFocusOutline(view: View) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            view.defaultFocusHighlightEnabled = false
        }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                hideSystemFocusOutline(view.getChildAt(i))
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun appVersion(): Map<String, Any> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode.toInt() else info.versionCode
        return mapOf("code" to code, "name" to (info.versionName ?: ""))
    }

    /**
     * What the website uses to recognise this TV after a reinstall: Android's device ID and the
     * addresses of the wired and Wi-Fi network cards as far as this Android version shows them
     * (newer versions hide them; the app then sends the device ID alone).
     */
    private fun deviceIds(): Map<String, Any> {
        var hwid = ""
        try {
            hwid = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""
        } catch (e: Exception) {
        }
        val macs = ArrayList<String>()
        for (name in listOf("eth0", "wlan0")) {
            var mac: String? = null
            try {
                val bytes = NetworkInterface.getByName(name)?.hardwareAddress
                if (bytes != null && bytes.size == 6) {
                    mac = bytes.joinToString(":") { String.format("%02X", it.toInt() and 0xFF) }
                }
            } catch (e: Exception) {
            }
            if (mac == null) {
                try {
                    mac = File("/sys/class/net/$name/address").readText().trim().uppercase()
                } catch (e: Exception) {
                }
            }
            if (!mac.isNullOrEmpty()) macs.add(mac)
        }
        return mapOf("hwid" to hwid, "macs" to macs)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The player asks to keep the screen awake while a stream is open.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "b1g/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "keepScreenOn") {
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                } else if (call.method == "openUrl") {
                    // Opens a link (a YouTube trailer) in whatever app the device has for it.
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(call.arguments as String))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                } else if (call.method == "appVersion") {
                    try {
                        result.success(appVersion())
                    } catch (e: Exception) {
                        result.success(null)
                    }
                } else if (call.method == "deviceIds") {
                    result.success(deviceIds())
                } else if (call.method == "cacheDir") {
                    result.success(cacheDir.absolutePath)
                } else if (call.method == "canInstall") {
                    // From Android 8 the customer allows "install unknown apps" per app, once.
                    result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
                    )
                } else if (call.method == "installApk") {
                    // "Update now": hands the downloaded APK to Android's installer.
                    try {
                        val file = File(call.arguments as String)
                        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                        val intent = Intent(Intent.ACTION_VIEW)
                        intent.setDataAndType(uri, "application/vnd.android.package-archive")
                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
