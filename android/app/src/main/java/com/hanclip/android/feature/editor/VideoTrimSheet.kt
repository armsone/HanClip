package com.hanclip.android.feature.editor

import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.SportsGolf
import androidx.compose.material.icons.outlined.Timelapse
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.hanclip.android.core.model.ClipItem
import com.hanclip.android.core.theme.HanClipPalette
import kotlin.math.max
import kotlin.math.min

private val TrimPrimary = Color(0xFF0B7A4E)
private val TrimText = Color(0xFF14221A)
private val TrimSubText = Color(0xFF46564C)
private val TrimBorder = Color(0xFFD4DDD7)

@Composable
fun VideoTrimSheet(
    clip: ClipItem,
    palette: HanClipPalette,
    onDismiss: () -> Unit,
    onApplyTrim: (startSeconds: Double, durationSeconds: Double) -> Unit
) {
    val sourceDuration = max(0.5, clip.sourceDurationSeconds ?: clip.durationSeconds)
    var startSeconds by remember(clip.id) {
        mutableDoubleStateOf(clip.trimStartSeconds.coerceIn(0.0, sourceDuration))
    }
    var durationSeconds by remember(clip.id) {
        mutableDoubleStateOf(clip.durationSeconds.coerceIn(0.5, sourceDuration))
    }

    LaunchedEffect(startSeconds, durationSeconds, sourceDuration) {
        if (startSeconds + durationSeconds > sourceDuration) {
            startSeconds = max(0.0, sourceDuration - durationSeconds)
        }
    }

    Surface(
        shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp),
        color = palette.panel
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "구간 선택",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = palette.text
                    )
                    Text(
                        text = "원본 ${formatSeconds(sourceDuration)}",
                        color = palette.subText
                    )
                }
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Outlined.Close, contentDescription = "닫기", tint = palette.text)
                }
            }

            VideoPreview(
                clip = clip,
                startSeconds = startSeconds
            )

            VideoImpactPanel(
                clip = clip,
                sourceDuration = sourceDuration,
                startSeconds = startSeconds,
                durationSeconds = durationSeconds,
                palette = palette,
                onCenterOnImpact = {
                    val peak = clip.audioPeakTimeSeconds
                        ?: clip.audioPeakTimesSeconds.firstOrNull()
                        ?: sourceDuration / 2.0
                    val selectedDuration = min(durationSeconds, sourceDuration)
                    startSeconds = max(
                        0.0,
                        min(sourceDuration - selectedDuration, peak - selectedDuration / 2.0)
                    )
                    durationSeconds = selectedDuration
                },
                onUseFullRange = {
                    startSeconds = 0.0
                    durationSeconds = sourceDuration
                }
            )

            TrimSliderBlock(
                title = "시작",
                valueText = formatSeconds(startSeconds),
                value = startSeconds,
                valueRange = 0.0..max(0.0, sourceDuration - durationSeconds),
                onValueChange = { startSeconds = it }
            )
            TrimSliderBlock(
                title = "길이",
                valueText = formatSeconds(durationSeconds),
                value = durationSeconds,
                valueRange = 0.5..sourceDuration,
                onValueChange = { value ->
                    durationSeconds = min(value, sourceDuration)
                    if (startSeconds + durationSeconds > sourceDuration) {
                        startSeconds = max(0.0, sourceDuration - durationSeconds)
                    }
                }
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text("선택 구간", color = TrimSubText)
                    Text(
                        "${formatSeconds(startSeconds)} - ${formatSeconds(startSeconds + durationSeconds)}",
                        color = TrimText,
                        fontWeight = FontWeight.Bold
                    )
                }
                Button(
                    onClick = {
                        onApplyTrim(startSeconds, durationSeconds)
                        onDismiss()
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = palette.primary,
                        contentColor = Color.White
                    )
                ) {
                    Text("적용")
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun VideoImpactPanel(
    clip: ClipItem,
    sourceDuration: Double,
    startSeconds: Double,
    durationSeconds: Double,
    palette: HanClipPalette,
    onCenterOnImpact: () -> Unit,
    onUseFullRange: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
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
                    Text("자동 타격점", color = palette.text, fontWeight = FontWeight.Bold)
                    Text(
                        impactSummaryText(clip),
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.subText
                    )
                }
                Text(
                    "${formatSeconds(startSeconds)} - ${formatSeconds(startSeconds + durationSeconds)}",
                    color = palette.primary,
                    fontWeight = FontWeight.Bold
                )
            }
            ImpactWaveform(
                waveform = clip.audioWaveform,
                peaks = clip.audioPeakTimesSeconds.ifEmpty { listOfNotNull(clip.audioPeakTimeSeconds) },
                sourceDuration = sourceDuration,
                startSeconds = startSeconds,
                durationSeconds = durationSeconds
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    modifier = Modifier.weight(1f),
                    onClick = onCenterOnImpact,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = palette.primary,
                        contentColor = Color.White
                    )
                ) {
                    Icon(Icons.Outlined.SportsGolf, contentDescription = null)
                    Text("타격점 맞춤")
                }
                OutlinedButton(
                    modifier = Modifier.weight(1f),
                    onClick = onUseFullRange,
                    border = BorderStroke(1.dp, palette.border),
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = palette.panel,
                        contentColor = palette.text
                    )
                ) {
                    Icon(Icons.Outlined.Timelapse, contentDescription = null)
                    Text("원본 전체")
                }
            }
        }
    }
}

