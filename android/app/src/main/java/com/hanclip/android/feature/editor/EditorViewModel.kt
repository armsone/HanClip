package com.hanclip.android.feature.editor

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.hanclip.android.core.media.MediaImportReader
import com.hanclip.android.core.media.Media3TransformerExportService
import com.hanclip.android.core.media.VideoExportRequest
import com.hanclip.android.core.model.BackgroundMusicSample
import com.hanclip.android.core.model.ClipItem
import com.hanclip.android.core.model.ClipMediaKind
import com.hanclip.android.core.model.MoviePreset
import com.hanclip.android.core.model.OutputAspectRatio
import com.hanclip.android.core.model.WatermarkFontSize
import com.hanclip.android.core.model.WatermarkLineSpacing
import com.hanclip.android.core.model.WatermarkPosition
import com.hanclip.android.core.model.WatermarkSettings
import com.hanclip.android.core.model.VideoSegmentMode
import com.hanclip.android.core.project.DraftProject
import com.hanclip.android.core.project.DraftProjectStore
import com.hanclip.android.core.project.EditorPreferenceStore
import com.hanclip.android.core.project.ExportHistoryStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

data class EditorUiState(
    val clips: List<ClipItem> = emptyList(),
    val preset: MoviePreset = MoviePreset.NewMovie,
    val defaultDurationSeconds: Double = 3.0,
    val defaultVideoSegmentMode: VideoSegmentMode = VideoSegmentMode.Single,
    val outputAspectRatio: OutputAspectRatio? = null,
    val watermarkSettings: WatermarkSettings = WatermarkSettings(),
    val isImportingMedia: Boolean = false,
    val importedMediaCount: Int = 0,
    val backgroundMusicUri: Uri? = null,
    val backgroundMusicTitle: String? = null,
    val backgroundMusicSampleId: String? = null,
    val backgroundMusicVolume: Double = 0.35,
    val originalAudioVolume: Double = 1.0,
    val isExporting: Boolean = false,
    val exportedVideoUri: Uri? = null,
    val recentlySavedMovieUriString: String? = null,
    val progressMessage: String = "",
    val alertMessage: String? = null,
    val undoDeleteMessage: String? = null,
    val expandedSimilarPhotoGroupIds: Set<String> = emptySet()
) {
    val renderableClips: List<ClipItem>
        get() = clips.filter { it.isRenderableClip }

    val visibleClips: List<ClipItem>
        get() = clips.filter { clip ->
            if (clip.isSimilarPhotoGroupMember) {
                clip.similarPhotoGroupId in expandedSimilarPhotoGroupIds
            } else {
                true
            }
        }

    val totalDurationSeconds: Double
        get() = renderableClips.sumOf { it.durationSeconds }
}

class EditorViewModel : ViewModel() {
    private val _uiState = MutableStateFlow(EditorUiState())
    val uiState: StateFlow<EditorUiState> = _uiState.asStateFlow()
    private var exportJob: Job? = null
    private var lastDeleteSnapshot: DeleteUndoSnapshot? = null

    fun openPreset(context: Context, preset: MoviePreset) {
        _uiState.update {
            if (it.preset == preset && it.clips.isNotEmpty()) {
                return@update it
            }
            presetInitialState(context.applicationContext, preset)
        }
    }

    fun startNewPreset(context: Context, preset: MoviePreset) {
        _uiState.value = presetInitialState(context.applicationContext, preset)
    }

    fun addPickedMedia(context: Context, uris: List<Uri>) {
        if (uris.isEmpty()) return

        viewModelScope.launch {
            val appContext = context.applicationContext
            _uiState.update {
                it.copy(
                    isImportingMedia = true,
                    progressMessage = "선택한 미디어 ${uris.size}개를 불러오는 중...",
                    alertMessage = null
                )
            }

            val state = _uiState.value
            val imported = mutableListOf<ClipItem>()
            uris.forEachIndexed { index, uri ->
                _uiState.update {
                    it.copy(
                        progressMessage = "미디어 ${index + 1}/${uris.size}개를 불러오는 중..."
                    )
                }
                runCatching {
                    MediaImportReader.makeClip(
                        context = appContext,
                        uri = uri,
                        defaultDurationSeconds = state.defaultDurationSeconds,
                        defaultVideoSegmentMode = state.defaultVideoSegmentMode
                    )
                }.onSuccess { clip ->
                    imported += clip
                }
            }

            _uiState.update {
                if (imported.isEmpty()) {
                    it.copy(
                        isImportingMedia = false,
                        progressMessage = "",
                        alertMessage = "선택한 미디어를 불러오지 못했습니다."
                    )
                } else {
                    val failedCount = uris.size - imported.size
                    val shouldReplaceSamples = it.importedMediaCount == 0
                        && it.clips.all { clip -> clip.sourceUri.scheme == "sample" }
                    val expandedImported = imported.flatMap { clip ->
                        expandImportedClipForPreset(
                            clip = clip,
                            defaultDurationSeconds = it.defaultDurationSeconds,
                            defaultVideoSegmentMode = it.defaultVideoSegmentMode
                        )
                    }
                    val groupedImported = applySimilarPhotoGrouping(expandedImported)
                    val hiddenSimilarPhotoCount = groupedImported.count { clip ->
                        clip.isSimilarPhotoGroupMember
                    }
                    it.copy(
                        clips = if (shouldReplaceSamples) groupedImported else it.clips + groupedImported,
                        isImportingMedia = false,
                        importedMediaCount = it.importedMediaCount + groupedImported.count { clip -> clip.isRenderableClip },
                        progressMessage = "",
                        alertMessage = if (failedCount > 0) {
                            "선택한 ${uris.size}개 중 ${imported.size}개를 가져왔습니다. ${failedCount}개는 지원하지 않거나 읽을 수 없습니다."
                        } else if (hiddenSimilarPhotoCount > 0) {
                            "미디어 ${imported.size}개를 가져왔습니다. 비슷한 사진 ${hiddenSimilarPhotoCount}개는 대표 컷 뒤에 묶었습니다."
                        } else {
                            null
                        }
                    )
                }
            }
        }
    }

