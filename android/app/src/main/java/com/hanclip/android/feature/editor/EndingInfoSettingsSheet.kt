package com.hanclip.android.feature.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Map
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hanclip.android.core.model.EndingInfoCardTheme
import com.hanclip.android.core.model.WatermarkFontSize
import com.hanclip.android.core.model.WatermarkLineSpacing
import com.hanclip.android.core.model.WatermarkSettings
import com.hanclip.android.core.theme.HanClipPalette

@Composable
fun EndingInfoSettingsSheet(
    settings: WatermarkSettings,
    stops: List<EndingInfoStop>,
    palette: HanClipPalette,
    onDismiss: () -> Unit,
    onApply: (WatermarkSettings) -> Unit
) {
    FullScreenDialogSystemBars(palette.solidPanel)
    var draft by remember(settings) { mutableStateOf(settings) }
    val previewStops = stops.ifEmpty {
        listOf(
            EndingInfoStop("서울", "8. 7."),
            EndingInfoStop("덕양구", "8. 8."),
            EndingInfoStop("Philippines Clark", "8. 9.")
        )
    }
    Surface(
        modifier = Modifier.fillMaxSize(),
        color = palette.solidPanel
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .background(palette.background)
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            FullScreenSettingsHeader(
                title = "엔딩",
                titleIcon = Icons.Outlined.Map,
                resetDescription = "엔딩 설정 되돌리기",
                palette = palette,
                onReset = { draft = settings },
                onDismiss = onDismiss
            )
            EndingUsageControl(
                enabled = draft.includesEndingInfoCard,
                palette = palette,
                onChange = { draft = draft.copy(includesEndingInfoCard = it) }
            )
            EndingThemePicker(
                selected = draft.endingInfoCardTheme,
                palette = palette,
                onSelect = { theme ->
                    draft = draft.copy(
                        endingInfoCardTheme = theme,
                        endingInfoCardVariation = if (theme == EndingInfoCardTheme.TreasureMap) {
                            draft.endingInfoCardVariation + 1
                        } else {
                            draft.endingInfoCardVariation
                        }
                    )
                }
            )
            EndingDurationControl(
                duration = draft.normalizedEndingInfoCardDuration,
                palette = palette,
                onDecrease = {
                    draft = draft.copy(
                        endingInfoCardDuration = draft.normalizedEndingInfoCardDuration - 0.5
                    )
                },
                onIncrease = {
                    draft = draft.copy(
                        endingInfoCardDuration = draft.normalizedEndingInfoCardDuration + 0.5
                    )
                }
            )
            EndingInfoCardPreview(
                theme = draft.endingInfoCardTheme,
                stops = previewStops,
                palette = palette
            )
            if (draft.endingInfoCardTheme == EndingInfoCardTheme.Caption) {
                EndingCaptionPresetGrid(
                    settings = draft,
                    palette = palette,
                    onChange = { draft = it }
                )
            }
            Button(
                onClick = {
                    onApply(draft)
                    onDismiss()
                },
                modifier = Modifier.fillMaxWidth().height(52.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = palette.primary,
                    contentColor = Color.White
                )
            ) {
                Text(
                    if (draft.includesEndingInfoCard) "엔딩 설정 적용" else "엔딩 사용 안함 적용",
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

@Composable
private fun EndingUsageControl(
    enabled: Boolean,
    palette: HanClipPalette,
    onChange: (Boolean) -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = androidx.compose.foundation.shape.RoundedCornerShape(50),
        color = palette.chip
    ) {
        Row {
            EndingSegment("사용", enabled, palette, Modifier.weight(1f)) { onChange(true) }
            EndingSegment("안함", !enabled, palette, Modifier.weight(1f)) { onChange(false) }
        }
    }
}

@Composable
private fun EndingSegment(
    text: String,
    selected: Boolean,
    palette: HanClipPalette,
    modifier: Modifier,
    onClick: () -> Unit
) {
    Surface(
        modifier = modifier.padding(3.dp),
        shape = androidx.compose.foundation.shape.RoundedCornerShape(50),
        color = if (selected) palette.primary else Color.Transparent,
        onClick = onClick
    ) {
        Text(
            text,
            modifier = Modifier.padding(vertical = 11.dp),
            color = if (selected) Color.White else palette.primary,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
private fun EndingThemePicker(
    selected: EndingInfoCardTheme,
    palette: HanClipPalette,
    onSelect: (EndingInfoCardTheme) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        EndingInfoCardTheme.entries.forEach { theme ->
            Surface(
                modifier = Modifier.weight(1f),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(9.dp),
                color = if (selected == theme) palette.primary.copy(alpha = 0.14f) else palette.solidPanel,
                border = BorderStroke(
                    1.dp,
                    if (selected == theme) palette.primary.copy(alpha = 0.42f) else palette.border
                ),
                onClick = { onSelect(theme) }
            ) {
                Column(
                    modifier = Modifier.height(46.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(endingThemeMark(theme), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    Text(theme.title, fontSize = 8.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun EndingDurationControl(
    duration: Double,
    palette: HanClipPalette,
    onDecrease: () -> Unit,
    onIncrease: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth().height(44.dp),
        shape = androidx.compose.foundation.shape.RoundedCornerShape(50),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.material3.IconButton(
                onClick = onDecrease,
                enabled = duration > 1.0,
                modifier = Modifier.size(52.dp)
            ) {
                androidx.compose.material3.Icon(Icons.Outlined.Remove, "엔딩 시간 줄이기")
            }
            Text(
                "%.1f초".format(duration),
                modifier = Modifier.weight(1f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                color = palette.text,
                fontWeight = FontWeight.Bold
            )
            androidx.compose.material3.IconButton(
                onClick = onIncrease,
                enabled = duration < 10.0,
                modifier = Modifier.size(52.dp)
            ) {
                androidx.compose.material3.Icon(Icons.Outlined.Add, "엔딩 시간 늘리기")
            }
        }
    }
}

private data class EndingCaptionPreset(
    val title: String,
    val fontName: String,
    val textColor: String,
    val shadowColor: String,
    val fontSize: WatermarkFontSize,
    val shadowOpacity: Double
)

private val EndingCaptionPresets = listOf(
    EndingCaptionPreset("가독성", "pretendard", "#FFFFFF", "#000000", WatermarkFontSize.Large, 0.50),
    EndingCaptionPreset("러블리", "ddulgi_mayo", "#FF6FAE", "#7A3FFF", WatermarkFontSize.Large, 0.50),
    EndingCaptionPreset("강력햐", "tenada", "#FFE600", "#000000", WatermarkFontSize.ExtraLarge, 0.50),
    EndingCaptionPreset("청량", "gowun_dodum", "#FFFFFF", "#18A8FF", WatermarkFontSize.Large, 0.50),
    EndingCaptionPreset("여행", "gowun_batang", "#FFF3D6", "#3F6F63", WatermarkFontSize.Large, 0.50),
    EndingCaptionPreset("시네마", "black_han_sans", "#F8F3E7", "#141414", WatermarkFontSize.ExtraLarge, 0.50),
    EndingCaptionPreset("데일리", "do_hyeon", "#FFFFFF", "#FF7A3D", WatermarkFontSize.Large, 0.50),
    EndingCaptionPreset("감성", "maruburi", "#FFE9F0", "#6E5BFF", WatermarkFontSize.Normal, 0.50),
    EndingCaptionPreset("그린골프", "pretendard_bold", "#FFFFFF", "#10B85A", WatermarkFontSize.Large, 0.50),
    EndingCaptionPreset("매거진", "paperlogy_bold", "#FFF4D6", "#D94A32", WatermarkFontSize.ExtraLarge, 0.55),
    EndingCaptionPreset("스포츠", "paperlogy_bold", "#D8FF3E", "#10223A", WatermarkFontSize.ExtraLarge, 0.70),
    EndingCaptionPreset("클린", "nexon_lv1_gothic", "#FFFFFF", "#1B4D89", WatermarkFontSize.Large, 0.35),
    EndingCaptionPreset("네온", "nexon_lv1_gothic", "#7DF9FF", "#6C2BFF", WatermarkFontSize.Large, 0.80),
    EndingCaptionPreset("VLOG", "poppins", "#FFFFFF", "#FF6B5E", WatermarkFontSize.Large, 0.55),
    EndingCaptionPreset("POP", "poppins", "#FFE45C", "#642BFF", WatermarkFontSize.ExtraLarge, 0.75)
)

@Composable
private fun EndingCaptionPresetGrid(
    settings: WatermarkSettings,
    palette: HanClipPalette,
    onChange: (WatermarkSettings) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        EndingCaptionPresets.chunked(3).forEach { rowPresets ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                rowPresets.forEach { preset ->
                    val selected = settings.fontName == preset.fontName &&
                        settings.textColorHex.equals(preset.textColor, true) &&
                        settings.shadowColorHex.equals(preset.shadowColor, true) &&
                        settings.fontSize == preset.fontSize
                    Surface(
                        modifier = Modifier.weight(1f),
                        shape = androidx.compose.foundation.shape.RoundedCornerShape(9.dp),
                        color = if (selected) palette.primary.copy(alpha = 0.14f) else palette.solidPanel,
                        border = BorderStroke(1.dp, if (selected) palette.primary else palette.border),
                        onClick = {
                            onChange(
                                settings.copy(
                                    fontName = preset.fontName,
                                    textColorHex = preset.textColor,
                                    shadowEnabled = preset.shadowOpacity > 0,
                                    shadowColorHex = preset.shadowColor,
                                    shadowOpacity = preset.shadowOpacity,
                                    fontSize = preset.fontSize,
                                    lineSpacing = WatermarkLineSpacing.Normal,
                                    lineSpacingScale = WatermarkLineSpacing.DefaultScale
                                )
                            )
                        }
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(if (selected) "◉" else "○", color = palette.primary)
                            Spacer(Modifier.size(5.dp))
                            Text(
                                preset.title,
                                modifier = Modifier.weight(1f),
                                color = palette.text,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                maxLines = 1
                            )
                            Text("Aa", color = Color(android.graphics.Color.parseColor(preset.textColor)), fontWeight = FontWeight.Bold)
                        }
                    }
                }
                repeat(3 - rowPresets.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}
