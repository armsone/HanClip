package com.hanclip.android.feature.editor

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hanclip.android.R
import com.hanclip.android.core.model.CopyrightIconColorMode
import com.hanclip.android.core.model.WatermarkFontSize
import com.hanclip.android.core.model.WatermarkLineSpacing
import com.hanclip.android.core.model.WatermarkPosition
import com.hanclip.android.core.model.WatermarkSettings
import com.hanclip.android.core.theme.HanClipPalette
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

private val SheetPrimary = Color(0xFF0B7A4E)
private val SheetText = Color(0xFF14221A)
private val SheetSubText = Color(0xFF46564C)
private val SheetBorder = Color(0xFFD4DDD7)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TextOverlaySheet(
    settings: WatermarkSettings,
    palette: HanClipPalette,
    fullScreen: Boolean = false,
    onDismiss: () -> Unit,
    onApply: (WatermarkSettings) -> Unit
) {
    var draft by remember(settings) { mutableStateOf(settings) }

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
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        "자막/로고",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = palette.text
                    )
                    Text("완성 MP4에 들어갈 문구와 HanClip 로고를 정합니다.", color = palette.subText)
                }
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Outlined.Close, contentDescription = "닫기", tint = palette.text)
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("자막 사용", fontWeight = FontWeight.SemiBold, color = SheetText)
                Switch(
                    checked = draft.isEnabled,
                    onCheckedChange = { draft = draft.copy(isEnabled = it) },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = palette.primary
                    )
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text("HanClip 로고", fontWeight = FontWeight.SemiBold, color = SheetText)
                    Text("완성본에 HanClip 표시를 작게 넣습니다.", color = SheetSubText)
                }
                Switch(
                    checked = draft.logoEnabled,
                    onCheckedChange = { draft = draft.copy(logoEnabled = it) },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = palette.primary
                    )
                )
            }

            SettingGroup(title = "자막 문구") {
                CaptionTextPreset.entries.forEach { preset ->
                    val presetText = preset.text()
                    FilterChip(
                        selected = draft.text == presetText,
                        onClick = {
                            draft = draft.copy(
                                isEnabled = presetText.isNotBlank(),
                                text = presetText
                            )
                        },
                        label = { Text(preset.title, fontWeight = FontWeight.SemiBold) },
                        colors = sheetFilterChipColors(),
                        border = sheetFilterChipBorder(draft.text == presetText)
                    )
                }
            }

            OutlinedTextField(
                value = draft.text,
                onValueChange = {
                    draft = draft.copy(
                        isEnabled = it.isNotBlank(),
                        text = it
                    )
                },
                modifier = Modifier.fillMaxWidth(),
                minLines = 3,
                label = { Text("자막 내용") },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = SheetText,
                    unfocusedTextColor = SheetText,
                    focusedBorderColor = palette.primary,
                    unfocusedBorderColor = palette.border,
                    focusedLabelColor = palette.primary,
                    unfocusedLabelColor = SheetSubText
                )
            )

            CaptionPreview(draft)

            CaptionStateSummary(draft, palette)

            Button(
                onClick = { draft = hanClipDefaultWatermark(draft) },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFFE9F4EE),
                    contentColor = SheetText
                )
            ) {
                Text("HanClip 골프 스타일로 맞추기", fontWeight = FontWeight.Bold)
            }

            SettingGroup(title = "스타일") {
                CaptionStylePreset.entries.forEach { preset ->
                    FilterChip(
                        selected = preset.matches(draft),
                        onClick = { draft = preset.applyTo(draft) },
                        label = { Text(preset.title, fontWeight = FontWeight.SemiBold) },
                        colors = sheetFilterChipColors(),
                        border = sheetFilterChipBorder(preset.matches(draft))
                    )
                }
            }

            SettingGroup(title = "글자 크기") {
                WatermarkFontSize.entries.forEach { size ->
                    FilterChip(
                        selected = draft.fontSize == size,
                        onClick = { draft = draft.copy(fontSize = size) },
                        label = { Text(size.title, fontWeight = FontWeight.SemiBold) },
                        colors = sheetFilterChipColors(),
                        border = sheetFilterChipBorder(draft.fontSize == size)
                    )
                }
            }

            SettingGroup(title = "줄간격") {
                WatermarkLineSpacing.entries.forEach { spacing ->
                    FilterChip(
                        selected = draft.lineSpacing == spacing,
                        onClick = {
                            draft = draft.copy(
                                lineSpacing = spacing,
                                lineSpacingScale = spacing.scale
                            )
                        },
                        label = { Text(spacing.title, fontWeight = FontWeight.SemiBold) },
                        colors = sheetFilterChipColors(),
                        border = sheetFilterChipBorder(draft.lineSpacing == spacing)
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("줄간격 세부 조절", fontWeight = FontWeight.SemiBold, color = SheetText)
                    Text(
                        "%.1fx".format(draft.lineSpacingScale.coerceIn(0.5, 2.0)),
                        color = SheetSubText,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = {
                            val next = WatermarkLineSpacing.normalize(
                                draft.lineSpacingScale - WatermarkLineSpacing.Step
                            )
                            draft = draft.copy(lineSpacingScale = next)
                        },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFFE9F4EE),
                            contentColor = SheetText
                        )
                    ) {
                        Text("-")
                    }
                    Button(
                        onClick = {
                            draft = draft.copy(
                                lineSpacing = WatermarkLineSpacing.Normal,
                                lineSpacingScale = WatermarkLineSpacing.DefaultScale
                            )
                        },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFFE9F4EE),
                            contentColor = SheetText
                        )
                    ) {
                        Text("기본")
                    }
                    Button(
                        onClick = {
                            val next = WatermarkLineSpacing.normalize(
                                draft.lineSpacingScale + WatermarkLineSpacing.Step
                            )
                            draft = draft.copy(lineSpacingScale = next)
                        },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFFE9F4EE),
                            contentColor = SheetText
                        )
                    ) {
                        Text("+")
                    }
                }
            }

            SettingGroup(title = "폰트") {
                listOf(
                    "pretendard",
                    "pretendard_bold",
                    "kakao_big_sans",
                    "gowun_batang",
                    "gowun_dodum",
                    "nanum_gothic",
                    "cafe24_ssurround",
                    "puradak_gentle_gothic",
                    "tenada",
                    "do_hyeon",
                    "black_han_sans",
                    "maruburi",
                    "ddulgi_mayo"
                ).forEach { font ->
                    FilterChip(
                        selected = draft.fontName == font,
                        onClick = { draft = draft.copy(fontName = font) },
                        label = { Text(fontDisplayName(font), fontWeight = FontWeight.SemiBold) },
                        colors = sheetFilterChipColors(),
                        border = sheetFilterChipBorder(draft.fontName == font)
                    )
                }
            }

            SettingGroup(title = "색상") {
                listOf(
                    "#FFFFFF" to "흰색",
                    "#007644" to "골프",
                    "#FFF3D6" to "크림",
                    "#111111" to "검정",
                    "#E45D42" to "레드"
                ).forEach { (colorHex, label) ->
                    ColorSwatchChip(
                        label = label,
                        colorHex = colorHex,
                        selected = draft.textColorHex == colorHex,
                        palette = palette,
                        onClick = { draft = draft.copy(textColorHex = colorHex) }
                    )
                }
            }

            if (draft.logoEnabled) {
                SettingGroup(title = "HanClip 로고 색상") {
                    listOf(
                        "#007644" to "골프",
                        "#FFFFFF" to "흰색",
                        "#FFF3D6" to "크림",
                        "#111111" to "검정",
                        "#E45D42" to "레드"
                    ).forEach { (colorHex, label) ->
                        ColorSwatchChip(
                            label = label,
                            colorHex = colorHex,
                            selected = draft.logoColorHex.equals(colorHex, ignoreCase = true),
                            palette = palette,
                            onClick = { draft = draft.copy(logoColorHex = colorHex) }
                        )
                    }
                }

                SettingGroup(title = "HanClip 로고 색상 모드") {
                    CopyrightIconColorMode.entries.forEach { mode ->
                        FilterChip(
                            selected = draft.copyrightIconColorMode == mode,
                            onClick = { draft = draft.copy(copyrightIconColorMode = mode) },
                            label = { Text(mode.title, fontWeight = FontWeight.SemiBold) },
                            colors = sheetFilterChipColors(),
                            border = sheetFilterChipBorder(draft.copyrightIconColorMode == mode)
                        )
                    }
                }

                if (draft.copyrightIconColorMode == CopyrightIconColorMode.Tint) {
                    SettingGroup(title = "HanClip 지정색") {
                        listOf(
                            "#007644" to "골프",
                            "#29AB87" to "민트",
                            "#FFFFFF" to "흰색",
                            "#FFF3D6" to "크림",
                            "#111111" to "검정"
                        ).forEach { (colorHex, label) ->
                            ColorSwatchChip(
                                label = label,
                                colorHex = colorHex,
                                selected = draft.copyrightIconColorHex.equals(colorHex, ignoreCase = true),
                                palette = palette,
                                onClick = { draft = draft.copy(copyrightIconColorHex = colorHex) }
                            )
                        }
                    }
                }

                SettingGroup(title = "HanClip 로고 그림자") {
                    listOf(
                        "#29AB87" to "골프",
                        "#000000" to "검정",
                        "#3F6F63" to "딥그린",
                        "#FFFFFF" to "흰색",
                        "#E45D42" to "레드"
                    ).forEach { (colorHex, label) ->
                        ColorSwatchChip(
                            label = label,
                            colorHex = colorHex,
                            selected = draft.logoShadowColorHex.equals(colorHex, ignoreCase = true),
                            palette = palette,
                            onClick = { draft = draft.copy(logoShadowColorHex = colorHex) }
                        )
                    }
                }

                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("로고 그림자 진하기", fontWeight = FontWeight.SemiBold, color = SheetText)
                        Text(
                            "%.0f%%".format(draft.logoShadowOpacity.coerceIn(0.0, 1.0) * 100),
                            color = SheetSubText,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                    Slider(
                        value = draft.logoShadowOpacity.coerceIn(0.0, 1.0).toFloat(),
                        onValueChange = { value ->
                            draft = draft.copy(logoShadowOpacity = value.toDouble())
                        },
                        valueRange = 0f..1f
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text("그림자", fontWeight = FontWeight.SemiBold, color = SheetText)
                    Text("밝은 영상에서도 글자가 보이게 합니다.", color = SheetSubText)
                }
                Switch(
                    checked = draft.shadowEnabled,
                    onCheckedChange = { draft = draft.copy(shadowEnabled = it) },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = SheetPrimary
                    )
                )
            }

            if (draft.shadowEnabled) {
                SettingGroup(title = "그림자 색상") {
                    listOf(
                        "#000000" to "검정",
                        "#10B85A" to "골프",
                        "#3F6F63" to "딥그린",
                        "#FFFFFF" to "흰색",
                        "#E45D42" to "레드"
                    ).forEach { (colorHex, label) ->
                        ColorSwatchChip(
                            label = label,
                            colorHex = colorHex,
                            selected = draft.shadowColorHex.equals(colorHex, ignoreCase = true),
                            palette = palette,
                            onClick = { draft = draft.copy(shadowColorHex = colorHex) }
                        )
                    }
                }

                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("그림자 진하기", fontWeight = FontWeight.SemiBold, color = SheetText)
                        Text(
                            "%.0f%%".format(draft.shadowOpacity.coerceIn(0.0, 1.0) * 100),
                            color = SheetSubText,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                    Slider(
                        value = draft.shadowOpacity.coerceIn(0.0, 1.0).toFloat(),
                        onValueChange = { value ->
                            draft = draft.copy(shadowOpacity = value.toDouble())
                        },
                        valueRange = 0f..1f
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("위치", fontWeight = FontWeight.SemiBold, color = SheetText)
                PositionPicker(
                    selected = draft.position,
                    markerText = "T",
                    palette = palette,
                    onSelect = { draft = draft.copy(position = it) }
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("HanClip 로고 위치", fontWeight = FontWeight.SemiBold, color = SheetText)
                PositionPicker(
                    selected = draft.copyrightPosition,
                    markerText = "H",
                    palette = palette,
                    onSelect = { draft = draft.copy(copyrightPosition = it) }
                )
            }

            Button(
                onClick = {
                    onApply(draft)
                    onDismiss()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = palette.primary,
                    contentColor = Color.White
                )
            ) {
                Text(
                    applyButtonText(draft),
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

@Composable
private fun CaptionPreview(settings: WatermarkSettings) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(178.dp),
        shape = RoundedCornerShape(8.dp),
        color = Color(0xFF163A2B),
        border = BorderStroke(1.dp, SheetBorder)
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color(0xFFBFD8CE),
                            Color(0xFF4C8D65),
                            Color(0xFF18392A)
                        )
                    )
                )
                .padding(14.dp)
        ) {
            Surface(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .height(26.dp),
                shape = RoundedCornerShape(50),
                color = Color.Black.copy(alpha = 0.24f),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.16f))
            ) {
                Text(
                    text = "미리보기",
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                    color = Color.White,
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold
                )
            }
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .width(84.dp)
                    .height(10.dp),
                shape = RoundedCornerShape(50),
                color = Color.White.copy(alpha = 0.22f)
            ) {}
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .width(118.dp)
                    .height(10.dp),
                shape = RoundedCornerShape(50),
                color = Color.White.copy(alpha = 0.14f)
            ) {}
            if (settings.shouldRenderText) {
                Text(
                    text = settings.text,
                    modifier = Modifier.align(previewAlignment(settings.position)),
                    color = parseHexColor(settings.textColorHex),
                    fontFamily = fontFamilyForName(settings.fontName),
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.bodyLarge.copy(
                        lineHeight = (18 * settings.lineSpacingScale.coerceIn(0.5, 2.0)).sp,
                        shadow = previewTextShadow(settings)
                    )
                )
            }
            if (settings.logoEnabled) {
                HanClipLogoPreview(
                    modifier = Modifier
                        .align(previewAlignment(settings.copyrightPosition))
                        .shadow(
                            elevation = (settings.logoShadowOpacity.coerceIn(0.0, 1.0) * 4).dp,
                            ambientColor = parseHexColor(settings.logoShadowColorHex),
                            spotColor = parseHexColor(settings.logoShadowColorHex)
                        ),
                    color = parseHexColor(settings.effectiveLogoColorHex)
                )
            }
            if (!settings.shouldRender) {
                Surface(
                    modifier = Modifier.align(Alignment.Center),
                    shape = RoundedCornerShape(50),
                    color = Color.Black.copy(alpha = 0.28f),
                    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.18f))
                ) {
                    Text(
                        text = "자막/로고 꺼짐",
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.labelMedium
                    )
                }
            }
        }
    }
}

