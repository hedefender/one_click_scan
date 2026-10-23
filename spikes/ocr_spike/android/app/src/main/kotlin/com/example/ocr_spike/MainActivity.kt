package com.example.ocr_spike

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
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
        // Phase 1.6c: battery temperature and why the previous process died
        // (numbers and system reason names only).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spike/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "batteryTemp" -> {
                        val intent = registerReceiver(
                            null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                        )
                        val tenths = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
                        result.success(
                            if (tenths == null || tenths == Int.MIN_VALUE) null else tenths / 10.0
                        )
                    }
                    "exitReasons" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                            result.success(emptyList<Any>())
                        } else {
                            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                            val list = am.getHistoricalProcessExitReasons(packageName, 0, 5).map {
                                mapOf(
                                    "reason" to it.reason,
                                    "name" to exitName(it.reason),
                                    "ts" to it.timestamp,
                                    "importance" to it.importance,
                                    "status" to it.status,
                                    "description" to it.description,
                                    "pssKb" to it.pss,
                                    "rssKb" to it.rss,
                                )
                            }
                            result.success(list)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
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

    private fun exitName(reason: Int): String =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) "unknown" else when (reason) {
            ApplicationExitInfo.REASON_ANR -> "ANR"
            ApplicationExitInfo.REASON_CRASH -> "CRASH (Java)"
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
            ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY (killed by the system)"
            ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
            ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
            ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
            ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
            ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
            ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
            ApplicationExitInfo.REASON_OTHER -> "OTHER"
            else -> "UNKNOWN($reason)"
        }

    override fun onDestroy() {
        api?.recycle()
        api = null
        super.onDestroy()
    }
}
