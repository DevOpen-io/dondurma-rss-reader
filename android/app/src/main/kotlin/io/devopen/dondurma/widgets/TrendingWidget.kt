package io.devopen.dondurma.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import io.devopen.dondurma.MainActivity
import io.devopen.dondurma.R
import org.json.JSONObject

class TrendingWidgetReceiver : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val views = buildViews(context)
        appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, views) }
    }

    private fun buildViews(context: Context): RemoteViews {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val json = prefs.getString("widget_trending", null)

        val views = RemoteViews(context.packageName, R.layout.widget_trending)
        views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context, 1))

        if (json != null) {
            runCatching {
                val obj = JSONObject(json)
                val id = obj.optString("id")
                if (id.isNotEmpty()) {
                    views.setOnClickPendingIntent(R.id.widget_root, articleClickIntent(context, id))
                }
                views.setTextViewText(R.id.trending_title, obj.optString("title"))
                views.setTextViewText(R.id.trending_description, obj.optString("description"))
                val source = obj.optString("siteName")
                val time = obj.optString("timeAgo")
                views.setTextViewText(R.id.trending_source, if (time.isNotEmpty()) "$source · $time" else source)
                views.setTextViewText(R.id.trending_time, time)
            }
        }

        return views
    }
}
