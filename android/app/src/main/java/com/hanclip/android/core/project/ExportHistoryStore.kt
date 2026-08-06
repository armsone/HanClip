package com.hanclip.android.core.project

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.hanclip.android.core.model.OutputAspectRatio
import com.hanclip.android.core.model.OutputQualityPreset
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class ExportedMovieSummary(
    val uriString: String,
    val title: String,
    val clipCount: Int,
    val totalDurationSeconds: Double,
    val updatedAtMillis: Long,
    val isPinned: Boolean = false,
    val memo: String = "",
    val byteCount: Long = 0L,
    val outputAspectRatio: OutputAspectRatio? = null,
    val outputQualityPreset: OutputQualityPreset? = null,
    val hasBackgroundMusic: Boolean? = null,
    val hasWatermark: Boolean? = null
)

enum class ExportedMoviePinResult {
    Toggled,
    LimitReached,
    NotFound
}

private const val ExportHistoryMaxItems = 10
private const val ExportHistoryMaxAiShotItems = 2
private const val ExportHistoryAiShotTitle = "AiShot"

object ExportHistoryStore {
    private const val PreferencesName = "hanclip_export_history"
    private const val HistoryKey = "items"
    const val MaxPinnedItems = 5

    fun add(
        context: Context,
        outputUri: Uri,
        title: String,
        clipCount: Int,
        totalDurationSeconds: Double,
        outputAspectRatio: OutputAspectRatio? = null,
        outputQualityPreset: OutputQualityPreset? = null,
        hasBackgroundMusic: Boolean? = null,
        hasWatermark: Boolean? = null,
        replaceUri: Uri? = null
    ) {
        if (clipCount <= 0 || totalDurationSeconds <= 0.0) return
        val items = list(context).toMutableList()
        val previousSummary = items.firstOrNull {
            it.uriString == outputUri.toString() || replaceUri?.toString() == it.uriString
        }
        items.removeAll { it.uriString == outputUri.toString() }
        replaceUri?.let { previous ->
            items.removeAll { it.uriString == previous.toString() }
        }
        items.add(
            0,
            ExportedMovieSummary(
                uriString = outputUri.toString(),
                title = title.ifBlank { "HanClip 영화" },
                clipCount = clipCount,
                totalDurationSeconds = totalDurationSeconds,
                updatedAtMillis = System.currentTimeMillis(),
                isPinned = previousSummary?.isPinned ?: false,
                memo = previousSummary?.memo.orEmpty(),
                byteCount = outputUri.byteCount(context),
                outputAspectRatio = outputAspectRatio ?: previousSummary?.outputAspectRatio,
                outputQualityPreset = outputQualityPreset ?: previousSummary?.outputQualityPreset,
                hasBackgroundMusic = hasBackgroundMusic ?: previousSummary?.hasBackgroundMusic,
                hasWatermark = hasWatermark ?: previousSummary?.hasWatermark
            )
        )
        save(context, items.enforceHomeLimits())
    }

    fun list(context: Context): List<ExportedMovieSummary> {
        val raw = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .getString(HistoryKey, "[]")
            .orEmpty()
        return runCatching {
            val array = JSONArray(raw)
            val parsedItems = List(array.length()) { index ->
                val item = array.getJSONObject(index)
                ExportedMovieSummary(
                    uriString = item.getString("uriString"),
                    title = item.optString("title", "HanClip 영화"),
                    clipCount = item.optInt("clipCount", 0),
                    totalDurationSeconds = item.optDouble("totalDurationSeconds", 0.0),
                    updatedAtMillis = item.optLong("updatedAtMillis", 0L),
                    isPinned = item.optBoolean("isPinned", false),
                    memo = item.optString("memo", ""),
                    byteCount = item.optLong("byteCount", 0L),
                    outputAspectRatio = item.optString("outputAspectRatio", "")
                        .takeIf { it.isNotBlank() }
                        ?.let { raw -> enumValueOrNull<OutputAspectRatio>(raw) },
                    outputQualityPreset = item.optString("outputQualityPreset", "")
                        .takeIf { it.isNotBlank() }
                        ?.let { raw -> enumValueOrNull<OutputQualityPreset>(raw) },
                    hasBackgroundMusic = item.optionalBoolean("hasBackgroundMusic"),
                    hasWatermark = item.optionalBoolean("hasWatermark")
                )
            }
                .filter { it.clipCount > 0 && it.totalDurationSeconds > 0.0 }
                .filter { it.isReadableFrom(context) }
                .sortedForHome()
            val backfilledItems = parsedItems.map { summary ->
                if (summary.byteCount > 0L) {
                    summary
                } else {
                    summary.copy(byteCount = summary.uri().byteCount(context))
                }
            }.sortedForHome()
            if (backfilledItems.any { it.byteCount > 0L } && backfilledItems != parsedItems) {
                save(context, backfilledItems)
            }
            backfilledItems
        }.getOrElse { emptyList() }
    }

    fun remove(context: Context, uriString: String) {
        val items = list(context).filterNot { it.uriString == uriString }
        save(context, items)
    }

