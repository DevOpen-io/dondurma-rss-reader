package io.devopen.dondurma.widgets

import android.app.ActivityOptions
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
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

/// Pending-intent template for the ListView collection. Each row supplies its
/// own article `id` via a fill-in Intent (the data Uri); the template carries
/// the action + component the home_widget plugin matches on so `widgetClicked`
/// fires. Must be MUTABLE so the fill-in data is merged in.
///
/// The [appWidgetId] becomes the requestCode so each widget instance gets a
/// DISTINCT template — sharing one across collections makes the launcher bind it
/// to the first widget, so other widgets' row clicks fall through to the root.
fun articleClickTemplate(context: Context, appWidgetId: Int): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).apply {
        action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
    }
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE

    if (Build.VERSION.SDK_INT < 34) {
        return PendingIntent.getActivity(context, appWidgetId, intent, flags)
    }

    val options = ActivityOptions.makeBasic()
    if (Build.VERSION.SDK_INT >= 35) {
        options.setPendingIntentCreatorBackgroundActivityStartMode(
            ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
        )
    } else {
        options.pendingIntentBackgroundActivityStartMode =
            ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
    }
    return PendingIntent.getActivity(context, appWidgetId, intent, flags, options.toBundle())
}
