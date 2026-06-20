package io.devopen.dondurma.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import io.devopen.dondurma.MainActivity
import io.devopen.dondurma.R
import org.json.JSONArray

class LatestNewsWidgetReceiver : AppWidgetProvider() {

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
        val json = prefs.getString("widget_latest", null)

        val views = RemoteViews(context.packageName, R.layout.widget_latest_news)

        val pi = openAppIntent(context, 0)
        views.setOnClickPendingIntent(R.id.widget_root, pi)

        val itemIds = listOf(R.id.item_1, R.id.item_2, R.id.item_3, R.id.item_4, R.id.item_5)
        val titleIds = listOf(R.id.title_1, R.id.title_2, R.id.title_3, R.id.title_4, R.id.title_5)
        val timeIds = listOf(R.id.time_1, R.id.time_2, R.id.time_3, R.id.time_4, R.id.time_5)

        itemIds.forEach { views.setViewVisibility(it, View.GONE) }

        if (json != null) {
            runCatching {
                val arr = JSONArray(json)
                val count = minOf(arr.length(), 5)
                views.setTextViewText(R.id.header_count, "$count")
                for (i in 0 until count) {
                    val a = arr.getJSONObject(i)
                    views.setViewVisibility(itemIds[i], View.VISIBLE)
                    views.setTextViewText(titleIds[i], a.optString("title"))
                    views.setTextViewText(timeIds[i], a.optString("timeAgo"))
                }
            }
        }

        return views
    }
}
