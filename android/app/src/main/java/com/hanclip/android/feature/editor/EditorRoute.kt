package com.hanclip.android.feature.editor

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AddPhotoAlternate
import androidx.compose.material.icons.outlined.AspectRatio
import androidx.compose.material.icons.outlined.AutoFixHigh
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.DragIndicator
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.LibraryMusic
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AddCircle
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.MovieCreation
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.hanclip.android.core.media.MediaImportReader
import com.hanclip.android.core.model.ClipItem
import com.hanclip.android.core.model.ClipMediaKind
import com.hanclip.android.core.model.MoviePreset
import com.hanclip.android.core.model.OutputAspectRatio
import com.hanclip.android.core.model.OutputQualityPreset
import com.hanclip.android.core.model.VideoSegmentMode
import com.hanclip.android.core.settings.SleepPreventionMode
import com.hanclip.android.core.theme.HanClipPalette
import com.hanclip.android.core.theme.HanClipThemeStore
import androidx.lifecycle.viewmodel.compose.viewModel

@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun EditorRoute(
    preset: MoviePreset,
    onBackHome: () -> Unit,
    onPreview: () -> Unit,
    onOpenBrowser: () -> Unit = {},
    sleepPreventionMode: SleepPreventionMode = SleepPreventionMode.Default,
    onSleepPreventionModeChange: (SleepPreventionMode) -> Unit = {},
    initialImportAction: EditorImportAction? = null,
    onInitialImportActionConsumed: () -> Unit = {},
    viewModel: EditorViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val palette = remember { HanClipThemeStore.load(context).palette }
    var trimmingClipID by remember { mutableStateOf<String?>(null) }
    var photoDurationClipID by remember { mutableStateOf<String?>(null) }
    var previewClipID by remember { mutableStateOf<String?>(null) }
    var isTextOverlaySheetVisible by remember { mutableStateOf(false) }
    var isMusicSettingsSheetVisible by remember { mutableStateOf(false) }
    var isCalendarPickerVisible by remember { mutableStateOf(false) }
    var mediaPickerTitle by remember { mutableStateOf("날짜별") }
    var isReorderMode by remember { mutableStateOf(false) }
    var isResetConfirmationVisible by remember { mutableStateOf(false) }
    var isExitConfirmationVisible by remember { mutableStateOf(false) }
    var isExportConfirmationVisible by remember { mutableStateOf(false) }
    val expandedCalendarSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val trimmingClip = state.clips.firstOrNull { it.id == trimmingClipID }
    val photoDurationClip = state.clips.firstOrNull { it.id == photoDurationClipID }
    val previewClip = state.clips.firstOrNull { it.id == previewClipID }
    val galleryPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            result.data.persistPickedUriPermissions(context)
            viewModel.addPickedMedia(context, result.data.extractPickedUris())
        }
    }
    val musicPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            result.data.persistPickedUriPermissions(context)
            viewModel.setBackgroundMusic(context, result.data?.data)
        }
    }
    val calendarPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { grants ->
        if (grants.values.any { it }) {
            isCalendarPickerVisible = true
        } else {
            viewModel.showAlert("기본 사진첩을 보려면 사진/영상 접근 권한이 필요합니다. Android 설정에서 HanClip 권한을 허용하거나, 파일 버튼으로 직접 선택해 주세요.")
        }
    }

    fun openCalendarPicker(title: String = "날짜별") {
        mediaPickerTitle = title
        val missingPermissions = calendarMediaPermissions()
            .filter { permission ->
                ContextCompat.checkSelfPermission(context, permission) != PackageManager.PERMISSION_GRANTED
            }
        if (missingPermissions.isEmpty()) {
            isCalendarPickerVisible = true
        } else {
            calendarPermissionLauncher.launch(missingPermissions.toTypedArray())
        }
    }

    LaunchedEffect(preset) {
        viewModel.openPreset(context, preset)
    }

    LaunchedEffect(initialImportAction) {
        when (initialImportAction) {
            EditorImportAction.Photo -> {
                onInitialImportActionConsumed()
                openCalendarPicker("기본 사진첩")
            }
            EditorImportAction.Calendar -> {
                onInitialImportActionConsumed()
                openCalendarPicker()
            }
            EditorImportAction.Files -> {
                onInitialImportActionConsumed()
                galleryPicker.launch(mediaFileIntent())
            }
            null -> Unit
        }
    }

    LaunchedEffect(
        state.clips,
        state.defaultDurationSeconds,
        state.defaultVideoSegmentMode,
        state.outputAspectRatio,
        state.outputQualityPreset,
        state.watermarkSettings,
        state.backgroundMusicUri,
        state.backgroundMusicTitle,
        state.backgroundMusicSampleId
    ) {
        if (state.clips.isNotEmpty() && !state.isImportingMedia && !state.isExporting) {
            viewModel.saveDraft(context)
        }
    }

    fun requestBackHome() {
        if (state.clips.isEmpty()) {
            onBackHome()
        } else {
            isExitConfirmationVisible = true
        }
    }

    BackHandler(enabled = state.clips.isNotEmpty()) {
        requestBackHome()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
    ) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(horizontal = 16.dp),
            contentPadding = PaddingValues(bottom = 138.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            item {
                Spacer(Modifier.height(18.dp))
                EditorHeader(
                    title = state.preset.title,
                    palette = palette,
                    onBackHome = ::requestBackHome
                )
            }
            item {
                SummaryPanel(
                    clipCount = state.renderableClips.size,
                    photoCount = state.renderableClips.count { it.mediaKind != ClipMediaKind.Video },
                    videoCount = state.renderableClips.count { it.mediaKind == ClipMediaKind.Video },
                    totalSeconds = state.totalDurationSeconds,
                    defaultDuration = state.defaultDurationSeconds,
                    segmentMode = state.defaultVideoSegmentMode,
                    palette = palette
                )
            }
            item {
                PresetStatusPanel(
                    preset = state.preset,
                    defaultDuration = state.defaultDurationSeconds,
                    segmentMode = state.defaultVideoSegmentMode,
                    hasTextOverlay = state.watermarkSettings.shouldRender,
                    hasMusic = state.backgroundMusicUri != null,
                    musicTitle = state.backgroundMusicTitle,
                    selectedRatio = state.outputAspectRatio,
                    selectedQuality = state.outputQualityPreset,
                    palette = palette
                )
            }
            item {
                ImportActionRow(
                    palette = palette,
                    onPickMedia = { openCalendarPicker("기본 사진첩") },
                    onPickFiles = {
                        galleryPicker.launch(mediaFileIntent())
                    },
                    onPickCalendar = { openCalendarPicker("날짜별") },
                    onPickVideos = { openCalendarPicker("영상만") },
                    onAiCut = {
                        viewModel.prepareAiCutImport()
                        openCalendarPicker("영상만")
                    }
                )
            }
            if (state.isImportingMedia || state.progressMessage.isNotBlank()) {
                item {
                    ImportStatusPanel(state.progressMessage)
                }
            }
            item {
                ProjectControls(
                    selectedRatio = state.outputAspectRatio,
                    selectedQuality = state.outputQualityPreset,
                    palette = palette,
                    hasTextOverlay = state.watermarkSettings.shouldRenderText,
                    hasMusic = state.backgroundMusicUri != null,
                    musicTitle = state.backgroundMusicTitle,
                    musicVolume = state.backgroundMusicVolume,
                    originalAudioVolume = state.originalAudioVolume,
                    isReorderMode = isReorderMode,
                    sleepPreventionMode = sleepPreventionMode,
                    hasClips = state.clips.isNotEmpty(),
                    onSelectRatio = { ratio -> viewModel.selectAspectRatio(context, ratio) },
                    onSelectQuality = { quality -> viewModel.selectOutputQualityPreset(context, quality) },
                    onOpenTextOverlay = { isTextOverlaySheetVisible = true },
                    onOpenMusicSettings = { isMusicSettingsSheetVisible = true },
                    onToggleReorder = { isReorderMode = !isReorderMode },
                    onCycleSleepPrevention = {
                        onSleepPreventionModeChange(sleepPreventionMode.next())
                    },
                    onResetProject = { isResetConfirmationVisible = true }
                )
            }
            if (isReorderMode && state.clips.isNotEmpty()) {
                item {
                    ReorderStrip(
                        clips = state.visibleClips,
                        palette = palette,
                        onMoveUp = { id -> viewModel.moveClipUp(id) },
                        onMoveDown = { id -> viewModel.moveClipDown(id) },
                        onDelete = { id -> viewModel.removeClip(id) },
                        onDone = { isReorderMode = false }
                    )
                }
            }
            if (state.clips.any { it.isVideoSegmentParent }) {
                item {
                    AutoSegmentStatusPanel(
                        sourceCount = state.clips.count { it.isVideoSegmentParent },
                        segmentCount = state.clips.count { it.isVideoSegmentChild },
                        defaultDuration = state.defaultDurationSeconds,
                        palette = palette
                    )
                }
            }
            if (state.clips.isEmpty()) {
                item {
                    EmptyClipPanel(
                        preset = state.preset,
                        palette = palette,
                        onPickMedia = { openCalendarPicker("기본 사진첩") },
                        onPickFiles = {
                            galleryPicker.launch(mediaFileIntent())
                        },
                        onPickCalendar = { openCalendarPicker("날짜별") },
                        onPickVideos = { openCalendarPicker("영상만") }
                    )
                }
            }
            if (state.clips.isNotEmpty()) {
                item {
                    Text(
                        text = "클립",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = palette.text
                    )
                }
            }
            itemsIndexed(state.visibleClips, key = { _, clip -> clip.id }) { _, clip ->
                val displayPosition = state.clips
                    .takeWhile { it.id != clip.id }
                    .count { it.isRenderableClip }
                    .let { if (clip.isRenderableClip) it + 1 else it }
                    .takeIf { !clip.isVideoSegmentParent && !clip.isSimilarPhotoGroupMember }
                val childSegmentCount = state.clips.count { it.videoSegmentParentId == clip.id }
                ClipRow(
                    palette = palette,
                    position = displayPosition,
                    clip = clip,
                    childSegmentCount = childSegmentCount,
                    isSimilarPhotoGroupExpanded = clip.similarPhotoGroupId in state.expandedSimilarPhotoGroupIds,
                    onClick = {
                        if (clip.mediaKind == ClipMediaKind.Video) {
                            trimmingClipID = clip.id
                        } else {
                            photoDurationClipID = clip.id
                        }
                    },
                    onDecreaseDuration = { viewModel.adjustClipDuration(clip.id, -0.5) },
                    onIncreaseDuration = { viewModel.adjustClipDuration(clip.id, 0.5) },
                    onMoveUp = { viewModel.moveClipUp(clip.id) },
                    onMoveDown = { viewModel.moveClipDown(clip.id) },
                    onDelete = { viewModel.removeClip(clip.id) },
                    onToggleSegmentMode = { viewModel.toggleVideoSegmentMode(clip.id) },
                    onResetSegments = { viewModel.resetVideoSegments(clip.id) },
                    onPreviewClip = { previewClipID = clip.id },
                    onToggleSimilarPhotoGroup = { viewModel.toggleSimilarPhotoGroup(clip.id) },
                    onIncludeSimilarPhoto = { viewModel.includeSimilarPhoto(clip.id) },
                    isReorderMode = isReorderMode
                )
            }
            if (state.clips.isNotEmpty()) {
                item {
                    GlobalTimePanel(
                        defaultDuration = state.defaultDurationSeconds,
                        hasVideoClips = state.renderableClips.any { it.mediaKind == ClipMediaKind.Video },
                        palette = palette,
                        onSetDuration = { seconds -> viewModel.setDefaultDuration(context, seconds) },
                        onApplyAll = viewModel::applyDefaultDurationToAll,
                        onSelectFullRange = viewModel::selectFullRangeForAllVideoClips
                    )
                }
            }
            item {
                Spacer(Modifier.height(if (isReorderMode) 24.dp else 88.dp))
            }
        }
        if (!isReorderMode && state.renderableClips.isNotEmpty()) {
            BottomMakeBar(
                modifier = Modifier.align(Alignment.BottomCenter),
                palette = palette,
                isExporting = state.isExporting,
                clipCount = state.renderableClips.size,
                totalSeconds = state.totalDurationSeconds,
                qualityTitle = state.outputQualityPreset.displayTitle,
                onMakeMovie = { isExportConfirmationVisible = true }
            )
        }
        if (state.isImportingMedia || state.isExporting) {
            WorkProgressOverlay(
                palette = palette,
                message = state.progressMessage.ifBlank {
                    if (state.isExporting) "영화를 만드는 중..." else "미디어를 불러오는 중..."
                },
                onCancel = if (state.isExporting) viewModel::cancelExport else null
            )
        }
        state.alertMessage?.let { message ->
            AlertDialog(
                onDismissRequest = viewModel::clearAlert,
                dismissButton = if (state.undoDeleteMessage != null) {
                    {
                        OutlinedButton(
                            onClick = viewModel::undoLastDelete,
                            border = BorderStroke(1.dp, palette.border),
                            colors = ButtonDefaults.outlinedButtonColors(
                                containerColor = palette.panel,
                                contentColor = palette.text
                            )
                        ) {
                            Text("되돌리기")
                        }
                    }
                } else {
                    null
                },
                confirmButton = {
                    Button(
                        onClick = viewModel::clearAlert,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = palette.primary,
                            contentColor = Color.White
                        )
                    ) {
                        Text("확인")
                    }
                },
                shape = RoundedCornerShape(8.dp),
                containerColor = palette.panel,
                titleContentColor = palette.text,
                textContentColor = palette.subText,
                title = { Text("HanClip") },
                text = { Text(message) }
            )
        }
        if (isResetConfirmationVisible) {
            AlertDialog(
                onDismissRequest = { isResetConfirmationVisible = false },
                dismissButton = {
                    OutlinedButton(
                        onClick = { isResetConfirmationVisible = false },
                        border = BorderStroke(1.dp, palette.border),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = palette.panel,
                            contentColor = palette.text
                        )
                    ) {
                        Text("취소")
                    }
                },
                confirmButton = {
                    Button(
                        onClick = {
                            isResetConfirmationVisible = false
                            viewModel.resetProject(context)
                        },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFFE45D42),
                            contentColor = Color.White
                        )
                    ) {
                        Text("초기화")
                    }
                },
                shape = RoundedCornerShape(8.dp),
                containerColor = palette.panel,
                titleContentColor = palette.text,
                textContentColor = palette.subText,
                title = { Text("현재 영화 초기화") },
                text = { Text("가져온 클립과 편집 설정을 모두 비우고 처음부터 다시 시작할까요?") }
            )
        }
        if (isExitConfirmationVisible) {
            AlertDialog(
                onDismissRequest = { isExitConfirmationVisible = false },
                dismissButton = {
                    OutlinedButton(
                        onClick = { isExitConfirmationVisible = false },
                        border = BorderStroke(1.dp, palette.border),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = palette.panel,
                            contentColor = palette.text
                        )
                    ) {
                        Text("계속 편집")
                    }
                },
                confirmButton = {
                    Button(
                        onClick = {
                            isExitConfirmationVisible = false
                            viewModel.saveDraft(context)
                            onBackHome()
                        },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = palette.primary,
                            contentColor = Color.White
                        )
                    ) {
                        Text("홈으로")
                    }
                },
                shape = RoundedCornerShape(8.dp),
                containerColor = palette.panel,
                titleContentColor = palette.text,
                textContentColor = palette.subText,
                title = { Text("편집을 닫을까요?") },
                text = { Text("현재 작업은 자동 저장됩니다. 홈에서 `작업 열기`로 이어서 편집할 수 있습니다.") }
            )
        }
        if (isExportConfirmationVisible) {
            ExportConfirmationDialog(
                state = state,
                palette = palette,
                onDismiss = { isExportConfirmationVisible = false },
                onConfirm = {
                    isExportConfirmationVisible = false
                    viewModel.exportMovie(context, onPreview)
                }
            )
        }
        trimmingClip?.let { clip ->
            ModalBottomSheet(
                onDismissRequest = { trimmingClipID = null },
                containerColor = Color.Transparent
            ) {
                VideoTrimSheet(
                    clip = clip,
                    palette = palette,
                    onDismiss = { trimmingClipID = null },
                    onApplyTrim = { startSeconds, durationSeconds ->
                        viewModel.updateVideoTrim(
                            id = clip.id,
                            startSeconds = startSeconds,
                            durationSeconds = durationSeconds
                        )
                    }
                )
            }
        }
        photoDurationClip?.let { clip ->
            ModalBottomSheet(
                onDismissRequest = { photoDurationClipID = null },
                containerColor = Color.Transparent
            ) {
                PhotoDurationSheet(
                    clip = clip,
                    palette = palette,
                    onDismiss = { photoDurationClipID = null },
                    onApplyDuration = { durationSeconds ->
                        viewModel.updatePhotoDuration(clip.id, durationSeconds)
                    }
                )
            }
        }
        previewClip?.let { clip ->
            ClipPreviewDialog(
                clip = clip,
                palette = palette,
                childSegmentCount = state.clips.count { it.videoSegmentParentId == clip.id },
                onDismiss = { previewClipID = null }
            )
        }
        if (isTextOverlaySheetVisible) {
            Dialog(
                onDismissRequest = { isTextOverlaySheetVisible = false },
                properties = DialogProperties(
                    usePlatformDefaultWidth = false,
                    decorFitsSystemWindows = false
                )
            ) {
                TextOverlaySheet(
                    settings = state.watermarkSettings,
                    palette = palette,
                    fullScreen = true,
                    onDismiss = { isTextOverlaySheetVisible = false },
                    onApply = viewModel::updateWatermark
                )
            }
        }
        if (isMusicSettingsSheetVisible) {
            Dialog(
                onDismissRequest = { isMusicSettingsSheetVisible = false },
                properties = DialogProperties(
                    usePlatformDefaultWidth = false,
                    decorFitsSystemWindows = false
                )
            ) {
                MusicSettingsSheet(
                    currentTitle = state.backgroundMusicTitle,
                    currentUri = state.backgroundMusicUri,
                    currentSampleId = state.backgroundMusicSampleId,
                    musicVolume = state.backgroundMusicVolume,
                    originalAudioVolume = state.originalAudioVolume,
                    palette = palette,
                    fullScreen = true,
                    onUseSample = { sample ->
                        viewModel.useSampleBackgroundMusic(context, sample)
                        isMusicSettingsSheetVisible = false
                    },
                    onPickFile = {
                        isMusicSettingsSheetVisible = false
                        musicPicker.launch(backgroundMusicIntent())
                    },
                    onOpenBrowser = {
                        isMusicSettingsSheetVisible = false
                        onOpenBrowser()
                    },
                    onRemove = {
                        viewModel.removeBackgroundMusic()
                        isMusicSettingsSheetVisible = false
                    },
                    onMusicVolumeChange = viewModel::updateBackgroundMusicVolume,
                    onOriginalAudioVolumeChange = viewModel::updateOriginalAudioVolume,
                    onDismiss = { isMusicSettingsSheetVisible = false }
                )
            }
        }
        if (isCalendarPickerVisible) {
            ModalBottomSheet(
                onDismissRequest = { isCalendarPickerVisible = false },
                sheetState = expandedCalendarSheetState,
                containerColor = Color.Transparent
            ) {
                CalendarMediaPickerSheet(
                    title = mediaPickerTitle,
                    palette = palette,
                    onDismiss = { isCalendarPickerVisible = false },
                    onImport = { uris ->
                        isCalendarPickerVisible = false
                        viewModel.addPickedMedia(context, uris)
                    }
                )
            }
        }
    }
}

