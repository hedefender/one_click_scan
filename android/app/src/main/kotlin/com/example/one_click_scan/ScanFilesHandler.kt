package com.example.one_click_scan

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executors

/**
 * Writes scan files into the user's SAF folder (the tree URI picked in the
 * wizard). File bytes never cross the MethodChannel: a picture is copied
 * straight from the cache file to the folder, on a background thread.
 *
 * Channel name must match AndroidScanFileStore.channelName (Dart). Error codes
 * must match AndroidScanFileStore._failureFor: no_access, exists,
 * write_failed, source_missing. The reply of openDocument ("opened",
 * "no_viewer", "failed") must match AndroidOpenPdf (Dart).
 */
class ScanFilesHandler(private val context: Context, messenger: BinaryMessenger) {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private class ScanFilesException(val code: String, message: String) : Exception(message)

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            // Showing a stored PDF is a start of an activity: it stays on the
            // UI thread and needs no folder permission of its own.
            if (call.method == "openDocument") {
                openDocument(call, result)
                return@setMethodCallHandler
            }
            if (call.method == "shareDocument") {
                shareDocument(call, result)
                return@setMethodCallHandler
            }
            if (call.method == "describeShare") {
                result.success(describeShare(call))
                return@setMethodCallHandler
            }
            if (call.method == "findMailApps") {
                result.success(findMailApps(call))
                return@setMethodCallHandler
            }
            if (call.method == "openLink") {
                openLink(call, result)
                return@setMethodCallHandler
            }
            // Copies a stored document into the app cache for the mail sender.
            if (call.method == "copyUriToFile") {
                executor.execute {
                    try {
                        copyUriToFile(call)
                        mainHandler.post { result.success(null) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("unreadable", e.javaClass.simpleName, null) }
                    }
                }
                return@setMethodCallHandler
            }
            // Discard (ADR-027): delete by URI only, never by name or folder.
            // Not tied to a folder argument, so they come before `handle`.
            if (call.method == "deleteDocument" ||
                call.method == "saveToGallery" ||
                call.method == "deleteGalleryItem"
            ) {
                executor.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "deleteDocument" -> {
                                deleteDocument(requireArgument(call, "uri"))
                                null
                            }
                            "saveToGallery" -> saveToGallery(
                                requireArgument(call, "sourcePath"),
                                requireArgument(call, "fileName")
                            )
                            else -> {
                                deleteGalleryItem(requireArgument(call, "uri"))
                                null
                            }
                        }
                        mainHandler.post { result.success(value) }
                    } catch (e: ScanFilesException) {
                        mainHandler.post { result.error(e.code, e.message, null) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("unknown", e.javaClass.simpleName, null) }
                    }
                }
                return@setMethodCallHandler
            }
            // All SAF and file work runs off the UI thread.
            executor.execute {
                try {
                    val value = handle(call)
                    mainHandler.post { result.success(value) }
                } catch (e: ScanFilesException) {
                    mainHandler.post { result.error(e.code, e.message, null) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("unknown", e.javaClass.simpleName, null) }
                }
            }
        }
    }

    private fun handle(call: MethodCall): Any? {
        val treeUri = Uri.parse(requireArgument(call, "treeUri"))
        requireAccess(treeUri)
        return when (call.method) {
            "ensureSubfolder" -> {
                ensureSubfolder(treeUri, requireArgument(call, "name"))
                null
            }
            "ensureNoMedia" -> {
                ensureNoMedia(treeUri, requireArgument(call, "subfolder"))
                null
            }
            "listFileNames" -> listFileNames(treeUri, requireArgument(call, "subfolder"))
            "copyToFolder" -> copyToFolder(
                treeUri,
                requireArgument(call, "subfolder"),
                requireArgument(call, "fileName"),
                requireArgument(call, "mimeType"),
                requireArgument(call, "sourcePath")
            )
            "deleteFile" -> {
                deleteFile(
                    treeUri,
                    requireArgument(call, "subfolder"),
                    requireArgument(call, "fileName")
                )
                null
            }
            else -> throw ScanFilesException("unknown", "Unknown method")
        }
    }

    /**
     * Hands a stored document to the viewer the user chooses (ACTION_VIEW). The
     * URI is the document URI of a file in the SAF folder; the viewer gets a
     * temporary read grant for it. Replies "opened", "no_viewer" or "failed".
     */
    private fun openDocument(call: MethodCall, result: MethodChannel.Result) {
        val uriText = call.argument<String>("uri")
        val mimeType = call.argument<String>("mimeType") ?: "application/pdf"
        if (uriText == null) {
            result.success("failed")
            return
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(uriText), mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            context.startActivity(intent)
            result.success("opened")
        } catch (e: ActivityNotFoundException) {
            result.success("no_viewer")
        } catch (e: Exception) {
            result.success("failed")
        }
    }

    /**
     * The `ACTION_SEND` intent that hands the PDF to an e-mail app: recipient,
     * subject, text and the document as `EXTRA_STREAM` with a read-only grant
     * (also on the ClipData, which is what the chooser passes on). With a
     * [targetPackage] the intent is explicit (`setPackage`), so the app opens at
     * once, and the grant is also given to that package. One function builds it
     * for [shareDocument] and [describeShare], so the test of the extras and
     * flags checks the real intent.
     */
    private fun buildShareIntent(call: MethodCall, targetPackage: String?): Intent {
        val uri = Uri.parse(call.argument<String>("uri") ?: "")
        val mimeType = call.argument<String>("mimeType") ?: "application/pdf"
        val to = call.argument<List<String>>("to") ?: emptyList()
        val subject = call.argument<String>("subject") ?: ""
        val body = call.argument<String>("body") ?: ""
        return Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_EMAIL, to.toTypedArray())
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, body)
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = android.content.ClipData.newRawUri("", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (targetPackage != null) setPackage(targetPackage)
        }
    }

    private fun routeOf(call: MethodCall): String = call.argument<String>("route") ?: "generic"

    private fun packagesOf(call: MethodCall): List<String> =
        call.argument<List<String>>("packages") ?: emptyList()

    /** Read-only grant of the PDF to one package; a failure is not fatal (the intent flag still applies). */
    private fun grantRead(call: MethodCall, targetPackage: String) {
        try {
            context.grantUriPermission(
                targetPackage,
                Uri.parse(call.argument<String>("uri") ?: ""),
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (e: Exception) {
        }
    }

    /**
     * Opens the e-mail app for the route that Dart chose: the app of the provider
     * or the only e-mail app (explicit intent), a chooser of e-mail apps only
     * (the first package is the target of the chooser, the others its initial
     * intents), or the generic share menu. Replies "opened", "no_app" or "failed".
     */
    private fun shareDocument(call: MethodCall, result: MethodChannel.Result) {
        try {
            val route = routeOf(call)
            val packages = packagesOf(call)
            val intent: Intent = when {
                (route == "provider" || route == "mail") && packages.size == 1 -> {
                    grantRead(call, packages[0])
                    buildShareIntent(call, packages[0])
                }
                route == "chooser" && packages.isNotEmpty() -> {
                    packages.forEach { grantRead(call, it) }
                    val first = buildShareIntent(call, packages[0])
                    val others = packages.drop(1).map { buildShareIntent(call, it) }
                    Intent.createChooser(first, null).apply {
                        putExtra(Intent.EXTRA_INITIAL_INTENTS, others.toTypedArray())
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                }
                else -> Intent.createChooser(buildShareIntent(call, null), null).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
            if (context !is android.app.Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            result.success("opened")
        } catch (e: ActivityNotFoundException) {
            result.success("no_app")
        } catch (e: Exception) {
            result.success("failed")
        }
    }

    /** What the intent carries, for the tests: nothing is started. */
    private fun describeShare(call: MethodCall): Map<String, Any?> {
        val route = routeOf(call)
        val packages = packagesOf(call)
        val single = (route == "provider" || route == "mail") && packages.size == 1
        val intent = buildShareIntent(call, if (single) packages[0] else null)
        return mapOf(
            "action" to intent.action,
            "type" to intent.type,
            "package" to intent.`package`,
            "route" to route,
            // True only for the generic share menu (a chooser with no package).
            "genericChooser" to (route != "provider" && route != "mail" && route != "chooser"),
            "chooserPackages" to (if (route == "chooser") packages else emptyList<String>()),
            "to" to (intent.getStringArrayExtra(Intent.EXTRA_EMAIL)?.toList() ?: emptyList<String>()),
            "subject" to intent.getStringExtra(Intent.EXTRA_SUBJECT),
            "text" to intent.getStringExtra(Intent.EXTRA_TEXT),
            "stream" to intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.toString(),
            "clip" to intent.clipData?.getItemAt(0)?.uri?.toString(),
            "grantsRead" to ((intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION) != 0),
            "grantsWrite" to ((intent.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION) != 0)
        )
    }

    /**
     * Which e-mail apps the phone has: whether [providerPackage] is installed and
     * the packages that handle `mailto:` (this app is left out). Needs the
     * `<queries>` of the manifest on Android 11 and newer.
     */
    private fun findMailApps(call: MethodCall): Map<String, Any?> {
        val manager = context.packageManager
        val providerPackage = call.argument<String>("providerPackage")
        val installed = providerPackage != null && try {
            manager.getPackageInfo(providerPackage, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        } catch (e: Exception) {
            false
        }
        val packages = try {
            manager.queryIntentActivities(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")), 0)
                .map { it.activityInfo.packageName }
                .filter { it != context.packageName }
                .distinct()
        } catch (e: Exception) {
            emptyList<String>()
        }
        return mapOf("providerAppInstalled" to installed, "mailtoPackages" to packages)
    }

    /** Shows a page in the browser (ACTION_VIEW). Only `https`; replies "opened" or "failed". */
    private fun openLink(call: MethodCall, result: MethodChannel.Result) {
        val uri = Uri.parse(call.argument<String>("url") ?: "")
        if (uri.scheme != "https" || uri.host.isNullOrEmpty()) {
            result.success("failed")
            return
        }
        try {
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
                if (context !is android.app.Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            result.success("opened")
        } catch (e: Exception) {
            result.success("failed")
        }
    }

    /** Copies the document behind a content URI to a file of the app cache (the mail send reads it). */
    private fun copyUriToFile(call: MethodCall) {
        val uri = Uri.parse(requireArgument(call, "uri"))
        val target = File(requireArgument(call, "targetPath"))
        val input = context.contentResolver.openInputStream(uri)
            ?: throw ScanFilesException("unknown", "Could not open the document")
        input.use { source ->
            target.outputStream().use { out -> source.copyTo(out) }
        }
    }

    private fun requireArgument(call: MethodCall, name: String): String {
        return call.argument<String>(name)
            ?: throw ScanFilesException("unknown", "Missing argument")
    }

    private fun requireAccess(treeUri: Uri) {
        val granted = context.contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission && it.isWritePermission
        }
        if (!granted) throw ScanFilesException("no_access", "No access to the folder")
    }

    private fun rootDocumentId(treeUri: Uri): String = DocumentsContract.getTreeDocumentId(treeUri)

    private fun documentUri(treeUri: Uri, documentId: String): Uri =
        DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)

    private class Child(val documentId: String, val name: String, val isDirectory: Boolean)

    private fun children(treeUri: Uri, parentId: String): List<Child> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        )
        val found = mutableListOf<Child>()
        try {
            context.contentResolver.query(childrenUri, columns, null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    found.add(
                        Child(
                            cursor.getString(0),
                            cursor.getString(1) ?: "",
                            cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR
                        )
                    )
                }
            }
        } catch (e: SecurityException) {
            throw ScanFilesException("no_access", "No access to the folder")
        }
        return found
    }

    private fun findSubfolderId(treeUri: Uri, name: String): String? =
        children(treeUri, rootDocumentId(treeUri))
            .firstOrNull { it.isDirectory && it.name == name }?.documentId

    private fun ensureSubfolder(treeUri: Uri, name: String) {
        if (findSubfolderId(treeUri, name) != null) return
        val created = try {
            DocumentsContract.createDocument(
                context.contentResolver,
                documentUri(treeUri, rootDocumentId(treeUri)),
                DocumentsContract.Document.MIME_TYPE_DIR,
                name
            )
        } catch (e: Exception) {
            null
        }
        if (created == null) throw ScanFilesException("write_failed", "Could not create folder")
    }

    /**
     * Creates an empty `.nomedia` in the sub-folder (if missing) so MediaStore
     * does not index the pictures. Whether the Gallery shows a scan is then
     * decided only by the Gallery switch.
     */
    private fun ensureNoMedia(treeUri: Uri, subfolder: String) {
        val folderId = findSubfolderId(treeUri, subfolder)
            ?: throw ScanFilesException("write_failed", "Sub-folder is missing")
        if (children(treeUri, folderId).any { it.name == NO_MEDIA }) return
        val created = try {
            DocumentsContract.createDocument(
                context.contentResolver,
                documentUri(treeUri, folderId),
                "application/octet-stream",
                NO_MEDIA
            )
        } catch (e: Exception) {
            null
        }
        if (created == null) throw ScanFilesException("write_failed", "Could not create marker")
    }

    private fun listFileNames(treeUri: Uri, subfolder: String): List<String> {
        val folderId = findSubfolderId(treeUri, subfolder) ?: return emptyList()
        return children(treeUri, folderId).filter { !it.isDirectory }.map { it.name }
    }

    /** Returns the document URI of the new file (what a viewer is given). */
    private fun copyToFolder(
        treeUri: Uri,
        subfolder: String,
        fileName: String,
        mimeType: String,
        sourcePath: String
    ): String {
        val source = File(sourcePath)
        if (!source.isFile) throw ScanFilesException("source_missing", "Source file is missing")

        val folderId = findSubfolderId(treeUri, subfolder)
            ?: throw ScanFilesException("write_failed", "Sub-folder is missing")
        if (children(treeUri, folderId).any { it.name == fileName }) {
            throw ScanFilesException("exists", "File already exists")
        }

        val target = try {
            DocumentsContract.createDocument(
                context.contentResolver,
                documentUri(treeUri, folderId),
                mimeType,
                fileName
            )
        } catch (e: Exception) {
            null
        } ?: throw ScanFilesException("write_failed", "Could not create file")

        try {
            val output = context.contentResolver.openOutputStream(target, "w")
                ?: throw ScanFilesException("write_failed", "Could not open file")
            output.use { out ->
                FileInputStream(source).use { input -> input.copyTo(out) }
            }
        } catch (e: Exception) {
            // Never leave a partial file in the user's folder.
            try {
                DocumentsContract.deleteDocument(context.contentResolver, target)
            } catch (ignored: Exception) {
            }
            if (e is ScanFilesException) throw e
            throw ScanFilesException("write_failed", "Could not write file")
        }
        return target.toString()
    }

    private fun deleteFile(treeUri: Uri, subfolder: String, fileName: String) {
        val folderId = findSubfolderId(treeUri, subfolder) ?: return
        val child = children(treeUri, folderId).firstOrNull { it.name == fileName } ?: return
        try {
            DocumentsContract.deleteDocument(
                context.contentResolver,
                documentUri(treeUri, child.documentId)
            )
        } catch (e: Exception) {
            throw ScanFilesException("write_failed", "Could not delete file")
        }
    }

    /**
     * Deletes one document of the user's folder, by the URI that
     * [copyToFolder] returned. Only a URI under a folder the user granted is
     * accepted, so nothing outside it can be deleted. A document that is
     * already gone counts as deleted; a failure is an error, never a silent
     * success.
     */
    private fun deleteDocument(uriText: String) {
        val uri = Uri.parse(uriText)
        val granted = context.contentResolver.persistedUriPermissions.any {
            it.isWritePermission && uri.toString().startsWith(it.uri.toString() + "/")
        }
        if (!granted) throw ScanFilesException("no_access", "Not inside the granted folder")
        try {
            if (!DocumentsContract.deleteDocument(context.contentResolver, uri)) {
                throw ScanFilesException("write_failed", "Could not delete file")
            }
        } catch (e: java.io.FileNotFoundException) {
            // Already gone.
        } catch (e: ScanFilesException) {
            throw e
        } catch (e: SecurityException) {
            throw ScanFilesException("no_access", "No access to the file")
        } catch (e: Exception) {
            throw ScanFilesException("write_failed", "Could not delete file")
        }
    }

    /**
     * Copies a picture into the Gallery (MediaStore, `Pictures/`) under the
     * given name and returns the URI of the entry, which is what a discard
     * deletes it by. From Android 10 on the entry belongs to this app, so it
     * needs no permission to delete it again; before that the storage
     * permission that the `gal` plugin asks for is needed.
     */
    private fun saveToGallery(sourcePath: String, fileName: String): String {
        val source = File(sourcePath)
        if (!source.isFile) throw ScanFilesException("source_missing", "Source file is missing")
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES)
                put(MediaStore.Images.Media.IS_PENDING, 1)
            } else {
                @Suppress("DEPRECATION")
                val directory = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                directory.mkdirs()
                @Suppress("DEPRECATION")
                put(MediaStore.Images.Media.DATA, File(directory, fileName).absolutePath)
            }
        }
        val uri = try {
            resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
        } catch (e: SecurityException) {
            throw ScanFilesException("no_access", "No permission for the Gallery")
        } ?: throw ScanFilesException("write_failed", "Could not create the Gallery entry")
        try {
            val output = resolver.openOutputStream(uri, "w")
                ?: throw ScanFilesException("write_failed", "Could not open the Gallery entry")
            output.use { out -> FileInputStream(source).use { input -> input.copyTo(out) } }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val done = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
                resolver.update(uri, done, null, null)
            }
        } catch (e: Exception) {
            // Never leave a half entry in the Gallery.
            try {
                resolver.delete(uri, null, null)
            } catch (ignored: Exception) {
            }
            if (e is ScanFilesException) throw e
            throw ScanFilesException("write_failed", "Could not write the Gallery entry")
        }
        return uri.toString()
    }

    /**
     * Deletes one Gallery entry by the URI [saveToGallery] returned. Only a
     * MediaStore image URI is accepted. Zero rows (already gone) counts as
     * deleted; a refusal is an error.
     */
    private fun deleteGalleryItem(uriText: String) {
        val uri = Uri.parse(uriText)
        if (uri.scheme != "content" || uri.authority != MediaStore.AUTHORITY ||
            !uri.toString().startsWith(MediaStore.Images.Media.EXTERNAL_CONTENT_URI.toString() + "/")
        ) {
            throw ScanFilesException("no_access", "Not a Gallery image")
        }
        try {
            context.contentResolver.delete(uri, null, null)
        } catch (e: SecurityException) {
            // Android 16 answers a delete of an entry that no longer exists with a
            // SecurityException, not with zero rows. The app always sees its own
            // entries, so an entry it cannot find is already gone.
            if (galleryEntryExists(uri)) {
                throw ScanFilesException("no_access", "No access to the Gallery entry")
            }
        } catch (e: Exception) {
            throw ScanFilesException("write_failed", "Could not delete the Gallery entry")
        }
    }

    private fun galleryEntryExists(uri: Uri): Boolean {
        return try {
            context.contentResolver.query(
                uri, arrayOf(MediaStore.Images.Media._ID), null, null, null,
            )?.use { it.moveToFirst() } ?: false
        } catch (e: Exception) {
            true
        }
    }

    companion object {
        private const val NO_MEDIA = ".nomedia"
        private const val CHANNEL = "com.example.one_click_scan/scan_files"
    }
}
