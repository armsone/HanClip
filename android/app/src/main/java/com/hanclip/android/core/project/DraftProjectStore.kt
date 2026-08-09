package com.hanclip.android.core.project

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import com.hanclip.android.core.model.ClipItem
import com.hanclip.android.core.model.ClipMediaKind
import com.hanclip.android.core.model.LivePhotoMode
import com.hanclip.android.core.model.MoviePreset
import com.hanclip.android.core.model.OutputAspectRatio
import com.hanclip.android.core.model.OutputQualityPreset
import com.hanclip.android.core.model.VideoSegmentMode
import com.hanclip.android.core.model.CopyrightIconColorMode
import com.hanclip.android.core.model.WatermarkFontSize
import com.hanclip.android.core.model.WatermarkLineSpacing
import com.hanclip.android.core.model.WatermarkPlatform
import com.hanclip.android.core.model.WatermarkPosition
import com.hanclip.android.core.model.WatermarkSettings
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.util.UUID

data class DraftProject(
    val projectId: String = UUID.randomUUID().toString(),
    val clips: List<ClipItem>,
    val preset: MoviePreset,
    val defaultDurationSeconds: Double,
    val defaultVideoSegmentMode: VideoSegmentMode,
    val outputAspectRatio: OutputAspectRatio?,
    val outputQualityPreset: OutputQualityPreset,
    val watermarkSettings: WatermarkSettings,
    val backgroundMusicUri: Uri?,
    val backgroundMusicTitle: String? = null,
    val backgroundMusicSampleId: String? = null,
    val backgroundMusicVolume: Double = 0.35,
    val originalAudioVolume: Double = 1.0,
    val backgroundMusicLoopsToFillVideo: Boolean = true,
    val backgroundMusicFadeInEnabled: Boolean = true,
    val backgroundMusicFadeOutEnabled: Boolean = true,
    val savedAtMillis: Long = System.currentTimeMillis()
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
        .put("projectId", projectId)
        .put("preset", preset.routeValue)
        .put("defaultDurationSeconds", defaultDurationSeconds)
        .put("defaultVideoSegmentMode", defaultVideoSegmentMode.name)
        .put("outputAspectRatio", outputAspectRatio?.name)
        .put("outputQualityPreset", outputQualityPreset.name)
        .put("backgroundMusicUri", backgroundMusicUri?.toString())
        .put("backgroundMusicTitle", backgroundMusicTitle)
        .put("backgroundMusicSampleId", backgroundMusicSampleId)
        .put("backgroundMusicVolume", backgroundMusicVolume)
        .put("originalAudioVolume", originalAudioVolume)
        .put("backgroundMusicLoopsToFillVideo", backgroundMusicLoopsToFillVideo)
        .put("backgroundMusicFadeInEnabled", backgroundMusicFadeInEnabled)
        .put("backgroundMusicFadeOutEnabled", backgroundMusicFadeOutEnabled)
        .put("savedAtMillis", savedAtMillis)
        .put("watermarkSettings", watermarkSettings.toJson())
        .put("clips", JSONArray().also { array ->
            clips.forEach { clip -> array.put(clip.toJson()) }
        })
}

private fun JSONObject.toDraftProject(): DraftProject {
    val clipsArray = optJSONArray("clips") ?: JSONArray()
    return DraftProject(
        projectId = optString("projectId").takeIf { it.isNotBlank() }
            ?: UUID.randomUUID().toString(),
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
        outputQualityPreset = enumValueOrDefault(
            optString("outputQualityPreset"),
            OutputQualityPreset.Standard
        ),
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
        originalAudioVolume = optDouble("originalAudioVolume", 1.0),
        backgroundMusicLoopsToFillVideo = optBoolean("backgroundMusicLoopsToFillVideo", true),
        backgroundMusicFadeInEnabled = optBoolean("backgroundMusicFadeInEnabled", true),
        backgroundMusicFadeOutEnabled = optBoolean("backgroundMusicFadeOutEnabled", true),
        savedAtMillis = optLong("savedAtMillis", System.currentTimeMillis())
    )
}

data class EditableProjectSummary(
    val projectId: String,
    val preset: MoviePreset,
    val clipCount: Int,
    val totalDurationSeconds: Double,
    val outputAspectRatio: OutputAspectRatio?,
    val outputQualityPreset: OutputQualityPreset,
    val savedAtMillis: Long,
    val isPinned: Boolean,
    val memo: String,
    val thumbnailUri: Uri?
)