enum class EditorImportAction {
    Photo,
    Calendar,
    Files
}

private fun calendarMediaPermissions(): List<String> {
    return when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> listOf(
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VIDEO,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
        )
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> listOf(
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VIDEO
        )
        else -> listOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }
}

private fun backgroundMusicIntent(): Intent {
    return Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        type = "audio/*"
        addCategory(Intent.CATEGORY_OPENABLE)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
    }
}

private fun mediaFileIntent(): Intent {
    return Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        type = "*/*"
        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        addCategory(Intent.CATEGORY_OPENABLE)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
    }
}

private fun Intent?.extractPickedUris(): List<Uri> {
    if (this == null) return emptyList()
    val selected = mutableListOf<Uri>()
    clipData?.forEachUri { selected += it }
    data?.let { selected += it }
    return selected.distinct()
}

private fun Intent?.persistPickedUriPermissions(context: Context) {
    if (this == null) return
    val canRead = flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0
    val canWrite = flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0
    extractPickedUris().forEach { uri ->
        if (canRead) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            }
        }
        if (canWrite) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            }
        }
    }
}

private fun ClipData.forEachUri(block: (Uri) -> Unit) {
    for (index in 0 until itemCount) {
        getItemAt(index).uri?.let(block)
    }
}

private val EditorBackground = Brush.verticalGradient(
    listOf(
        Color(0xFFFAFCFA),
        Color(0xFFF4F7F5)
    )
)

