package com.pcitrue.pcitrue

import android.app.ActivityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "pcitrue/gl"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getGlEsVersion") {
                result.success(detectGlEsVersion())
            } else {
                result.notImplemented()
            }
        }
    }

    /**
     * Detect the highest supported OpenGL ES version.
     * Returns a string like "2.0", "3.0", "3.2". Defaults to "2.0" if unknown.
     */
    private fun detectGlEsVersion(): String {
        return try {
            val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            val info = am.deviceConfigurationInfo
            // reqGlEsVersion is encoded as 0x00030002 for 3.2 etc.
            val v = info.reqGlEsVersion
            val major = (v shr 16) and 0xFFFF
            val minor = v and 0xFFFF
            "$major.$minor"
        } catch (e: Exception) {
            // Fallback: assume GLES 2.0 (Android 5.0 devices ship with at least 2.0).
            "2.0"
        }
    }
}