    fun togglePinned(context: Context, uriString: String): ExportedMoviePinResult {
        val currentItems = list(context)
        val target = currentItems.firstOrNull { it.uriString == uriString }
            ?: return ExportedMoviePinResult.NotFound
        if (!target.isPinned && currentItems.count { it.isPinned } >= MaxPinnedItems) {
            return ExportedMoviePinResult.LimitReached
        }
        val items = currentItems.map { summary ->
            if (summary.uriString == uriString) {
                summary.copy(isPinned = !summary.isPinned)
            } else {
                summary
            }
        }
        save(context, items.sortedForHome())
        return ExportedMoviePinResult.Toggled
    }

    fun updateMemo(context: Context, uriString: String, memo: String) {
        val normalizedMemo = memo.trim().take(80)
        val items = list(context).map { summary ->
            if (summary.uriString == uriString) {
                summary.copy(memo = normalizedMemo)
            } else {
                summary
            }
        }
        save(context, items.sortedForHome())
    }

    private fun save(context: Context, items: List<ExportedMovieSummary>) {
        val array = JSONArray()
        items.forEach { summary ->
            array.put(
                JSONObject()
                    .put("uriString", summary.uriString)
                    .put("title", summary.title)
                    .put("clipCount", summary.clipCount)
                    .put("totalDurationSeconds", summary.totalDurationSeconds)
                    .put("updatedAtMillis", summary.updatedAtMillis)
                    .put("isPinned", summary.isPinned)
                    .put("memo", summary.memo)
                    .put("byteCount", summary.byteCount)
                    .put("outputAspectRatio", summary.outputAspectRatio?.name.orEmpty())
                    .put("outputQualityPreset", summary.outputQualityPreset?.name.orEmpty())
                    .putNullable("hasBackgroundMusic", summary.hasBackgroundMusic)
                    .putNullable("hasWatermark", summary.hasWatermark)
            )
        }
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .putString(HistoryKey, array.toString())
            .apply()
    }
}

private fun Uri.byteCount(context: Context): Long {
    return when (scheme) {
        "file" -> File(path.orEmpty()).length().coerceAtLeast(0L)
        "content" -> {
            val descriptorSize = runCatching {
                context.contentResolver.openAssetFileDescriptor(this, "r")?.use { descriptor ->
                    descriptor.length.takeIf { it > 0L } ?: 0L
                } ?: 0L
            }.getOrDefault(0L)
            if (descriptorSize > 0L) {
                descriptorSize
            } else {
                runCatching {
                    context.contentResolver.query(
                        this,
                        arrayOf(OpenableColumns.SIZE),
                        null,
                        null,
                        null
                    )?.use { cursor ->
                        val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (sizeIndex >= 0 && cursor.moveToFirst()) {
                            cursor.getLong(sizeIndex).coerceAtLeast(0L)
                        } else {
                            0L
                        }
                    } ?: 0L
                }.getOrDefault(0L)
            }
        }
        else -> 0L
    }
}

private fun List<ExportedMovieSummary>.sortedForHome(): List<ExportedMovieSummary> {
    return sortedWith(
        compareByDescending<ExportedMovieSummary> { it.isPinned }
            .thenByDescending { it.updatedAtMillis }
    )
}

private fun List<ExportedMovieSummary>.enforceHomeLimits(): List<ExportedMovieSummary> {
    val limitedItems = toMutableList()
    while (limitedItems.count { it.title == ExportHistoryAiShotTitle } > ExportHistoryMaxAiShotItems) {
        val oldestAiShot = limitedItems
            .filter { it.title == ExportHistoryAiShotTitle }
            .minByOrNull { it.updatedAtMillis }
            ?: break
        limitedItems.remove(oldestAiShot)
    }
    while (limitedItems.size > ExportHistoryMaxItems) {
        val oldestUnpinned = limitedItems
            .filterNot { it.isPinned }
            .minByOrNull { it.updatedAtMillis }
            ?: break
        limitedItems.remove(oldestUnpinned)
    }
    return limitedItems.sortedForHome()
}

private fun ExportedMovieSummary.isReadableFrom(context: Context): Boolean {
    val uri = uri()
    return when (uri.scheme) {
        "file" -> File(uri.path.orEmpty()).exists()
        "content" -> runCatching {
            context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { true } == true
        }.getOrDefault(false)
        else -> uriString.isNotBlank()
    }
}

private fun ExportedMovieSummary.uri(): Uri {
    return runCatching { Uri.parse(uriString) }.getOrNull() ?: Uri.EMPTY
}

private inline fun <reified T : Enum<T>> enumValueOrNull(value: String): T? {
    return enumValues<T>().firstOrNull { it.name == value }
}

private fun JSONObject.optionalBoolean(key: String): Boolean? {
    return if (has(key) && !isNull(key)) {
        optBoolean(key)
    } else {
        null
    }
}

private fun JSONObject.putNullable(key: String, value: Boolean?): JSONObject {
    return if (value == null) {
        put(key, JSONObject.NULL)
    } else {
        put(key, value)
    }
}
