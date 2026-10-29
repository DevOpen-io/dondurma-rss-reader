package io.devopen.dondurma

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
    }

    private var shareChannel: MethodChannel? = null

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