    fun exportMovie(context: Context, onExported: () -> Unit) {
        if (exportJob?.isActive == true) return
        val state = _uiState.value
        val clips = state.renderableClips.filter { it.sourceUri.scheme != "sample" }
        if (clips.isEmpty()) {
            _uiState.update {
                it.copy(alertMessage = "실제 사진이나 영상을 먼저 선택해 주세요.")
            }
            return
        }

        exportJob = viewModelScope.launch {
            val renderSize = state.outputAspectRatio?.let { it.width to it.height }
                ?: OutputAspectRatio.automaticSize(
                    clips.firstOrNull()?.sourceWidth ?: 1080,
                    clips.firstOrNull()?.sourceHeight ?: 1920
                )
            val exportLabel = "${clips.size}개 클립 · ${renderSize.first}x${renderSize.second}"
            _uiState.update {
                it.copy(
                    isExporting = true,
                    progressMessage = "영화를 만드는 중... $exportLabel",
                    alertMessage = null
                )
            }
            runCatching {
                Media3TransformerExportService(context.applicationContext).export(
                    VideoExportRequest(
                        clips = clips,
                        renderWidth = renderSize.first,
                        renderHeight = renderSize.second,
                        watermarkSettings = state.watermarkSettings,
                        backgroundMusicUri = state.backgroundMusicUri,
                        backgroundMusicVolume = state.backgroundMusicVolume,
                        originalAudioVolume = state.originalAudioVolume
                    )
                ) { progress ->
                    _uiState.update {
                        it.copy(
                            progressMessage = "영화를 만드는 중... ${(progress * 100).toInt()}% · $exportLabel"
                        )
                    }
                }
            }.onSuccess { outputUri ->
                ExportHistoryStore.add(
                    context = context.applicationContext,
                    outputUri = outputUri,
                    title = state.preset.title,
                    clipCount = clips.size,
                    totalDurationSeconds = clips.sumOf { it.durationSeconds },
                    outputAspectRatio = state.outputAspectRatio,
                    hasBackgroundMusic = state.backgroundMusicUri != null ||
                        state.backgroundMusicSampleId != null,
                    hasWatermark = state.watermarkSettings.shouldRender
                )
                _uiState.update {
                    it.copy(
                        isExporting = false,
                        exportedVideoUri = outputUri,
                        recentlySavedMovieUriString = outputUri.toString(),
                        progressMessage = "",
                        alertMessage = null
                    )
                }
                onExported()
            }.onFailure { error ->
                val message = if (error is CancellationException) {
                    "영화 만들기를 취소했습니다."
                } else if (error is IllegalStateException || error is IllegalArgumentException) {
                    error.message?.takeIf { it.isNotBlank() }
                        ?: "선택한 구간에서 영상을 만들 수 없습니다. 클립 시간을 다시 조절해 주세요."
                } else {
                    "영화를 만들지 못했습니다. 사진/영상 파일을 다시 선택한 뒤 시도해 주세요."
                }
                _uiState.update {
                    it.copy(
                        isExporting = false,
                        progressMessage = "",
                        alertMessage = message
                    )
                }
            }
        }
    }

    fun cancelExport() {
        exportJob?.cancel()
        exportJob = null
        _uiState.update {
            if (!it.isExporting) {
                it
            } else {
                it.copy(
                    isExporting = false,
                    progressMessage = "",
                    alertMessage = "영화 만들기를 취소했습니다."
                )
            }
        }
    }

    fun setDefaultDuration(context: Context, seconds: Double) {
        EditorPreferenceStore.saveDefaultDurationSeconds(context.applicationContext, seconds)
        _uiState.update {
            it.copy(defaultDurationSeconds = seconds.coerceIn(0.5, 30.0))
        }
    }

    fun applyDefaultDurationToAll() {
        _uiState.update { state ->
            state.copy(
                clips = state.clips.map { clip ->
                    if (clip.mediaKind == ClipMediaKind.Video) {
                        val sourceDuration = clip.sourceDurationSeconds ?: clip.durationSeconds
                        val selectedDuration = min(state.defaultDurationSeconds, sourceDuration)
                        val center = clip.trimStartSeconds + clip.durationSeconds / 2.0
                        clip.copy(
                            durationSeconds = selectedDuration,
                            photoDurationSeconds = selectedDuration,
                            trimStartSeconds = max(
                                0.0,
                                min(sourceDuration - selectedDuration, center - selectedDuration / 2.0)
                            )
                        )
                    } else {
                        clip.copy(
                            durationSeconds = state.defaultDurationSeconds,
                            photoDurationSeconds = state.defaultDurationSeconds,
                            trimStartSeconds = 0.0
                        )
                    }
                }
            )
        }
    }

    fun selectAspectRatio(context: Context, ratio: OutputAspectRatio?) {
        EditorPreferenceStore.saveOutputAspectRatio(context.applicationContext, ratio)
        _uiState.update { it.copy(outputAspectRatio = ratio) }
    }

    fun prepareAiCutImport() {
        _uiState.update {
            it.copy(
                defaultVideoSegmentMode = VideoSegmentMode.Multiple,
                alertMessage = null
            )
        }
    }

    fun updateWatermark(settings: WatermarkSettings) {
        _uiState.update { it.copy(watermarkSettings = settings) }
    }

