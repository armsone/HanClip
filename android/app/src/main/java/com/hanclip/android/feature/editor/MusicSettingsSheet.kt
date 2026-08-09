package com.hanclip.android.feature.editor

import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
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
import kotlin.math.abs

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
    val context = LocalContext.current
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
        color = palette.panel
    ) {
        Column(
            modifier = Modifier
                .then(if (fullScreen) Modifier.fillMaxSize().statusBarsPadding() else Modifier.fillMaxWidth())
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
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

            if (currentTitle != null && currentUri != null) {
                SelectedMusicPreviewRow(
                    title = currentTitle,
                    isPlaying = previewTarget?.id == SelectedMusicPreviewId,
                    palette = palette,
                    onTogglePreview = {
                        previewTarget = togglePreviewTarget(
                            current = previewTarget,
                            next = MusicPreviewTarget(
                                id = SelectedMusicPreviewId,
                                uri = currentUri
                            )
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
                                        id = sample.id,
                                        uri = sample.previewUri(context.packageName)
                                    )
                                )
                            }
                        )
                    }
                }
            }

            OutlinedButton(
                modifier = Modifier.fillMaxWidth(),
                onClick = onOpenBrowser,
                border = BorderStroke(1.dp, palette.border),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = palette.chip,
                    contentColor = palette.text
                )
            ) {
                Icon(Icons.Outlined.Public, contentDescription = null)
                Text("브라우저")
            }

            OutlinedButton(
                modifier = Modifier.fillMaxWidth(),
                onClick = onPickFile,
                border = BorderStroke(1.dp, palette.border),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = palette.chip,
                    contentColor = palette.text
                )
            ) {
                Icon(Icons.Outlined.FolderOpen, contentDescription = null)
                Text("음악 파일 불러오기")
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                OutlinedButton(
                    onClick = {},
                    enabled = currentTitle != null,
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = if (currentTitle != null) palette.primary else palette.chip,
                        contentColor = Color.White
                    )
                ) { Text("사용") }
                OutlinedButton(
                    onClick = onRemove,
                    enabled = true,
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = if (currentTitle == null) palette.primary else palette.chip,
                        contentColor = if (currentTitle == null) Color.White else palette.text
                    )
                ) { Text("안함") }
            }

            MusicMixSummaryPanel(
                currentTitle = currentTitle,
                musicVolume = musicVolume,
                originalAudioVolume = originalAudioVolume,
                palette = palette
            )

            MusicVolumePanel(
                title = "배경음악",
                subtitle = if (currentTitle == null) "음악을 선택하면 타격음을 해치지 않게 낮게 섞습니다." else currentTitle,
                value = musicVolume,
                enabled = currentTitle != null,
                palette = palette,
                resetLabel = "기본 35%",
                resetValue = 0.35,
                onValueChange = onMusicVolumeChange
            )

            MusicVolumePanel(
                title = "원본 소리",
                subtitle = "스윙 타격음과 현장 소리를 완성본에 남기는 비율입니다.",
                value = originalAudioVolume,
                enabled = true,
                palette = palette,
                resetLabel = "원본 100%",
                resetValue = 1.0,
                onValueChange = onOriginalAudioVolumeChange
            )

            MusicPlaybackOptionRow(
                title = "영상 끝까지 반복",
                detail = "음악이 짧으면 완성본 길이만큼 처음부터 반복합니다.",
                checked = loopsToFillVideo,
                enabled = currentTitle != null,
                palette = palette,
                onCheckedChange = onLoopingChange
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                MusicPlaybackOptionRow(
                    title = "페이드 인",
                    detail = "0.3초",
                    checked = fadeInEnabled,
                    enabled = currentTitle != null,
                    palette = palette,
                    onCheckedChange = onFadeInChange,
                    modifier = Modifier.weight(1f)
                )
                MusicPlaybackOptionRow(
                    title = "페이드 아웃",
                    detail = "1.0초",
                    checked = fadeOutEnabled,
                    enabled = currentTitle != null,
                    palette = palette,
                    onCheckedChange = onFadeOutChange,
                    modifier = Modifier.weight(1f)
                )
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
private fun MusicPlaybackOptionRow(
    title: String,
    detail: String,
    checked: Boolean,
    enabled: Boolean,
    palette: HanClipPalette,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        color = if (enabled) palette.chip else palette.chip.copy(alpha = 0.58f),
        border = BorderStroke(1.dp, palette.border)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 9.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, fontWeight = FontWeight.SemiBold, color = palette.text)
                Text(detail, style = MaterialTheme.typography.bodySmall, color = palette.subText)
            }
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange,
                enabled = enabled
            )
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
        shape = RoundedCornerShape(8.dp),
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
private fun MusicMixSummaryPanel(
    currentTitle: String?,
    musicVolume: Double,
    originalAudioVolume: Double,
    palette: HanClipPalette
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("소리 믹스", color = palette.text, fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MusicMixChip(
                    label = "배경음악 낮게",
                    value = if (currentTitle == null) "꺼짐" else percentText(musicVolume),
                    active = currentTitle != null,
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
                MusicMixChip(
                    label = "타격음/원본",
                    value = percentText(originalAudioVolume),
                    active = originalAudioVolume > 0.0,
                    palette = palette,
                    modifier = Modifier.weight(1f)
                )
            }
            Text(
                text = if (currentTitle == null) {
                    "배경음악 없이 스윙 타격음과 원본 현장 소리를 그대로 사용합니다."
                } else {
                    "${currentTitle}은 낮게 얹고 스윙 타격음과 원본 현장 소리는 선명하게 남깁니다."
                },
                color = palette.subText,
                style = MaterialTheme.typography.bodySmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun MusicMixChip(
    label: String,
    value: String,
    active: Boolean,
    palette: HanClipPalette,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(7.dp),
        color = if (active) Color.White else palette.panel,
        border = BorderStroke(1.dp, if (active) palette.primary.copy(alpha = 0.24f) else palette.border)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                label,
                color = palette.subText,
                fontWeight = FontWeight.SemiBold,
                style = MaterialTheme.typography.labelMedium
            )
            Text(
                value,
                color = if (active) palette.primary else palette.subText,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.labelMedium
            )
        }
    }
}

