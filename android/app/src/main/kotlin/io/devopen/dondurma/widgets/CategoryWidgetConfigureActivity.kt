package io.devopen.dondurma.widgets

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONArray

/// Configuration screen shown when the user drops a Category widget onto the
/// home screen. Lets them pick which feed category that specific widget shows.
class CategoryWidgetConfigureActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // If the user backs out, the widget is not added.
        setResult(RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContentView(buildUi())
    }

    private fun buildUi(): ViewGroup {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(16))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#131325"))
                cornerRadius = dp(24).toFloat()
            }
        }

        root.addView(TextView(this).apply {
            text = "Kategori seç"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        })

        root.addView(TextView(this).apply {
            text = "Bu widget hangi kategoriyi göstersin?"
            setTextColor(Color.parseColor("#99FFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setPadding(0, dp(4), 0, dp(16))
        })

        val categories = loadCategories()

        if (categories.isEmpty()) {
            root.addView(TextView(this).apply {
                text = "Henüz kategori yok. Önce uygulamayı açıp feedleri yükleyin."
                setTextColor(Color.parseColor("#CCFFFFFF"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setPadding(0, dp(8), 0, dp(8))
            })
            root.addView(categoryRow("Tamam") { confirm(null) })
            return root
        }

        val scroll = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            isVerticalScrollBarEnabled = false
        }
        val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        categories.forEach { cat ->
            list.addView(categoryRow(cat) { confirm(cat) })
        }
        scroll.addView(list)
        root.addView(scroll)

        return root
    }

    private fun categoryRow(label: String, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1AFFFFFF"))
                cornerRadius = dp(14).toFloat()
            }
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            lp.topMargin = dp(8)
            layoutParams = lp
            isClickable = true
            setOnClickListener { onClick() }
        }
    }

    private fun loadCategories(): List<String> {
        val prefs = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val listJson = prefs.getString("widget_category_list", null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(listJson)
            (0 until arr.length()).map { arr.getString(it) }
        }.getOrDefault(emptyList())
    }

    private fun confirm(category: String?) {
        val prefs = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        if (category != null) {
            prefs.edit().putString("widget_category_selected_$appWidgetId", category).apply()
        }

        val manager = AppWidgetManager.getInstance(this)
        manager.updateAppWidget(
            appWidgetId,
            CategoryWidgetReceiver.buildCategoryViews(this, appWidgetId)
        )

        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        )
        finish()
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()
}
