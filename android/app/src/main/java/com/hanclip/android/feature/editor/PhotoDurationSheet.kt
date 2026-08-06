package com.hanclip.android.feature.editor

import android.graphics.Bitmap
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.hanclip.android.core.media.MediaImportReader
import com.hanclip.android.core.model.ClipItem
import com.hanclip.android.core.theme.HanClipPalette

private val SheetPrimary = Color(0xFF0B7A4E)
private val SheetText = Color(0xFF14221A)
private val SheetSubText = Color(0xFF46564C)
private val SheetBorder = Color(0xFFD4DDD7)

@Composable
fun PhotoDurationSheet(
    clip: ClipItem,
    palette: HanClipPalette,
    onDismiss: () -> Unit,
    onApplyDuration: (Double) -> Unit
) {
    var duration by remember(clip.id) {
        mutableFloatStateOf(clip.durationSeconds.toFloat().coerceIn(0.5f, 30f))
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
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column {
                    Text(
                        "사진 시간",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = palette.text
                    )
                    Text(
                        "사진 한 장이 영화에 보이는 길이를 정합니다.",
                        color = palette.subText
                    )
                }
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Outlined.Close, contentDescription = "닫기", tint = palette.text)
                }
            }
            PhotoDurationPreview(clip = clip, palette = palette)
            Text(
                text = "%.1f초".format(duration),
                style = MaterialTheme.typography.titleMedium,
                color = palette.primary,
                fontWeight = FontWeight.Bold
            )
            Slider(
                value = duration,
                onValueChange = { duration = it.coerceIn(0.5f, 30f) },
                valueRange = 0.5f..30f,
                steps = 58
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(1.5f, 2f, 3f, 4f, 6f).forEach { seconds ->
                    FilterChip(
                        selected = kotlin.math.abs(duration - seconds) < 0.05f,
                        onClick = { duration = seconds },
                        label = { Text("%.1f초".format(seconds), fontWeight = FontWeight.SemiBold) },
                        colors = FilterChipDefaults.filterChipColors(
                            containerColor = Color.White,
                            labelColor = palette.text,
                            selectedContainerColor = palette.primary,
                            selectedLabelColor = Color.White
                        ),
                        border = FilterChipDefaults.filterChipBorder(
                            enabled = true,
                            selected = kotlin.math.abs(duration - seconds) < 0.05f,
                            borderColor = palette.border,
                            selectedBorderColor = palette.primary
                        )
                    )
                }
            }
            Button(
                onClick = {
                    onApplyDuration(duration.toDouble())
                    onDismiss()
                },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = palette.primary,
                    contentColor = Color.White
                )
            ) {
                Text("적용")
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun PhotoDurationPreview(
    clip: ClipItem,
    palette: HanClipPalette
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

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(220.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(palette.chip),
        contentAlignment = Alignment.Center
    ) {
        if (thumbnail != null) {
            Image(
                bitmap = thumbnail!!.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize()
            )
        } else {
            Text("사진 미리보기", color = palette.subText)
        }
    }
}
