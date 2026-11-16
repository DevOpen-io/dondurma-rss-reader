package io.devopen.dondurma

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        // Text handed over by ShareActivity, read once (#67). It lives in
        // memory only, so an activity recreated after process death or from
        // Recents never sees an old share again.
        @Volatile
        var pendingShare: String? = null

        // Distinct from the plugins' request codes (file_selector,
        // share_plus); their results still go through super.
        private const val SAVE_FILE_REQUEST = 7301
    }

    private var shareChannel: MethodChannel? = null

    // The bytes of an export waiting for the user to pick where it goes.
    private var pendingSave: Pair<ByteArray, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.devopen.dondurma/share",
        ).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "initialText") {
                    result.success(pendingShare)
                    pendingShare = null
                } else {
                    result.notImplemented()
                }
            }
        }
        // Exports saved through the system "save as" dialog (Storage
        // Access Framework): no storage permission, any provider.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.devopen.dondurma/files",
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingSave != null) {
                result.error("busy", "A save dialog is already open", null)
                return@setMethodCallHandler
            }
            val name = call.argument<String>("name")
            val mimeType = call.argument<String>("mimeType")
            val bytes = call.argument<ByteArray>("bytes")
            if (name == null || mimeType == null || bytes == null) {
                result.error("args", "name, mimeType and bytes are required", null)
                return@setMethodCallHandler
            }
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType
                putExtra(Intent.EXTRA_TITLE, name)
            }
            pendingSave = bytes to result
            try {
                startActivityForResult(intent, SAVE_FILE_REQUEST)
            } catch (e: ActivityNotFoundException) {
                pendingSave = null
                result.error("unavailable", e.message, null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != SAVE_FILE_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val (bytes, result) = pendingSave ?: return
        pendingSave = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // cancelled
            return
        }
        try {
            contentResolver.openOutputStream(uri, "w").use { stream ->
                checkNotNull(stream).write(bytes)
            }
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    // A share while the app runs brings the task to the front.
    override fun onResume() {
        super.onResume()
        val text = pendingShare ?: return
        val channel = shareChannel ?: return
        pendingShare = null
        channel.invokeMethod("shared", text)
    }
}