@Composable
private fun HanClipLogoPreview(
    modifier: Modifier = Modifier,
    color: Color
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Image(
            painter = painterResource(R.drawable.logo_mark),
            contentDescription = null,
            modifier = Modifier.size(18.dp),
            colorFilter = ColorFilter.tint(color)
        )
        Text(
            text = "HanClip",
            color = color,
            fontWeight = FontWeight.Black,
            style = MaterialTheme.typography.labelLarge
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CaptionStateSummary(
    settings: WatermarkSettings,
    palette: HanClipPalette
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        FlowRow(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            CaptionStateChip(
                text = if (settings.shouldRenderText) "자막 켬" else "자막 꺼짐",
                active = settings.shouldRenderText,
                palette = palette
            )
            CaptionStateChip(
                text = if (settings.logoEnabled) "로고 켬" else "로고 꺼짐",
                active = settings.logoEnabled,
                palette = palette
            )
            CaptionStateChip(
                text = fontDisplayName(settings.fontName),
                active = settings.shouldRenderText,
                palette = palette
            )
            CaptionStateChip(
                text = settings.fontSize.title,
                active = settings.shouldRenderText,
                palette = palette
            )
            CaptionStateChip(
                text = "자막 ${watermarkPositionShortTitle(settings.position)}",
                active = settings.shouldRenderText,
                palette = palette
            )
            CaptionStateChip(
                text = "로고 ${watermarkPositionShortTitle(settings.copyrightPosition)}",
                active = settings.logoEnabled,
                palette = palette
            )
        }
    }
}

@Composable
private fun CaptionStateChip(
    text: String,
    active: Boolean,
    palette: HanClipPalette
) {
    Surface(
        shape = RoundedCornerShape(50),
        color = if (active) palette.primary.copy(alpha = 0.12f) else palette.panel,
        border = BorderStroke(1.dp, if (active) palette.primary.copy(alpha = 0.38f) else palette.border)
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 9.dp, vertical = 6.dp),
            color = if (active) palette.primary else palette.subText,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold
        )
    }
}

