package com.amllystudio.amlly_edit_pad

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream

/**
 * Medya dosyalarını yerel Android API'leriyle inceler:
 * süre, çözünürlük, döndürme, kare hızı, codec, ses bilgisi ve küçük resim.
 */
class MediaInspector(private val context: Context) {

    fun describe(uri: Uri): Map<String, Any?> {
        try {
            context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: Exception) {
            // Bazı sağlayıcılar kalıcı izin vermez; dosya yine bu oturumda okunabilir.
        }
        var name: String? = null
        var size: Long? = null
        try {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIndex >= 0 && !cursor.isNull(nameIndex)) name = cursor.getString(nameIndex)
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex)
                }
            }
        } catch (e: Exception) {
        }
        return hashMapOf(
            "uri" to uri.toString(),
            "name" to (name ?: uri.lastPathSegment ?: "Adsız medya"),
            "size" to size,
            "mime" to context.contentResolver.getType(uri)
        )
    }

    fun probe(uri: Uri): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        val mime = context.contentResolver.getType(uri) ?: ""
        if (mime.startsWith("image/")) {
            readImageBounds(uri, out)
            out["hasVideo"] = false
            out["hasAudio"] = false
            return out
        }

        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            out["durationMs"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            out["hasVideo"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            out["hasAudio"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            out["width"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            out["height"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            out["rotation"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull()
            out["bitrate"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull()
        } catch (e: Exception) {
            out["error"] = e.message ?: e.javaClass.simpleName
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
            }
        }

        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(context, uri, null)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val trackMime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (trackMime.startsWith("video/") && out["videoCodec"] == null) {
                    out["videoCodec"] = trackMime
                    val fps = readNumber(format, MediaFormat.KEY_FRAME_RATE)
                    if (fps != null) out["frameRate"] = fps
                    if (out["width"] == null && format.containsKey(MediaFormat.KEY_WIDTH)) {
                        out["width"] = format.getInteger(MediaFormat.KEY_WIDTH)
                    }
                    if (out["height"] == null && format.containsKey(MediaFormat.KEY_HEIGHT)) {
                        out["height"] = format.getInteger(MediaFormat.KEY_HEIGHT)
                    }
                } else if (trackMime.startsWith("audio/") && out["audioCodec"] == null) {
                    out["audioCodec"] = trackMime
                    if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                        out["sampleRate"] = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    }
                    if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        out["channels"] = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                }
            }
        } catch (e: Exception) {
            if (out["error"] == null) out["error"] = e.message ?: e.javaClass.simpleName
        } finally {
            extractor.release()
        }
        return out
    }

    fun thumbnail(uri: Uri, atMs: Long, maxSize: Int): ByteArray? {
        val mime = context.contentResolver.getType(uri) ?: ""
        val bitmap = if (mime.startsWith("image/")) decodeImage(uri, maxSize) else frameAt(uri, atMs, maxSize)
        if (bitmap == null) return null
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 82, stream)
        bitmap.recycle()
        return stream.toByteArray()
    }

    fun isAccessible(uri: Uri): Boolean {
        return try {
            val descriptor = context.contentResolver.openFileDescriptor(uri, "r")
            descriptor?.close()
            descriptor != null
        } catch (e: Exception) {
            false
        }
    }

    fun releasePermission(uri: Uri) {
        try {
            context.contentResolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: Exception) {
        }
    }

    private fun frameAt(uri: Uri, atMs: Long, maxSize: Int): Bitmap? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            val hasVideo = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            if (!hasVideo) {
                // Ses dosyası: gömülü kapak resmi varsa onu kullan.
                val art = retriever.embeddedPicture ?: return null
                return decodeBytes(art, maxSize)
            }
            val timeUs = atMs * 1000L
            return if (Build.VERSION.SDK_INT >= 27) {
                retriever.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, maxSize, maxSize)
            } else {
                val frame = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                if (frame == null) null else scaleDown(frame, maxSize)
            }
        } catch (e: Exception) {
            return null
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
            }
        }
    }

    private fun readImageBounds(uri: Uri, out: HashMap<String, Any?>) {
        try {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
            if (options.outWidth > 0 && options.outHeight > 0) {
                out["width"] = options.outWidth
                out["height"] = options.outHeight
            }
        } catch (e: Exception) {
            out["error"] = e.message ?: e.javaClass.simpleName
        }
    }

    private fun decodeImage(uri: Uri, maxSize: Int): Bitmap? {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSize) {
                sample *= 2
            }
            val options = BitmapFactory.Options().apply { inSampleSize = sample }
            val bitmap = context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, options)
            } ?: return null
            scaleDown(bitmap, maxSize)
        } catch (e: Exception) {
            null
        }
    }

    private fun decodeBytes(bytes: ByteArray, maxSize: Int): Bitmap? {
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        return scaleDown(bitmap, maxSize)
    }

    private fun scaleDown(source: Bitmap, maxSize: Int): Bitmap {
        val longest = maxOf(source.width, source.height)
        if (longest <= maxSize) return source
        val scale = maxSize.toFloat() / longest
        val width = maxOf(1, (source.width * scale).toInt())
        val height = maxOf(1, (source.height * scale).toInt())
        val scaled = Bitmap.createScaledBitmap(source, width, height, true)
        if (scaled !== source) source.recycle()
        return scaled
    }

    private fun readNumber(format: MediaFormat, key: String): Double? {
        if (!format.containsKey(key)) return null
        return try {
            format.getInteger(key).toDouble()
        } catch (e: Exception) {
            try {
                format.getFloat(key).toDouble()
            } catch (e2: Exception) {
                null
            }
        }
    }
}
