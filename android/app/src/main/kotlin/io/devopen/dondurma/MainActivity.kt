package io.devopen.dondurma

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null

    // Text shared to the app at launch, handed out once (#67).
    private var initialText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initialText = sharedText(intent)
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.devopen.dondurma/share",
        ).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "initialText") {
                    result.success(initialText)
                    initialText = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    // A share while the app runs (singleTask) arrives here.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        sharedText(intent)?.let { shareChannel?.invokeMethod("shared", it) }
    }

    private fun sharedText(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            intent.getStringExtra(Intent.EXTRA_TEXT)
        } else {
            null
        }
}
