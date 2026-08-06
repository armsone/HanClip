package com.hanclip.android.core.project

import android.content.Context
import android.net.Uri
import com.hanclip.android.core.model.ClipItem
import com.hanclip.android.core.model.ClipMediaKind
import com.hanclip.android.core.model.LivePhotoMode
import com.hanclip.android.core.model.MoviePreset
import com.hanclip.android.core.model.OutputAspectRatio
import com.hanclip.android.core.model.VideoSegmentMode
import com.hanclip.android.core.model.CopyrightIconColorMode
import com.hanclip.android.core.model.WatermarkFontSize
import com.hanclip.android.core.model.WatermarkLineSpacing
import com.hanclip.android.core.model.WatermarkPosition
import com.hanclip.android.core.model.WatermarkSettings
import org.json.JSONArray
import org.json.JSONObject

data class DraftProject(
    val clips: List<ClipItem>,
    val preset: MoviePreset,
    val defaultDurationSeconds: Double,
    val defaultVideoSegmentMode: VideoSegmentMode,
    val outputAspectRatio: OutputAspectRatio?,
    val watermarkSettings: WatermarkSettings,
    val backgroundMusicUri: Uri?,
    val backgroundMusicTitle: String? = null,
    val backgroundMusicSampleId: String? = null,
    val backgroundMusicVolume: Double = 0.35,
    val originalAudioVolume: Double = 1.0
)

object DraftProjectStore {
    private const val PreferencesName = "hanclip_draft_project"
    private const val DraftKey = "draft"

    fun save(context: Context, project: DraftProject) {
        if (project.clips.isEmpty()) {
            clear(context)
            return
        }
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .putString(DraftKey, project.toJson().toString())
            .apply()
    }

    fun load(context: Context): DraftProject? {
        val raw = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .getString(DraftKey, null)
            ?: return null
        return runCatching {
            JSONObject(raw).toDraftProject()
        }.getOrNull()
    }

    fun hasDraft(context: Context): Boolean = load(context)?.clips?.isNotEmpty() == true

    fun clear(context: Context) {
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .remove(DraftKey)
            .apply()
    }
}

private fun DraftProject.toJson(): JSONObject {
    return JSONObject()
        .put("preset", preset.routeValue)
        .put("defaultDurationSeconds", defaultDurationSeconds)
        .put("defaultVideoSegmentMode", defaultVideoSegmentMode.name)
        .put("outputAspectRatio", outputAspectRatio?.name)
        .put("backgroundMusicUri", backgroundMusicUri?.toString())
        .put("backgroundMusicTitle", backgroundMusicTitle)
        .put("backgroundMusicSampleId", backgroundMusicSampleId)
        .put("backgroundMusicVolume", backgroundMusicVolume)
        .put("originalAudioVolume", originalAudioVolume)
        .put("watermarkSettings", watermarkSettings.toJson())
        .put("clips", JSONArray().also { array ->
            clips.forEach { clip -> array.put(clip.toJson()) }
        })
}

private fun JSONObject.toDraftProject(): DraftProject {
    val clipsArray = optJSONArray("clips") ?: JSONArray()
    return DraftProject(
        clips = List(clipsArray.length()) { index ->
            clipsArray.getJSONObject(index).toClipItem()
        },
        preset = MoviePreset.fromRouteValue(optString("preset", MoviePreset.NewMovie.routeValue)),
        defaultDurationSeconds = optDouble("defaultDurationSeconds", 2.0),
        defaultVideoSegmentMode = enumValueOrDefault(
            optString("defaultVideoSegmentMode"),
            VideoSegmentMode.Single
        ),
        outputAspectRatio = optString("outputAspectRatio")
            .takeIf { it.isNotBlank() && it != "null" }
            ?.let { enumValueOrNull<OutputAspectRatio>(it) },
        watermarkSettings = optJSONObject("watermarkSettings")?.toWatermarkSettings()
            ?: WatermarkSettings(),
        backgroundMusicUri = optString("backgroundMusicUri")
            .takeIf { it.isNotBlank() && it != "null" }
            ?.let(Uri::parse),
        backgroundMusicTitle = optString("backgroundMusicTitle")
            .takeIf { it.isNotBlank() && it != "null" },
        backgroundMusicSampleId = optString("backgroundMusicSampleId")
            .takeIf { it.isNotBlank() && it != "null" },
        backgroundMusicVolume = optDouble("backgroundMusicVolume", 0.35),
        originalAudioVolume = optDouble("originalAudioVolume", 1.0)
    )
}