private fun previewTextShadow(settings: WatermarkSettings): Shadow? {
    if (!settings.shadowEnabled || settings.shadowOpacity <= 0.0) return null
    return Shadow(
        color = parseHexColor(settings.shadowColorHex).copy(
            alpha = settings.shadowOpacity.coerceIn(0.0, 1.0).toFloat()
        ),
        offset = Offset(1.6f, 1.8f),
        blurRadius = 4f
    )
}

private fun applyButtonText(settings: WatermarkSettings): String {
    return when {
        settings.shouldRenderText && settings.logoEnabled -> "자막과 HanClip 로고 적용"
        settings.shouldRenderText -> "자막 적용"
        settings.logoEnabled -> "HanClip 로고 적용"
        else -> "자막/로고 끄기 적용"
    }
}

private fun hanClipDefaultWatermark(settings: WatermarkSettings): WatermarkSettings {
    return settings.copy(
        isEnabled = true,
        logoEnabled = true,
        text = settings.text.ifBlank { CaptionTextPreset.Swing.text() },
        position = WatermarkPosition.TopLeading,
        copyrightPosition = WatermarkPosition.BottomTrailing,
        fontName = "pretendard_bold",
        fontSize = WatermarkFontSize.Large,
        textColorHex = "#FFFFFF",
        shadowEnabled = true,
        shadowOpacity = 0.45,
        shadowColorHex = "#000000",
        lineSpacing = WatermarkLineSpacing.Normal,
        lineSpacingScale = WatermarkLineSpacing.DefaultScale,
        logoColorHex = "#007644",
        logoShadowColorHex = "#29AB87",
        logoShadowOpacity = 0.5,
        copyrightIconColorMode = CopyrightIconColorMode.Original,
        copyrightIconColorHex = "#007644"
    )
}

