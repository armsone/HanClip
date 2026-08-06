package com.hanclip.android.feature.preview

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Fullscreen
import androidx.compose.material.icons.outlined.FullscreenExit
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.Photo
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material.icons.outlined.VideoFile
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.hanclip.android.core.media.VideoSaveShare
import com.hanclip.android.core.model.OutputAspectRatio
import com.hanclip.android.core.model.OutputQualityPreset
import com.hanclip.android.core.model.WatermarkSettings
import com.hanclip.android.core.project.ExportedMovieSummary
import com.hanclip.android.core.project.hanClipCompletionTitle
import com.hanclip.android.core.theme.HanClipPalette
import com.hanclip.android.core.theme.HanClipThemeStore
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class PreviewMovieSummary(
    val presetTitle: String,
    val clipCount: Int,
    val totalDurationSeconds: Double,
    val outputAspectRatio: OutputAspectRatio?,
    val outputQualityPreset: OutputQualityPreset = OutputQualityPreset.Standard,
    val hasBackgroundMusic: Boolean,
    val watermarkSettings: WatermarkSettings,
    val hasWatermark: Boolean = watermarkSettings.shouldRender,
    val detailStatusKnown: Boolean = true
) {
    companion object {
        fun fromHistory(summary: ExportedMovieSummary): PreviewMovieSummary {
            val hasMusic = summary.hasBackgroundMusic
            val hasWatermark = summary.hasWatermark
            val hasTextOverlay = summary.hasTextOverlay
            val hasLogoOverlay = summary.hasLogoOverlay
            return PreviewMovieSummary(
                presetTitle = hanClipCompletionTitle(summary.title),
                clipCount = summary.clipCount,
                totalDurationSeconds = summary.totalDurationSeconds,
                outputAspectRatio = summary.outputAspectRatio,
                outputQualityPreset = summary.outputQualityPreset ?: OutputQualityPreset.Standard,
                hasBackgroundMusic = hasMusic ?: false,
                watermarkSettings = WatermarkSettings(
                    isEnabled = hasTextOverlay == true,
                    logoEnabled = hasLogoOverlay == true
                ),
                hasWatermark = hasWatermark ?: (hasTextOverlay == true || hasLogoOverlay == true),
                detailStatusKnown = hasMusic != null && hasTextOverlay != null && hasLogoOverlay != null
            )
        }
    }
}