private fun ClipItem.toJson(): JSONObject {
    return JSONObject()
        .put("id", id)
        .put("sourceUri", sourceUri.toString())
        .put("thumbnailUri", thumbnailUri?.toString())
        .put("durationSeconds", durationSeconds)
        .put("photoDurationSeconds", photoDurationSeconds)
        .put("livePhotoDurationSeconds", livePhotoDurationSeconds)
        .put("isLivePhoto", isLivePhoto)
        .put("livePhotoMode", livePhotoMode.name)
        .put("mediaKind", mediaKind.name)
        .put("sourceDurationSeconds", sourceDurationSeconds)
        .put("trimStartSeconds", trimStartSeconds)
        .put("audioWaveform", JSONArray().also { array ->
            audioWaveform.forEach(array::put)
        })
        .put("audioPeakTimeSeconds", audioPeakTimeSeconds)
        .put("audioPeakTimesSeconds", JSONArray().also { array ->
            audioPeakTimesSeconds.forEach(array::put)
        })
        .put("videoSegmentMode", videoSegmentMode.name)
        .put("isVideoSegmentParent", isVideoSegmentParent)
        .put("videoSegmentParentId", videoSegmentParentId)
        .put("photoSimilarityFingerprint", JSONArray().also { array ->
            photoSimilarityFingerprint.forEach(array::put)
        })
        .put("similarPhotoGroupId", similarPhotoGroupId)
        .put("similarPhotoGroupIndex", similarPhotoGroupIndex)
        .put("similarPhotoGroupCount", similarPhotoGroupCount)
        .put("isSimilarPhotoGroupRepresentative", isSimilarPhotoGroupRepresentative)
        .put("sourceWidth", sourceWidth)
        .put("sourceHeight", sourceHeight)
}

private fun JSONObject.toClipItem(): ClipItem {
    return ClipItem(
        id = getString("id"),
        sourceUri = Uri.parse(getString("sourceUri")),
        thumbnailUri = optString("thumbnailUri")
            .takeIf { it.isNotBlank() && it != "null" }
            ?.let(Uri::parse),
        durationSeconds = optDouble("durationSeconds", 2.0),
        photoDurationSeconds = optDouble("photoDurationSeconds", optDouble("durationSeconds", 2.0)),
        livePhotoDurationSeconds = optNullableDouble("livePhotoDurationSeconds"),
        isLivePhoto = optBoolean("isLivePhoto", false),
        livePhotoMode = enumValueOrDefault(optString("livePhotoMode"), LivePhotoMode.Still),
        mediaKind = enumValueOrDefault(optString("mediaKind"), ClipMediaKind.Photo),
        sourceDurationSeconds = optNullableDouble("sourceDurationSeconds"),
        trimStartSeconds = optDouble("trimStartSeconds", 0.0),
        audioWaveform = optDoubleList("audioWaveform"),
        audioPeakTimeSeconds = optNullableDouble("audioPeakTimeSeconds"),
        audioPeakTimesSeconds = optDoubleList("audioPeakTimesSeconds"),
        videoSegmentMode = enumValueOrDefault(optString("videoSegmentMode"), VideoSegmentMode.Single),
        isVideoSegmentParent = optBoolean("isVideoSegmentParent", false),
        videoSegmentParentId = optString("videoSegmentParentId")
            .takeIf { it.isNotBlank() && it != "null" },
        photoSimilarityFingerprint = optIntList("photoSimilarityFingerprint"),
        similarPhotoGroupId = optString("similarPhotoGroupId")
            .takeIf { it.isNotBlank() && it != "null" },
        similarPhotoGroupIndex = optInt("similarPhotoGroupIndex", 0),
        similarPhotoGroupCount = optInt("similarPhotoGroupCount", 1).coerceAtLeast(1),
        isSimilarPhotoGroupRepresentative = optBoolean("isSimilarPhotoGroupRepresentative", true),
        sourceWidth = optInt("sourceWidth", 1),
        sourceHeight = optInt("sourceHeight", 1)
    )
}

