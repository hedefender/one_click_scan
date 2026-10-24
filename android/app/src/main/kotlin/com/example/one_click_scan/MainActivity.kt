package com.example.one_click_scan

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Storage Access Framework folder picker used by the first-run
 * wizard. The chosen tree URI is made persistable, so later phases can write
 * scans into the folder without asking again.
 *
 * Channel name must match AndroidStorageFolderPicker.channelName (Dart).
 */
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolder" -> pickFolder(result)
                    "hasAccess" -> result.success(hasAccess(call.argument<String>("uri")))
                    else -> result.notImplemented()
                }
            }

        // Phase 1: writing scans into the folder, and small system helpers.
        ScanFilesHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        SystemHandler(this, flutterEngine.dartExecutor.binaryMessenger)

        // Phase 2: upright working copy of large photos for the OCR.
        ImageDecodeHandler(flutterEngine.dartExecutor.binaryMessenger)
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "A folder picker is already open", null)
            return
        }
        pendingResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQUEST_PICK_FOLDER)
        } catch (e: Exception) {
            pendingResult = null
            result.error("launch_failed", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_FOLDER) return

        val result = pendingResult ?: return
        pendingResult = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }

        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            result.success(mapOf("uri" to uri.toString(), "name" to displayName(uri)))
        } catch (e: Exception) {
            result.error("permission_failed", e.message, null)
        }
    }

    private fun displayName(treeUri: Uri): String {
        return try {
            val documentId = DocumentsContract.getTreeDocumentId(treeUri)
            val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
            val name = contentResolver.query(
                documentUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
            name ?: documentId
        } catch (e: Exception) {
            treeUri.lastPathSegment ?: treeUri.toString()
        }
    }

    private fun hasAccess(uriString: String?): Boolean {
        if (uriString == null) return false
        val target = Uri.parse(uriString)
        return contentResolver.persistedUriPermissions.any {
            it.uri == target && it.isReadPermission && it.isWritePermission
        }
    }

    companion object {
        private const val CHANNEL = "com.example.one_click_scan/storage"
        private const val REQUEST_PICK_FOLDER = 4201
    }
}
