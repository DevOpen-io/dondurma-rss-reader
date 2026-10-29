package io.devopen.dondurma

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null

    // Text shared to the app at launch, handed out once (#67).
    private var initialText: String? = null

    // A recreated activity (process death, Recents) still carries the
    // share it was first started with; that share was already handled.
    private var relaunched = false

    override fun onCreate(savedInstanceState: Bundle?) {
        relaunched = savedInstanceState != null ||
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initialText = if (relaunched) null else sharedText(intent)
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

    // Styled text arrives as a Spanned CharSequence; a share with no text
    // (a file) becomes "" so the app can say it found no link.
    private fun sharedText(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: ""
        } else {
            null
        }
}
