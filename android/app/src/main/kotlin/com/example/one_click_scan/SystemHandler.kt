package com.example.one_click_scan

import android.content.Context
import android.content.Intent
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

    companion object {
        private const val CHANNEL = "com.example.one_click_scan/system"
    }
}
