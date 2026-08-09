package com.hanclip.android.feature.editor

import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.LibraryMusic
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.PauseCircle
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.hanclip.android.core.model.BackgroundMusicSample
import com.hanclip.android.core.theme.HanClipPalette

private val MusicPrimary = Color(0xFF0B7A4E)
private val MusicText = Color(0xFF14221A)
private val MusicSubText = Color(0xFF46564C)
private val MusicBorder = Color(0xFFD4DDD7)

@Composable
fun MusicSettingsSheet(
    currentTitle: String?,
    currentUri: Uri?,
    currentSampleId: String?,
    musicVolume: Double,
    originalAudioVolume: Double,
    loopsToFillVideo: Boolean,
    fadeInEnabled: Boolean,
    fadeOutEnabled: Boolean,
    palette: HanClipPalette,
    fullScreen: Boolean = false,
    onUseSample: (BackgroundMusicSample) -> Unit,
    onPickFile: () -> Unit,
    onOpenBrowser: () -> Unit,
    onRemove: () -> Unit,
    onMusicVolumeChange: (Double) -> Unit,
    onOriginalAudioVolumeChange: (Double) -> Unit,
    onLoopingChange: (Boolean) -> Unit,
    onFadeInChange: (Boolean) -> Unit,
    onFadeOutChange: (Boolean) -> Unit,
    onDismiss: () -> Unit
) {
    if (fullScreen) FullScreenDialogSystemBars(palette.solidPanel)
    val context = LocalContext.current
    val initialMusicVolume = remember { musicVolume }
    val initialOriginalAudioVolume = remember { originalAudioVolume }
    val initialLoopsToFillVideo = remember { loopsToFillVideo }
    val initialFadeInEnabled = remember { fadeInEnabled }
    val initialFadeOutEnabled = remember { fadeOutEnabled }
    var previewTarget by remember { mutableStateOf<MusicPreviewTarget?>(null) }
    val previewPlayer = remember {
        ExoPlayer.Builder(context).build().apply {
            repeatMode = Player.REPEAT_MODE_ONE
        }
    }

    LaunchedEffect(previewTarget, musicVolume) {
        val target = previewTarget
        if (target == null) {
            previewPlayer.stop()
        } else {
            previewPlayer.volume = musicVolume.toFloat().coerceIn(0f, 1f)
            previewPlayer.setMediaItem(MediaItem.fromUri(target.uri))
            previewPlayer.prepare()
            previewPlayer.playWhenReady = true
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            previewPlayer.release()
        }
    }

    Surface(
        modifier = if (fullScreen) Modifier.fillMaxSize() else Modifier.fillMaxWidth(),
        shape = if (fullScreen) RoundedCornerShape(0.dp) else RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp),
        color = if (fullScreen) palette.solidPanel else palette.panel
    ) {
        Column(
            modifier = Modifier
                .then(if (fullScreen) Modifier.fillMaxSize().statusBarsPadding() else Modifier.fillMaxWidth())
                .then(if (fullScreen) Modifier.background(palette.background) else Modifier)
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            if (fullScreen) {
                FullScreenSettingsHeader(
                    title = "음악",
                    titleIcon = Icons.Outlined.MusicNote,
                    resetDescription = "음악 설정 되돌리기",
                    palette = palette,
                    onReset = {
                        onMusicVolumeChange(initialMusicVolume)
                        onOriginalAudioVolumeChange(initialOriginalAudioVolume)
                        onLoopingChange(initialLoopsToFillVideo)
                        onFadeInChange(initialFadeInEnabled)
                        onFadeOutChange(initialFadeOutEnabled)
                    },
                    onDismiss = onDismiss
                )
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "음악",
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                            color = palette.text
                        )
                        Text(
                            currentTitle ?: "배경음악은 낮게 얹고 스윙 타격음은 선명하게 남깁니다.",
                            color = palette.subText,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Outlined.Close, contentDescription = "닫기", tint = palette.text)
                    }
                }
            }

            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(8.dp),
                color = palette.panel,
                border = BorderStroke(1.dp, palette.border)
            ) {
                Column(
                    modifier = Modifier.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    if (currentTitle != null && currentUri != null && currentSampleId == null) {
                        SelectedMusicPreviewRow(
                            title = currentTitle,
                            isPlaying = previewTarget?.id == SelectedMusicPreviewId,
                            palette = palette,
                            onTogglePreview = {
                                previewTarget = togglePreviewTarget(
                                    current = previewTarget,
                                    next = MusicPreviewTarget(SelectedMusicPreviewId, currentUri)
                                )
                            }
                        )
                    }
                    BackgroundMusicSample.entries.chunked(2).forEach { rowSamples ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            rowSamples.forEach { sample ->
                                SampleMusicButton(
                                    sample = sample,
                                    selected = currentSampleId == sample.id,
                                    isPreviewing = previewTarget?.id == sample.id,
                                    palette = palette,
                                    modifier = Modifier.weight(1f),
                                    onClick = { onUseSample(sample) },
                                    onTogglePreview = {
                                        previewTarget = togglePreviewTarget(
                                            current = previewTarget,
                                            next = MusicPreviewTarget(
                                                sample.id,
                                                sample.previewUri(context.packageName)
                                            )
                                        )
                                    }
                                )
                            }
                        }
                    }
                    Box(Modifier.fillMaxWidth().height(1.dp).background(palette.border))
                    OutlinedButton(
                        modifier = Modifier.fillMaxWidth().height(42.dp),
                        onClick = onOpenBrowser,
                        shape = RoundedCornerShape(8.dp),
                        border = BorderStroke(1.dp, palette.border),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = palette.primary.copy(alpha = 0.10f),
                            contentColor = palette.primary
                        )
                    ) {
                        Icon(Icons.Outlined.Public, contentDescription = null)
                        Text("브라우저")
                    }
                    Box(Modifier.fillMaxWidth().height(1.dp).background(palette.border))
                    OutlinedButton(
                        modifier = Modifier.fillMaxWidth().height(42.dp),
                        onClick = onPickFile,
                        shape = RoundedCornerShape(8.dp),
                        border = BorderStroke(1.dp, palette.border),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = palette.primary.copy(alpha = 0.10f),
                            contentColor = palette.primary
                        )
                    ) {
                        Icon(Icons.Outlined.FolderOpen, contentDescription = null)
                        Text("음악 파일 불러오기")
                    }
                    if (currentTitle != null) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.End
                        ) {
                            OutlinedButton(
                                onClick = {},
                                shape = RoundedCornerShape(8.dp),
                                colors = ButtonDefaults.outlinedButtonColors(
                                    containerColor = palette.primary,
                                    contentColor = Color.White
                                )
                            ) { Text("사용") }
                            OutlinedButton(
                                onClick = onRemove,
                                shape = RoundedCornerShape(8.dp),
                                colors = ButtonDefaults.outlinedButtonColors(
                                    containerColor = palette.chip,
                                    contentColor = palette.text
                                )
                            ) { Text("안함") }
                        }
                    }
                }
            }

            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(8.dp),
                color = palette.panel,
                border = BorderStroke(1.dp, palette.border)
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    MusicVolumePanel(
                        title = "음량",
                        value = musicVolume,
                        enabled = currentTitle != null,
                        palette = palette,
                        onValueChange = onMusicVolumeChange
                    )
                    Box(Modifier.fillMaxWidth().height(1.dp).background(palette.border))
                    MusicVolumePanel(
                        title = "원본 소리",
                        value = originalAudioVolume,
                        enabled = true,
                        palette = palette,
                        onValueChange = onOriginalAudioVolumeChange
                    )
                }
            }

            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(8.dp),
                color = palette.panel,
                border = BorderStroke(1.dp, palette.border)
            ) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    MusicFadeToggle(
                        title = "페이드 인",
                        checked = fadeInEnabled,
                        enabled = currentTitle != null,
                        onCheckedChange = onFadeInChange,
                        modifier = Modifier.weight(1f)
                    )
                    Box(Modifier.width(1.dp).height(24.dp).background(palette.border))
                    MusicFadeToggle(
                        title = "페이드 아웃",
                        checked = fadeOutEnabled,
                        enabled = currentTitle != null,
                        onCheckedChange = onFadeOutChange,
                        modifier = Modifier.weight(1f)
                    )
                }
            }

            Text(
                "받은 음악은 Downloads/HanClip 폴더에서 `음악 파일 불러오기`로 적용합니다.",
                color = palette.subText,
                style = MaterialTheme.typography.bodySmall
            )
            Spacer(Modifier.height(6.dp))
        }
    }
}