private fun watermarkPositionShortTitle(position: WatermarkPosition): String {
    val vertical = when (position.gridRow) {
        0 -> "상단"
        1 -> "상단"
        2 -> "중앙"
        3 -> "하단"
        else -> "하단"
    }
    val horizontal = when (position.gridColumn) {
        0 -> "왼쪽"
        1 -> "왼쪽"
        2 -> "가운데"
        3 -> "오른쪽"
        else -> "오른쪽"
    }
    return if (vertical == "중앙" && horizontal == "가운데") {
        "중앙"
    } else {
        "$vertical $horizontal"
    }
}

@Composable
private fun ColorSwatchChip(
    label: String,
    colorHex: String,
    selected: Boolean,
    palette: HanClipPalette,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(8.dp),
        color = if (selected) palette.primary.copy(alpha = 0.12f) else palette.panel,
        border = BorderStroke(1.dp, if (selected) palette.primary else palette.border)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(18.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(parseHexColor(colorHex))
            )
            Text(label, fontWeight = FontWeight.SemiBold, color = palette.text)
        }
    }
}

@Composable
private fun PositionPicker(
    selected: WatermarkPosition,
    markerText: String,
    palette: HanClipPalette,
    onSelect: (WatermarkPosition) -> Unit
) {
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            WatermarkPosition.entries.chunked(5).forEach { rowPositions ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    rowPositions.forEach { position ->
                        val isSelected = selected == position
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(34.dp)
                                .clip(RoundedCornerShape(6.dp))
                                .background(if (isSelected) palette.primary else palette.panel)
                                .clickable { onSelect(position) },
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                markerText,
                                color = if (isSelected) Color.White else palette.subText,
                                fontWeight = FontWeight.Black
                            )
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun SettingGroup(
    title: String,
    content: @Composable () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, fontWeight = FontWeight.SemiBold, color = SheetText)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            content()
        }
    }
}

