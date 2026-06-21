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
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(id, buildCategoryViews(context, id))
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        appWidgetIds.forEach { editor.remove("widget_category_selected_$it") }
        editor.apply()
    }

    companion object {
        /// Builds the category widget for a single instance, honoring the
        /// category chosen for that [appWidgetId] in the config screen.
        fun buildCategoryViews(context: Context, appWidgetId: Int): RemoteViews {
            val prefs =
                context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.widget_category)
            views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context, 2))

            val itemIds = listOf(R.id.item_1, R.id.item_2, R.id.item_3, R.id.item_4, R.id.item_5)
            val titleIds = listOf(R.id.title_1, R.id.title_2, R.id.title_3, R.id.title_4, R.id.title_5)
            val timeIds = listOf(R.id.time_1, R.id.time_2, R.id.time_3, R.id.time_4, R.id.time_5)
            itemIds.forEach { views.setViewVisibility(it, View.GONE) }

            val dataJson = prefs.getString("widget_category_data", null) ?: return views

            runCatching {
                val data = JSONObject(dataJson)
                val selected = prefs.getString("widget_category_selected_$appWidgetId", null)
                val category = if (selected != null && data.has(selected)) {
                    selected
                } else {
                    data.keys().asSequence().firstOrNull()
                } ?: return@runCatching

                views.setTextViewText(R.id.header_title, category)
                val arr = data.optJSONArray(category) ?: return@runCatching
                val count = minOf(arr.length(), 5)
                views.setTextViewText(R.id.header_count, "$count")
                for (i in 0 until count) {
                    val a = arr.getJSONObject(i)
                    views.setViewVisibility(itemIds[i], View.VISIBLE)
                    views.setTextViewText(titleIds[i], a.optString("title"))
                    views.setTextViewText(timeIds[i], a.optString("timeAgo"))
                    val id = a.optString("id")
                    if (id.isNotEmpty()) {
                        views.setOnClickPendingIntent(itemIds[i], articleClickIntent(context, id))
                    }
                }
            }

            return views
        }
    }
}
