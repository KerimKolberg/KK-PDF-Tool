package com.kerimkolberg.doc_scanner

import android.content.ContentValues
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Small native features that don't need a third-party Flutter plugin:
 *
 *  - Saves exported PDFs/images into the public Downloads/DocScanner folder
 *    via MediaStore (API 29+) or a plain file write (older versions), which
 *    needs no runtime permission at all.
 *  - Lets the app show up in "Open with" / the share sheet for PDFs and
 *    images (see the intent-filters in AndroidManifest.xml) by copying the
 *    incoming content:// Uri into the app's cache and handing the resulting
 *    file path to Flutter.
 *  - Offline text recognition (OCR) via the bundled ML Kit Latin model, so
 *    it works without internet or a Google account.
 */
class MainActivity : FlutterActivity() {
    private val downloadsChannelName = "docscanner/downloads"
    private val sharedFilesChannelName = "docscanner/shared_files"
    private val ocrChannelName = "docscanner/ocr"
    private var eventSink: EventChannel.EventSink? = null
    private var pendingSharedFile: Map<String, String?>? = null
    private var textRecognizer: TextRecognizer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ocrChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null) {
                    result.error("bad_args", "bytes is required", null)
                    return@setMethodCallHandler
                }
                recognizeText(bytes, result)
            }

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

    override fun onDestroy() {
        textRecognizer?.close()
        textRecognizer = null
        super.onDestroy()
    }

    /**
     * Returns the full text plus every recognised line with its bounding box
     * (in the pixel space of the decoded bitmap, whose size is returned too),
     * so Flutter can lay an invisible, selectable text layer over the page.
     * Very large photos are downsampled first to keep memory in check.
     */
    private fun recognizeText(bytes: ByteArray, result: MethodChannel.Result) {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 4096) {
            sample *= 2
        }
        val bitmap = BitmapFactory.decodeByteArray(
            bytes,
            0,
            bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sample },
        )
        if (bitmap == null) {
            result.error("decode_failed", "Bild konnte nicht gelesen werden", null)
            return
        }

        val recognizer = textRecognizer
            ?: TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                .also { textRecognizer = it }
        val width = bitmap.width
        val height = bitmap.height

        recognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { text ->
                val lines = ArrayList<Map<String, Any>>()
                for (block in text.textBlocks) {
                    for (line in block.lines) {
                        val box = line.boundingBox ?: continue
                        lines.add(
                            mapOf(
                                "text" to line.text,
                                "left" to box.left,
                                "top" to box.top,
                                "right" to box.right,
                                "bottom" to box.bottom,
                            ),
                        )
                    }
                }
                result.success(
                    mapOf(
                        "text" to text.text,
                        "width" to width,
                        "height" to height,
                        "lines" to lines,
                    ),
                )
            }
            .addOnFailureListener { e ->
                result.error("ocr_failed", e.message, null)
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