@Composable
private fun sheetFilterChipColors() = FilterChipDefaults.filterChipColors(
    containerColor = Color.White,
    labelColor = SheetText,
    selectedContainerColor = SheetPrimary,
    selectedLabelColor = Color.White
)

@Composable
private fun sheetFilterChipBorder(selected: Boolean) = FilterChipDefaults.filterChipBorder(
    enabled = true,
    selected = selected,
    borderColor = SheetBorder,
    selectedBorderColor = SheetPrimary
)

private fun fontDisplayName(font: String): String {
    return when (font) {
        "pretendard" -> "프리텐다드"
        "pretendard_bold" -> "프리텐다드B"
        "kakao_big_sans" -> "카카오"
        "gowun_batang" -> "고운바탕"
        "gowun_dodum" -> "고운돋움"
        "nanum_gothic" -> "나눔고딕"
        "cafe24_ssurround" -> "써라운드"
        "puradak_gentle_gothic" -> "젠틀고딕"
        "tenada" -> "태나다"
        "do_hyeon" -> "도현"
        "black_han_sans" -> "검은고딕"
        "maruburi" -> "마루부리"
        "ddulgi_mayo" -> "둘기마요"
        else -> font
    }
}

private fun fontFamilyForName(font: String): FontFamily {
    return when (font) {
        "gowun_batang" -> FontFamily.Serif
        "maruburi" -> FontFamily.Serif
        "do_hyeon", "black_han_sans", "cafe24_ssurround", "puradak_gentle_gothic", "tenada" ->
            FontFamily.SansSerif
        "nanum_gothic", "gowun_dodum", "pretendard", "pretendard_bold", "kakao_big_sans", "ddulgi_mayo" ->
            FontFamily.SansSerif
        else -> FontFamily.SansSerif
    }
}

