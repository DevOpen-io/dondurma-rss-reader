package io.devopen.dondurma.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import io.devopen.dondurma.R
import org.json.JSONArray

class LatestNewsWidgetReceiver : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(id, buildViews(context, id))
            appWidgetManager.notifyAppWidgetViewDataChanged(id, R.id.widget_list)
        }
    }

    private fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val json = prefs.getString("widget_latest", null)

        val views = RemoteViews(context.packageName, R.layout.widget_latest_news)
        views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context, 0))

        val count = runCatching { JSONArray(json).length() }.getOrDefault(0)
        views.setTextViewText(R.id.header_count, "$count")

        val serviceIntent = Intent(context, WidgetListService::class.java).apply {
            putExtra(EXTRA_WIDGET_TYPE, TYPE_LATEST)
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            // Unique data Uri so each widget instance gets its own factory.
            data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
        }
        views.setRemoteAdapter(R.id.widget_list, serviceIntent)
        views.setEmptyView(R.id.widget_list, R.id.empty_view)
        views.setPendingIntentTemplate(R.id.widget_list, articleClickTemplate(context, appWidgetId))

        return views
    }
}
