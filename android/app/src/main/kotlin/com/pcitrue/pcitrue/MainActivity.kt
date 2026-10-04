package com.pcitrue.pcitrue

import android.app.ActivityManager
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val GL_CHANNEL = "pcitrue/gl"
    private val FILE_CHANNEL = "pcitrue/file"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GL_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getGlEsVersion") {
                result.success(detectGlEsVersion())
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureLegacyStoragePermission" -> {
                    result.success(true)
                }
                "saveBytesToPictures" -> {
                    try {
                        val filename = call.argument<String>("filename")!!
                        val bytes = call.argument<ByteArray>("bytes")!!
                        val mime = call.argument<String>("mime") ?: "image/png"
                        val savedPath = saveToPublicPcitrue(filename, bytes, mime)
                        result.success(savedPath)
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun detectGlEsVersion(): String {
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = am.deviceConfigurationInfo
            val v = info.reqGlEsVersion
            val major = (v shr 16) and 0xFFFF
            val minor = v and 0xFFFF
            "$major.$minor"
        } catch (e: Exception) {
            "2.0"
        }
    }

    private fun saveToPublicPcitrue(filename: String, bytes: ByteArray, mime: String): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Pcitrue")
            }
            val resolver = contentResolver
            val uri: Uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("Failed to create MediaStore entry")
            resolver.openOutputStream(uri).use { os ->
                os!!.write(bytes)
            }
            "Download/Pcitrue/$filename"
        } else {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Pcitrue")
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, filename)
            FileOutputStream(file).use { fos ->
                fos.write(bytes)
            }
            file.absolutePath
        }
    }
}
