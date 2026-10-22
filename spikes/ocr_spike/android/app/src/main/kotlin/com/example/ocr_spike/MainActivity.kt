package com.example.ocr_spike

import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Minimal Tesseract bridge on tesseract4android (the spike's own channel,
 * because the pub.dev wrapper does not build with AGP 9 / Gradle 9).
 * One TessBaseAPI is kept; it is re-created when the data key (variant +
 * language) changes.
 */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var api: TessBaseAPI? = null
    private var apiKey: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spike/tesseract")
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val imagePath = call.argument<String>("imagePath")!!
                val dataDir = call.argument<String>("dataDir")!!
                val language = call.argument<String>("language")!!
                val key = call.argument<String>("key")!!
                val psm = call.argument<Int>("psm") ?: TessBaseAPI.PageSegMode.PSM_AUTO
                worker.execute {
                    try {
                        val started = System.nanoTime()
                        if (api == null || apiKey != key) {
                            api?.recycle()
                            val fresh = TessBaseAPI()
                            if (!fresh.init(dataDir, language)) {
                                throw IllegalStateException("init failed")
                            }
                            api = fresh
                            apiKey = key
                        }
                        val initMs = (System.nanoTime() - started) / 1_000_000
                        val tess = api!!
                        tess.setPageSegMode(psm)
                        tess.setVariable("preserve_interword_spaces", "1")
                        tess.setImage(File(imagePath))
                        val hocr = tess.getHOCRText(0)
                        val confidence = tess.meanConfidence()
                        tess.clear()
                        val reply = mapOf(
                            "hocr" to hocr,
                            "confidence" to confidence,
                            "initMs" to initMs,
                        )
                        main.post { result.success(reply) }
                    } catch (e: Throwable) {
                        main.post { result.error("tess", e.javaClass.simpleName, null) }
                    }
                }
            }
    }

    override fun onDestroy() {
        api?.recycle()
        api = null
        super.onDestroy()
    }
}
