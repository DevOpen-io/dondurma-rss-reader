package io.devopen.dondurma.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import io.devopen.dondurma.R
import org.json.JSONObject

class CategoryWidgetReceiver : AppWidgetProvider() {

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
        val json = prefs.getString("widget_category", null)

        val views = RemoteViews(context.packageName, R.layout.widget_category)
        views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context, 2))

        val itemIds = listOf(R.id.item_1, R.id.item_2, R.id.item_3, R.id.item_4, R.id.item_5)
        val titleIds = listOf(R.id.title_1, R.id.title_2, R.id.title_3, R.id.title_4, R.id.title_5)
        val timeIds = listOf(R.id.time_1, R.id.time_2, R.id.time_3, R.id.time_4, R.id.time_5)

        itemIds.forEach { views.setViewVisibility(it, View.GONE) }

        if (json != null) {
            runCatching {
                val obj = JSONObject(json)
                val catName = obj.optString("name", "Kategori")
                views.setTextViewText(R.id.header_title, catName)

                val arr = obj.optJSONArray("articles")
                if (arr != null) {
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
        }

        return views
    }
}