    fun setBackgroundMusic(context: Context, uri: Uri?) {
        val appContext = context.applicationContext
        val storedUri = uri?.let { musicUri ->
            persistBackgroundMusic(appContext, musicUri)
        }
        _uiState.update {
            it.copy(
                backgroundMusicUri = storedUri,
                backgroundMusicTitle = uri?.let { musicUri ->
                    displayNameForUri(appContext, musicUri)
                },
                backgroundMusicSampleId = null,
                backgroundMusicVolume = 0.35,
                alertMessage = if (uri == null) "음악을 제거했습니다." else "배경 음악을 선택했습니다."
            )
        }
    }

    fun useSampleBackgroundMusic(context: Context, sample: BackgroundMusicSample) {
        _uiState.update {
            it.copy(
                backgroundMusicUri = sampleBackgroundMusicUri(context.applicationContext, sample),
                backgroundMusicTitle = sample.title,
                backgroundMusicSampleId = sample.id,
                backgroundMusicVolume = 0.35,
                alertMessage = "${sample.title} 음악을 선택했습니다."
            )
        }
    }

    fun updateBackgroundMusicVolume(volume: Double) {
        _uiState.update {
            it.copy(backgroundMusicVolume = volume.coerceIn(0.0, 1.0))
        }
    }

    fun updateOriginalAudioVolume(volume: Double) {
        _uiState.update {
            it.copy(originalAudioVolume = volume.coerceIn(0.0, 1.0))
        }
    }

    fun removeBackgroundMusic() {
        _uiState.update {
            it.copy(
                backgroundMusicUri = null,
                backgroundMusicTitle = null,
                backgroundMusicSampleId = null,
                backgroundMusicVolume = 0.35,
                alertMessage = "음악을 제거했습니다."
            )
        }
    }

    fun openExportedMovie(uri: Uri) {
        _uiState.update {
            it.copy(exportedVideoUri = uri)
        }
    }

    fun recordSavedMovie(context: Context, uri: Uri) {
        val state = _uiState.value
        val clips = state.renderableClips
        val existingSummary = ExportHistoryStore.list(context.applicationContext)
            .firstOrNull { it.uriString == state.exportedVideoUri?.toString() }
        val clipCount = clips.size.takeIf { it > 0 } ?: existingSummary?.clipCount ?: 0
        val totalDurationSeconds = clips.sumOf { it.durationSeconds }
            .takeIf { it > 0.0 } ?: existingSummary?.totalDurationSeconds ?: 0.0
        ExportHistoryStore.add(
            context = context.applicationContext,
            outputUri = uri,
            title = existingSummary?.title ?: state.preset.title,
            clipCount = clipCount,
            totalDurationSeconds = totalDurationSeconds,
            outputAspectRatio = state.outputAspectRatio ?: existingSummary?.outputAspectRatio,
            hasBackgroundMusic = existingSummary?.hasBackgroundMusic ?: (
                state.backgroundMusicUri != null || state.backgroundMusicSampleId != null
            ),
            hasWatermark = existingSummary?.hasWatermark ?: state.watermarkSettings.shouldRender,
            replaceUri = state.exportedVideoUri
        )
        _uiState.update {
            it.copy(
                exportedVideoUri = uri,
                recentlySavedMovieUriString = uri.toString()
            )
        }
    }

    fun saveDraft(context: Context) {
        val state = _uiState.value
        DraftProjectStore.save(
            context = context.applicationContext,
            project = DraftProject(
                clips = state.clips,
                preset = state.preset,
                defaultDurationSeconds = state.defaultDurationSeconds,
                defaultVideoSegmentMode = state.defaultVideoSegmentMode,
                outputAspectRatio = state.outputAspectRatio,
                watermarkSettings = state.watermarkSettings,
                backgroundMusicUri = state.backgroundMusicUri,
                backgroundMusicTitle = state.backgroundMusicTitle,
                backgroundMusicSampleId = state.backgroundMusicSampleId,
                backgroundMusicVolume = state.backgroundMusicVolume,
                originalAudioVolume = state.originalAudioVolume
            )
        )
    }

    fun openDraft(context: Context): Boolean {
        val draft = DraftProjectStore.load(context.applicationContext) ?: return false
        _uiState.update {
            it.copy(
                clips = draft.clips,
                preset = draft.preset,
                defaultDurationSeconds = draft.defaultDurationSeconds,
                defaultVideoSegmentMode = draft.defaultVideoSegmentMode,
                outputAspectRatio = draft.outputAspectRatio,
                watermarkSettings = draft.watermarkSettings,
                backgroundMusicUri = draft.backgroundMusicUri,
                backgroundMusicTitle = draft.backgroundMusicTitle,
                backgroundMusicSampleId = draft.backgroundMusicSampleId,
                backgroundMusicVolume = draft.backgroundMusicVolume,
                originalAudioVolume = draft.originalAudioVolume,
                importedMediaCount = draft.clips.count { clip -> clip.isRenderableClip },
                alertMessage = null
            )
        }
        return true
    }

    fun clearAlert() {
        _uiState.update { it.copy(alertMessage = null, undoDeleteMessage = null) }
    }

    fun showAlert(message: String) {
        _uiState.update { it.copy(alertMessage = message, undoDeleteMessage = null) }
    }

    fun updatePhotoDuration(id: String, durationSeconds: Double) {
        _uiState.update { state ->
            state.copy(
                clips = state.clips.map { clip ->
                    if (clip.id == id && clip.mediaKind != ClipMediaKind.Video) {
                        clip.copy(
                            durationSeconds = durationSeconds.coerceIn(0.5, 30.0),
                            photoDurationSeconds = durationSeconds.coerceIn(0.5, 30.0),
                            trimStartSeconds = 0.0
                        )
                    } else {
                        clip
                    }
                }
            )
        }
    }