@Composable
fun PreviewRoute(
    exportedVideoUri: Uri?,
    movieSummary: PreviewMovieSummary,
    canReturnToEditor: Boolean = true,
    onEdit: () -> Unit,
    onDone: () -> Unit,
    onSavingStateChanged: (Boolean) -> Unit = {},
    onSavedMovie: (Uri) -> Unit
) {
    val context = LocalContext.current
    val palette = remember { HanClipThemeStore.load(context).palette }
    var message by remember { mutableStateOf<String?>(null) }
    var showSaveOptions by remember { mutableStateOf(false) }
    var showFullscreenPreview by remember { mutableStateOf(false) }
    var isSavingVideo by remember { mutableStateOf(false) }
    var pendingMovieFileName by remember { mutableStateOf(VideoSaveShare.newMovieFileName(movieSummary.presetTitle)) }
    var preferredShareUri by remember(exportedVideoUri) { mutableStateOf(exportedVideoUri) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(isSavingVideo) {
        onSavingStateChanged(isSavingVideo)
    }
    DisposableEffect(Unit) {
        onDispose {
            onSavingStateChanged(false)
        }
    }

    fun performGallerySave() {
        if (exportedVideoUri == null) {
            message = "저장할 영상이 없습니다."
            return
        }
        isSavingVideo = true
        scope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    VideoSaveShare.saveToGallery(
                        context = context,
                        sourceUri = exportedVideoUri,
                        label = movieSummary.presetTitle,
                        filename = pendingMovieFileName
                    )
                }
            }.onSuccess { savedUri ->
                preferredShareUri = savedUri
                onSavedMovie(savedUri)
                message = "저장 완료 · Android 기본 사진첩의 HanClip 앨범에서 확인하세요."
            }.onFailure {
                message = "Android 기본 사진첩 저장에 실패했습니다. 파일 저장을 선택해 원하는 위치에 다시 저장해 주세요."
            }
            isSavingVideo = false
        }
    }
    val legacyStoragePermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            performGallerySave()
        } else {
            message = "기본 사진첩 저장에는 저장 권한이 필요합니다. 권한을 허용하거나 파일 저장을 선택해 주세요."
        }
    }
    val createVideoDocumentLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("video/mp4")
    ) { targetUri ->
        if (targetUri == null || exportedVideoUri == null) return@rememberLauncherForActivityResult
        isSavingVideo = true
        scope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    VideoSaveShare.copyToUri(context, exportedVideoUri, targetUri)
                }
            }.onSuccess {
                preferredShareUri = targetUri
                onSavedMovie(targetUri)
                message = "파일 저장 완료 · 방금 선택한 MP4로 공유할 수 있습니다."
            }.onFailure {
                message = "파일 저장에 실패했습니다. 저장 위치 권한을 확인해 주세요."
            }
            isSavingVideo = false
        }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 18.dp),
        contentPadding = PaddingValues(top = 14.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Text(
                text = "완성 시사회",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = palette.text
            )
        }
        item {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f),
                shape = RoundedCornerShape(26.dp),
                color = Color.Black
            ) {
                Box(contentAlignment = Alignment.Center) {
                    if (exportedVideoUri != null) {
                        ExportedVideoPlayer(exportedVideoUri)
                        IconButton(
                            onClick = { showFullscreenPreview = true },
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .padding(10.dp)
                        ) {
                            Icon(
                                Icons.Outlined.Fullscreen,
                                contentDescription = "전체 화면",
                                tint = Color.White
                            )
                        }
                    } else {
                        Icon(
                            imageVector = Icons.Outlined.PlayCircle,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.height(72.dp)
                        )
                    }
                }
            }
        }
        item {
            PreviewSummaryPanel(
                summary = movieSummary,
                palette = palette
            )
        }
        item {
            PreviewActionRow(
                palette = palette,
                canReturnToEditor = canReturnToEditor,
                onEdit = onEdit,
                onShare = {
                    val shareUri = preferredShareUri ?: exportedVideoUri
                    if (shareUri == null) {
                        message = "공유할 영상이 없습니다."
                    } else {
                        runCatching {
                            VideoSaveShare.shareVideo(context, shareUri)
                        }.onFailure {
                            message = "공유 화면을 열지 못했습니다. 기본 사진첩 저장 후 다시 공유해 주세요."
                        }
                    }
                },
                onRelease = {
                    if (exportedVideoUri == null) {
                        message = "저장할 영상이 없습니다."
                    } else {
                        pendingMovieFileName = VideoSaveShare.newMovieFileName(movieSummary.presetTitle)
                        showSaveOptions = true
                    }
                }
            )
        }
        item {
            OutlinedButton(
                onClick = onDone,
                modifier = Modifier.fillMaxWidth(),
                border = BorderStroke(1.dp, palette.border),
                shape = RoundedCornerShape(50),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = palette.panel,
                    contentColor = palette.text
                )
            ) {
                Icon(Icons.Outlined.Home, contentDescription = null)
                Text("홈으로")
            }
        }
        message?.let {
            item {
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                    color = palette.panel,
                    border = BorderStroke(1.dp, palette.border)
                ) {
                    Text(
                        text = it,
                        modifier = Modifier.padding(14.dp),
                        fontWeight = FontWeight.SemiBold,
                        color = palette.subText
                    )
                }
            }
        }
    }
    if (showSaveOptions) {
        SaveOptionsSheet(
            palette = palette,
            fileName = pendingMovieFileName,
            onDismiss = { showSaveOptions = false },
            onSaveToGallery = {
                showSaveOptions = false
                if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
                    ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    legacyStoragePermissionLauncher.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                } else {
                    performGallerySave()
                }
            },
            onSaveToFile = {
                showSaveOptions = false
                createVideoDocumentLauncher.launch(pendingMovieFileName)
            }
        )
    }
    if (showFullscreenPreview && exportedVideoUri != null) {
        FullscreenPreviewDialog(
            uri = exportedVideoUri,
            onClose = { showFullscreenPreview = false }
        )
    }
    if (isSavingVideo) {
        SavingMovieDialog(palette)
    }
}