@Composable
private fun ImpactWaveform(
    waveform: List<Double>,
    peaks: List<Double>,
    sourceDuration: Double,
    startSeconds: Double,
    durationSeconds: Double
) {
    val bars = if (waveform.isEmpty()) List(48) { 0.18 } else waveform
    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(64.dp)
    ) {
        val safeDuration = sourceDuration.coerceAtLeast(0.5)
        val selectedStartX = (startSeconds / safeDuration).toFloat() * size.width
        val selectedEndX = ((startSeconds + durationSeconds) / safeDuration).toFloat() * size.width
        drawRoundRect(
            color = TrimPrimary.copy(alpha = 0.12f),
            topLeft = Offset(selectedStartX, 0f),
            size = androidx.compose.ui.geometry.Size(
                width = (selectedEndX - selectedStartX).coerceAtLeast(2f),
                height = size.height
            )
        )
        val gap = size.width / bars.size.coerceAtLeast(1)
        bars.forEachIndexed { index, value ->
            val x = gap * index + gap / 2f
            val normalized = value.coerceIn(0.04, 1.0).toFloat()
            val barHeight = size.height * (0.18f + normalized * 0.72f)
            val inSelection = x in selectedStartX..selectedEndX
            drawLine(
                color = if (inSelection) TrimPrimary else TrimSubText.copy(alpha = 0.34f),
                start = Offset(x, (size.height - barHeight) / 2f),
                end = Offset(x, (size.height + barHeight) / 2f),
                strokeWidth = 3.2f,
                cap = StrokeCap.Round
            )
        }
        peaks
            .filter { it.isFinite() && it in 0.0..safeDuration }
            .take(12)
            .forEach { peak ->
                val x = (peak / safeDuration).toFloat() * size.width
                drawLine(
                    color = Color(0xFFE45D42),
                    start = Offset(x, 2f),
                    end = Offset(x, size.height - 2f),
                    strokeWidth = 2.8f,
                    cap = StrokeCap.Round
                )
            }
    }
}

private fun impactSummaryText(clip: ClipItem): String {
    val peakCount = clip.audioPeakTimesSeconds.size
    val primary = clip.audioPeakTimeSeconds ?: clip.audioPeakTimesSeconds.firstOrNull()
    return when {
        primary != null && peakCount > 1 -> "주요 ${formatSeconds(primary)} · 후보 ${peakCount}개"
        primary != null -> "주요 ${formatSeconds(primary)}"
        else -> "피크가 없으면 영상 중앙을 기준으로 맞춥니다."
    }
}

@OptIn(UnstableApi::class)
@Composable
private fun VideoPreview(
    clip: ClipItem,
    startSeconds: Double
) {
    val context = LocalContext.current
    val isSample = clip.sourceUri.scheme == "sample"
    val player = remember(clip.sourceUri) {
        if (isSample) {
            null
        } else {
            ExoPlayer.Builder(context).build().apply {
                repeatMode = Player.REPEAT_MODE_ONE
                setMediaItem(MediaItem.fromUri(clip.sourceUri))
                prepare()
            }
        }
    }

    LaunchedEffect(player, startSeconds) {
        player?.seekTo((startSeconds * 1000).toLong())
    }

    DisposableEffect(player) {
        onDispose {
            player?.release()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(230.dp)
            .background(Color.Black, RoundedCornerShape(8.dp)),
        contentAlignment = Alignment.Center
    ) {
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
                    modifier = Modifier.height(64.dp)
                )
                Spacer(Modifier.height(8.dp))
                Text("실제 영상을 선택하면 여기서 재생됩니다.", color = Color.White)
            }
        }
    }
}

@Composable
private fun TrimSliderBlock(
    title: String,
    valueText: String,
    value: Double,
    valueRange: ClosedFloatingPointRange<Double>,
    onValueChange: (Double) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(title, color = TrimText, fontWeight = FontWeight.SemiBold)
            Text(valueText, color = TrimPrimary, fontWeight = FontWeight.Bold)
        }
        Slider(
            value = value.toFloat(),
            onValueChange = { onValueChange(it.toDouble()) },
            valueRange = valueRange.start.toFloat()..valueRange.endInclusive.toFloat()
        )
    }
}

private fun formatSeconds(seconds: Double): String {
    val minutes = (seconds / 60).toInt()
    val remainingSeconds = seconds - minutes * 60
    return if (minutes > 0) {
        "%d:%04.1f".format(minutes, remainingSeconds)
    } else {
        "%.1f초".format(seconds)
    }
}
