package com.hanclip.android.feature.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import com.hanclip.android.MainActivity
import com.hanclip.android.R

class HanClipQuickWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.hanclip_quick_widget).apply {
                setOnClickPendingIntent(
                    R.id.widget_photo,
                    quickActionIntent(context, "photo", requestCode = appWidgetId * 10 + 1)
                )
                setOnClickPendingIntent(
                    R.id.widget_quick,
                    quickActionIntent(context, "quick", requestCode = appWidgetId * 10 + 2)
                )
                setOnClickPendingIntent(
                    R.id.widget_aishot,
                    quickActionIntent(context, "aishot", requestCode = appWidgetId * 10 + 3)
                )
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun quickActionIntent(
        context: Context,
        path: String,
        requestCode: Int
    ): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("hanclip://$path"), context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