private fun WatermarkSettings.toJson(): JSONObject {
    return JSONObject()
        .put("isEnabled", isEnabled)
        .put("logoEnabled", logoEnabled)
        .put("text", text)
        .put("position", position.name)
        .put("fontName", fontName)
        .put("textColorHex", textColorHex)
        .put("shadowEnabled", shadowEnabled)
        .put("shadowOpacity", shadowOpacity)
        .put("shadowColorHex", shadowColorHex)
        .put("lineSpacing", lineSpacing.name)
        .put("lineSpacingScale", lineSpacingScale)
        .put("fontSize", fontSize.name)
        .put("logoColorHex", logoColorHex)
        .put("logoShadowColorHex", logoShadowColorHex)
        .put("logoShadowOpacity", logoShadowOpacity)
        .put("copyrightPosition", copyrightPosition.name)
        .put("copyrightIconColorMode", copyrightIconColorMode.name)
        .put("copyrightIconColorHex", copyrightIconColorHex)
        .put("customCopyrightIconPath", customCopyrightIconPath)
}

private fun JSONObject.toWatermarkSettings(): WatermarkSettings {
    return WatermarkSettings(
        isEnabled = optBoolean("isEnabled", false),
        logoEnabled = optBoolean("logoEnabled", false),
        text = optString("text", ""),
        position = enumValueOrDefault(optString("position"), WatermarkPosition.TopLeading),
        fontName = optString("fontName", "pretendard"),
        textColorHex = optString("textColorHex", "#FFFFFF"),
        shadowEnabled = optBoolean("shadowEnabled", true),
        shadowOpacity = optDouble("shadowOpacity", 0.2),
        shadowColorHex = optString("shadowColorHex", "#000000"),
        lineSpacing = enumValueOrDefault(optString("lineSpacing"), WatermarkLineSpacing.Normal),
        lineSpacingScale = WatermarkLineSpacing.normalize(
            optDouble("lineSpacingScale", WatermarkLineSpacing.DefaultScale)
        ),
        fontSize = enumValueOrDefault(optString("fontSize"), WatermarkFontSize.Large),
        logoColorHex = optString("logoColorHex", "#007644"),
        logoShadowColorHex = optString("logoShadowColorHex", "#29AB87"),
        logoShadowOpacity = optDouble("logoShadowOpacity", 0.5).coerceIn(0.0, 1.0),
        copyrightPosition = enumValueOrDefault(
            optString("copyrightPosition"),
            WatermarkPosition.BottomTrailing
        ),
        copyrightIconColorMode = CopyrightIconColorMode.fromStoredValue(
            optString("copyrightIconColorMode")
        ),
        copyrightIconColorHex = optString("copyrightIconColorHex", "#007644"),
        customCopyrightIconPath = optString("customCopyrightIconPath", "")
    )
}

private fun JSONObject.optDoubleList(key: String): List<Double> {
    val array = optJSONArray(key) ?: return emptyList()
    return List(array.length()) { index -> array.optDouble(index, 0.0) }
}

private fun JSONObject.optIntList(key: String): List<Int> {
    val array = optJSONArray(key) ?: return emptyList()
    return List(array.length()) { index -> array.optInt(index, 0) }
}

private fun JSONObject.optNullableDouble(key: String): Double? {
    if (!has(key) || isNull(key)) return null
    return optDouble(key)
}

private inline fun <reified T : Enum<T>> enumValueOrNull(value: String): T? {
    return runCatching { enumValueOf<T>(value) }.getOrNull()
}

private inline fun <reified T : Enum<T>> enumValueOrDefault(value: String, default: T): T {
    return enumValueOrNull<T>(value) ?: default
}