@Composable
private fun SelectedMusicPreviewRow(
    title: String,
    isPlaying: Boolean,
    palette: HanClipPalette,
    onTogglePreview: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, if (isPlaying) palette.primary else palette.border)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onTogglePreview) {
                Icon(
                    if (isPlaying) Icons.Outlined.PauseCircle else Icons.Outlined.PlayCircle,
                    contentDescription = if (isPlaying) "미리듣기 정지" else "미리듣기",
                    tint = if (isPlaying) palette.primary else palette.text
                )
            }
            Column(Modifier.weight(1f)) {
                Text("선택된 음악 미리듣기", color = palette.text, fontWeight = FontWeight.Bold)
                Text(
                    title,
                    color = palette.subText,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun MusicVolumePanel(
    title: String,
    value: Double,
    enabled: Boolean,
    palette: HanClipPalette,
    onValueChange: (Double) -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(title, color = palette.text, fontWeight = FontWeight.SemiBold)
            Text(
                "${(value.coerceIn(0.0, 1.0) * 100).toInt()}%",
                color = palette.subText,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.bodySmall
            )
        }
        Slider(
            value = value.toFloat().coerceIn(0f, 1f),
            onValueChange = { onValueChange(it.toDouble()) },
            enabled = enabled,
            valueRange = 0f..1f,
            steps = 19
        )
    }
}

