package io.devopen.dondurma.widgets

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import io.devopen.dondurma.MainActivity

fun openAppIntent(context: Context, requestCode: Int): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    return PendingIntent.getActivity(
        context,
        requestCode,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
}

/// Launch intent that opens a specific article in the Flutter app.
/// Distinct per-id Uri makes each PendingIntent unique.
fun articleClickIntent(context: Context, id: String): PendingIntent {
    return HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("homewidget://article?id=" + Uri.encode(id))
    )
}
