package com.hanclip.android.core.project

import android.content.Context
import com.hanclip.android.core.model.OutputAspectRatio
import com.hanclip.android.core.model.OutputQualityPreset

object EditorPreferenceStore {
    private const val PreferencesName = "hanclip_editor_preferences"
    private const val DefaultDurationKey = "default_duration_seconds"
    private const val AspectRatioKey = "output_aspect_ratio"
    private const val QualityPresetKey = "output_quality_preset"
    private const val SimilarPhotoRepresentativeIntervalKey = "similar_photo_representative_interval"
    private const val AutomaticAspectRatioValue = "automatic"

    fun defaultDurationSeconds(context: Context, fallback: Double): Double {
        val preferences = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
        if (!preferences.contains(DefaultDurationKey)) return fallback
        return preferences
            .getFloat(DefaultDurationKey, fallback.toFloat())
            .toDouble()
            .coerceIn(0.1, 30.0)
    }

    fun saveDefaultDurationSeconds(context: Context, seconds: Double) {
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .putFloat(DefaultDurationKey, seconds.coerceIn(0.1, 30.0).toFloat())
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

    fun outputQualityPreset(context: Context): OutputQualityPreset {
        val rawValue = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .getString(QualityPresetKey, null)
            ?: return OutputQualityPreset.Standard
        return runCatching { enumValueOf<OutputQualityPreset>(rawValue) }
            .getOrDefault(OutputQualityPreset.Standard)
    }

    fun saveOutputQualityPreset(context: Context, preset: OutputQualityPreset) {
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .putString(QualityPresetKey, preset.name)
            .apply()
    }

    fun similarPhotoRepresentativeInterval(context: Context): Int {
        return context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .getInt(SimilarPhotoRepresentativeIntervalKey, 6)
            .coerceIn(1, 20)
    }

    fun saveSimilarPhotoRepresentativeInterval(context: Context, value: Int) {
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .putInt(SimilarPhotoRepresentativeIntervalKey, value.coerceIn(1, 20))
            .apply()
    }
}