private fun parseHexColor(hex: String): Color {
    return runCatching { Color(android.graphics.Color.parseColor(hex)) }
        .getOrDefault(Color.White)
}

private enum class CaptionStylePreset(
    val title: String,
    private val fontName: String,
    private val textColorHex: String,
    private val shadowColorHex: String,
    private val fontSize: WatermarkFontSize,
    private val lineSpacing: WatermarkLineSpacing = WatermarkLineSpacing.Normal,
    private val lineSpacingScale: Double = WatermarkLineSpacing.DefaultScale,
    private val shadowOpacity: Double = 0.5
) {
    Readable(
        title = "가독성",
        fontName = "pretendard_bold",
        textColorHex = "#FFFFFF",
        shadowColorHex = "#000000",
        fontSize = WatermarkFontSize.Large,
        lineSpacing = WatermarkLineSpacing.Normal,
        lineSpacingScale = WatermarkLineSpacing.DefaultScale,
        shadowOpacity = 0.45
    ),
    Travel(
        title = "여행",
        fontName = "gowun_batang",
        textColorHex = "#FFF3D6",
        shadowColorHex = "#3F6F63",
        fontSize = WatermarkFontSize.Large,
        lineSpacing = WatermarkLineSpacing.Wide,
        lineSpacingScale = WatermarkLineSpacing.Wide.scale
    ),
    Cinema(
        title = "시네마",
        fontName = "black_han_sans",
        textColorHex = "#F8F3E7",
        shadowColorHex = "#141414",
        fontSize = WatermarkFontSize.ExtraLarge,
        lineSpacing = WatermarkLineSpacing.Tight,
        lineSpacingScale = WatermarkLineSpacing.Tight.scale
    ),
    GreenGolf(
        title = "골프",
        fontName = "do_hyeon",
        textColorHex = "#FFFFFF",
        shadowColorHex = "#10B85A",
        fontSize = WatermarkFontSize.ExtraLarge,
        lineSpacing = WatermarkLineSpacing.Normal,
        lineSpacingScale = WatermarkLineSpacing.DefaultScale
    );

    fun applyTo(settings: WatermarkSettings): WatermarkSettings {
        return settings.copy(
            isEnabled = true,
            fontName = fontName,
            textColorHex = textColorHex,
            shadowEnabled = true,
            shadowOpacity = shadowOpacity,
            shadowColorHex = shadowColorHex,
            lineSpacing = lineSpacing,
            lineSpacingScale = lineSpacingScale,
            fontSize = fontSize
        )
    }

    fun matches(settings: WatermarkSettings): Boolean {
        return settings.fontName == fontName &&
            settings.textColorHex.equals(textColorHex, ignoreCase = true) &&
            settings.shadowColorHex.equals(shadowColorHex, ignoreCase = true) &&
            settings.lineSpacing == lineSpacing &&
            kotlin.math.abs(settings.lineSpacingScale - lineSpacingScale) < 0.001 &&
            settings.fontSize == fontSize
    }
}

private enum class CaptionTextPreset(val title: String) {
    Today("오늘 날짜"),
    Swing("오늘의 스윙"),
    Round("라운드 기록"),
    Empty("비우기");

    fun text(): String {
        val dateText = LocalDate.now().format(
            DateTimeFormatter.ofPattern("yy.MM.dd(E)", Locale.KOREAN)
        )
        return when (this) {
            Today -> dateText
            Swing -> "오늘의 스윙\n$dateText"
            Round -> "라운드 기록\n$dateText"
            Empty -> ""
        }
    }
}

private fun previewAlignment(position: WatermarkPosition): Alignment {
    return when (position.gridRow) {
        0 -> when (position.gridColumn) {
            0, 1 -> Alignment.TopStart
            2 -> Alignment.TopCenter
            else -> Alignment.TopEnd
        }
        1, 2, 3 -> when (position.gridColumn) {
            0, 1 -> Alignment.CenterStart
            2 -> Alignment.Center
            else -> Alignment.CenterEnd
        }
        else -> when (position.gridColumn) {
            0, 1 -> Alignment.BottomStart
            2 -> Alignment.BottomCenter
            else -> Alignment.BottomEnd
        }
    }
}