@Composable
private fun MusicFadeToggle(
    title: String,
    checked: Boolean,
    enabled: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, fontWeight = FontWeight.SemiBold)
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            enabled = enabled
        )
    }
}

@Composable
private fun SampleMusicButton(
    sample: BackgroundMusicSample,
    selected: Boolean,
    isPreviewing: Boolean,
    palette: HanClipPalette,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    onTogglePreview: () -> Unit
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        color = if (selected) palette.primary.copy(alpha = 0.08f) else palette.secondary.copy(alpha = 0.05f),
        contentColor = palette.text,
        border = BorderStroke(
            1.dp,
            if (selected) palette.primary.copy(alpha = 0.34f) else palette.border.copy(alpha = 0.70f)
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick)
                .height(66.dp)
                .padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    sample.title,
                    color = if (selected) palette.primary else palette.text,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    sample.detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.subText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            IconButton(onClick = onTogglePreview) {
                Icon(
                    if (isPreviewing) Icons.Outlined.PauseCircle else Icons.Outlined.PlayCircle,
                    contentDescription = if (isPreviewing) "미리듣기 정지" else "미리듣기",
                    tint = if (selected || isPreviewing) palette.primary else palette.text
                )
            }
        }
    }
}

private data class MusicPreviewTarget(
    val id: String,
    val uri: Uri
)

private const val SelectedMusicPreviewId = "selected"

private fun togglePreviewTarget(
    current: MusicPreviewTarget?,
    next: MusicPreviewTarget
): MusicPreviewTarget? {
    return if (current?.id == next.id) null else next
}

private fun BackgroundMusicSample.previewUri(packageName: String): Uri {
    return Uri.parse("android.resource://$packageName/raw/$rawResourceName")
}
