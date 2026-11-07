package com.example.one_click_scan

import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.net.Uri
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
        private const val CHANNEL = "com.example.one_click_scan/system"
    }
}
