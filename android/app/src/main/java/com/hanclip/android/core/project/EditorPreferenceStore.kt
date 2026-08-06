package com.hanclip.android.core.project

import android.content.Context
import com.hanclip.android.core.model.OutputAspectRatio

object EditorPreferenceStore {
    private const val PreferencesName = "hanclip_editor_preferences"
    private const val DefaultDurationKey = "default_duration_seconds"
    private const val AspectRatioKey = "output_aspect_ratio"
    private const val AutomaticAspectRatioValue = "automatic"

    fun defaultDurationSeconds(context: Context, fallback: Double): Double {
        val preferences = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
        if (!preferences.contains(DefaultDurationKey)) return fallback
        return preferences
            .getFloat(DefaultDurationKey, fallback.toFloat())
            .toDouble()
            .coerceIn(0.5, 30.0)
    }

    fun saveDefaultDurationSeconds(context: Context, seconds: Double) {
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .putFloat(DefaultDurationKey, seconds.coerceIn(0.5, 30.0).toFloat())
            .apply()
    }

    fun outputAspectRatio(context: Context): OutputAspectRatio? {
        val rawValue = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .getString(AspectRatioKey, null)
            ?: return null
        if (rawValue == AutomaticAspectRatioValue) return null
        return runCatching { enumValueOf<OutputAspectRatio>(rawValue) }.getOrNull()
    }

    fun saveOutputAspectRatio(context: Context, ratio: OutputAspectRatio?) {
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .putString(AspectRatioKey, ratio?.name ?: AutomaticAspectRatioValue)
            .apply()
    }
}