    fun updateVideoTrim(id: String, startSeconds: Double, durationSeconds: Double) {
        _uiState.update { state ->
            state.copy(
                clips = state.clips.map { clip ->
                    if (clip.id != id || clip.mediaKind != ClipMediaKind.Video) {
                        clip
                    } else {
                        val sourceDuration = clip.sourceDurationSeconds ?: clip.durationSeconds
                        val safeDuration = min(sourceDuration, max(0.5, durationSeconds))
                        clip.copy(
                            durationSeconds = safeDuration,
                            photoDurationSeconds = safeDuration,
                            trimStartSeconds = max(
                                0.0,
                                min(sourceDuration - safeDuration, startSeconds)
                            )
                        )
                    }
                }
            )
        }
    }

    fun adjustClipDuration(id: String, deltaSeconds: Double) {
        _uiState.update { state ->
            state.copy(
                clips = state.clips.map { clip ->
                    if (clip.id != id) {
                        clip
                    } else if (clip.mediaKind == ClipMediaKind.Video) {
                        val sourceDuration = clip.sourceDurationSeconds ?: clip.durationSeconds
                        val center = clip.trimStartSeconds + clip.durationSeconds / 2.0
                        val newDuration = min(sourceDuration, max(0.5, clip.durationSeconds + deltaSeconds))
                        clip.copy(
                            durationSeconds = newDuration,
                            photoDurationSeconds = newDuration,
                            trimStartSeconds = max(
                                0.0,
                                min(sourceDuration - newDuration, center - newDuration / 2.0)
                            )
                        )
                    } else {
                        val newDuration = max(0.5, clip.durationSeconds + deltaSeconds)
                        clip.copy(
                            durationSeconds = newDuration,
                            photoDurationSeconds = newDuration,
                            trimStartSeconds = 0.0
                        )
                    }
                }
            )
        }
    }

    fun selectFullRangeForAllVideoClips() {
        _uiState.update { state ->
            state.copy(
                clips = state.clips.map { clip ->
                    if (clip.mediaKind == ClipMediaKind.Video) {
                        val sourceDuration = clip.sourceDurationSeconds ?: clip.durationSeconds
                        clip.copy(
                            durationSeconds = sourceDuration,
                            photoDurationSeconds = sourceDuration,
                            trimStartSeconds = 0.0,
                            videoSegmentMode = VideoSegmentMode.Single
                        )
                    } else {
                        clip.copy(
                            durationSeconds = state.defaultDurationSeconds,
                            photoDurationSeconds = state.defaultDurationSeconds,
                            trimStartSeconds = 0.0
                        )
                    }
                },
                defaultVideoSegmentMode = VideoSegmentMode.Single
            )
        }
    }

    fun toggleVideoSegmentMode(id: String) {
        _uiState.update { state ->
            val index = state.clips.indexOfFirst { it.id == id }
            if (index == -1) return@update state

            val clip = state.clips[index]
            if (clip.mediaKind != ClipMediaKind.Video || clip.isVideoSegmentChild) {
                return@update state
            }

            if (clip.videoSegmentMode == VideoSegmentMode.Multiple || clip.isVideoSegmentParent) {
                val singleClip = clip.copy(
                    videoSegmentMode = VideoSegmentMode.Single,
                    isVideoSegmentParent = false,
                    videoSegmentParentId = null,
                    durationSeconds = min(
                        state.defaultDurationSeconds,
                        clip.sourceDurationSeconds ?: clip.durationSeconds
                    ).coerceAtLeast(0.5),
                    photoDurationSeconds = min(
                        state.defaultDurationSeconds,
                        clip.sourceDurationSeconds ?: clip.durationSeconds
                    ).coerceAtLeast(0.5),
                    trimStartSeconds = centeredTrimStart(
                        clip = clip,
                        selectedDuration = min(
                            state.defaultDurationSeconds,
                            clip.sourceDurationSeconds ?: clip.durationSeconds
                        ).coerceAtLeast(0.5)
                    )
                )
                return@update state.copy(
                    clips = state.clips
                        .filterNot { it.videoSegmentParentId == clip.id }
                        .map { if (it.id == clip.id) singleClip else it }
                )
            }

            val split = expandImportedClipForPreset(
                clip = clip,
                defaultDurationSeconds = state.defaultDurationSeconds,
                defaultVideoSegmentMode = VideoSegmentMode.Multiple
            )
            if (split.size <= 1) {
                return@update state.copy(
                    alertMessage = "이 영상에서 나눌 수 있는 추가 사운드 피크를 찾지 못했습니다.",
                    clips = state.clips.map {
                        if (it.id == clip.id) it.copy(videoSegmentMode = VideoSegmentMode.Single) else it
                    }
                )
            }

            val mutable = state.clips
                .filterNot { it.videoSegmentParentId == clip.id }
                .toMutableList()
            mutable.removeAt(index)
            mutable.addAll(index, split)
            state.copy(clips = mutable, alertMessage = null)
        }
    }

    fun resetVideoSegments(id: String) {
        _uiState.update { state ->
            val index = state.clips.indexOfFirst { it.id == id }
            val clip = state.clips.getOrNull(index)
            if (clip == null || clip.mediaKind != ClipMediaKind.Video || clip.isVideoSegmentChild) {
                return@update state
            }

            val sourceDuration = clip.sourceDurationSeconds ?: clip.durationSeconds
            val selectedDuration = min(state.defaultDurationSeconds, sourceDuration).coerceAtLeast(0.5)
            val baseClip = clip.copy(
                videoSegmentMode = VideoSegmentMode.Single,
                isVideoSegmentParent = false,
                videoSegmentParentId = null,
                durationSeconds = selectedDuration,
                photoDurationSeconds = selectedDuration,
                trimStartSeconds = centeredTrimStart(clip, selectedDuration)
            )
            val split = expandImportedClipForPreset(
                clip = baseClip,
                defaultDurationSeconds = state.defaultDurationSeconds,
                defaultVideoSegmentMode = VideoSegmentMode.Multiple
            )

            if (split.size <= 1) {
                return@update state.copy(
                    alertMessage = "이 영상에서 다시 나눌 수 있는 사운드 피크를 찾지 못했습니다."
                )
            }

            val mutable = state.clips
                .filterNot { it.videoSegmentParentId == clip.id }
                .toMutableList()
            val parentIndex = mutable.indexOfFirst { it.id == clip.id }
            if (parentIndex == -1) {
                return@update state
            }
            mutable.removeAt(parentIndex)
            mutable.addAll(parentIndex, split)
            state.copy(clips = mutable, alertMessage = "자동 컷을 %.1f초 기준으로 다시 만들었습니다.".format(selectedDuration))
        }
    }

