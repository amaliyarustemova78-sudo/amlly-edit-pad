package com.amllystudio.amlly_edit_pad

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Flutter ile yerel Android medya katmanı arasındaki köprü ("amlly/media").
 * Dosya seçimi sistem belge seçicisiyle yapılır; dosyalar kopyalanmaz, kalıcı okuma izniyle bağlanır.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "amlly/media"
    private val pickRequestCode = 4101
    private var pendingPick: MethodChannel.Result? = null
    private val worker: ExecutorService = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var inspector: MediaInspector

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        inspector = MediaInspector(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "appDir" -> result.success(filesDir.absolutePath)
            "pickMedia" -> startPicker(call.argument<Boolean>("multiple") ?: true, result)
            "probe" -> {
                val uri = call.argument<String>("uri")
                if (uri == null) {
                    result.error("ARG", "uri eksik", null)
                    return
                }
                background(result) { inspector.probe(Uri.parse(uri)) }
            }
            "thumbnail" -> {
                val uri = call.argument<String>("uri")
                if (uri == null) {
                    result.error("ARG", "uri eksik", null)
                    return
                }
                val maxSize = call.argument<Number>("maxSize")?.toInt() ?: 480
                val atMs = call.argument<Number>("atMs")?.toLong() ?: 0L
                background(result) { inspector.thumbnail(Uri.parse(uri), atMs, maxSize) }
            }
            "isAccessible" -> {
                val uri = call.argument<String>("uri")
                if (uri == null) {
                    result.error("ARG", "uri eksik", null)
                    return
                }
                background(result) { inspector.isAccessible(Uri.parse(uri)) }
            }
            "release" -> {
                val uri = call.argument<String>("uri")
                if (uri != null) inspector.releasePermission(Uri.parse(uri))
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Throwable) {
                mainHandler.post { result.error("NATIVE", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun startPicker(multiple: Boolean, result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("BUSY", "Dosya seçici zaten açık", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("video/*", "audio/*", "image/*"))
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        pendingPick = result
        try {
            startActivityForResult(intent, pickRequestCode)
        } catch (e: Exception) {
            pendingPick = null
            result.error("PICKER", e.message ?: "Dosya seçici açılamadı", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequestCode) return
        val result = pendingPick ?: return
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        val uris = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) {
                uris.add(clip.getItemAt(i).uri)
            }
        } else {
            val single = data.data
            if (single != null) uris.add(single)
        }
        background(result) { uris.map { inspector.describe(it) } }
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }
}