enum class EditableProjectPinResult {
    Toggled,
    LimitReached,
    Missing
}

object EditableProjectStore {
    private const val PreferencesName = "hanclip_editable_projects"
    private const val ProjectsKey = "projects"
    private const val ProjectsDirectoryName = "editable-projects"
    private const val ProjectMetadataFilename = "project.json"
    private const val MediaDirectoryName = "media"
    const val MaximumProjectCount = 10
    const val MaximumAiShotProjectCount = 2
    const val MaximumPinnedProjectCount = 5

    fun upsert(context: Context, project: DraftProject): DraftProject {
        val records = loadRecords(context).toMutableList()
        val existingIndex = records.indexOfFirst { it.project.projectId == project.projectId }
        val existing = records.getOrNull(existingIndex)
        val record = EditableProjectRecord(
            project = persistProjectMedia(
                context,
                project.copy(savedAtMillis = System.currentTimeMillis())
            ),
            isPinned = existing?.isPinned ?: false,
            memo = existing?.memo.orEmpty()
        )
        if (existingIndex >= 0) records[existingIndex] = record else records += record
        saveRecords(context, enforceLimits(records))
        return load(context, project.projectId) ?: record.project
    }

    fun load(context: Context, projectId: String): DraftProject? {
        return loadRecords(context).firstOrNull { it.project.projectId == projectId }?.project
    }

    fun list(context: Context): List<EditableProjectSummary> {
        return loadRecords(context)
            .sortedWith(
                compareByDescending<EditableProjectRecord> { it.isPinned }
                    .thenByDescending { it.project.savedAtMillis }
            )
            .map { record ->
                EditableProjectSummary(
                    projectId = record.project.projectId,
                    preset = record.project.preset,
                    clipCount = record.project.clips.count { it.isRenderableClip },
                    totalDurationSeconds = record.project.clips
                        .filter { it.isRenderableClip }
                        .sumOf { it.durationSeconds },
                    outputAspectRatio = record.project.outputAspectRatio,
                    outputQualityPreset = record.project.outputQualityPreset,
                    savedAtMillis = record.project.savedAtMillis,
                    isPinned = record.isPinned,
                    memo = record.memo,
                    thumbnailUri = record.project.clips
                        .firstOrNull { it.isRenderableClip }
                        ?.thumbnailUri
                )
            }
    }

    fun remove(context: Context, projectId: String) {
        saveRecords(context, loadRecords(context).filterNot { it.project.projectId == projectId })
    }

    fun updateMemo(context: Context, projectId: String, memo: String) {
        saveRecords(
            context,
            loadRecords(context).map { record ->
                if (record.project.projectId == projectId) record.copy(memo = memo.trim()) else record
            }
        )
    }

    fun togglePinned(context: Context, projectId: String): EditableProjectPinResult {
        val records = loadRecords(context)
        val target = records.firstOrNull { it.project.projectId == projectId }
            ?: return EditableProjectPinResult.Missing
        if (!target.isPinned && records.count { it.isPinned } >= MaximumPinnedProjectCount) {
            return EditableProjectPinResult.LimitReached
        }
        saveRecords(
            context,
            records.map { record ->
                if (record.project.projectId == projectId) record.copy(isPinned = !record.isPinned) else record
            }
        )
        return EditableProjectPinResult.Toggled
    }

    private fun enforceLimits(records: List<EditableProjectRecord>): List<EditableProjectRecord> {
        var kept = records.toMutableList()
        fun removeOldestUnpinned(candidates: List<EditableProjectRecord>): Boolean {
            val target = candidates.filterNot { it.isPinned }.minByOrNull { it.project.savedAtMillis }
                ?: candidates.minByOrNull { it.project.savedAtMillis }
                ?: return false
            kept.removeAll { it.project.projectId == target.project.projectId }
            return true
        }
        while (kept.count { it.project.preset == MoviePreset.AiShot } > MaximumAiShotProjectCount) {
            val oldestAiShot = kept
                .filter { it.project.preset == MoviePreset.AiShot }
                .minByOrNull { it.project.savedAtMillis }
                ?: break
            kept.removeAll { it.project.projectId == oldestAiShot.project.projectId }
        }
        while (kept.size > MaximumProjectCount) {
            if (!removeOldestUnpinned(kept)) break
        }
        return kept
    }