@Composable
private fun PreviewSummaryPanel(
    summary: PreviewMovieSummary,
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
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = "완성 정보",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = palette.text
                    )
                    Text(
                        text = summary.presetTitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.subText
                    )
                }
                Surface(
                    shape = RoundedCornerShape(50),
                    color = palette.chip,
                    border = BorderStroke(1.dp, palette.border)
                ) {
                    Text(
                        text = if (summary.clipCount > 0) "${summary.clipCount}개 클립" else "클립 없음",
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Bold,
                        color = palette.primary
                    )
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                SummaryInfoCell(
                    label = "전체 길이",
                    value = formatPreviewDuration(summary.totalDurationSeconds),
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
                SummaryInfoCell(
                    label = "화면",
                    value = previewAspectRatioText(summary.outputAspectRatio),
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                SummaryInfoCell(
                    label = "품질",
                    value = summary.outputQualityPreset.chipTitle,
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
                SummaryInfoCell(
                    label = "형식",
                    value = OutputQualityPreset.ExportFormatDetail,
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                SummaryStatusChip(
                    label = when {
                        !summary.detailStatusKnown -> "저장 이력"
                        summary.hasBackgroundMusic -> "음악 적용"
                        else -> "음악 없음"
                    },
                    active = summary.hasBackgroundMusic,
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
                SummaryStatusChip(
                    label = previewWatermarkStatusText(summary),
                    active = summary.hasWatermark,
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
            }
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(8.dp),
                color = palette.chip,
                border = BorderStroke(1.dp, palette.border)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(
                        Icons.Outlined.Photo,
                        contentDescription = null,
                        tint = palette.primary,
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        text = "Android 기본 사진첩의 HanClip 앨범에 저장한 뒤 바로 공유할 수 있습니다.",
                        color = palette.subText,
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

private fun previewWatermarkStatusText(summary: PreviewMovieSummary): String {
    if (!summary.detailStatusKnown) return "정보 확인"
    val hasText = summary.watermarkSettings.shouldRenderText
    val hasLogo = summary.watermarkSettings.logoEnabled
    return when {
        hasText && hasLogo -> "자막/로고 적용"
        hasText -> "자막 적용"
        hasLogo -> "HanClip 로고"
        else -> "자막/로고 없음"
    }
}

private fun previewAspectRatioText(ratio: OutputAspectRatio?): String {
    return ratio?.let { "${it.title} · ${it.width}x${it.height}" } ?: "자동 비율"
}

@Composable
private fun SummaryInfoCell(
    label: String,
    value: String,
    palette: HanClipPalette,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = palette.subText
            )
            Text(
                text = value,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = palette.text
            )
        }
    }
}

@Composable
private fun SummaryStatusChip(
    label: String,
    active: Boolean,
    palette: HanClipPalette,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(50),
        color = if (active) palette.primary.copy(alpha = 0.14f) else palette.chip,
        border = BorderStroke(
            1.dp,
            if (active) palette.primary.copy(alpha = 0.42f) else palette.border
        )
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Surface(
                modifier = Modifier.size(8.dp),
                shape = RoundedCornerShape(50),
                color = if (active) palette.primary else palette.subText.copy(alpha = 0.45f)
            ) {}
            Box(Modifier.width(8.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = if (active) palette.primary else palette.subText
            )
        }
    }
}

private fun formatPreviewDuration(seconds: Double): String {
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
private fun PreviewActionRow(
    palette: HanClipPalette,
    canReturnToEditor: Boolean,
    onEdit: () -> Unit,
    onShare: () -> Unit,
    onRelease: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        OutlinedButton(
            onClick = onEdit,
            modifier = Modifier
                .weight(1f)
                .height(48.dp),
            border = BorderStroke(1.dp, palette.border),
            shape = RoundedCornerShape(50),
            colors = ButtonDefaults.outlinedButtonColors(
                containerColor = palette.chip,
                contentColor = palette.text
            )
        ) {
            Icon(
                if (canReturnToEditor) Icons.Outlined.Edit else Icons.Outlined.Home,
                contentDescription = null
            )
            Text(if (canReturnToEditor) "다시 편집" else "목록으로")
        }
        OutlinedButton(
            onClick = onShare,
            modifier = Modifier
                .weight(0.86f)
                .height(48.dp),
            border = BorderStroke(1.dp, palette.border),
            shape = RoundedCornerShape(50),
            colors = ButtonDefaults.outlinedButtonColors(
                containerColor = palette.chip,
                contentColor = palette.text
            )
        ) {
            Icon(Icons.Outlined.IosShare, contentDescription = null)
            Text("공유")
        }
        Button(
            onClick = onRelease,
            modifier = Modifier
                .weight(1f)
                .height(48.dp),
            shape = RoundedCornerShape(50),
            colors = ButtonDefaults.buttonColors(
                containerColor = palette.primary,
                contentColor = Color.White
            )
        ) {
            Icon(Icons.Outlined.Download, contentDescription = null)
            Text("사진첩에 저장")
        }
    }
}

@Composable
private fun SaveOptionsSheet(
    palette: HanClipPalette,
    fileName: String,
    onDismiss: () -> Unit,
    onSaveToGallery: () -> Unit,
    onSaveToFile: () -> Unit
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false
        )
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(palette.background)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .navigationBarsPadding()
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text(
                            text = "완성본 저장 위치",
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = palette.text
                        )
                        Text(
                            text = "기본 사진첩의 HanClip 앨범에 저장하거나 MP4 파일로 보관합니다.",
                            color = palette.subText
                        )
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Outlined.Close, contentDescription = "취소", tint = palette.text)
                    }
                }
                SaveDestinationCard(
                    title = "Android 기본 사진첩",
                    badge = "추천",
                    body = "폰 기본 사진첩의 HanClip 앨범에 남기고 바로 공유합니다.",
                    icon = Icons.Outlined.Photo,
                    palette = palette,
                    primary = true,
                    onClick = onSaveToGallery
                )
                SaveDestinationCard(
                    title = "파일로 저장",
                    badge = "대안",
                    body = "원하는 폴더와 파일명을 직접 선택해 MP4로 보관합니다.",
                    icon = Icons.Outlined.FolderOpen,
                    palette = palette,
                    primary = false,
                    onClick = onSaveToFile
                )
                SaveFileNameNote(fileName = fileName, palette = palette)
                SaveFormatNote(palette)
                OutlinedButton(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth(),
                    border = BorderStroke(1.dp, palette.border),
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = palette.panel,
                        contentColor = palette.text
                    )
                ) {
                    Icon(Icons.Outlined.Close, contentDescription = null)
                    Text("취소")
                }
            }
        }
    }
}

