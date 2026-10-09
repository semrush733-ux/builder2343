package com.b1g.b1gtv

import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
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
                } else {
                    result.notImplemented()
                }
            }
    }
}
