package com.kerimkolberg.doc_scanner

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Saves exported PDFs/images into the public Downloads/DocScanner folder.
 * Implemented directly against the platform SDK (MediaStore on API 29+,
 * a plain file write on older versions) instead of a third-party plugin,
 * since MediaStore.Downloads needs no runtime permission at all.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "docscanner/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "saveToDownloads") {
                val fileName = call.argument<String>("fileName")
                val bytes = call.argument<ByteArray>("bytes")
                if (fileName == null || bytes == null) {
                    result.error("bad_args", "fileName and bytes are required", null)
                    return@setMethodCallHandler
                }
                try {
                    result.success(saveToDownloads(fileName, bytes))
                } catch (e: Exception) {
                    result.error("save_failed", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun saveToDownloads(fileName: String, bytes: ByteArray): String {
        val subFolder = "DocScanner"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + subFolder)
            }
            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore lehnte das Erstellen der Datei ab")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Konnte Datei nicht öffnen")
            return "Downloads/$subFolder/$fileName"
        } else {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), subFolder)
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, fileName)
            FileOutputStream(file).use { it.write(bytes) }
            return file.absolutePath
        }
    }
}