private val HanPrimary = Color(0xFF0B7A4E)
private val HanText = Color(0xFF14221A)
private val HanSubText = Color(0xFF46564C)
private val HanBorder = Color(0xFFD4DDD7)
private val HanChipSurface = Color.White

@Composable
private fun EditorHeader(
    title: String,
    palette: HanClipPalette,
    onBackHome: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBackHome) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "홈", tint = palette.text)
            }
            Column {
                Text(
                    "편집",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    color = palette.text
                )
                Text(title, style = MaterialTheme.typography.bodyMedium, color = palette.subText)
            }
        }
        IconButton(onClick = onBackHome) {
            Icon(Icons.Outlined.Close, contentDescription = "닫기", tint = palette.text)
        }
    }
}

@Composable
private fun SummaryPanel(
    clipCount: Int,
    photoCount: Int,
    videoCount: Int,
    totalSeconds: Double,
    defaultDuration: Double,
    segmentMode: VideoSegmentMode,
    palette: HanClipPalette
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = palette.primary
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                SummaryMetric("클립", "${clipCount}개", palette, Modifier.weight(1f))
                SummaryMetric("전체", formatSummaryDuration(totalSeconds), palette, Modifier.weight(1f))
                SummaryMetric("기본", "%.1f초".format(defaultDuration), palette, Modifier.weight(1f))
                SummaryMetric("분할", segmentMode.title, palette, Modifier.weight(1f))
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                SummaryReadinessPill(
                    text = if (clipCount > 0) "영화 만들기 준비됨" else "사진/영상을 선택하세요",
                    active = clipCount > 0,
                    palette = palette,
                    modifier = Modifier.weight(1.35f)
                )
                SummaryReadinessPill(
                    text = "사진 ${photoCount}개",
                    active = photoCount > 0,
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
                SummaryReadinessPill(
                    text = "영상 ${videoCount}개",
                    active = videoCount > 0,
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun SummaryMetric(
    label: String,
    value: String,
    palette: HanClipPalette,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = Color.White.copy(alpha = 0.72f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            value,
            style = MaterialTheme.typography.titleMedium,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun SummaryReadinessPill(
    text: String,
    active: Boolean,
    palette: HanClipPalette,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(50),
        color = Color.White.copy(alpha = if (active) 0.20f else 0.10f),
        border = BorderStroke(1.dp, Color.White.copy(alpha = if (active) 0.34f else 0.16f))
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
            color = Color.White.copy(alpha = if (active) 0.96f else 0.72f),
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.labelMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

private fun formatSummaryDuration(seconds: Double): String {
    val safeSeconds = seconds.coerceAtLeast(0.0)
    val minutes = (safeSeconds / 60).toInt()
    val remainingSeconds = safeSeconds - minutes * 60
    return if (minutes > 0) {
        "%d분 %.1f초".format(minutes, remainingSeconds)
    } else {
        "%.1f초".format(remainingSeconds)
    }
}

@Composable
private fun ExportConfirmationDialog(
    state: EditorUiState,
    palette: HanClipPalette,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    val renderableClipCount = state.renderableClips.size
    val aspectRatioText = state.outputAspectRatio?.title ?: "원본 비율"
    val musicText = when {
        state.backgroundMusicUri != null || state.backgroundMusicSampleId != null ->
            state.backgroundMusicTitle ?: "음악 적용"
        else -> "음악 없음"
    }
    val captionText = when {
        state.watermarkSettings.shouldRenderText && state.watermarkSettings.logoEnabled -> "자막 · HanClip 로고"
        state.watermarkSettings.shouldRenderText -> "자막 적용"
        state.watermarkSettings.logoEnabled -> "HanClip 로고"
        else -> "자막 없음"
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        dismissButton = {
            OutlinedButton(
                onClick = onDismiss,
                border = BorderStroke(1.dp, palette.border),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = palette.panel,
                    contentColor = palette.text
                )
            ) {
                Text("다시 보기")
            }
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(
                    containerColor = palette.primary,
                    contentColor = Color.White
                )
            ) {
                Icon(Icons.Outlined.MovieCreation, contentDescription = null)
                Text("제작 시작")
            }
        },
        shape = RoundedCornerShape(8.dp),
        containerColor = palette.panel,
        titleContentColor = palette.text,
        textContentColor = palette.subText,
        title = { Text("영화를 만들까요?") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "아래 설정으로 HanClip 영화를 만듭니다.",
                    color = palette.subText,
                    style = MaterialTheme.typography.bodyMedium
                )
                ExportConfirmationLine("클립", "${renderableClipCount}개 · ${formatSummaryDuration(state.totalDurationSeconds)}", palette)
                ExportConfirmationLine("화면", aspectRatioText, palette)
                ExportConfirmationLine("품질", state.outputQualityPreset.displayTitle, palette)
                ExportConfirmationLine("음악", musicText, palette)
                ExportConfirmationLine("자막", captionText, palette)
            }
        }
    )
}

@Composable
private fun ExportConfirmationLine(
    label: String,
    value: String,
    palette: HanClipPalette
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            label,
            color = palette.subText,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            value,
            color = palette.text,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PresetStatusPanel(
    preset: MoviePreset,
    defaultDuration: Double,
    segmentMode: VideoSegmentMode,
    hasTextOverlay: Boolean,
    hasMusic: Boolean,
    musicTitle: String?,
    selectedRatio: OutputAspectRatio?,
    selectedQuality: OutputQualityPreset,
    palette: HanClipPalette
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = palette.panel,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        text = preset.title,
                        color = palette.text,
                        fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = presetStatusDescription(preset),
                        color = palette.subText,
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Surface(
                    shape = RoundedCornerShape(7.dp),
                    color = palette.chip,
                    border = BorderStroke(1.dp, palette.border)
                ) {
                    Text(
                        text = "%.1f초".format(defaultDuration),
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
                        color = palette.primary,
                        fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.labelLarge
                    )
                }
            }
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                verticalArrangement = Arrangement.spacedBy(7.dp)
            ) {
                PresetStatusPill(
                    text = if (segmentMode == VideoSegmentMode.Multiple) "자동 컷" else "단일 컷",
                    active = segmentMode == VideoSegmentMode.Multiple,
                    palette = palette
                )
                PresetStatusPill(
                    text = if (hasTextOverlay) "자막/로고 켬" else "자막 꺼짐",
                    active = hasTextOverlay,
                    palette = palette
                )
                PresetStatusPill(
                    text = if (hasMusic) musicTitle ?: "음악 켬" else "음악 꺼짐",
                    active = hasMusic,
                    palette = palette
                )
                PresetStatusPill(
                    text = selectedRatio?.title ?: "원본 비율",
                    active = selectedRatio != null,
                    palette = palette
                )
                PresetStatusPill(
                    text = selectedQuality.displayTitle,
                    active = selectedQuality != OutputQualityPreset.Standard,
                    palette = palette
                )
                PresetStatusPill(
                    text = OutputQualityPreset.ExportFormatDetail,
                    active = false,
                    palette = palette
                )
            }
        }
    }
}

