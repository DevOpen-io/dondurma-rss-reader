package io.devopen.dondurma.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import io.devopen.dondurma.R
import org.json.JSONArray
import org.json.JSONObject

const val EXTRA_WIDGET_TYPE = "widget_type"
const val TYPE_LATEST = "latest"
const val TYPE_CATEGORY = "category"

/// Backs the scrollable ListView in both home screen widgets. The factory reads
/// the same HomeWidget SharedPreferences the static layout used to, but renders
/// as many rows as the data holds so a resized/full-page widget can scroll.
class WidgetListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val type = intent.getStringExtra(EXTRA_WIDGET_TYPE) ?: TYPE_LATEST
        val appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        )
        return WidgetListFactory(applicationContext, type, appWidgetId)
    }
}

private class WidgetListFactory(
    private val context: Context,
    private val type: String,
    private val appWidgetId: Int
) : RemoteViewsService.RemoteViewsFactory {

    private var items: List<JSONObject> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        items = loadItems()
    }

    private fun loadItems(): List<JSONObject> {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        return runCatching {
            if (type == TYPE_CATEGORY) {
                val dataJson = prefs.getString("widget_category_data", null) ?: return emptyList()
                val data = JSONObject(dataJson)
                val selected = prefs.getString("widget_category_selected_$appWidgetId", null)
                val category = (if (selected != null && data.has(selected)) selected
                else data.keys().asSequence().firstOrNull()) ?: return emptyList()
                val arr = data.optJSONArray(category) ?: return emptyList()
                (0 until arr.length()).map { arr.getJSONObject(it) }
            } else {
                val json = prefs.getString("widget_latest", null) ?: return emptyList()
                val arr = JSONArray(json)
                (0 until arr.length()).map { arr.getJSONObject(it) }
            }
        }.getOrDefault(emptyList())
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
        val a = items[position]
        val row = RemoteViews(context.packageName, R.layout.widget_list_item)
        row.setTextViewText(R.id.row_title, a.optString("title"))
        row.setTextViewText(R.id.row_time, a.optString("timeAgo"))
        val id = a.optString("id")
        if (id.isNotEmpty()) {
            // Only the data Uri varies per row; the action/component come from the
            // pending-intent template set on the ListView.
            val fillIn = Intent().apply {
                data = Uri.parse("homewidget://article?id=" + Uri.encode(id))
            }
            row.setOnClickFillInIntent(R.id.row_root, fillIn)
        }
        return row
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = false
    override fun onDestroy() {}
}