@Composable
private fun SaveFileNameNote(
    fileName: String,
    palette: HanClipPalette
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = palette.panel,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Text(
                text = "저장 파일명",
                color = palette.subText,
                style = MaterialTheme.typography.labelMedium
            )
            Text(
                text = fileName,
                color = palette.text,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun SaveFormatNote(palette: HanClipPalette) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Surface(
                shape = RoundedCornerShape(8.dp),
                color = palette.panel,
                border = BorderStroke(1.dp, palette.border)
            ) {
                Icon(
                    imageVector = Icons.Outlined.VideoFile,
                    contentDescription = null,
                    tint = palette.primary,
                    modifier = Modifier.padding(9.dp)
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = "저장 형식 · 공유 호환",
                    color = palette.text,
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.labelLarge
                )
                Text(
                    text = "${OutputQualityPreset.ExportFormatDetail} · Android/iPhone 모두 재생 가능",
                    color = palette.subText,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    }
}

@Composable
private fun SaveDestinationCard(
    title: String,
    badge: String,
    body: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    palette: HanClipPalette,
    primary: Boolean,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = if (primary) palette.primary else palette.panel,
        border = BorderStroke(1.dp, if (primary) palette.primary else palette.border),
        onClick = onClick
    ) {
        Row(
            modifier = Modifier.padding(18.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Surface(
                shape = RoundedCornerShape(8.dp),
                color = if (primary) Color.White.copy(alpha = 0.16f) else palette.chip,
                border = BorderStroke(
                    1.dp,
                    if (primary) Color.White.copy(alpha = 0.22f) else palette.border
                )
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = if (primary) Color.White else palette.primary,
                    modifier = Modifier.padding(12.dp)
                )
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = title,
                        color = if (primary) Color.White else palette.text,
                        fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    Surface(
                        shape = RoundedCornerShape(50),
                        color = if (primary) Color.White.copy(alpha = 0.18f) else palette.chip,
                        border = BorderStroke(
                            1.dp,
                            if (primary) Color.White.copy(alpha = 0.24f) else palette.border
                        )
                    ) {
                        Text(
                            text = badge,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                            color = if (primary) Color.White else palette.primary,
                            fontWeight = FontWeight.Bold,
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                }
                Text(
                    text = body,
                    color = if (primary) Color.White.copy(alpha = 0.82f) else palette.subText,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    }
}

@OptIn(UnstableApi::class)
@Composable
private fun FullscreenPreviewDialog(
    uri: Uri,
    onClose: () -> Unit
) {
    var isLooping by remember { mutableStateOf(true) }
    var isFillMode by remember { mutableStateOf(false) }
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false
        )
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
        ) {
            ExportedVideoPlayer(
                uri = uri,
                repeatMode = if (isLooping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF,
                resizeMode = if (isFillMode) {
                    AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                } else {
                    AspectRatioFrameLayout.RESIZE_MODE_FIT
                }
            )
            Row(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(18.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FullscreenCircleButton(
                    onClick = { isLooping = !isLooping },
                    active = isLooping,
                    contentDescription = if (isLooping) "반복 재생 끄기" else "반복 재생 켜기"
                ) {
                    Icon(Icons.Outlined.Repeat, contentDescription = null, tint = Color.White)
                }
                FullscreenCircleButton(
                    onClick = { isFillMode = !isFillMode },
                    active = isFillMode,
                    contentDescription = if (isFillMode) "화면에 맞추기" else "화면 채우기"
                ) {
                    Icon(
                        if (isFillMode) Icons.Outlined.FullscreenExit else Icons.Outlined.Fullscreen,
                        contentDescription = null,
                        tint = Color.White
                    )
                }
                FullscreenCircleButton(
                    onClick = onClose,
                    contentDescription = "닫기"
                ) {
                    Icon(Icons.Outlined.Close, contentDescription = null, tint = Color.White)
                }
            }
        }
    }
}

@Composable
private fun FullscreenCircleButton(
    onClick: () -> Unit,
    contentDescription: String,
    active: Boolean = false,
    icon: @Composable () -> Unit
) {
    Surface(
        modifier = Modifier.height(44.dp),
        shape = RoundedCornerShape(50),
        color = Color.White.copy(alpha = if (active) 0.24f else 0.14f),
        border = BorderStroke(1.dp, Color.White.copy(alpha = if (active) 0.42f else 0.24f)),
        onClick = onClick
    ) {
        Box(
            modifier = Modifier
                .height(44.dp)
                .padding(horizontal = 12.dp),
            contentAlignment = Alignment.Center
        ) {
            Box(contentAlignment = Alignment.Center) {
                icon()
            }
        }
    }
}

@Composable
private fun SavingMovieDialog(palette: HanClipPalette) {
    Dialog(
        onDismissRequest = {},
        properties = DialogProperties(
            dismissOnBackPress = false,
            dismissOnClickOutside = false
        )
    ) {
        Surface(
            shape = RoundedCornerShape(8.dp),
            color = palette.panel,
            shadowElevation = 10.dp
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 28.dp, vertical = 26.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                CircularProgressIndicator(
                    color = palette.primary,
                    trackColor = palette.chip
                )
                Text(
                    text = "완성본을 저장하는 중...",
                    color = palette.text,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "MP4 영상을 Android 기본 사진첩 또는 선택한 파일 위치에 저장하고 있습니다.",
                    color = palette.subText,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    }
}

@OptIn(UnstableApi::class)
@Composable
private fun ExportedVideoPlayer(uri: Uri) {
    ExportedVideoPlayer(
        uri = uri,
        repeatMode = Player.REPEAT_MODE_OFF,
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
    )
}

@OptIn(UnstableApi::class)
@Composable
private fun ExportedVideoPlayer(
    uri: Uri,
    repeatMode: Int,
    resizeMode: Int
) {
    val context = LocalContext.current
    val player = remember(uri) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(uri))
            this.repeatMode = repeatMode
            playWhenReady = true
            prepare()
        }
    }
    player.repeatMode = repeatMode
    player.playWhenReady = true
    DisposableEffect(player) {
        onDispose { player.release() }
    }
    AndroidView(
        factory = { viewContext ->
            PlayerView(viewContext).apply {
                this.player = player
                useController = true
                this.resizeMode = resizeMode
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            }
        },
        update = { view ->
            view.player = player
            view.resizeMode = resizeMode
        },
        modifier = Modifier.fillMaxSize()
    )
}
