package io.devopen.dondurma.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import io.devopen.dondurma.R
import org.json.JSONArray

class ReadLaterWidgetReceiver : AppWidgetProvider() {

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
        val json = prefs.getString("widget_bookmarks", null)

        val views = RemoteViews(context.packageName, R.layout.widget_read_later)
        views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context, 3))

        val itemIds = listOf(R.id.item_1, R.id.item_2, R.id.item_3, R.id.item_4, R.id.item_5)
        val titleIds = listOf(R.id.title_1, R.id.title_2, R.id.title_3, R.id.title_4, R.id.title_5)
        val sourceIds = listOf(R.id.source_1, R.id.source_2, R.id.source_3, R.id.source_4, R.id.source_5)

        itemIds.forEach { views.setViewVisibility(it, View.GONE) }

        if (json != null) {
            runCatching {
                val arr = JSONArray(json)
                val count = minOf(arr.length(), 5)
                views.setTextViewText(R.id.header_count, if (count > 0) "$count" else "")
                for (i in 0 until count) {
                    val a = arr.getJSONObject(i)
                    views.setViewVisibility(itemIds[i], View.VISIBLE)
                    views.setTextViewText(titleIds[i], a.optString("title"))
                    val source = a.optString("siteName")
                    val time = a.optString("timeAgo")
                    views.setTextViewText(sourceIds[i], if (time.isNotEmpty()) "$source · $time" else source)
                }
            }
        }

        return views
    }
}
