package com.example.one_click_scan

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Makes the upright working copy of a large photo for the OCR: decodes with
 * inSampleSize (the full-size bitmap is never created), applies the EXIF
 * orientation, scales so the long side is at most maxSide and writes a JPEG.
 * Runs on its own thread; only paths and numbers cross the channel.
 *
 * Channel name must match NativeUprightImageMaker.channelName (Dart). Error
 * codes must match NativeUprightImageMaker.make: unreadable, out_of_memory,
 * failed.
 */
class ImageDecodeHandler(messenger: BinaryMessenger) {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private class ImageDecodeException(val code: String) : Exception(code)

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "makeUpright") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            executor.execute {
                try {
                    val value = makeUpright(call)
                    mainHandler.post { result.success(value) }
                } catch (e: ImageDecodeException) {
                    mainHandler.post { result.error(e.code, null, null) }
                } catch (e: OutOfMemoryError) {
                    mainHandler.post { result.error("out_of_memory", null, null) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("failed", e.javaClass.simpleName, null) }
                }
            }
        }
    }

    private fun makeUpright(call: MethodCall): Map<String, Int> {
        val source = call.argument<String>("source") ?: throw ImageDecodeException("failed")
        val target = call.argument<String>("target") ?: throw ImageDecodeException("failed")
        val maxSide = call.argument<Int>("maxSide") ?: throw ImageDecodeException("failed")
        val quality = call.argument<Int>("quality") ?: 95

        // 1. Size from the header only (BitmapFactory ignores the EXIF tag).
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw ImageDecodeException("unreadable")
        }

        // 2. Largest power of two that keeps the long side at or above maxSide.
        val longSide = maxOf(bounds.outWidth, bounds.outHeight)
        var sample = 1
        while (longSide / (sample * 2) >= maxSide) sample *= 2

        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeFile(source, options)
            ?: throw ImageDecodeException("unreadable")

        // 3. Orientation and final scale in one pass. 0 and anything outside
        //    1..8 mean "no rotation".
        val orientation = try {
            ExifInterface(source).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
        } catch (e: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> {
                matrix.setRotate(180f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.setRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.setRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            else -> Unit
        }
        val decodedLong = maxOf(decoded.width, decoded.height)
        if (decodedLong > maxSide) {
            val scale = maxSide.toFloat() / decodedLong
            matrix.postScale(scale, scale)
        }

        val upright = if (matrix.isIdentity) {
            decoded
        } else {
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        }
        if (upright !== decoded) decoded.recycle()

        // 4. Write the JPEG.
        try {
            BufferedOutputStream(FileOutputStream(File(target))).use { out ->
                if (!upright.compress(Bitmap.CompressFormat.JPEG, quality, out)) {
                    throw ImageDecodeException("failed")
                }
            }
            return mapOf("width" to upright.width, "height" to upright.height)
        } finally {
            upright.recycle()
        }
    }

    companion object {
        private const val CHANNEL = "com.example.one_click_scan/image_decode"
    }
}