    private fun loadRecords(context: Context): List<EditableProjectRecord> {
        val storedRecords = loadFileRecords(context)
        if (storedRecords.isNotEmpty()) return storedRecords

        val legacyRecords = loadLegacyRecords(context)
        if (legacyRecords.isNotEmpty()) {
            saveRecords(context, legacyRecords)
            return loadFileRecords(context)
        }
        return emptyList()
    }

    private fun loadFileRecords(context: Context): List<EditableProjectRecord> {
        return projectsRoot(context).listFiles()
            ?.filter { it.isDirectory }
            ?.mapNotNull { directory ->
                runCatching {
                    val json = JSONObject(File(directory, ProjectMetadataFilename).readText())
                    EditableProjectRecord(
                        project = json.getJSONObject("project").toDraftProject(),
                        isPinned = json.optBoolean("isPinned", false),
                        memo = json.optString("memo", "")
                    )
                }.getOrNull()
            }
            .orEmpty()
    }

    private fun loadLegacyRecords(context: Context): List<EditableProjectRecord> {
        val raw = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .getString(ProjectsKey, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            List(array.length()) { index ->
                val json = array.getJSONObject(index)
                EditableProjectRecord(
                    project = json.getJSONObject("project").toDraftProject(),
                    isPinned = json.optBoolean("isPinned", false),
                    memo = json.optString("memo", "")
                )
            }
        }.getOrDefault(emptyList())
    }

    private fun saveRecords(context: Context, records: List<EditableProjectRecord>) {
        val root = projectsRoot(context)
        val keptDirectoryNames = records.map { safeProjectDirectoryName(it.project.projectId) }.toSet()
        root.listFiles()
            ?.filter { it.isDirectory && it.name !in keptDirectoryNames }
            ?.forEach { directory -> runCatching { directory.deleteRecursively() } }

        records.forEach { originalRecord ->
            val record = originalRecord.copy(
                project = persistProjectMedia(context, originalRecord.project)
            )
            val directory = projectDirectory(context, record.project.projectId).apply { mkdirs() }
            val metadata = JSONObject()
                .put("project", record.project.toJson())
                .put("isPinned", record.isPinned)
                .put("memo", record.memo)
            val destination = File(directory, ProjectMetadataFilename)
            val staging = File(directory, "$ProjectMetadataFilename.tmp")
            staging.writeText(metadata.toString())
            if (!staging.renameTo(destination)) {
                staging.copyTo(destination, overwrite = true)
                staging.delete()
            }
        }
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .remove(ProjectsKey)
            .apply()
    }

    private fun persistProjectMedia(context: Context, project: DraftProject): DraftProject {
        val directory = File(projectDirectory(context, project.projectId), MediaDirectoryName)
            .apply { mkdirs() }
        val persistedSources = mutableMapOf<String, Uri>()
        val clips = project.clips.map { clip ->
            val source = persistedSources.getOrPut(clip.sourceUri.toString()) {
                persistProjectUri(
                    context = context,
                    source = clip.sourceUri,
                    destination = File(
                        directory,
                        "source-${safeFilename(clip.id)}.${fileExtension(clip.sourceUri, clip.mediaKind)}"
                    )
                )
            }
            val thumbnail = ensureProjectThumbnail(
                source = source,
                mediaKind = clip.mediaKind,
                destination = File(directory, "thumbnail-${safeFilename(clip.id)}.jpg")
            )
            clip.copy(sourceUri = source, thumbnailUri = thumbnail)
        }
        val musicUri = project.backgroundMusicUri?.let { source ->
            persistProjectUri(
                context = context,
                source = source,
                destination = File(directory, "background-music.${fileExtension(source, null)}")
            )
        }
        return project.copy(clips = clips, backgroundMusicUri = musicUri)
    }

