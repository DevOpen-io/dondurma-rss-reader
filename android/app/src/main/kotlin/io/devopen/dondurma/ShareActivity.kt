package io.devopen.dondurma

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Receives text shared from other apps (#67) without a UI of its own, and
 * brings the app up the way the launcher does: the running task comes to the
 * front, or a cold start begins. Launching MainActivity straight from a share
 * could leave a second instance (and a second Flutter engine on the same Hive
 * files) beside a task kept in Recents.
 */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            // Styled text arrives as a Spanned CharSequence; a share without
            // text (a file) becomes "" so the app can say it found no link.
            MainActivity.pendingShare =
                intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: ""
        }
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            // The launcher's intent names no package. Recents keeps one task
            // per launch intent, so a share task that carried one would sit
            // beside the launcher's task — and both could hold the app.
            it.setPackage(null)
            it.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
            )
            startActivity(it)
        }
        finish()
    }
}
