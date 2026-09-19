package com.kerimkolberg.doc_scanner

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Two small native features that don't need a third-party plugin:
 *
 *  - Saves exported PDFs/images into the public Downloads/DocScanner folder
 *    via MediaStore (API 29+) or a plain file write (older versions), which
 *    needs no runtime permission at all.
 *  - Lets the app show up in "Open with" / the share sheet for PDFs and
 *    images (see the intent-filters in AndroidManifest.xml) by copying the
 *    incoming content:// Uri into the app's cache and handing the resulting
 *    file path to Flutter.
 */
class MainActivity : FlutterActivity() {
    private val downloadsChannelName = "docscanner/downloads"
    private val sharedFilesChannelName = "docscanner/shared_files"
    private var eventSink: EventChannel.EventSink? = null
    private var pendingSharedFile: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannelName)
            .setMethodCallHandler { call, result ->
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "$sharedFilesChannelName/methods")
            .setMethodCallHandler { call, result ->
                if (call.method == "getInitialSharedFile") {
                    result.success(pendingSharedFile)
                    pendingSharedFile = null
                } else {
                    result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "$sharedFilesChannelName/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        handleIncomingIntent(intent, isInitial = true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingIntent(intent, isInitial = false)
    }

    private fun handleIncomingIntent(intent: Intent?, isInitial: Boolean) {
        val uri: Uri? = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri == null) return

        val fileInfo = copyUriToCache(uri) ?: return
        if (isInitial) {
            pendingSharedFile = fileInfo
        } else {
            eventSink?.success(fileInfo)
        }
    }

    private fun copyUriToCache(uri: Uri): Map<String, String?>? {
        val resolver = applicationContext.contentResolver
        val mimeType = resolver.getType(uri)

        var displayName = "geteilte_datei"
        resolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                cursor.getString(nameIndex)?.let { displayName = it }
            }
        }

        val outFile = File(cacheDir, "shared_${System.currentTimeMillis()}_$displayName")
        return try {
            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output -> input.copyTo(output) }
            } ?: return null
            mapOf(
                "path" to outFile.absolutePath,
                "name" to displayName,
                "mimeType" to mimeType,
            )
        } catch (e: Exception) {
            null
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