    fun removeClip(id: String) {
        _uiState.update { state ->
            val removedClip = state.clips.firstOrNull { it.id == id }
                ?: return@update state
            val removedGroupId = removedClip.similarPhotoGroupId
            val nextClips = state.clips.filterNot { clip ->
                clip.id == id || clip.videoSegmentParentId == id
            }
            val rebalanced = removedGroupId?.let { rebalanceSimilarPhotoGroup(nextClips, it) } ?: nextClips
            lastDeleteSnapshot = DeleteUndoSnapshot(
                clips = state.clips,
                importedMediaCount = state.importedMediaCount,
                expandedSimilarPhotoGroupIds = state.expandedSimilarPhotoGroupIds
            )
            val removedCount = state.clips.size - rebalanced.size
            state.copy(
                clips = rebalanced,
                importedMediaCount = rebalanced.count { it.isRenderableClip },
                expandedSimilarPhotoGroupIds = state.expandedSimilarPhotoGroupIds
                    .filter { groupId -> rebalanced.any { it.similarPhotoGroupId == groupId } }
                    .toSet(),
                alertMessage = if (removedCount > 1) {
                    "클립 ${removedCount}개를 삭제했습니다."
                } else {
                    "클립을 삭제했습니다."
                },
                undoDeleteMessage = "방금 삭제한 클립을 되돌릴 수 있습니다."
            )
        }
    }

    fun undoLastDelete() {
        val snapshot = lastDeleteSnapshot ?: return
        lastDeleteSnapshot = null
        _uiState.update {
            it.copy(
                clips = snapshot.clips,
                importedMediaCount = snapshot.importedMediaCount,
                expandedSimilarPhotoGroupIds = snapshot.expandedSimilarPhotoGroupIds,
                alertMessage = "삭제를 되돌렸습니다.",
                undoDeleteMessage = null
            )
        }
    }

    fun toggleSimilarPhotoGroup(id: String) {
        _uiState.update { state ->
            val groupId = state.clips.firstOrNull { it.id == id }?.similarPhotoGroupId
                ?: return@update state
            state.copy(
                expandedSimilarPhotoGroupIds = if (groupId in state.expandedSimilarPhotoGroupIds) {
                    state.expandedSimilarPhotoGroupIds - groupId
                } else {
                    state.expandedSimilarPhotoGroupIds + groupId
                }
            )
        }
    }

    fun includeSimilarPhoto(id: String) {
        _uiState.update { state ->
            val target = state.clips.firstOrNull { it.id == id }
            val groupId = target?.similarPhotoGroupId ?: return@update state
            val detached = state.clips.map { clip ->
                if (clip.id == id) {
                    clip.copy(
                        similarPhotoGroupId = null,
                        similarPhotoGroupIndex = 0,
                        similarPhotoGroupCount = 1,
                        isSimilarPhotoGroupRepresentative = true
                    )
                } else {
                    clip
                }
            }
            val rebalanced = rebalanceSimilarPhotoGroup(detached, groupId)
            state.copy(
                clips = rebalanced,
                importedMediaCount = rebalanced.count { it.isRenderableClip },
                expandedSimilarPhotoGroupIds = state.expandedSimilarPhotoGroupIds
                    .filter { expandedGroupId -> rebalanced.any { it.similarPhotoGroupId == expandedGroupId } }
                    .toSet(),
                alertMessage = "선택한 사진을 영상에 함께 사용합니다."
            )
        }
    }

    private fun centeredTrimStart(clip: ClipItem, selectedDuration: Double): Double {
        val sourceDuration = clip.sourceDurationSeconds ?: clip.durationSeconds
        val center = clip.audioPeakTimeSeconds
            ?: (clip.trimStartSeconds + clip.durationSeconds / 2.0)
        return max(
            0.0,
            min(sourceDuration - selectedDuration, center - selectedDuration / 2.0)
        )
    }

    fun resetProject(context: Context) {
        DraftProjectStore.clear(context.applicationContext)
        _uiState.update { state ->
            state.copy(
                clips = emptyList(),
                importedMediaCount = 0,
                exportedVideoUri = null,
                progressMessage = "",
                alertMessage = "현재 영화를 초기화했습니다."
            )
        }
    }

    fun moveClipUp(id: String) {
        _uiState.update { state ->
            val index = state.clips.indexOfFirst { it.id == id }
            if (index <= 0) {
                state
            } else {
                state.copy(clips = moveClipGroup(state.clips, index, -1))
            }
        }
    }

    fun moveClipDown(id: String) {
        _uiState.update { state ->
            val index = state.clips.indexOfFirst { it.id == id }
            if (index == -1 || index >= state.clips.lastIndex) {
                state
            } else {
                state.copy(clips = moveClipGroup(state.clips, index, 1))
            }
        }
    }

