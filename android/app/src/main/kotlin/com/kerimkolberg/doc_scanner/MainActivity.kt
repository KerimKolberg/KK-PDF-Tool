package com.kerimkolberg.doc_scanner

import android.content.ContentValues
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
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
import java.util.concurrent.Executors

/**
 * Small native features that don't need a third-party Flutter plugin:
 *
 *  - Saves exported PDFs/images into the public Downloads/KK-PDF-Tool folder
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

    // File copies and image decoding run here, never on the UI thread.
    private val io = Executors.newSingleThreadExecutor()

    // The file the app was opened with is still being copied: Flutter's
    // "getInitialSharedFile" call is answered once the copy has finished.
    private var initialCopyRunning = false
    private var initialFileRequest: MethodChannel.Result? = null

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
                io.execute { recognizeText(bytes, result) }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannelName)
            .setMethodCallHandler { call, result ->
                val fileName = call.argument<String>("fileName")?.let(::safeFileName)
                when (call.method) {
                    "saveToDownloads" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (fileName == null || bytes == null) {
                            result.error("bad_args", "fileName and bytes are required", null)
                            return@setMethodCallHandler
                        }
                        runInBackground(result, "save_failed") { saveToDownloads(fileName, bytes) }
                    }
                    // Streams a (possibly very large) file, e.g. a library
                    // backup, instead of passing its bytes through the channel.
                    "saveFileToDownloads" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val mimeType = call.argument<String>("mimeType")
                        if (fileName == null || sourcePath == null) {
                            result.error("bad_args", "fileName and sourcePath are required", null)
                            return@setMethodCallHandler
                        }
                        runInBackground(result, "save_failed") {
                            copyFileToDownloads(fileName, File(sourcePath), mimeType)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "$sharedFilesChannelName/methods")
            .setMethodCallHandler { call, result ->
                if (call.method == "getInitialSharedFile") {
                    if (initialCopyRunning) {
                        initialFileRequest = result
                    } else {
                        result.success(pendingSharedFile)
                        pendingSharedFile = null
                    }
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

        io.execute(::deleteOldIncomingFiles)
        handleIncomingIntent(intent, isInitial = true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingIntent(intent, isInitial = false)
    }

    /** Runs [work] on the IO thread and reports its value or error to Flutter. */
    private fun runInBackground(result: MethodChannel.Result, errorCode: String, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                runOnUiThread { result.error(errorCode, e.message, null) }
            }
        }
    }

    private fun handleIncomingIntent(intent: Intent?, isInitial: Boolean) {
        if (intent == null || intent.getBooleanExtra(EXTRA_HANDLED, false)) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
            else -> null
        }
        // Only content:// Uris: a file:// Uri could point another app's
        // request at this app's own private files.
        if (uri == null || uri.scheme != "content") return
        // Don't offer the same file again when the activity is recreated.
        intent.putExtra(EXTRA_HANDLED, true)

        if (isInitial) initialCopyRunning = true
        io.execute {
            val fileInfo = copyUriToCache(uri)
            runOnUiThread {
                if (!isInitial) {
                    if (fileInfo != null) eventSink?.success(fileInfo)
                    return@runOnUiThread
                }
                initialCopyRunning = false
                val request = initialFileRequest
                initialFileRequest = null
                if (request != null) request.success(fileInfo) else pendingSharedFile = fileInfo
            }
        }
    }

    override fun onDestroy() {
        textRecognizer?.close()
        textRecognizer = null
        io.shutdown()
        super.onDestroy()
    }

    /**
     * Runs on the IO thread; ML Kit calls the listeners on the UI thread.
     *
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
            runOnUiThread { result.error("decode_failed", "Could not read image", null) }
            return
        }

        val recognizer = synchronized(this) {
            textRecognizer
                ?: TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                    .also { textRecognizer = it }
        }
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
            .addOnCompleteListener { bitmap.recycle() }
    }

    /**
     * Copies a file another app handed over into the app's cache.
     *
     * The other app controls the display name, so it is reduced to a plain
     * file name first - a name like "../../files/x" must never let a
     * foreign app write outside the incoming folder.
     */
    private fun copyUriToCache(uri: Uri): Map<String, String?>? {
        return try {
            val resolver = applicationContext.contentResolver
            val mimeType = resolver.getType(uri)

            var displayName = "shared_file"
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0 && cursor.moveToFirst()) {
                    cursor.getString(nameIndex)?.let { displayName = it }
                }
            }
            displayName = safeFileName(displayName)

            // The tools recognise files by extension, so make sure there is one.
            if (!displayName.contains('.') && mimeType != null) {
                MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)?.let {
                    displayName = "$displayName.$it"
                }
            }

            // Each file gets its own folder, so it keeps its real name.
            val dir = File(incomingDir(), System.currentTimeMillis().toString())
            val outFile = File(dir, displayName)
            if (!outFile.canonicalPath.startsWith(incomingDir().canonicalPath + File.separator)) {
                return null
            }
            dir.mkdirs()
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

    private fun incomingDir() = File(cacheDir, "incoming")

    /** Removes copies of shared files that are more than a day old. */
    private fun deleteOldIncomingFiles() {
        try {
            val cutoff = System.currentTimeMillis() - 24L * 60 * 60 * 1000
            incomingDir().listFiles()?.forEach { if (it.lastModified() < cutoff) it.deleteRecursively() }
            // Copies made by older versions of the app.
            cacheDir.listFiles { file -> file.isFile && file.name.startsWith("shared_") }
                ?.forEach { if (it.lastModified() < cutoff) it.delete() }
        } catch (e: Exception) {
            // Cleaning up is best effort.
        }
    }

    /** A plain file name: no folders, no characters file systems reject. */
    private fun safeFileName(raw: String): String {
        val base = raw.substringAfterLast('/').substringAfterLast('\\')
        val cleaned = base.replace(Regex("[\\x00-\\x1F<>:\"|?*]"), "_").trim().trimStart('.')
        if (cleaned.isEmpty()) return "file"
        if (cleaned.length <= 120) return cleaned
        val extension = cleaned.substringAfterLast('.', "").take(10)
        return cleaned.take(100) + if (extension.isEmpty()) "" else ".$extension"
    }

    private fun copyFileToDownloads(fileName: String, source: File, mimeType: String?): String {
        val subFolder = "KK-PDF-Tool"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                if (mimeType != null) put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + subFolder)
            }
            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore refused to create the file")
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("Could not open the file")
            return "Downloads/$subFolder/$fileName"
        } else {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), subFolder)
            if (!dir.exists()) dir.mkdirs()
            val target = File(dir, fileName)
            source.copyTo(target, overwrite = true)
            return target.absolutePath
        }
    }

    private fun saveToDownloads(fileName: String, bytes: ByteArray): String {
        val subFolder = "KK-PDF-Tool"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + subFolder)
            }
            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore refused to create the file")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Could not open the file")
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

    private companion object {
        const val EXTRA_HANDLED = "com.kerimkolberg.doc_scanner.HANDLED"
    }
}
