package com.pcitrue.pcitrue

import android.Manifest
import android.app.ActivityManager
import android.content.ContentValues
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val GL_CHANNEL = "pcitrue/gl"
    private val FILE_CHANNEL = "pcitrue/file"

    private var pendingLegacyResult: MethodChannel.Result? = null

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
                    if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
                        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                            == PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(true)
                        } else {
                            pendingLegacyResult = result
                            requestPermissions(
                                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                                1001
                            )
                        }
                    } else {
                        result.success(true)
                    }
                }
                "saveBytesToPictures" -> {
                    val filename = call.argument<String>("filename")
                    val mime = call.argument<String>("mime")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (filename == null || mime == null || bytes == null) {
                        result.error("BAD_ARGS", "missing filename/mime/bytes", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val rel = saveToPublicPictures(filename, mime, bytes)
                        result.success(rel)
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingLegacyResult?.success(granted)
            pendingLegacyResult = null
        }
    }

    private fun detectGlEsVersion(): String {
        return try {
            val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            val info = am.deviceConfigurationInfo
            val v = info.reqGlEsVersion
            val major = (v shr 16) and 0xFFFF
            val minor = v and 0xFFFF
            "$major.$minor"
        } catch (e: Exception) {
            "2.0"
        }
    }

    /**
     * Save [bytes] into the PUBLIC Pictures/Pcitrue folder so a normal file
     * manager can see it. Returns the relative display path.
     */
    private fun saveToPublicPictures(filename: String, mime: String, bytes: ByteArray): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(filename, mime, bytes)
        } else {
            saveViaLegacy(filename, bytes)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveViaMediaStore(filename: String, mime: String, bytes: ByteArray): String {
        val resolver = contentResolver
        // Images (png/jpg) go to the Images collection; arbitrary .bin files go
        // through the Downloads collection, but both are placed under
        // Pictures/Pcitrue so they appear in the public Pictures folder.
        val collection = if (mime.startsWith("image/")) {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Downloads.EXTERNAL_CONTENT_URI
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/Pcitrue")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val uri: Uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore insert failed")
        resolver.openOutputStream(uri)?.use { out ->
            FileOutputStream(out.fd).use { it.write(bytes) }
        } ?: throw IllegalStateException("Cannot open output stream")

        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)

        return "Pictures/Pcitrue/$filename"
    }

    @Suppress("DEPRECATION")
    private fun saveViaLegacy(filename: String, bytes: ByteArray): String {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            "Pcitrue"
        )
        if (!dir.exists()) dir.mkdirs()
        val outFile = File(dir, filename)
        FileOutputStream(outFile).use { it.write(bytes) }
        return "Pictures/Pcitrue/$filename"
    }
}