@Composable
private fun PresetStatusPill(text: String, active: Boolean, palette: HanClipPalette) {
    Surface(
        shape = RoundedCornerShape(7.dp),
        color = if (active) palette.chip else palette.panel,
        border = BorderStroke(1.dp, if (active) palette.secondary else palette.border)
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            color = if (active) palette.primary else palette.subText,
            fontWeight = FontWeight.SemiBold,
            style = MaterialTheme.typography.labelMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

private fun presetStatusDescription(preset: MoviePreset): String {
    return when (preset) {
        MoviePreset.NewMovie -> "선택한 사진과 영상을 순서대로 짧은 영화로 만듭니다."
        MoviePreset.AiShot -> "카메라로 저장한 스윙 클립을 바로 편집합니다."
        MoviePreset.Travel -> "여행 사진과 영상을 부드러운 짧은 영화로 엮습니다."
        MoviePreset.Golf -> "타격점을 중심으로 골프 클립과 자막을 자동 구성합니다."
    }
}

@Composable
private fun ImportActionRow(
    palette: HanClipPalette,
    onPickMedia: () -> Unit,
    onPickFiles: () -> Unit,
    onPickCalendar: () -> Unit,
    onPickVideos: () -> Unit,
    onAiCut: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            onClick = onPickMedia,
            colors = ButtonDefaults.buttonColors(
                containerColor = palette.primary,
                contentColor = Color.White
            )
        ) {
            Icon(Icons.Outlined.AddPhotoAlternate, contentDescription = null)
            Spacer(Modifier.width(6.dp))
            ActionButtonText("기본 사진첩에서 선택")
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                modifier = Modifier
                    .weight(1f)
                    .height(46.dp),
                onClick = onPickVideos,
                colors = ButtonDefaults.buttonColors(
                    containerColor = palette.secondary,
                    contentColor = Color.White
                )
            ) {
                Icon(Icons.Outlined.MovieCreation, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                ActionButtonText("영상만")
            }
            OutlinedButton(
                modifier = Modifier
                    .weight(1f)
                    .height(46.dp),
                onClick = onPickCalendar,
                border = BorderStroke(1.dp, palette.border),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = palette.panel,
                    contentColor = palette.text
                )
            ) {
                Icon(Icons.Outlined.CalendarMonth, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                ActionButtonText("날짜별")
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                modifier = Modifier
                    .weight(1f)
                    .height(46.dp),
                onClick = onPickFiles,
                border = BorderStroke(1.dp, palette.border),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = palette.panel,
                    contentColor = palette.text
                )
            ) {
                Icon(Icons.Outlined.FolderOpen, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                ActionButtonText("파일")
            }
            OutlinedButton(
                modifier = Modifier
                    .weight(1f)
                    .height(46.dp),
                onClick = onAiCut,
                border = BorderStroke(1.dp, palette.border),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = palette.panel,
                    contentColor = palette.text
                )
            ) {
                Icon(Icons.Outlined.AutoFixHigh, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                ActionButtonText("Ai컷")
            }
        }
    }
}

@Composable
private fun ActionButtonText(text: String) {
    Text(
        text = text,
        fontWeight = FontWeight.Bold,
        fontSize = 14.sp,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis
    )
}

@Composable
private fun EmptyClipPanel(
    preset: MoviePreset,
    palette: HanClipPalette,
    onPickMedia: () -> Unit,
    onPickFiles: () -> Unit,
    onPickCalendar: () -> Unit,
    onPickVideos: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = palette.panel,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                text = if (preset == MoviePreset.Golf || preset == MoviePreset.AiShot) {
                    "골프 영상과 사진을 선택하세요"
                } else {
                    "사진과 영상을 선택하세요"
                },
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = palette.text
            )
            Text(
                text = if (preset == MoviePreset.Golf || preset == MoviePreset.AiShot) {
                    "스윙 소리 피크를 찾아 자동으로 짧은 클립을 만듭니다."
                } else {
                    "선택한 순서대로 클립을 만들고 한 번에 이어 붙입니다."
                },
                style = MaterialTheme.typography.bodyMedium,
                color = palette.subText
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(
                    modifier = Modifier.weight(1f).height(50.dp),
                    onClick = onPickMedia,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = palette.primary,
                        contentColor = Color.White
                    )
                ) {
                    Icon(Icons.Outlined.AddPhotoAlternate, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    ActionButtonText("기본 사진첩")
                }
                Button(
                    modifier = Modifier.weight(1f).height(50.dp),
                    onClick = onPickVideos,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = palette.secondary,
                        contentColor = Color.White
                    )
                ) {
                    Icon(Icons.Outlined.MovieCreation, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    ActionButtonText("영상")
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(
                    modifier = Modifier.weight(1f).height(50.dp),
                    onClick = onPickCalendar,
                    border = BorderStroke(1.dp, palette.border),
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = palette.panel,
                        contentColor = palette.text
                    )
                ) {
                    Icon(Icons.Outlined.CalendarMonth, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    ActionButtonText("날짜별")
                }
                OutlinedButton(
                    modifier = Modifier.weight(1f).height(50.dp),
                    onClick = onPickFiles,
                    border = BorderStroke(1.dp, palette.border),
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = palette.panel,
                        contentColor = palette.text
                    )
                ) {
                    Icon(Icons.Outlined.FolderOpen, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    ActionButtonText("파일")
                }
            }
        }
    }
}