@Composable
private fun MusicVolumePanel(
    title: String,
    subtitle: String,
    value: Double,
    enabled: Boolean,
    palette: HanClipPalette,
    resetLabel: String,
    resetValue: Double,
    onValueChange: (Double) -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = if (enabled) palette.chip else palette.chip.copy(alpha = 0.58f),
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(Modifier.weight(1f)) {
                    Text(title, color = palette.text, fontWeight = FontWeight.Bold)
                    Text(
                        subtitle,
                        color = palette.subText,
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Text(
                    "${(value.coerceIn(0.0, 1.0) * 100).toInt()}%",
                    color = if (enabled) palette.primary else palette.subText,
                    fontWeight = FontWeight.Bold
                )
            }
            Slider(
                value = value.toFloat().coerceIn(0f, 1f),
                onValueChange = { onValueChange(it.toDouble()) },
                enabled = enabled,
                valueRange = 0f..1f,
                steps = 19
            )
            OutlinedButton(
                modifier = Modifier.fillMaxWidth(),
                onClick = { onValueChange(resetValue) },
                enabled = enabled && abs(value - resetValue) > 0.01,
                border = BorderStroke(1.dp, palette.border),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = Color.White,
                    contentColor = palette.text
                )
            ) {
                Text(resetLabel)
            }
        }
    }
}

private fun percentText(value: Double): String {
    return "${(value.coerceIn(0.0, 1.0) * 100).toInt()}%"
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
        color = if (selected) palette.primary else palette.chip,
        contentColor = if (selected) Color.White else palette.text
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick)
                .height(74.dp)
                .padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(sample.title, fontWeight = FontWeight.Bold)
                Text(
                    sample.detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (selected) Color.White.copy(alpha = 0.86f) else palette.subText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            IconButton(onClick = onTogglePreview) {
                Icon(
                    if (isPreviewing) Icons.Outlined.PauseCircle else Icons.Outlined.PlayCircle,
                    contentDescription = if (isPreviewing) "미리듣기 정지" else "미리듣기",
                    tint = if (selected || isPreviewing) Color.White else palette.text
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
