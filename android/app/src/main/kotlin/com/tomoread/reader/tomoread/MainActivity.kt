package com.tomoread.reader.tomoread

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "dev.tomoread/import_inbox"
    private val wakeLockChannelName = "dev.tomoread/wake_lock"
    private val pendingIntents = mutableListOf<Intent>()
    private var importChannel: MethodChannel? = null
    private var dartReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        intent?.let { pendingIntents.add(Intent(it)) }
        importChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).apply {
            setMethodCallHandler { call, result ->
                if (call.method != "getInitialSources") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                dartReady = true
                val intents = pendingIntents.toList()
                pendingIntents.clear()
                processIntents(intents) { sources -> result.success(sources) }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            wakeLockChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "setEnabled") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val enabled = call.argument<Boolean>("enabled") == true
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
            result.success(true)
        }
    }

    override fun onDestroy() {
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (dartReady) {
            processIntents(listOf(Intent(intent))) { sources ->
                if (sources.isNotEmpty()) {
                    importChannel?.invokeMethod("incomingSources", sources)
                }
            }
        } else {
            pendingIntents.add(Intent(intent))
        }
    }

    private fun processIntents(
        intents: List<Intent>,
        callback: (List<Map<String, Any?>>) -> Unit,
    ) {
        Thread {
            cleanupExpiredIncomingFiles()
            val sources = intents.flatMap(::readIntent)
            runOnUiThread {
                if (!isDestroyed) callback(sources)
            }
        }.start()
    }

    private fun readIntent(intent: Intent?): List<Map<String, Any?>> {
        if (intent == null) return emptyList()
        val kind = when (intent.action) {
            Intent.ACTION_VIEW -> "androidView"
            Intent.ACTION_SEND -> "androidShare"
            else -> return emptyList()
        }
        val uris = linkedSetOf<Uri>()
        if (intent.action == Intent.ACTION_VIEW) {
            intent.data?.let(uris::add)
        } else {
            streamUri(intent)?.let(uris::add)
            intent.clipData?.let { clip ->
                for (index in 0 until clip.itemCount) {
                    clip.getItemAt(index).uri?.let(uris::add)
                }
            }
        }
        if (uris.isEmpty()) {
            return listOf(errorResult("系统没有提供可读取的分享文件。"))
        }
        return uris.map { uri -> copyIncomingUri(uri, intent.type, kind) }
    }

    @Suppress("DEPRECATION")
    private fun streamUri(intent: Intent): Uri? = if (Build.VERSION.SDK_INT >= 33) {
        intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
    } else {
        intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
    }

    private fun copyIncomingUri(
        uri: Uri,
        declaredMimeType: String?,
        kind: String,
    ): Map<String, Any?> {
        if (uri.scheme != "content") {
            return errorResult("仅接受由 Android 授权的 content URI。")
        }
        val displayName = queryDisplayName(uri)
            ?: uri.lastPathSegment?.substringAfterLast('/')
            ?: "shared-book"
        val extension = displayName.substringAfterLast('.', "").lowercase()
        val mimeType = contentResolver.getType(uri) ?: declaredMimeType
        if (!isSupported(extension, mimeType)) {
            return errorResult("分享文件的格式或 MIME 类型不受支持。")
        }
        var target: File? = null
        return try {
            val incomingDirectory = File(cacheDir, "incoming-books").canonicalFile
            incomingDirectory.mkdirs()
            val destination = File(
                incomingDirectory,
                "${UUID.randomUUID()}.$extension",
            ).canonicalFile
            target = destination
            if (destination.parentFile != incomingDirectory) {
                return errorResult("无法创建安全的临时导入文件。")
            }
            val input = contentResolver.openInputStream(uri)
                ?: return errorResult("无法读取分享文件。")
            input.use { source ->
                destination.outputStream().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var totalBytes = 0L
                    while (true) {
                        val read = source.read(buffer)
                        if (read < 0) break
                        totalBytes += read
                        if (totalBytes > MAX_INCOMING_BYTES) {
                            throw IncomingFileTooLargeException()
                        }
                        output.write(buffer, 0, read)
                    }
                }
            }
            mapOf(
                "kind" to kind,
                "path" to destination.absolutePath,
                "displayName" to displayName.take(240),
                "mimeType" to mimeType,
                "temporary" to true,
            )
        } catch (_: IncomingFileTooLargeException) {
            target?.delete()
            errorResult("分享文件超过 2 GB 限制。")
        } catch (_: Exception) {
            target?.delete()
            errorResult("复制分享文件失败，请确认来源应用仍授予读取权限。")
        }
    }

    private fun queryDisplayName(uri: Uri): String? = try {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index < 0) null else cursor.getString(index)
        }
    } catch (_: Exception) {
        null
    }

    private fun isSupported(extension: String, mimeType: String?): Boolean {
        val normalizedMime = mimeType?.substringBefore(';')?.trim()?.lowercase()
        return when (extension) {
            "epub" -> normalizedMime == "application/epub+zip"
            "pdf" -> normalizedMime == "application/pdf"
            "txt" -> normalizedMime == "text/plain"
            "md", "markdown" -> normalizedMime in setOf(
                "text/plain",
                "text/markdown",
                "text/x-markdown",
            )
            else -> false
        }
    }

    private fun cleanupExpiredIncomingFiles() {
        val directory = File(cacheDir, "incoming-books")
        val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        directory.listFiles()?.forEach { file ->
            if (file.isFile && file.lastModified() < cutoff) file.delete()
        }
    }

    private fun errorResult(message: String): Map<String, Any?> =
        mapOf("error" to message)

    private class IncomingFileTooLargeException : Exception()

    companion object {
        private const val MAX_INCOMING_BYTES = 2L * 1024 * 1024 * 1024
    }
}