@Composable
private fun ReorderStrip(
    clips: List<ClipItem>,
    palette: HanClipPalette,
    onMoveUp: (String) -> Unit,
    onMoveDown: (String) -> Unit,
    onDelete: (String) -> Unit,
    onDone: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.primary.copy(alpha = 0.38f))
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        "순서 변경",
                        color = palette.text,
                        fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        "썸네일에서 클립 위치를 빠르게 조정합니다.",
                        color = palette.subText,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Button(
                    onClick = onDone,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = palette.primary,
                        contentColor = Color.White
                    )
                ) {
                    Text("완료")
                }
            }
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                contentPadding = PaddingValues(end = 4.dp)
            ) {
                itemsIndexed(clips, key = { _, clip -> clip.id }) { index, clip ->
                    ReorderTile(
                        clip = clip,
                        index = index,
                        totalCount = clips.size,
                        palette = palette,
                        canMoveUp = index > 0,
                        canMoveDown = index < clips.lastIndex,
                        onMoveUp = { onMoveUp(clip.id) },
                        onMoveDown = { onMoveDown(clip.id) },
                        onDelete = { onDelete(clip.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun ReorderTile(
    clip: ClipItem,
    index: Int,
    totalCount: Int,
    palette: HanClipPalette,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onDelete: () -> Unit
) {
    Surface(
        modifier = Modifier.width(148.dp),
        shape = RoundedCornerShape(8.dp),
        color = palette.panel,
        border = BorderStroke(1.dp, clipRowBorder(clip, palette))
    ) {
        Column(
            modifier = Modifier.padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(86.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(clipFallbackBrush(clip, palette)),
                contentAlignment = Alignment.Center
            ) {
                ClipThumbnail(
                    clip = clip,
                    modifier = Modifier.matchParentSize()
                )
                Text(
                    text = reorderTileBadge(clip, index),
                    color = Color.White,
                    fontWeight = FontWeight.Black
                )
            }
            Text(
                text = "${index + 1}/$totalCount  ${clipTitle(clip)}",
                color = palette.text,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                IconButton(
                    onClick = onMoveUp,
                    enabled = canMoveUp,
                    modifier = Modifier.size(32.dp)
                ) {
                    Icon(
                        Icons.Outlined.KeyboardArrowUp,
                        contentDescription = "앞으로",
                        tint = if (canMoveUp) palette.text else palette.subText.copy(alpha = 0.35f)
                    )
                }
                IconButton(
                    onClick = onMoveDown,
                    enabled = canMoveDown,
                    modifier = Modifier.size(32.dp)
                ) {
                    Icon(
                        Icons.Outlined.KeyboardArrowDown,
                        contentDescription = "뒤로",
                        tint = if (canMoveDown) palette.text else palette.subText.copy(alpha = 0.35f)
                    )
                }
                IconButton(onClick = onDelete, modifier = Modifier.size(32.dp)) {
                    Icon(Icons.Outlined.Delete, contentDescription = "삭제", tint = palette.secondary)
                }
            }
        }
    }
}

private fun reorderTileBadge(clip: ClipItem, index: Int): String {
    return when {
        clip.isVideoSegmentParent -> "원본"
        clip.isVideoSegmentChild -> "자동"
        else -> "${index + 1}"
    }
}

@Composable
private fun ImportStatusPanel(message: String) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = Color(0xFFEAF5F0)
    ) {
        Text(
            text = message.ifBlank { "미디어를 불러오는 중..." },
            modifier = Modifier.padding(14.dp),
            color = Color(0xFF1D4F38),
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
private fun AutoSegmentStatusPanel(
    sourceCount: Int,
    segmentCount: Int,
    defaultDuration: Double,
    palette: HanClipPalette
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Surface(
                modifier = Modifier.size(38.dp),
                shape = RoundedCornerShape(8.dp),
                color = palette.primary
            ) {
                Icon(
                    Icons.Outlined.AutoFixHigh,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.padding(8.dp)
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = "자동 타격점 분할 완료",
                    color = palette.text,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "스윙 소리 후보를 중심으로 ${segmentCount}개 클립을 만들었습니다.",
                    color = palette.subText,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = "원본 ${sourceCount}개 · 클립당 약 ${autoSegmentAverageDurationText(segmentCount, defaultDuration)}",
                    color = palette.subText,
                    style = MaterialTheme.typography.labelMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Text(
                text = "후보 ${segmentCount}",
                color = palette.primary,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.labelLarge
            )
        }
    }
}

private fun autoSegmentAverageDurationText(segmentCount: Int, defaultDuration: Double): String {
    return if (segmentCount <= 0) {
        "0.0초"
    } else {
        "%.1f초".format(defaultDuration)
    }
}

@Composable
private fun WorkProgressOverlay(
    palette: HanClipPalette,
    message: String,
    onCancel: (() -> Unit)? = null
) {
    val title = progressTitle(message, onCancel != null)
    val detail = progressDetail(message, onCancel != null)
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.32f))
            .clickable(enabled = true, onClick = {}),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            shape = RoundedCornerShape(8.dp),
            color = palette.panel,
            shadowElevation = 10.dp
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth(0.78f)
                    .padding(horizontal = 24.dp, vertical = 26.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                CircularProgressIndicator(
                    color = palette.primary,
                    trackColor = palette.chip
                )
                Text(
                    text = title,
                    color = palette.text,
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.titleMedium
                )
                if (detail.isNotBlank()) {
                    Text(
                        text = detail,
                        color = palette.subText,
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
                Text(
                    text = if (onCancel == null) {
                        "잠시만 기다려 주세요."
                    } else {
                        "완성 전까지 이 화면을 유지합니다."
                    },
                    color = palette.subText,
                    style = MaterialTheme.typography.bodyMedium
                )
                if (onCancel != null) {
                    OutlinedButton(
                        onClick = onCancel,
                        border = BorderStroke(1.dp, Color(0xFFF0C6BC)),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = palette.panel,
                            contentColor = Color(0xFFE45D42)
                        )
                    ) {
                        Text("제작 취소", fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

private fun progressTitle(message: String, isExporting: Boolean): String {
    val cleanMessage = message.trim()
    val percent = Regex("""\d+%""").find(cleanMessage)?.value
    return when {
        isExporting && percent != null -> "영화 만드는 중 $percent"
        isExporting -> "영화를 만드는 중"
        cleanMessage.contains("불러오는 중") -> "미디어를 불러오는 중"
        cleanMessage.isNotBlank() -> cleanMessage.substringBefore(" · ").substringBefore("...")
        else -> "작업 중"
    }
}

private fun progressDetail(message: String, isExporting: Boolean): String {
    val cleanMessage = message.trim()
    return when {
        isExporting -> cleanMessage
            .substringAfter(" · ", missingDelimiterValue = cleanMessage)
            .removePrefix("영화를 만드는 중...")
            .trim()
        cleanMessage.contains("불러오는 중") -> cleanMessage
        else -> ""
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProjectControls(
    selectedRatio: OutputAspectRatio?,
    selectedQuality: OutputQualityPreset,
    palette: HanClipPalette,
    hasTextOverlay: Boolean,
    hasMusic: Boolean,
    musicTitle: String?,
    musicVolume: Double,
    originalAudioVolume: Double,
    isReorderMode: Boolean,
    sleepPreventionMode: SleepPreventionMode,
    hasClips: Boolean,
    onSelectRatio: (OutputAspectRatio?) -> Unit,
    onSelectQuality: (OutputQualityPreset) -> Unit,
    onOpenTextOverlay: () -> Unit,
    onOpenMusicSettings: () -> Unit,
    onToggleReorder: () -> Unit,
    onCycleSleepPrevention: () -> Unit,
    onResetProject: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            AssistChip(
                onClick = onOpenTextOverlay,
                leadingIcon = { Icon(Icons.Outlined.TextFields, contentDescription = null) },
                label = { Text(if (hasTextOverlay) "자막 켬" else "자막", fontWeight = FontWeight.SemiBold) },
                colors = clearAssistChipColors(active = hasTextOverlay, palette = palette),
                border = BorderStroke(1.dp, if (hasTextOverlay) palette.primary else palette.border)
            )
            AssistChip(
                onClick = onOpenMusicSettings,
                leadingIcon = { Icon(Icons.Outlined.LibraryMusic, contentDescription = null) },
                label = {
                    Text(
                        if (hasMusic) {
                            "${musicTitle ?: "음악"} ${percentText(musicVolume)} · 원본 ${percentText(originalAudioVolume)}"
                        } else {
                            "음악"
                        },
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                },
                colors = clearAssistChipColors(active = hasMusic, palette = palette),
                border = BorderStroke(1.dp, if (hasMusic) palette.primary else palette.border)
            )
            AssistChip(
                onClick = onToggleReorder,
                leadingIcon = { Icon(Icons.Outlined.DragIndicator, contentDescription = null) },
                label = { Text(if (isReorderMode) "순서 켬" else "순서", fontWeight = FontWeight.SemiBold) },
                colors = clearAssistChipColors(active = isReorderMode, palette = palette),
                border = BorderStroke(1.dp, if (isReorderMode) palette.primary else palette.border)
            )
            AssistChip(
                onClick = onCycleSleepPrevention,
                leadingIcon = { Icon(Icons.Outlined.LightMode, contentDescription = null) },
                label = { Text(sleepPreventionMode.chipTitle, fontWeight = FontWeight.SemiBold) },
                colors = clearAssistChipColors(
                    active = sleepPreventionMode != SleepPreventionMode.AlwaysOff,
                    palette = palette
                ),
                border = BorderStroke(
                    1.dp,
                    if (sleepPreventionMode == SleepPreventionMode.AlwaysOff) palette.border else palette.primary
                )
            )
            if (hasClips) {
                AssistChip(
                    onClick = onResetProject,
                    leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null) },
                    label = { Text("초기화", fontWeight = FontWeight.SemiBold) },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = palette.panel,
                        labelColor = palette.secondary,
                        leadingIconContentColor = palette.secondary
                    ),
                    border = BorderStroke(1.dp, palette.border)
                )
            }
        }
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutputQualityPreset.entries.forEach { quality ->
                FilterChip(
                    selected = selectedQuality == quality,
                    onClick = { onSelectQuality(quality) },
                    label = { Text(quality.displayTitle) },
                    leadingIcon = {
                        Icon(Icons.Outlined.MovieCreation, contentDescription = null)
                    },
                    colors = clearFilterChipColors(palette),
                    border = FilterChipDefaults.filterChipBorder(
                        enabled = true,
                        selected = selectedQuality == quality,
                        borderColor = palette.border,
                        selectedBorderColor = palette.primary
                    )
                )
            }
            AssistChip(
                onClick = {},
                leadingIcon = { Icon(Icons.Outlined.MovieCreation, contentDescription = null) },
                label = {
                    Text(
                        OutputQualityPreset.ExportFormatDetail,
                        fontWeight = FontWeight.SemiBold
                    )
                },
                enabled = false,
                colors = AssistChipDefaults.assistChipColors(
                    disabledContainerColor = palette.panel,
                    disabledLabelColor = palette.subText,
                    disabledLeadingIconContentColor = palette.subText
                ),
                border = BorderStroke(1.dp, palette.border)
            )
        }
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilterChip(
                selected = selectedRatio == null,
                onClick = { onSelectRatio(null) },
                label = { Text("자동") },
                leadingIcon = { Icon(Icons.Outlined.AspectRatio, contentDescription = null) },
                colors = clearFilterChipColors(palette),
                border = FilterChipDefaults.filterChipBorder(
                    enabled = true,
                    selected = selectedRatio == null,
                    borderColor = palette.border,
                    selectedBorderColor = palette.primary
                )
            )
            OutputAspectRatio.entries.take(3).forEach { ratio ->
                FilterChip(
                    selected = selectedRatio == ratio,
                    onClick = { onSelectRatio(ratio) },
                    label = { Text(ratio.title) },
                    colors = clearFilterChipColors(palette),
                    border = FilterChipDefaults.filterChipBorder(
                        enabled = true,
                        selected = selectedRatio == ratio,
                        borderColor = palette.border,
                        selectedBorderColor = palette.primary
                    )
                )
            }
        }
    }
}

private fun percentText(value: Double): String {
    return "${(value.coerceIn(0.0, 1.0) * 100).toInt()}%"
}

@Composable
private fun clearAssistChipColors(
    active: Boolean,
    palette: HanClipPalette
) = AssistChipDefaults.assistChipColors(
    containerColor = if (active) palette.chip else palette.panel,
    labelColor = if (active) palette.primary else palette.text,
    leadingIconContentColor = if (active) palette.primary else palette.subText
)

@Composable
private fun clearFilterChipColors(palette: HanClipPalette) = FilterChipDefaults.filterChipColors(
    containerColor = palette.panel,
    labelColor = palette.text,
    iconColor = palette.subText,
    selectedContainerColor = palette.primary,
    selectedLabelColor = Color.White,
    selectedLeadingIconColor = Color.White
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ClipRow(
    palette: HanClipPalette,
    position: Int?,
    clip: ClipItem,
    childSegmentCount: Int,
    isSimilarPhotoGroupExpanded: Boolean,
    onClick: () -> Unit,
    onDecreaseDuration: () -> Unit,
    onIncreaseDuration: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onDelete: () -> Unit,
    onToggleSegmentMode: () -> Unit,
    onResetSegments: () -> Unit,
    onPreviewClip: () -> Unit,
    onToggleSimilarPhotoGroup: () -> Unit,
    onIncludeSimilarPhoto: () -> Unit,
    isReorderMode: Boolean
) {
    Card(
        shape = RoundedCornerShape(8.dp),
        colors = CardDefaults.cardColors(containerColor = clipRowFill(clip, palette)),
        elevation = CardDefaults.cardElevation(defaultElevation = if (clip.isVideoSegmentChild) 0.dp else 1.dp),
        border = BorderStroke(1.dp, clipRowBorder(clip, palette))
    ) {
        Box {
            Box(
                modifier = Modifier
                    .width(if (clip.isVideoSegmentParent) 5.dp else if (clip.isVideoSegmentChild) 3.dp else 0.dp)
                    .fillMaxSize()
                    .background(if (clip.isVideoSegmentParent) palette.primary else palette.secondary)
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onClick)
                    .padding(
                        start = if (clip.isVideoSegmentChild) 18.dp else 10.dp,
                        top = 9.dp,
                        end = 8.dp,
                        bottom = 9.dp
                    ),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = when {
                        clip.isVideoSegmentParent -> "·"
                        clip.isSimilarPhotoGroupMember -> "+"
                        else -> "${position ?: 0}"
                    },
                    style = MaterialTheme.typography.titleMedium,
                    color = palette.primary,
                    fontWeight = if (clip.isVideoSegmentParent) FontWeight.Black else FontWeight.SemiBold,
                    modifier = Modifier.width(18.dp)
                )
                Box(
                    modifier = Modifier
                        .size(
                            width = if (clip.isVideoSegmentChild) 50.dp else 58.dp,
                            height = if (clip.isVideoSegmentChild) 50.dp else 58.dp
                        )
                        .clip(RoundedCornerShape(6.dp))
                        .background(clipFallbackBrush(clip, palette)),
                    contentAlignment = Alignment.Center
                ) {
                    ClipThumbnail(
                        clip = clip,
                        modifier = Modifier.matchParentSize()
                    )
                    Text(
                        text = when {
                            clip.isVideoSegmentParent -> "$childSegmentCount"
                            clip.isSimilarPhotoGroupMember -> "+"
                            else -> "${position ?: 0}"
                        },
                        color = Color.White,
                        fontWeight = FontWeight.Bold
                    )
                    if (clip.similarPhotoGroupCount > 1 && clip.isSimilarPhotoGroupRepresentative && !clip.isVideoSegmentParent) {
                        Surface(
                            modifier = Modifier
                                .align(Alignment.BottomEnd)
                                .padding(4.dp),
                            shape = RoundedCornerShape(50),
                            color = palette.secondary.copy(alpha = 0.9f),
                            border = BorderStroke(1.dp, Color.White.copy(alpha = 0.28f))
                        ) {
                            Text(
                                text = "${clip.similarPhotoGroupCount}",
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
                                color = Color.White,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Black
                            )
                        }
                    }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        text = clipTitle(clip),
                        fontWeight = FontWeight.SemiBold,
                        color = palette.text,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = clipPrimaryTimeText(clip, childSegmentCount),
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.subText,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = clipModeText(clip, childSegmentCount),
                        style = MaterialTheme.typography.labelMedium,
                        color = palette.primary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                        verticalArrangement = Arrangement.spacedBy(5.dp)
                    ) {
                        clipInfoChips(clip, childSegmentCount).forEach { info ->
                            ClipInfoChip(
                                palette = palette,
                                text = info,
                                active = clip.mediaKind == ClipMediaKind.Video
                            )
                        }
                    }
                    if (clip.isSimilarPhotoGroupMember) {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            ClipControlPill(
                                palette = palette,
                                text = "사용",
                                active = true,
                                icon = { Icon(Icons.Outlined.AddCircle, contentDescription = null, modifier = Modifier.size(15.dp)) },
                                onClick = onIncludeSimilarPhoto
                            )
                        }
                    } else if (!clip.isVideoSegmentParent) {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            if (clip.mediaKind == ClipMediaKind.Video) {
                                ClipControlPill(
                                    palette = palette,
                                    text = "미리보기",
                                    active = clip.isVideoSegmentChild,
                                    icon = { Icon(Icons.Outlined.PlayCircle, contentDescription = null, modifier = Modifier.size(15.dp)) },
                                    onClick = onPreviewClip
                                )
                            }
                            if (clip.mediaKind == ClipMediaKind.Video && !clip.isVideoSegmentChild) {
                                ClipControlPill(
                                    palette = palette,
                                    text = if (clip.videoSegmentMode == VideoSegmentMode.Multiple) "다중" else "단일",
                                    active = clip.videoSegmentMode == VideoSegmentMode.Multiple,
                                    icon = { Icon(Icons.Outlined.DragIndicator, contentDescription = null, modifier = Modifier.size(15.dp)) },
                                    onClick = onToggleSegmentMode
                                )
                            }
                            if (clip.similarPhotoGroupCount > 1 && clip.isSimilarPhotoGroupRepresentative) {
                                ClipControlPill(
                                    palette = palette,
                                    text = if (isSimilarPhotoGroupExpanded) "접기" else "묶음",
                                    active = isSimilarPhotoGroupExpanded,
                                    icon = { Icon(Icons.Outlined.Collections, contentDescription = null, modifier = Modifier.size(15.dp)) },
                                    onClick = onToggleSimilarPhotoGroup
                                )
                            }
                            ClipControlPill(
                                palette = palette,
                                text = "-0.5초",
                                icon = { Icon(Icons.Outlined.Remove, contentDescription = null, modifier = Modifier.size(15.dp)) },
                                onClick = onDecreaseDuration
                            )
                            ClipControlPill(
                                palette = palette,
                                text = "+0.5초",
                                icon = { Icon(Icons.Outlined.Add, contentDescription = null, modifier = Modifier.size(15.dp)) },
                                onClick = onIncreaseDuration
                            )
                        }
                    } else if (clip.mediaKind == ClipMediaKind.Video) {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            ClipControlPill(
                                palette = palette,
                                text = "원본보기",
                                active = true,
                                icon = { Icon(Icons.Outlined.PlayCircle, contentDescription = null, modifier = Modifier.size(15.dp)) },
                                onClick = onPreviewClip
                            )
                            ClipControlPill(
                                palette = palette,
                                text = "재분할",
                                active = true,
                                icon = { Icon(Icons.Outlined.AutoFixHigh, contentDescription = null, modifier = Modifier.size(15.dp)) },
                                onClick = onResetSegments
                            )
                            ClipControlPill(
                                palette = palette,
                                text = "단일",
                                icon = { Icon(Icons.Outlined.MovieCreation, contentDescription = null, modifier = Modifier.size(15.dp)) },
                                onClick = onToggleSegmentMode
                            )
                        }
                    }
                }
                Column {
                    if (isReorderMode) {
                        IconButton(onClick = onMoveUp, modifier = Modifier.size(36.dp)) {
                            Icon(Icons.Outlined.KeyboardArrowUp, contentDescription = "위로", tint = palette.text)
                        }
                        IconButton(onClick = onMoveDown, modifier = Modifier.size(36.dp)) {
                            Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = "아래로", tint = palette.text)
                        }
                    }
                    IconButton(onClick = onDelete, modifier = Modifier.size(36.dp)) {
                        Icon(Icons.Outlined.Delete, contentDescription = "삭제", tint = palette.secondary)
                    }
                }
            }
        }
    }
}

