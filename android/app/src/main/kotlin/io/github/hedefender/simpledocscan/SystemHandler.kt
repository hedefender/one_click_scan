package io.github.hedefender.simpledocscan

import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Small system helpers. Channel name must match
 * PluginCameraService.systemChannelName (Dart).
 */
class SystemHandler(private val context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> openAppSettings(result)
                "hasFlashUnit" -> result.success(hasBackFlash())
                "appInfo" -> result.success(appInfo())
                "composeMail" -> composeMail(
                    call.argument<String>("to"),
                    call.argument<String>("subject"),
                    call.argument<String>("body"),
                    result
                )
                else -> result.notImplemented()
            }
        }
    }

    /** Opens this app's page in the system settings (to grant a blocked permission). */
    private fun openAppSettings(result: MethodChannel.Result) {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null)
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            result.error("launch_failed", e.message, null)
        }
    }

    /**
     * The version of this app and of Android, nothing else (the About screen
     * and the technical lines of the feedback e-mail). No plugin is needed.
     */
    private fun appInfo(): Map<String, String> {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        @Suppress("DEPRECATION")
        val build = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        return mapOf(
            "versionName" to (info.versionName ?: ""),
            "buildNumber" to build.toString(),
            "androidRelease" to Build.VERSION.RELEASE
        )
    }

    /**
     * Opens the e-mail app with a message to write (`ACTION_SENDTO`, `mailto:`):
     * recipient, subject and text, no attachment. The user presses send.
     * Replies `opened` or `no_app`.
     */
    private fun composeMail(
        to: String?,
        subject: String?,
        body: String?,
        result: MethodChannel.Result
    ) {
        if (to.isNullOrBlank()) {
            result.error("bad_arguments", "no recipient", null)
            return
        }
        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")).apply {
            putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
            putExtra(Intent.EXTRA_SUBJECT, subject ?: "")
            putExtra(Intent.EXTRA_TEXT, body ?: "")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
            result.success("opened")
        } catch (e: android.content.ActivityNotFoundException) {
            result.success("no_app")
        } catch (e: Exception) {
            result.error("launch_failed", e.message, null)
        }
    }

    /**
     * True when a back camera has a flash unit. The camera plugin does not
     * expose this, so it is asked of the system directly (only a yes/no
     * crosses the channel).
     */
    private fun hasBackFlash(): Boolean {
        return try {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            manager.cameraIdList.any { id ->
                val c = manager.getCameraCharacteristics(id)
                c.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK &&
                    c.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
        } catch (e: Exception) {
            false
        }
    }

    companion object {
        private const val CHANNEL = "io.github.hedefender.simpledocscan/system"
    }
}