    private fun moveClipGroup(
        clips: List<ClipItem>,
        index: Int,
        direction: Int
    ): List<ClipItem> {
        val clip = clips.getOrNull(index) ?: return clips
        if (clip.isVideoSegmentChild) {
            return moveSegmentChild(clips, index, direction)
        }

        val movingRange = if (clip.isVideoSegmentParent) {
            index..clips.indexOfLast { it.id == clip.id || it.videoSegmentParentId == clip.id }
        } else if (clip.similarPhotoGroupId != null) {
            val groupId = clip.similarPhotoGroupId
            val first = clips.indexOfFirst { it.similarPhotoGroupId == groupId }
            val last = clips.indexOfLast { it.similarPhotoGroupId == groupId }
            first..last
        } else {
            index..index
        }
        if (movingRange.first < 0 || movingRange.last < movingRange.first) return clips

        val mutable = clips.toMutableList()
        val moving = mutable.subList(movingRange.first, movingRange.last + 1).toList()
        repeat(moving.size) {
            mutable.removeAt(movingRange.first)
        }

        val targetIndex = if (direction < 0) {
            previousGroupStart(mutable, movingRange.first)
        } else {
            nextGroupEnd(mutable, movingRange.first)
        }
        if (targetIndex == movingRange.first) return clips

        val insertIndex = if (direction < 0) targetIndex else targetIndex + 1
        mutable.addAll(insertIndex.coerceIn(0, mutable.size), moving)
        return mutable
    }

    private fun applySimilarPhotoGrouping(clips: List<ClipItem>): List<ClipItem> {
        if (clips.count { canGroupAsSimilarPhoto(it) } <= 1) return clips
        val mutable = clips.map(::clearSimilarPhotoGroup).toMutableList()
        var currentGroup = mutableListOf<Int>()

        fun commitCurrentGroup() {
            if (currentGroup.size <= 1) return
            val groupId = UUID.randomUUID().toString()
            val representativeIndex = currentGroup.maxBy { index ->
                photoRepresentativeScore(mutable[index])
            }
            currentGroup.forEachIndexed { offset, clipIndex ->
                mutable[clipIndex] = mutable[clipIndex].copy(
                    similarPhotoGroupId = groupId,
                    similarPhotoGroupIndex = offset,
                    similarPhotoGroupCount = currentGroup.size,
                    isSimilarPhotoGroupRepresentative = clipIndex == representativeIndex
                )
            }
        }

        mutable.indices.forEach { index ->
            val clip = mutable[index]
            if (!canGroupAsSimilarPhoto(clip)) {
                commitCurrentGroup()
                currentGroup = mutableListOf()
                return@forEach
            }

            val previousIndex = currentGroup.lastOrNull()
            if (previousIndex == null || areSimilarPhotos(mutable[previousIndex], clip)) {
                currentGroup.add(index)
            } else {
                commitCurrentGroup()
                currentGroup = mutableListOf(index)
            }
        }
        commitCurrentGroup()
        return mutable
    }

    private fun clearSimilarPhotoGroup(clip: ClipItem): ClipItem {
        return clip.copy(
            similarPhotoGroupId = null,
            similarPhotoGroupIndex = 0,
            similarPhotoGroupCount = 1,
            isSimilarPhotoGroupRepresentative = true
        )
    }

    private fun canGroupAsSimilarPhoto(clip: ClipItem): Boolean {
        return clip.mediaKind == ClipMediaKind.Photo && clip.photoSimilarityFingerprint.size == 64
    }

    private fun areSimilarPhotos(lhs: ClipItem, rhs: ClipItem): Boolean {
        val aspectDifference = abs(lhs.sourceAspectRatio - rhs.sourceAspectRatio)
        if (aspectDifference > 0.10) return false
        return photoFingerprintDistance(lhs.photoSimilarityFingerprint, rhs.photoSimilarityFingerprint) <= 18.0
    }

    private fun photoFingerprintDistance(lhs: List<Int>, rhs: List<Int>): Double {
        if (lhs.size != rhs.size || lhs.isEmpty()) return Double.POSITIVE_INFINITY
        return lhs.zip(rhs).sumOf { (left, right) -> abs(left - right).toDouble() } / lhs.size
    }

    private fun photoRepresentativeScore(clip: ClipItem): Double {
        val fingerprint = clip.photoSimilarityFingerprint.map(Int::toDouble)
        if (fingerprint.isEmpty()) return 0.0
        val average = fingerprint.sum() / fingerprint.size
        val exposureScore = max(0.0, 1.0 - abs(average - 138.0) / 138.0)
        val contrast = sqrt(
            fingerprint.sumOf { value -> (value - average).pow(2) } / fingerprint.size
        ) / 80.0
        val detail = fingerprint.zip(fingerprint.drop(1)).sumOf { (left, right) ->
            abs(left - right)
        } / max(1, fingerprint.size - 1).toDouble() / 55.0
        return exposureScore * 0.42 + min(1.0, contrast) * 0.34 + min(1.0, detail) * 0.24
    }

    private fun rebalanceSimilarPhotoGroup(clips: List<ClipItem>, groupId: String): List<ClipItem> {
        val groupIndices = clips.indices.filter { clips[it].similarPhotoGroupId == groupId }
        if (groupIndices.size <= 1) {
            return clips.mapIndexed { index, clip ->
                if (index in groupIndices) clearSimilarPhotoGroup(clip) else clip
            }
        }

        val representativeIndex = groupIndices.firstOrNull {
            clips[it].isSimilarPhotoGroupRepresentative
        } ?: groupIndices.maxBy { index ->
            photoRepresentativeScore(clips[index])
        }
        return clips.mapIndexed { index, clip ->
            if (index !in groupIndices) {
                clip
            } else {
                clip.copy(
                    similarPhotoGroupIndex = groupIndices.indexOf(index),
                    similarPhotoGroupCount = groupIndices.size,
                    isSimilarPhotoGroupRepresentative = index == representativeIndex
                )
            }
        }
    }

    private fun moveSegmentChild(
        clips: List<ClipItem>,
        index: Int,
        direction: Int
    ): List<ClipItem> {
        val child = clips[index]
        val parentId = child.videoSegmentParentId ?: return clips
        val targetIndex = if (direction < 0) index - 1 else index + 1
        val target = clips.getOrNull(targetIndex) ?: return clips
        if (target.videoSegmentParentId != parentId) return clips

        val mutable = clips.toMutableList()
        mutable[index] = target
        mutable[targetIndex] = child
        return mutable
    }