@androidx.annotation.OptIn(UnstableApi::class)
@Composable
private fun ClipPreviewDialog(
    clip: ClipItem,
    palette: HanClipPalette,
    childSegmentCount: Int,
    onDismiss: () -> Unit
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false
        )
    ) {
        Surface(color = Color.Black) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .navigationBarsPadding()
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            text = if (clip.isVideoSegmentParent) "원본 영상 미리보기" else "클립 미리보기",
                            color = Color.White,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = clipPreviewSubtitle(clip, childSegmentCount),
                            color = Color.White.copy(alpha = 0.72f),
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Outlined.Close, contentDescription = "닫기", tint = Color.White)
                    }
                }
                ClipPreviewPlayer(
                    clip = clip,
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color.Black)
                )
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                    color = palette.panel.copy(alpha = 0.98f),
                    border = BorderStroke(1.dp, palette.border.copy(alpha = 0.65f))
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                text = clipTitle(clip),
                                color = palette.text,
                                fontWeight = FontWeight.Bold
                            )
                            Text(
                                text = clipModeText(clip, childSegmentCount),
                                color = palette.subText,
                                style = MaterialTheme.typography.bodySmall,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                        Button(
                            onClick = onDismiss,
                            colors = ButtonDefaults.buttonColors(
                                containerColor = palette.primary,
                                contentColor = Color.White
                            )
                        ) {
                            Text("확인")
                        }
                    }
                }
            }
        }
    }
}

