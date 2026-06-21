package io.devopen.dondurma.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
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
            appWidgetManager.notifyAppWidgetViewDataChanged(id, R.id.widget_list)
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
        /// category chosen for that [appWidgetId] in the config screen. The body
        /// is a scrollable ListView fed by [WidgetListService].
        fun buildCategoryViews(context: Context, appWidgetId: Int): RemoteViews {
            val prefs =
                context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.widget_category)
            views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context, 2))

            // Resolve the selected category for the header (name + count).
            var category: String? = null
            var count = 0
            val dataJson = prefs.getString("widget_category_data", null)
            if (dataJson != null) {
                runCatching {
                    val data = JSONObject(dataJson)
                    val selected = prefs.getString("widget_category_selected_$appWidgetId", null)
                    category = if (selected != null && data.has(selected)) selected
                    else data.keys().asSequence().firstOrNull()
                    category?.let { count = data.optJSONArray(it)?.length() ?: 0 }
                }
            }
            views.setTextViewText(R.id.header_title, category ?: "Kategori")
            views.setTextViewText(R.id.header_count, "$count")

            val serviceIntent = Intent(context, WidgetListService::class.java).apply {
                putExtra(EXTRA_WIDGET_TYPE, TYPE_CATEGORY)
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
}