    private fun previousGroupStart(clips: List<ClipItem>, insertionPoint: Int): Int {
        if (insertionPoint <= 0) return insertionPoint
        var previousIndex = insertionPoint - 1
        val previous = clips[previousIndex]
        if (previous.isVideoSegmentChild) {
            val parentId = previous.videoSegmentParentId
            previousIndex = clips.indexOfFirst { it.id == parentId }.takeIf { it >= 0 } ?: previousIndex
        } else if (previous.similarPhotoGroupId != null) {
            val groupId = previous.similarPhotoGroupId
            previousIndex = clips.indexOfFirst { it.similarPhotoGroupId == groupId }
                .takeIf { it >= 0 }
                ?: previousIndex
        }
        return previousIndex
    }

    private fun nextGroupEnd(clips: List<ClipItem>, insertionPoint: Int): Int {
        if (insertionPoint >= clips.size) return insertionPoint
        val next = clips[insertionPoint]
        return if (next.isVideoSegmentParent) {
            clips.indexOfLast { it.id == next.id || it.videoSegmentParentId == next.id }
                .takeIf { it >= 0 }
                ?: insertionPoint
        } else if (next.similarPhotoGroupId != null) {
            val groupId = next.similarPhotoGroupId
            clips.indexOfLast { it.similarPhotoGroupId == groupId }
                .takeIf { it >= 0 }
                ?: insertionPoint
        } else {
            insertionPoint
        }
    }

    private fun presetInitialState(context: Context?, preset: MoviePreset): EditorUiState {
        val presetDefaultDuration = when (preset) {
            MoviePreset.NewMovie -> 2.0
            MoviePreset.AiShot -> 4.0
            MoviePreset.Travel -> 1.5
            MoviePreset.Golf -> 4.0
        }
        val defaultDuration = context?.let {
            EditorPreferenceStore.defaultDurationSeconds(it, presetDefaultDuration)
        } ?: presetDefaultDuration
        val outputAspectRatio = context?.let(EditorPreferenceStore::outputAspectRatio)
        val sampleMusic = presetSampleMusic(preset)
        return EditorUiState(
            preset = preset,
            defaultDurationSeconds = defaultDuration,
            defaultVideoSegmentMode = if (preset == MoviePreset.NewMovie) {
                VideoSegmentMode.Single
            } else {
                VideoSegmentMode.Multiple
            },
            outputAspectRatio = outputAspectRatio,
            watermarkSettings = presetWatermark(preset),
            backgroundMusicUri = sampleMusic?.let { sampleBackgroundMusicUri(null, it) },
            backgroundMusicTitle = sampleMusic?.title,
            backgroundMusicSampleId = sampleMusic?.id,
            backgroundMusicVolume = 0.35,
            originalAudioVolume = 1.0
        )
    }