@androidx.annotation.OptIn(UnstableApi::class)
@Composable
private fun ClipPreviewPlayer(
    clip: ClipItem,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val isSample = clip.sourceUri.scheme == "sample"
    val mediaItem = remember(clip.id, clip.sourceUri, clip.trimStartSeconds, clip.durationSeconds) {
        if (isSample) {
            null
        } else {
            val sourceDuration = clip.sourceDurationSeconds ?: clip.durationSeconds
            val startSeconds = if (clip.isVideoSegmentParent) 0.0 else clip.trimStartSeconds
            val endSeconds = if (clip.isVideoSegmentParent) {
                sourceDuration
            } else {
                (clip.trimStartSeconds + clip.durationSeconds).coerceAtMost(sourceDuration)
            }
            MediaItem.Builder()
                .setUri(clip.sourceUri)
                .setClipStartPositionMs((startSeconds * 1000).toLong().coerceAtLeast(0))
                .setClipEndPositionMs((endSeconds * 1000).toLong().coerceAtLeast(500))
                .build()
        }
    }
    val player = remember(mediaItem) {
        mediaItem?.let {
            ExoPlayer.Builder(context).build().apply {
                repeatMode = Player.REPEAT_MODE_ONE
                playWhenReady = true
                setMediaItem(it)
                prepare()
            }
        }
    }

    DisposableEffect(player) {
        onDispose {
            player?.release()
        }
    }

    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        if (player != null) {
            AndroidView(
                factory = { viewContext ->
                    PlayerView(viewContext).apply {
                        this.player = player
                        useController = true
                        layoutParams = FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                    }
                },
                modifier = Modifier.matchParentSize()
            )
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    Icons.Outlined.PlayCircle,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(66.dp)
                )
                Spacer(Modifier.height(8.dp))
                Text("실제 영상을 선택하면 미리볼 수 있습니다.", color = Color.White)
            }
        }
    }
}

private fun clipPreviewSubtitle(clip: ClipItem, childSegmentCount: Int): String {
    return if (clip.isVideoSegmentParent) {
        "전체 ${formatClipSeconds(clip.sourceDurationSeconds ?: clip.durationSeconds)} · 자동 클립 ${childSegmentCount}개"
    } else {
        "${formatClipSeconds(clip.trimStartSeconds)} - ${formatClipSeconds(clip.trimEndSeconds)} · ${formatClipSeconds(clip.durationSeconds)}"
    }
}

@Composable
private fun ClipControlPill(
    palette: HanClipPalette,
    text: String,
    modifier: Modifier = Modifier,
    active: Boolean = false,
    icon: @Composable (() -> Unit)? = null,
    onClick: () -> Unit
) {
    Surface(
        modifier = modifier
            .height(30.dp)
            .defaultMinSize(minWidth = 56.dp),
        shape = RoundedCornerShape(7.dp),
        color = if (active) palette.chip else palette.panel,
        contentColor = if (active) palette.primary else palette.text,
        border = BorderStroke(1.dp, if (active) palette.primary else palette.border),
        onClick = onClick
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            if (icon != null) {
                Box(contentAlignment = Alignment.Center) {
                    icon()
                }
            }
            Text(
                text = text,
                color = if (active) palette.primary else palette.text,
                fontWeight = FontWeight.SemiBold,
                fontSize = 12.sp,
                maxLines = 1
            )
        }
    }
}

private fun clipRowFill(clip: ClipItem, palette: HanClipPalette): Color {
    return when {
        clip.isVideoSegmentParent -> palette.chip
        clip.isSimilarPhotoGroupMember -> palette.chip.copy(alpha = 0.58f)
        clip.isVideoSegmentChild -> palette.chip.copy(alpha = 0.72f)
        else -> palette.panel
    }
}