    private fun ensureProjectThumbnail(
        source: Uri,
        mediaKind: ClipMediaKind,
        destination: File
    ): Uri? {
        if (destination.isFile && destination.length() > 0L) return Uri.fromFile(destination)
        val sourcePath = source.takeIf { it.scheme == "file" }?.path ?: return null
        val decoded = runCatching {
            if (mediaKind == ClipMediaKind.Video) {
                MediaMetadataRetriever().let { retriever ->
                    try {
                        retriever.setDataSource(sourcePath)
                        retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    } finally {
                        retriever.release()
                    }
                }
            } else {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(sourcePath, bounds)
                val longest = maxOf(bounds.outWidth, bounds.outHeight).coerceAtLeast(1)
                var sampleSize = 1
                while (longest / (sampleSize * 2) >= ProjectThumbnailLongEdgePx) sampleSize *= 2
                BitmapFactory.decodeFile(
                    sourcePath,
                    BitmapFactory.Options().apply { inSampleSize = sampleSize }
                )
            }
        }.getOrNull() ?: return null
        val thumbnail = decoded.scaledToLongEdge(ProjectThumbnailLongEdgePx)
        return runCatching {
            destination.parentFile?.mkdirs()
            destination.outputStream().use { output ->
                check(thumbnail.compress(Bitmap.CompressFormat.JPEG, 84, output))
            }
            Uri.fromFile(destination)
        }.getOrNull().also {
            if (thumbnail !== decoded) thumbnail.recycle()
            decoded.recycle()
        }
    }

    private fun Bitmap.scaledToLongEdge(targetLongEdge: Int): Bitmap {
        val longest = maxOf(width, height)
        if (longest <= targetLongEdge) return this
        val scale = targetLongEdge.toFloat() / longest.toFloat()
        return Bitmap.createScaledBitmap(
            this,
            (width * scale).toInt().coerceAtLeast(1),
            (height * scale).toInt().coerceAtLeast(1),
            true
        )
    }

    private fun persistProjectUri(context: Context, source: Uri, destination: File): Uri {
        if (source.scheme == "sample") return source
        val sourceFile = source.takeIf { it.scheme == "file" }?.path?.let(::File)
        if (sourceFile?.canonicalPath == destination.canonicalPath) return Uri.fromFile(destination)
        if (destination.isFile && destination.length() > 0L) return Uri.fromFile(destination)
        destination.parentFile?.mkdirs()
        if (sourceFile?.isFile == true) {
            runCatching { Files.createLink(destination.toPath(), sourceFile.toPath()) }
                .recoverCatching { sourceFile.copyTo(destination, overwrite = true) }
                .getOrThrow()
        } else {
            context.contentResolver.openInputStream(source)?.use { input ->
                destination.outputStream().use(input::copyTo)
            } ?: error("프로젝트 미디어를 열 수 없습니다: $source")
        }
        return Uri.fromFile(destination)
    }

    private fun projectsRoot(context: Context): File {
        return File(context.filesDir, ProjectsDirectoryName).apply { mkdirs() }
    }

    private fun projectDirectory(context: Context, projectId: String): File {
        return File(projectsRoot(context), safeProjectDirectoryName(projectId))
    }

    private fun safeProjectDirectoryName(projectId: String): String = safeFilename(projectId)

    private fun safeFilename(value: String): String {
        return value.replace(Regex("[^A-Za-z0-9._-]"), "_").ifBlank { UUID.randomUUID().toString() }
    }

    private fun fileExtension(uri: Uri, mediaKind: ClipMediaKind?): String {
        return uri.lastPathSegment
            ?.substringAfterLast('.', missingDelimiterValue = "")
            ?.lowercase()
            ?.takeIf { it.matches(Regex("[a-z0-9]{1,5}")) }
            ?: if (mediaKind == ClipMediaKind.Video) "mp4" else "jpg"
    }

    private const val ProjectThumbnailLongEdgePx = 480
}

private data class EditableProjectRecord(
    val project: DraftProject,
    val isPinned: Boolean,
    val memo: String
)

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
        .put("sourceCreatedAtMillis", sourceCreatedAtMillis)
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
        sourceCreatedAtMillis = optNullableLong("sourceCreatedAtMillis"),
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
        .put("address", address)
        .put("platform", platform.storedValue)
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
        address = optString("address", ""),
        platform = WatermarkPlatform.fromStoredValue(optString("platform", "hanclip")),
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

private fun JSONObject.optNullableLong(key: String): Long? {
    if (!has(key) || isNull(key)) return null
    return optLong(key)
}

private inline fun <reified T : Enum<T>> enumValueOrNull(value: String): T? {
    return runCatching { enumValueOf<T>(value) }.getOrNull()
}

private inline fun <reified T : Enum<T>> enumValueOrDefault(value: String, default: T): T {
    return enumValueOrNull<T>(value) ?: default
}