    private fun displayNameForUri(context: Context, uri: Uri): String {
        return runCatching {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) cursor.getString(index) else null
                    } else {
                        null
                    }
                }
        }.getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?: uri.lastPathSegment
            ?: "선택한 음악"
    }

    private fun persistBackgroundMusic(context: Context, uri: Uri): Uri {
        if (uri.scheme == "android.resource") return uri
        if (uri.scheme == "file" && uri.path.orEmpty().contains("/background-music/")) return uri

        val mimeType = context.contentResolver.getType(uri).orEmpty()
        val extension = MimeTypeMap.getSingleton()
            .getExtensionFromMimeType(mimeType)
            ?.takeIf { it.isNotBlank() }
            ?: uri.lastPathSegment
                ?.substringAfterLast('.', missingDelimiterValue = "")
                ?.takeIf { it.isNotBlank() && it.length <= 5 }
            ?: "m4a"
        val directory = File(context.filesDir, "background-music").apply { mkdirs() }
        pruneBackgroundMusicDirectory(directory)
        val target = File(directory, "hanclip-music-${UUID.randomUUID()}.$extension")
        context.contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: return uri
        return Uri.fromFile(target)
    }

    private fun pruneBackgroundMusicDirectory(directory: File) {
        val files = directory.listFiles()
            ?.filter { it.isFile }
            ?.sortedByDescending { it.lastModified() }
            .orEmpty()
        files.drop(24).forEach { file ->
            runCatching { file.delete() }
        }
    }

    private fun sampleBackgroundMusicUri(context: Context?, sample: BackgroundMusicSample): Uri {
        val packageName = context?.packageName ?: "com.hanclip.android"
        return Uri.parse("android.resource://$packageName/raw/${sample.rawResourceName}")
    }

    private fun presetSampleMusic(preset: MoviePreset): BackgroundMusicSample? {
        return when (preset) {
            MoviePreset.Golf -> BackgroundMusicSample.GolfLetsGo
            MoviePreset.Travel -> BackgroundMusicSample.TravelJoy
            MoviePreset.NewMovie,
            MoviePreset.AiShot -> null
        }
    }

    private fun presetWatermark(preset: MoviePreset): WatermarkSettings {
        val dateText = LocalDate.now().format(
            DateTimeFormatter.ofPattern("yy.MM.dd(E)", Locale.KOREAN)
        )
        return when (preset) {
            MoviePreset.AiShot,
            MoviePreset.Golf -> WatermarkSettings(
                isEnabled = true,
                logoEnabled = preset == MoviePreset.Golf,
                text = dateText,
                position = WatermarkPosition.BottomLeading,
                fontName = "do_hyeon",
                textColorHex = "#FFFFFF",
                shadowEnabled = true,
                shadowOpacity = 0.5,
                shadowColorHex = "#10B85A",
                lineSpacing = WatermarkLineSpacing.Normal,
                lineSpacingScale = WatermarkLineSpacing.DefaultScale,
                fontSize = WatermarkFontSize.ExtraLarge,
                logoColorHex = "#007644",
                logoShadowColorHex = "#29AB87",
                logoShadowOpacity = 0.5,
                copyrightPosition = WatermarkPosition.BottomTrailing
            )
            MoviePreset.Travel -> WatermarkSettings(
                isEnabled = true,
                logoEnabled = true,
                text = dateText,
                position = WatermarkPosition.BottomCenter,
                fontName = "gowun_batang",
                textColorHex = "#FFF3D6",
                shadowEnabled = true,
                shadowOpacity = 0.5,
                shadowColorHex = "#3F6F63",
                lineSpacing = WatermarkLineSpacing.Normal,
                lineSpacingScale = WatermarkLineSpacing.DefaultScale,
                fontSize = WatermarkFontSize.Large,
                logoColorHex = "#FFF3D6",
                logoShadowColorHex = "#3F6F63",
                logoShadowOpacity = 0.45,
                copyrightPosition = WatermarkPosition.BottomTrailing
            )
            MoviePreset.NewMovie -> WatermarkSettings(isEnabled = false)
        }
    }

    private fun expandImportedClipForPreset(
        clip: ClipItem,
        defaultDurationSeconds: Double,
        defaultVideoSegmentMode: VideoSegmentMode
    ): List<ClipItem> {
        if (clip.mediaKind != ClipMediaKind.Video || defaultVideoSegmentMode != VideoSegmentMode.Multiple) {
            return listOf(clip.copy(videoSegmentMode = VideoSegmentMode.Single))
        }

        val sourceDuration = clip.sourceDurationSeconds ?: clip.durationSeconds
        val selectedDuration = min(defaultDurationSeconds, sourceDuration).coerceAtLeast(0.5)
        val peaks = normalizedSegmentPeaks(
            clip = clip,
            sourceDuration = sourceDuration,
            selectedDuration = selectedDuration
        )

        if (peaks.size <= 1) {
            return listOf(clip.copy(videoSegmentMode = VideoSegmentMode.Single))
        }

        val parentId = clip.id
        val parent = clip.copy(
            videoSegmentMode = VideoSegmentMode.Multiple,
            isVideoSegmentParent = true,
            videoSegmentParentId = null,
            trimStartSeconds = 0.0,
            durationSeconds = sourceDuration,
            photoDurationSeconds = sourceDuration
        )
        val children = peaks.mapIndexed { index, peak ->
            val trimStart = max(
                0.0,
                min(sourceDuration - selectedDuration, peak - selectedDuration / 2.0)
            )
            clip.copy(
                id = "${parentId}-segment-${index}-${UUID.randomUUID()}",
                videoSegmentMode = VideoSegmentMode.Multiple,
                isVideoSegmentParent = false,
                videoSegmentParentId = parentId,
                durationSeconds = selectedDuration,
                photoDurationSeconds = selectedDuration,
                trimStartSeconds = trimStart,
                audioPeakTimeSeconds = peak,
                audioPeakTimesSeconds = peaks
            )
        }
        return listOf(parent) + children
    }

    private fun normalizedSegmentPeaks(
        clip: ClipItem,
        sourceDuration: Double,
        selectedDuration: Double
    ): List<Double> {
        val fallbackPeak = clip.audioPeakTimeSeconds
            ?: (clip.trimStartSeconds + clip.durationSeconds / 2.0)
        val rawPeaks = clip.audioPeakTimesSeconds.ifEmpty {
            listOf(fallbackPeak)
        }
        val deduplicated = rawPeaks
            .mapNotNull { peak ->
                peak
                    .takeIf { it.isFinite() }
                    ?.coerceIn(0.0, sourceDuration)
            }
            .fold(emptyList<Double>()) { result, peak ->
                if (result.any { kotlin.math.abs(it - peak) < 0.08 }) {
                    result
                } else {
                    result + peak
                }
            }

        val enriched = enrichSparsePeaks(
            peaks = deduplicated.ifEmpty { listOf(sourceDuration / 2.0) },
            sourceDuration = sourceDuration,
            selectedDuration = selectedDuration
        )
        return nonOverlappingPeaks(
            rankedPeaks = enriched,
            sourceDuration = sourceDuration,
            selectedDuration = selectedDuration,
            limit = 12
        ).sorted()
    }

    private fun enrichSparsePeaks(
        peaks: List<Double>,
        sourceDuration: Double,
        selectedDuration: Double
    ): List<Double> {
        if (peaks.size >= 2 || sourceDuration <= selectedDuration * 1.35) {
            return peaks
        }
        val primary = peaks.firstOrNull() ?: sourceDuration / 2.0
        val spacing = max(selectedDuration * 0.8, min(2.0, sourceDuration / 3.0))
        return listOf(
            primary,
            primary - spacing,
            primary + spacing,
            sourceDuration * 0.33,
            sourceDuration * 0.67
        )
            .map { it.coerceIn(selectedDuration / 2.0, sourceDuration - selectedDuration / 2.0) }
            .distinctBy { (it * 10).toInt() }
    }

    private fun nonOverlappingPeaks(
        rankedPeaks: List<Double>,
        sourceDuration: Double,
        selectedDuration: Double,
        limit: Int
    ): List<Double> {
        val minimumSeparation = max(0.45, selectedDuration * 0.72)
        val selected = mutableListOf<Double>()
        rankedPeaks.forEach { peak ->
            val safePeak = peak.coerceIn(0.0, sourceDuration)
            if (selected.all { kotlin.math.abs(it - safePeak) >= minimumSeparation }) {
                selected += safePeak
            }
            if (selected.size >= limit) return@forEach
        }
        return selected.ifEmpty {
            listOf(sourceDuration / 2.0)
        }
    }
}

private data class DeleteUndoSnapshot(
    val clips: List<ClipItem>,
    val importedMediaCount: Int,
    val expandedSimilarPhotoGroupIds: Set<String>
)