private fun clipRowBorder(clip: ClipItem, palette: HanClipPalette): Color {
    return when {
        clip.isVideoSegmentParent -> palette.primary.copy(alpha = 0.45f)
        clip.isSimilarPhotoGroupMember -> palette.secondary.copy(alpha = 0.28f)
        clip.isVideoSegmentChild -> palette.secondary.copy(alpha = 0.35f)
        else -> palette.border
    }
}

private fun clipFallbackBrush(clip: ClipItem, palette: HanClipPalette): Brush {
    return Brush.verticalGradient(
        if (clip.mediaKind == ClipMediaKind.Video) {
            listOf(palette.secondary, palette.primary)
        } else {
            listOf(palette.primary.copy(alpha = 0.76f), palette.secondary)
        }
    )
}

private fun clipTitle(clip: ClipItem): String {
    if (clip.isVideoSegmentParent) return "원본 영상"
    if (clip.isVideoSegmentChild) return "자동 클립"
    if (clip.isSimilarPhotoGroupMember) return "묶음 사진"
    return when (clip.mediaKind) {
        ClipMediaKind.Video -> "영상 클립"
        ClipMediaKind.Photo -> "사진 클립"
        ClipMediaKind.LivePhoto -> "Live Photo"
    }
}

private fun clipPrimaryTimeText(clip: ClipItem, childSegmentCount: Int): String {
    val source = clip.sourceDurationSeconds ?: clip.durationSeconds
    return if (clip.isVideoSegmentParent) {
        "전체 ${formatClipSeconds(source)} · ${childSegmentCount}개"
    } else if (clip.mediaKind == ClipMediaKind.Video) {
        "${formatClipSeconds(clip.durationSeconds)} / 전체 ${formatClipSeconds(source)}"
    } else {
        formatClipSeconds(clip.durationSeconds)
    }
}

private fun clipModeText(clip: ClipItem, childSegmentCount: Int): String {
    return when {
        clip.isVideoSegmentParent -> "스윙 피크 자동 분할 ${childSegmentCount}개"
        clip.isVideoSegmentChild -> "타격점 중심 구간"
        clip.isSimilarPhotoGroupMember -> "대표 컷 뒤에 묶임 · 사용하면 영상에 포함"
        clip.similarPhotoGroupCount > 1 -> "비슷한 사진 ${clip.similarPhotoGroupCount}장 중 대표 컷"
        clip.videoSegmentMode == VideoSegmentMode.Multiple -> "자동 타격점 후보 ${clip.audioPeakTimesSeconds.size}개"
        else -> "단일 구간"
    }
}

private fun clipInfoChips(clip: ClipItem, childSegmentCount: Int): List<String> {
    val resolution = "${clip.sourceWidth}x${clip.sourceHeight}".takeIf {
        clip.sourceWidth > 1 && clip.sourceHeight > 1
    }
    return buildList {
        add(
            when (clip.mediaKind) {
                ClipMediaKind.Video -> "영상"
                ClipMediaKind.Photo -> "사진"
                ClipMediaKind.LivePhoto -> clip.livePhotoMode.title
            }
        )
        resolution?.let { add(it) }
        if (clip.mediaKind == ClipMediaKind.Video && !clip.isVideoSegmentParent) {
            add("시작 ${formatClipSeconds(clip.trimStartSeconds)}")
        }
        if (clip.audioPeakTimesSeconds.isNotEmpty()) {
            add("타격점 ${clip.audioPeakTimesSeconds.size}")
        } else if (clip.audioPeakTimeSeconds != null) {
            add("타격점 1")
        }
        if (clip.isVideoSegmentParent && childSegmentCount > 0) {
            add("자동 ${childSegmentCount}컷")
        }
        if (clip.similarPhotoGroupCount > 1) {
            add("묶음 ${clip.similarPhotoGroupCount}")
        }
    }
}

@Composable
private fun ClipInfoChip(
    palette: HanClipPalette,
    text: String,
    active: Boolean
) {
    Surface(
        shape = RoundedCornerShape(50),
        color = if (active) palette.primary.copy(alpha = 0.08f) else palette.chip.copy(alpha = 0.72f),
        border = BorderStroke(1.dp, if (active) palette.primary.copy(alpha = 0.22f) else palette.border)
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 7.dp, vertical = 3.dp),
            color = if (active) palette.primary else palette.subText,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1
        )
    }
}

private fun formatClipSeconds(seconds: Double): String {
    val totalTenths = (seconds * 10).toInt().coerceAtLeast(0)
    val minutes = totalTenths / 600
    val remaining = (totalTenths % 600) / 10.0
    return "%d:%04.1f".format(minutes, remaining)
}

@Composable
private fun ClipThumbnail(
    clip: ClipItem,
    modifier: Modifier
) {
    val context = LocalContext.current
    val thumbnail by produceState<Bitmap?>(initialValue = null, clip.thumbnailUri, clip.mediaKind) {
        val uri = clip.thumbnailUri ?: clip.sourceUri
        value = if (uri.scheme == "sample") {
            null
        } else {
            MediaImportReader.loadThumbnailBitmap(context, uri, clip.mediaKind)
        }
    }

    thumbnail?.let { bitmap ->
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = modifier
        )
        Box(
            modifier = modifier
                .background(Color.Black.copy(alpha = 0.18f))
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun GlobalTimePanel(
    defaultDuration: Double,
    hasVideoClips: Boolean,
    palette: HanClipPalette,
    onSetDuration: (Double) -> Unit,
    onApplyAll: () -> Unit,
    onSelectFullRange: () -> Unit
) {
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text("전체 영상 시간", fontWeight = FontWeight.Bold, color = palette.text)
                    Text(
                        "기본 길이를 전체 클립에 적용합니다.",
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.subText
                    )
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    IconButton(
                        onClick = { onSetDuration(defaultDuration - 0.5) },
                        modifier = Modifier.size(34.dp)
                    ) {
                        Icon(Icons.Outlined.Remove, contentDescription = "전체 시간 줄이기", tint = palette.secondary)
                    }
                    Text("%.1f초".format(defaultDuration), fontWeight = FontWeight.Bold, color = palette.primary)
                    IconButton(
                        onClick = { onSetDuration(defaultDuration + 0.5) },
                        modifier = Modifier.size(34.dp)
                    ) {
                        Icon(Icons.Outlined.Add, contentDescription = "전체 시간 늘리기", tint = palette.secondary)
                    }
                }
            }
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                listOf(1.5, 2.0, 3.0, 4.0, 5.0, 6.0).forEach { seconds ->
                    FilterChip(
                        selected = defaultDuration == seconds,
                        onClick = { onSetDuration(seconds) },
                        label = { Text("%.1f".format(seconds)) },
                        colors = clearFilterChipColors(palette),
                        border = FilterChipDefaults.filterChipBorder(
                            enabled = true,
                            selected = defaultDuration == seconds,
                            borderColor = palette.border,
                            selectedBorderColor = palette.primary
                        )
                    )
                }
            }
            Button(
                onClick = onApplyAll,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = palette.primary,
                    contentColor = Color.White
                )
            ) {
                Text("모든 클립에 %.1f초 적용".format(defaultDuration))
            }
            OutlinedButton(
                onClick = onSelectFullRange,
                enabled = hasVideoClips,
                modifier = Modifier.fillMaxWidth(),
                border = BorderStroke(1.dp, palette.border),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = palette.panel,
                    contentColor = palette.text,
                    disabledContainerColor = palette.chip,
                    disabledContentColor = palette.subText
                )
            ) {
                Text("영상은 원본 전체로 맞추기")
            }
        }
    }
}

@Composable
private fun BottomMakeBar(
    modifier: Modifier,
    palette: HanClipPalette,
    isExporting: Boolean,
    clipCount: Int,
    totalSeconds: Double,
    qualityTitle: String,
    onMakeMovie: () -> Unit
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = palette.panel.copy(alpha = 0.96f),
        shadowElevation = 8.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "${clipCount}개 클립 · ${formatSummaryDuration(totalSeconds)} · $qualityTitle · ${OutputQualityPreset.ExportFormatTitle}",
                color = palette.subText,
                fontWeight = FontWeight.SemiBold,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Button(
                onClick = onMakeMovie,
                enabled = !isExporting,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = palette.primary,
                    contentColor = Color.White,
                    disabledContainerColor = palette.chip,
                    disabledContentColor = palette.subText
                )
            ) {
                Icon(Icons.Outlined.MovieCreation, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(if (isExporting) "만드는 중..." else "영화 만들기")
            }
        }
    }
}
