package com.hanclip.android.feature.editor

import android.graphics.BitmapFactory
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.TextFields
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
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hanclip.android.R
import com.hanclip.android.core.model.CopyrightIconColorMode
import com.hanclip.android.core.model.EndingInfoCardTheme
import com.hanclip.android.core.model.WatermarkFontSize
import com.hanclip.android.core.model.WatermarkLineSpacing
import com.hanclip.android.core.model.WatermarkPosition
import com.hanclip.android.core.model.WatermarkPlatform
import com.hanclip.android.core.model.WatermarkSettings
import com.hanclip.android.core.model.drawableResId
import com.hanclip.android.core.project.ImportedFontStore
import com.hanclip.android.core.theme.HanClipPalette
import org.json.JSONObject
import java.time.LocalDate
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.pow
import java.io.File

private val SheetPrimary = Color(0xFF0B7A4E)
private val SheetText = Color(0xFF14221A)
private val SheetSubText = Color(0xFF46564C)
private val SheetBorder = Color(0xFFD4DDD7)

data class EndingInfoStop(
    val location: String,
    val dateText: String
)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun TextOverlaySheet(
    settings: WatermarkSettings,
    palette: HanClipPalette,
    fullScreen: Boolean = false,
    mediaCreatedAtMillis: List<Long> = emptyList(),
    onDismiss: () -> Unit,
    onApply: (WatermarkSettings) -> Unit
) {
    if (fullScreen) FullScreenDialogSystemBars(palette.solidPanel)
    val context = LocalContext.current
    val scrollState = rememberScrollState()
    var draft by remember(settings) { mutableStateOf(settings) }
    var activeCaptionPreset by remember { mutableStateOf<CaptionStylePreset?>(null) }
    var captionPresetAppearances by remember(context) {
        mutableStateOf(loadCaptionPresetAppearances(context))
    }
    var showAdvancedFonts by remember { mutableStateOf(false) }
    val captionPreviewBackground = remember(draft.textColorHex, draft.shadowColorHex) {
        captionPreviewBackgroundColor(draft.textColorHex, draft.shadowColorHex)
    }
    val mediaDateCaptionText = remember(mediaCreatedAtMillis) {
        mediaDateRangeCaptionText(mediaCreatedAtMillis)
    }
    var importedFonts by remember { mutableStateOf(ImportedFontStore.list(context)) }
    val fontPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            runCatching { ImportedFontStore.import(context, uri) }
                .onSuccess { imported ->
                    importedFonts = ImportedFontStore.list(context)
                    draft = draft.copy(fontName = imported.id)
                }
                .onFailure { error ->
                    Toast.makeText(
                        context,
                        error.message ?: "글꼴 파일을 가져오지 못했습니다.",
                        Toast.LENGTH_LONG
                    ).show()
                }
        }
    }
    val copyrightImagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            runCatching {
                val directory = File(context.filesDir, "copyright-icons").apply { mkdirs() }
                val target = File(directory, "custom-icon")
                context.contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input) { "선택한 이미지를 읽을 수 없습니다." }
                    target.outputStream().use(input::copyTo)
                }
                target.absolutePath
            }.onSuccess { path ->
                draft = draft.copy(
                    platform = WatermarkPlatform.Custom,
                    customCopyrightIconPath = path
                )
            }.onFailure { error ->
                Toast.makeText(
                    context,
                    error.message ?: "사용자 이미지를 가져오지 못했습니다.",
                    Toast.LENGTH_LONG
                ).show()
            }
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
                .verticalScroll(scrollState)
                .navigationBarsPadding()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (fullScreen) {
                FullScreenSettingsHeader(
                    title = "자막",
                    titleIcon = Icons.Outlined.TextFields,
                    resetDescription = "자막 설정 되돌리기",
                    palette = palette,
                    onReset = { draft = settings },
                    onResetLongPress = {
                        activeCaptionPreset = null
                        captionPresetAppearances = emptyMap()
                        saveCaptionPresetAppearances(context, emptyMap())
                        Toast.makeText(context, "자막 프리셋을 초기화했습니다.", Toast.LENGTH_SHORT).show()
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
                            "자막/로고",
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                            color = palette.text
                        )
                        Text("미리보기 위치 그대로 완성 MP4에 합성할 자막과 HanClip 로고를 정합니다.", color = palette.subText)
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Outlined.Close, contentDescription = "닫기", tint = palette.text)
                    }
                }
            }

            CaptionModeSegmentedControl(
                enabled = draft.isEnabled,
                palette = palette,
                onChange = { draft = draft.copy(isEnabled = it) }
            )

            Row(
                modifier = Modifier.padding(horizontal = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                listOf(
                    "오늘 날짜 삽입" to CaptionTextPreset.Today.text(),
                    "촬영 기간 삽입" to mediaDateCaptionText
                ).forEach { (label, presetText) ->
                    val selected = draft.text == presetText
                    Surface(
                        modifier = Modifier
                            .weight(1f)
                            .height(32.dp)
                            .clickable {
                                draft = draft.copy(isEnabled = true, text = presetText)
                            },
                        shape = RoundedCornerShape(16.dp),
                        color = if (selected) palette.primary.copy(alpha = 0.13f) else palette.panel,
                        border = BorderStroke(1.dp, if (selected) palette.primary.copy(alpha = 0.30f) else palette.border)
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Text(
                                label,
                                color = palette.primary,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
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
                minLines = 4,
                textStyle = MaterialTheme.typography.headlineSmall.copy(
                    color = parseHexColor(draft.textColorHex),
                    fontFamily = fontFamilyForName(context, draft.fontName),
                    fontWeight = FontWeight.Medium,
                    shadow = previewTextShadow(draft)
                ),
                shape = RoundedCornerShape(12.dp),
                placeholder = {
                    Text(
                        "여기에 글을 넣으세요\nI Love you ♡\n+82 10-0000-0000",
                        color = parseHexColor(draft.textColorHex),
                        style = MaterialTheme.typography.headlineSmall.copy(
                            fontFamily = fontFamilyForName(context, draft.fontName),
                            fontWeight = FontWeight.Medium,
                            shadow = previewTextShadow(draft)
                        )
                    )
                },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = SheetText,
                    unfocusedTextColor = SheetText,
                    focusedBorderColor = palette.primary,
                    unfocusedBorderColor = palette.border,
                    focusedLabelColor = palette.primary,
                    unfocusedLabelColor = SheetSubText,
                    focusedPlaceholderColor = parseHexColor(draft.textColorHex),
                    unfocusedPlaceholderColor = parseHexColor(draft.textColorHex),
                    focusedContainerColor = captionPreviewBackground.copy(alpha = 0.72f),
                    unfocusedContainerColor = captionPreviewBackground.copy(alpha = 0.72f),
                    disabledContainerColor = captionPreviewBackground.copy(alpha = 0.72f)
                )
            )

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CaptionStylePicker(
                    settings = draft,
                    palette = palette,
                    appearances = captionPresetAppearances,
                    onSelect = { preset, appearance ->
                        activeCaptionPreset = preset
                        draft = preset.applyTo(draft, appearance)
                    }
                )
            }

            LaunchedEffect(
                activeCaptionPreset,
                draft.fontName,
                draft.textColorHex,
                draft.shadowColorHex,
                draft.shadowOpacity,
                draft.fontSize,
                draft.lineSpacing,
                draft.lineSpacingScale
            ) {
                val preset = activeCaptionPreset ?: return@LaunchedEffect
                if (draft.fontName != preset.fontName) return@LaunchedEffect
                val updated = captionPresetAppearances + (
                    preset to CaptionPresetAppearance.from(draft)
                )
                if (updated != captionPresetAppearances) {
                    captionPresetAppearances = updated
                    saveCaptionPresetAppearances(context, updated)
                }
            }

            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = Color.White.copy(alpha = 0.22f),
                border = BorderStroke(1.dp, palette.border)
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    CaptionChoiceSegment(
                        labels = WatermarkFontSize.entries.map { "${it.title} ${it.pointSize}" },
                        selectedIndex = WatermarkFontSize.entries.indexOf(draft.fontSize),
                        palette = palette,
                        onSelect = { index -> draft = draft.copy(fontSize = WatermarkFontSize.entries[index]) }
                    )
                    Box(Modifier.fillMaxWidth().height(1.dp).background(palette.border))
                    CaptionChoiceSegment(
                        labels = WatermarkLineSpacing.entries.map { it.title },
                        selectedIndex = WatermarkLineSpacing.entries.indexOf(draft.lineSpacing),
                        palette = palette,
                        onSelect = { index ->
                            val spacing = WatermarkLineSpacing.entries[index]
                            draft = draft.copy(lineSpacing = spacing, lineSpacingScale = spacing.scale)
                        }
                    )
                    Box(Modifier.fillMaxWidth().height(1.dp).background(palette.border))
                    CaptionColorAndShadowControls(
                        settings = draft,
                        palette = palette,
                        onChange = { draft = it }
                    )
                }
            }

            Surface(
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .width(48.dp)
                    .height(26.dp)
                    .clickable { showAdvancedFonts = !showAdvancedFonts },
                shape = RoundedCornerShape(13.dp),
                color = palette.secondary.copy(alpha = 0.08f),
                border = BorderStroke(1.dp, palette.secondary.copy(alpha = 0.14f))
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(if (showAdvancedFonts) "⌃" else "⌄", color = palette.subText, fontWeight = FontWeight.Black)
                }
            }

            if (showAdvancedFonts) {
                SettingGroup(title = "전체 서체") {
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
                    "ddulgi_mayo",
                    "paperlogy_bold",
                    "nexon_lv1_gothic",
                    "poppins"
                    ).forEach { font ->
                        val fontFamily = remember(font) { fontFamilyForName(context, font) }
                        FilterChip(
                            selected = draft.fontName == font,
                            onClick = { draft = draft.copy(fontName = font) },
                            label = {
                                Text(
                                    fontDisplayName(font),
                                    fontWeight = FontWeight.SemiBold,
                                    fontFamily = fontFamily
                                )
                            },
                            colors = sheetFilterChipColors(),
                            border = sheetFilterChipBorder(draft.fontName == font)
                        )
                    }
                    importedFonts.forEach { font ->
                        val fontFamily = remember(font.id) { fontFamilyForName(context, font.id) }
                        FilterChip(
                            selected = draft.fontName == font.id,
                            onClick = { draft = draft.copy(fontName = font.id) },
                            label = {
                                Text(
                                    font.displayName,
                                    fontWeight = FontWeight.SemiBold,
                                    fontFamily = fontFamily
                                )
                            },
                            colors = sheetFilterChipColors(),
                            border = sheetFilterChipBorder(draft.fontName == font.id)
                        )
                    }
                    Button(
                        onClick = {
                            fontPicker.launch(
                                arrayOf(
                                    "font/ttf",
                                    "font/otf",
                                    "application/x-font-ttf",
                                    "application/x-font-opentype",
                                    "application/octet-stream"
                                )
                            )
                        },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFFE9F4EE),
                            contentColor = SheetText
                        )
                    ) {
                        Text("TTF/OTF 가져오기", fontWeight = FontWeight.Bold)
                    }
                }
            }

            // 워터마크는 iOS와 동일하게 카피라이터 설정에서만 편집합니다.
            if (false && draft.logoEnabled) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("플랫폼", fontWeight = FontWeight.SemiBold, color = SheetText)
                    PlatformPicker(
                        selected = draft.platform,
                        palette = palette,
                        onSelect = { draft = draft.copy(platform = it) }
                    )
                }

                if (draft.platform != WatermarkPlatform.HanClip) {
                    OutlinedTextField(
                        value = draft.address,
                        onValueChange = { draft = draft.copy(address = it.take(120)) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        label = {
                            Text(
                                if (draft.platform == WatermarkPlatform.Custom) {
                                    "표시할 자막"
                                } else {
                                    "${draft.platform.title} 한 줄 입력"
                                }
                            )
                        },
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = SheetText,
                            unfocusedTextColor = SheetText,
                            focusedBorderColor = palette.primary,
                            unfocusedBorderColor = palette.border
                        )
                    )
                }
                if (draft.platform == WatermarkPlatform.Custom) {
                    Button(
                        onClick = { copyrightImagePicker.launch(arrayOf("image/*")) },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = palette.chip,
                            contentColor = palette.text
                        )
                    ) {
                        Text(
                            if (draft.customCopyrightIconPath.isBlank()) "사용자 이미지 선택" else "사용자 이미지 바꾸기",
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

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

            if (false) Row(
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

            if (false && draft.shadowEnabled) {
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

            if (false) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
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

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun EndingInfoCardSettings(
    settings: WatermarkSettings,
    stops: List<EndingInfoStop>,
    palette: HanClipPalette,
    onChange: (WatermarkSettings) -> Unit
) {
    val previewStops = stops.ifEmpty {
        listOf(
            EndingInfoStop("서울", "8. 7."),
            EndingInfoStop("덕양구", "8. 8."),
            EndingInfoStop("Philippines Clark", "8. 9.")
        )
    }
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("▤  정보 삽입", fontWeight = FontWeight.Bold, color = palette.text)
                    Text(
                        if (stops.isNotEmpty()) "날짜와 촬영 위치를 마지막 장면에 넣습니다."
                        else "미리 설정해 두면 위치 미디어를 추가할 때 적용됩니다.",
                        color = palette.subText
                    )
                }
                Switch(
                    checked = settings.includesEndingInfoCard,
                    onCheckedChange = { onChange(settings.copy(includesEndingInfoCard = it)) },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = palette.primary
                    )
                )
            }

            if (settings.includesEndingInfoCard) {
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                    verticalArrangement = Arrangement.spacedBy(7.dp)
                ) {
                    EndingInfoCardTheme.entries.forEach { theme ->
                        FilterChip(
                            selected = settings.endingInfoCardTheme == theme,
                            onClick = { onChange(settings.copy(endingInfoCardTheme = theme)) },
                            label = { Text("${endingThemeMark(theme)}  ${theme.title}") },
                            colors = sheetFilterChipColors(),
                            border = sheetFilterChipBorder(settings.endingInfoCardTheme == theme)
                        )
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("표시 시간", fontWeight = FontWeight.SemiBold, color = palette.text)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(
                            onClick = {
                                onChange(settings.copy(endingInfoCardDuration = settings.normalizedEndingInfoCardDuration - 0.5))
                            }
                        ) {
                            Icon(Icons.Outlined.Remove, contentDescription = "시간 줄이기", tint = palette.text)
                        }
                        Text(
                            "%.1f초".format(settings.normalizedEndingInfoCardDuration),
                            fontWeight = FontWeight.Bold,
                            color = palette.text
                        )
                        IconButton(
                            onClick = {
                                onChange(settings.copy(endingInfoCardDuration = settings.normalizedEndingInfoCardDuration + 0.5))
                            }
                        ) {
                            Icon(Icons.Outlined.Add, contentDescription = "시간 늘리기", tint = palette.text)
                        }
                    }
                }

                EndingInfoCardPreview(
                    theme = settings.endingInfoCardTheme,
                    stops = previewStops,
                    palette = palette,
                    settings = settings
                )
            }
        }
    }
}

@Composable
internal fun EndingInfoCardPreview(
    theme: EndingInfoCardTheme,
    stops: List<EndingInfoStop>,
    palette: HanClipPalette,
    settings: WatermarkSettings? = null
) {
    val colors = endingPreviewColors(theme)
    val context = LocalContext.current
    val previewFont = remember(settings?.fontName, theme) {
        fontFamilyForName(
            context,
            when (theme) {
                EndingInfoCardTheme.TreasureMap -> "gowun_batang"
                EndingInfoCardTheme.Landmark -> "maruburi"
                else -> settings?.fontName ?: "pretendard"
            }
        )
    }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(230.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(Brush.linearGradient(listOf(colors[0], colors[1])))
            .padding(16.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(18.dp))
                .background(colors[2])
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(7.dp)
        ) {
            Text(
                endingThemeHeading(theme, stops),
                color = colors[3],
                fontWeight = FontWeight.ExtraBold,
                fontFamily = previewFont
            )
            Text(
                stops.map { it.dateText }.filter { it.isNotBlank() }.let { dates ->
                    when {
                        dates.isEmpty() -> ""
                        dates.first() == dates.last() -> dates.first()
                        else -> "${dates.first()}  –  ${dates.last()}"
                    }
                },
                color = colors[4],
                style = MaterialTheme.typography.bodySmall
            )
            EndingPreviewBody(theme = theme, stops = stops, colors = colors, fontFamily = previewFont)
        }
    }
}

@Composable
private fun EndingPreviewBody(
    theme: EndingInfoCardTheme,
    stops: List<EndingInfoStop>,
    colors: List<Color>,
    fontFamily: androidx.compose.ui.text.font.FontFamily
) {
    when (theme) {
        EndingInfoCardTheme.Caption -> EndingPreviewCaption(stops, colors, fontFamily)
        EndingInfoCardTheme.TreasureMap -> EndingPreviewRoute(
            stops,
            colors,
            treasureMap = true,
            fontFamily = fontFamily
        )
        EndingInfoCardTheme.Itinerary -> EndingPreviewItinerary(stops, colors)
        EndingInfoCardTheme.Landmark -> EndingPreviewLandmarks(stops, colors, fontFamily)
        EndingInfoCardTheme.Office -> EndingPreviewOffice(stops, colors)
    }
}

@Composable
private fun EndingPreviewCaption(
    stops: List<EndingInfoStop>,
    colors: List<Color>,
    fontFamily: androidx.compose.ui.text.font.FontFamily
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        stops.take(4).forEachIndexed { index, stop ->
            if (index > 0) {
                Text(if (index % 2 == 0) "  ✈  " else "  ◈  ", color = colors[4], fontSize = 10.sp)
            }
            Text(
                stop.location,
                color = colors[3],
                fontFamily = fontFamily,
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp,
                maxLines = 1
            )
        }
    }
}

@Composable
private fun EndingPreviewRoute(
    stops: List<EndingInfoStop>,
    colors: List<Color>,
    treasureMap: Boolean,
    fontFamily: androidx.compose.ui.text.font.FontFamily
) {
    stops.take(3).forEachIndexed { index, stop ->
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = if (treasureMap && index % 2 == 1) 30.dp else 0.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                when {
                    treasureMap && index == minOf(2, stops.lastIndex) -> "×"
                    treasureMap -> "◉"
                    index == 0 -> "◉"
                    else -> if (index % 2 == 0) "✈" else "◈"
                },
                color = colors[4],
                fontWeight = FontWeight.Black
            )
            Text(
                if (treasureMap && index > 0) " · · · " else "  ",
                color = colors[4],
                fontSize = 10.sp
            )
            Text(
                stop.location,
                modifier = Modifier.weight(1f),
                color = colors[3],
                maxLines = 1,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = fontFamily
            )
            Text(stop.dateText, color = colors[4], fontSize = 9.sp)
        }
    }
}

@Composable
private fun EndingPreviewItinerary(stops: List<EndingInfoStop>, colors: List<Color>) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        stops.take(3).forEachIndexed { index, stop ->
            Column(
                modifier = Modifier.weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Text(if (index % 2 == 0) "●" else "◆", color = colors[3], fontSize = 10.sp)
                Surface(shape = RoundedCornerShape(50), color = colors[4]) {
                    Text(
                        stop.dateText,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                        color = Color.White,
                        fontSize = 8.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                Text(stop.location, color = colors[3], fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            }
        }
    }
}

@Composable
private fun EndingPreviewLandmarks(
    stops: List<EndingInfoStop>,
    colors: List<Color>,
    fontFamily: androidx.compose.ui.text.font.FontFamily
) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        stops.take(3).forEach { stop ->
            Column(
                modifier = Modifier.weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(landmarkEmoji(stop.location), fontSize = 22.sp)
                Text("●", color = colors[4], fontSize = 9.sp)
                Text(stop.location, color = colors[3], fontFamily = fontFamily, fontSize = 8.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            }
        }
    }
}

@Composable
private fun EndingPreviewOffice(stops: List<EndingInfoStop>, colors: List<Color>) {
    Row(Modifier.fillMaxWidth()) {
        Text("DOC. HAN-${stops.size.toString().padStart(2, '0')}", modifier = Modifier.weight(1f), color = colors[4], fontSize = 8.sp, fontWeight = FontWeight.Black)
        Text("TRAVEL LOG", color = colors[4], fontSize = 8.sp, fontWeight = FontWeight.Black)
    }
    Row(Modifier.fillMaxWidth().background(colors[4])) {
        Text("NO.", modifier = Modifier.width(24.dp), color = Color.White, fontSize = 7.sp, fontWeight = FontWeight.Bold)
        Text("DATE", modifier = Modifier.width(50.dp), color = Color.White, fontSize = 7.sp, fontWeight = FontWeight.Bold)
        Text("REGION", modifier = Modifier.weight(1f), color = Color.White, fontSize = 7.sp, fontWeight = FontWeight.Bold)
        Text("MOVE", color = Color.White, fontSize = 7.sp, fontWeight = FontWeight.Bold)
    }
    stops.take(3).forEachIndexed { index, stop ->
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(if (index % 2 == 0) colors[0].copy(alpha = 0.045f) else Color.Transparent)
                .padding(horizontal = 5.dp, vertical = 3.dp)
        ) {
            Text((index + 1).toString().padStart(2, '0'), modifier = Modifier.width(24.dp), color = colors[4], fontSize = 8.sp)
            Text(stop.dateText, modifier = Modifier.width(50.dp), color = colors[3], fontSize = 9.sp)
            Text(stop.location, modifier = Modifier.weight(1f), color = colors[3], fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(if (index == 0) "START" else if (index % 2 == 0) "AIR" else "CAR", color = colors[4], fontSize = 7.sp, fontWeight = FontWeight.Bold)
        }
    }
}

private fun landmarkEmoji(location: String): String = when {
    location.contains("서울", ignoreCase = true) -> "🏯"
    location.contains("부산", ignoreCase = true) -> "🌊"
    location.contains("제주", ignoreCase = true) -> "🌋"
    location.contains("Paris", ignoreCase = true) -> "🗼"
    location.contains("Clark", ignoreCase = true) || location.contains("Philippines", ignoreCase = true) -> "🏝"
    else -> "📍"
}

internal fun endingThemeMark(theme: EndingInfoCardTheme): String = when (theme) {
    EndingInfoCardTheme.Caption -> "가"
    EndingInfoCardTheme.TreasureMap -> "⌖"
    EndingInfoCardTheme.Itinerary -> "≡"
    EndingInfoCardTheme.Landmark -> "⌂"
    EndingInfoCardTheme.Office -> "▦"
}

private fun endingThemeHeading(theme: EndingInfoCardTheme, stops: List<EndingInfoStop>): String = when (theme) {
    EndingInfoCardTheme.Caption -> "여행 기록"
    EndingInfoCardTheme.TreasureMap -> "여행 기록"
    EndingInfoCardTheme.Itinerary -> "여행 일정표"
    EndingInfoCardTheme.Landmark -> {
        val first = stops.firstOrNull()?.location ?: "여행"
        val last = stops.lastOrNull()?.location ?: first
        if (first == last) "$first 여행" else "$first · $last 여행"
    }
    EndingInfoCardTheme.Office -> "여행 기록 보고서"
}

private fun endingPreviewColors(theme: EndingInfoCardTheme): List<Color> = when (theme) {
    EndingInfoCardTheme.Caption -> listOf(Color(0xFF121617), Color(0xFF22312F), Color(0xCC34433F), Color.White, Color(0xFFA0CDBE))
    EndingInfoCardTheme.TreasureMap -> listOf(Color(0xFF7A4A1F), Color(0xFFE8C27A), Color(0xFFF2D69C), Color(0xFF3D1F0E), Color(0xFF7A2E0F))
    EndingInfoCardTheme.Itinerary -> listOf(Color(0xFFFCF5F0), Color(0xFFFFFCFA), Color.White, Color(0xFF383336), Color(0xFFD64761))
    EndingInfoCardTheme.Landmark -> listOf(Color(0xFFF5E6DE), Color(0xFFFFFAF0), Color(0xFFFFF7EB), Color(0xFF45302B), Color(0xFF8F4A47))
    EndingInfoCardTheme.Office -> listOf(Color(0xFFF2F2EB), Color.White, Color.White, Color(0xFF242933), Color(0xFF213D66))
}

@Composable
private fun CaptionPreview(settings: WatermarkSettings) {
    val context = LocalContext.current
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(178.dp),
        shape = RoundedCornerShape(16.dp),
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
                    fontFamily = fontFamilyForName(context, settings.fontName),
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.bodyLarge.copy(
                        lineHeight = (18 * settings.lineSpacingScale.coerceIn(0.5, 2.0)).sp,
                        shadow = previewTextShadow(settings)
                    )
                )
            }
            if (settings.logoEnabled) {
                CopyrightLogoPreview(
                    modifier = Modifier
                        .align(previewAlignment(settings.copyrightPosition))
                        .shadow(
                            elevation = (settings.logoShadowOpacity.coerceIn(0.0, 1.0) * 4).dp,
                            ambientColor = parseHexColor(settings.logoShadowColorHex),
                            spotColor = parseHexColor(settings.logoShadowColorHex)
                        ),
                    settings = settings,
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
private fun CopyrightLogoPreview(
    modifier: Modifier = Modifier,
    settings: WatermarkSettings,
    color: Color
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        val customBitmap = remember(settings.customCopyrightIconPath, settings.platform) {
            settings.customCopyrightIconPath
                .takeIf { settings.platform == WatermarkPlatform.Custom && it.isNotBlank() }
                ?.let(BitmapFactory::decodeFile)
        }
        if (customBitmap != null) {
            Image(
                bitmap = customBitmap.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                colorFilter = if (settings.copyrightIconColorMode == CopyrightIconColorMode.Original) {
                    null
                } else {
                    ColorFilter.tint(color)
                }
            )
        } else {
            Image(
                painter = painterResource(settings.platform.drawableResId),
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                colorFilter = if (settings.copyrightIconColorMode == CopyrightIconColorMode.Original) {
                    null
                } else {
                    ColorFilter.tint(color)
                }
            )
        }
        Text(
            text = if (settings.platform == WatermarkPlatform.HanClip) {
                "HanClip"
            } else {
                settings.displayCopyrightText
            },
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
        shape = RoundedCornerShape(16.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        FlowRow(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            CaptionStateChip(
                text = "미리보기 위치 그대로",
                active = settings.shouldRender,
                palette = palette
            )
            CaptionStateChip(
                text = "완성 MP4 합성",
                active = settings.shouldRender,
                palette = palette
            )
            CaptionStateChip(
                text = if (settings.shouldRenderText) "MP4 자막 켬" else "MP4 자막 꺼짐",
                active = settings.shouldRenderText,
                palette = palette
            )
            CaptionStateChip(
                text = if (settings.logoEnabled) "${settings.platform.title} 워터마크 켬" else "워터마크 꺼짐",
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
                text = "워터마크 ${watermarkPositionShortTitle(settings.copyrightPosition)}",
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
        settings.shouldRenderText && settings.logoEnabled -> "MP4에 자막과 워터마크 적용"
        settings.shouldRenderText -> "MP4에 자막 적용"
        settings.logoEnabled -> "MP4에 워터마크 적용"
        else -> "MP4 자막/로고 끄기 적용"
    }
}

private fun hanClipDefaultWatermark(settings: WatermarkSettings): WatermarkSettings {
    return settings.copy(
        isEnabled = true,
        logoEnabled = true,
        address = "",
        platform = WatermarkPlatform.HanClip,
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
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
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
                    .clip(RoundedCornerShape(10.dp))
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
        shape = RoundedCornerShape(16.dp),
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
                                .clip(RoundedCornerShape(10.dp))
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

@Composable
private fun PlatformPicker(
    selected: WatermarkPlatform,
    palette: HanClipPalette,
    onSelect: (WatermarkPlatform) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        WatermarkPlatform.entries.chunked(5).forEach { rowPlatforms ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(7.dp)
            ) {
                rowPlatforms.forEach { platform ->
                    val isSelected = selected == platform
                    Surface(
                        modifier = Modifier
                            .weight(1f)
                            .height(54.dp)
                            .clickable { onSelect(platform) },
                        shape = RoundedCornerShape(16.dp),
                        color = if (isSelected) palette.primary else palette.chip,
                        border = BorderStroke(
                            1.dp,
                            if (isSelected) palette.primary else palette.border
                        )
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Image(
                                painter = painterResource(platform.drawableResId),
                                contentDescription = platform.title,
                                modifier = Modifier.size(32.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CaptionModeSegmentedControl(
    enabled: Boolean,
    palette: HanClipPalette,
    onChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .clip(RoundedCornerShape(25.dp))
            .background(palette.secondary.copy(alpha = 0.14f))
            .padding(3.dp)
    ) {
        listOf(true to "사용", false to "안함").forEach { (value, label) ->
            val selected = enabled == value
            Surface(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxSize()
                    .clickable { onChange(value) },
                shape = RoundedCornerShape(22.dp),
                color = if (selected) palette.primary else Color.Transparent
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        label,
                        color = if (selected) Color.White else palette.primary,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }
}

@Composable
private fun CaptionChoiceSegment(
    labels: List<String>,
    selectedIndex: Int,
    palette: HanClipPalette,
    onSelect: (Int) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(40.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(palette.secondary.copy(alpha = 0.14f))
            .padding(3.dp)
    ) {
        labels.forEachIndexed { index, label ->
            val selected = selectedIndex == index
            Surface(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxSize()
                    .clickable { onSelect(index) },
                shape = RoundedCornerShape(18.dp),
                color = if (selected) palette.primary else Color.Transparent
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        label,
                        color = if (selected) Color.White else palette.primary,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1
                    )
                }
            }
        }
    }
}

@Composable
private fun CaptionColorAndShadowControls(
    settings: WatermarkSettings,
    palette: HanClipPalette,
    onChange: (WatermarkSettings) -> Unit
) {
    val textColors = listOf("#FFFFFF", "#FFE45C", "#0B7A4E", "#111111", "#FF6B5E")
    val shadowColors = listOf("#000000", "#642BFF", "#18A8FF", "#3F6F63", "#FFFFFF")
    fun nextColor(current: String, choices: List<String>): String {
        val index = choices.indexOfFirst { it.equals(current, ignoreCase = true) }
        return choices[(index + 1).mod(choices.size)]
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        CaptionColorButton("글자색", settings.textColorHex, palette) {
            onChange(settings.copy(textColorHex = nextColor(settings.textColorHex, textColors)))
        }
        Box(Modifier.width(1.dp).height(30.dp).background(palette.border))
        CaptionColorButton("그림자색", settings.shadowColorHex, palette) {
            onChange(
                settings.copy(
                    shadowEnabled = true,
                    shadowColorHex = nextColor(settings.shadowColorHex, shadowColors)
                )
            )
        }
        Slider(
            value = settings.shadowOpacity.coerceIn(0.0, 1.0).toFloat(),
            onValueChange = { value ->
                onChange(settings.copy(shadowEnabled = value > 0f, shadowOpacity = value.toDouble()))
            },
            valueRange = 0f..1f,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun CaptionColorButton(
    title: String,
    colorHex: String,
    palette: HanClipPalette,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier.clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(title, color = palette.subText, fontWeight = FontWeight.Bold, fontSize = 12.sp)
        Surface(
            modifier = Modifier.size(30.dp),
            shape = RoundedCornerShape(15.dp),
            color = parseHexColor(colorHex),
            border = BorderStroke(3.dp, Color.White)
        ) {}
    }
}

@Composable
private fun CaptionStylePicker(
    settings: WatermarkSettings,
    palette: HanClipPalette,
    appearances: Map<CaptionStylePreset, CaptionPresetAppearance>,
    onSelect: (CaptionStylePreset, CaptionPresetAppearance) -> Unit
) {
    val context = LocalContext.current
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        CaptionStylePreset.entries.chunked(3).forEach { rowPresets ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(7.dp)
            ) {
                rowPresets.forEach { preset ->
                    val appearance = appearances[preset] ?: preset.defaultAppearance
                    val previewFontFamily = remember(preset.fontName) {
                        fontFamilyForName(context, preset.fontName)
                    }
                    val selected = preset.matches(settings, appearance)
                    Surface(
                        modifier = Modifier
                            .weight(1f)
                            .height(40.dp)
                            .clickable { onSelect(preset, appearance) },
                        shape = RoundedCornerShape(10.dp),
                        color = if (selected) palette.secondary.copy(alpha = 0.20f) else palette.chip,
                        border = BorderStroke(1.dp, if (selected) palette.primary else palette.border)
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 9.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(7.dp)
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(17.dp)
                                    .border(
                                        2.dp,
                                        if (selected) palette.primary else palette.secondary.copy(alpha = 0.52f),
                                        RoundedCornerShape(9.dp)
                                    ),
                                contentAlignment = Alignment.Center
                            ) {
                                if (selected) {
                                    Box(
                                        Modifier
                                            .size(8.dp)
                                            .clip(RoundedCornerShape(4.dp))
                                            .background(palette.primary)
                                    )
                                }
                            }
                            Text(
                                preset.title,
                                color = if (selected) palette.primary else palette.subText,
                                fontWeight = if (selected) FontWeight.Black else FontWeight.SemiBold,
                                fontSize = 12.sp,
                                maxLines = 1,
                                modifier = Modifier.weight(1f)
                            )
                            Text(
                                "Aa",
                                color = parseHexColor(appearance.textColorHex),
                                fontWeight = FontWeight.Black,
                                fontFamily = previewFontFamily,
                                style = MaterialTheme.typography.titleMedium
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
    if (ImportedFontStore.isImportedFont(font)) {
        return font.removePrefix("imported_font:")
            .substringBeforeLast('.')
            .substringBeforeLast("--")
            .ifBlank { "사용자 글꼴" }
    }
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
        "paperlogy_bold" -> "페이퍼로지B"
        "nexon_lv1_gothic" -> "넥슨Lv1"
        "poppins" -> "Poppins"
        else -> font
    }
}

internal fun fontFamilyForName(context: android.content.Context, font: String): FontFamily {
    ImportedFontStore.typeface(context, font)?.let { return FontFamily(it) }
    val assetPath = when (font) {
        "pretendard_bold" -> "fonts/pretendard_bold.ttf"
        "kakao_big_sans" -> "fonts/kakao_big_sans_regular.ttf"
        "gowun_batang" -> "fonts/gowun_batang_regular.ttf"
        "gowun_dodum" -> "fonts/gowun_dodum_regular.ttf"
        "nanum_gothic" -> "fonts/nanum_gothic_regular.ttf"
        "cafe24_ssurround" -> "fonts/cafe24_ssurround.ttf"
        "puradak_gentle_gothic" -> "fonts/puradak_gentle_gothic.ttf"
        "tenada" -> "fonts/tenada.ttf"
        "do_hyeon" -> "fonts/do_hyeon_regular.ttf"
        "black_han_sans" -> "fonts/black_han_sans_regular.ttf"
        "maruburi" -> "fonts/maru_buri_regular.ttf"
        "ddulgi_mayo" -> "fonts/ddulgi_mayo.otf"
        "paperlogy_bold" -> "fonts/paperlogy_bold.ttf"
        "nexon_lv1_gothic" -> "fonts/nexon_lv1_gothic.ttf"
        "poppins" -> "fonts/poppins_regular.ttf"
        "pretendard" -> "fonts/pretendard_regular.otf"
        else -> null
    }
    assetPath?.let { path ->
        runCatching {
            FontFamily(android.graphics.Typeface.createFromAsset(context.assets, path))
        }.getOrNull()?.let { return it }
    }
    return when (font) {
        "gowun_batang" -> FontFamily.Serif
        "maruburi" -> FontFamily.Serif
        "do_hyeon", "black_han_sans", "cafe24_ssurround", "puradak_gentle_gothic", "tenada" ->
            FontFamily.SansSerif
        "nanum_gothic", "gowun_dodum", "pretendard", "pretendard_bold", "kakao_big_sans", "ddulgi_mayo",
        "paperlogy_bold", "nexon_lv1_gothic", "poppins" ->
            FontFamily.SansSerif
        else -> FontFamily.SansSerif
    }
}

private fun parseHexColor(hex: String): Color {
    return runCatching { Color(android.graphics.Color.parseColor(hex)) }
        .getOrDefault(Color.White)
}

private val CaptionPreviewBackgroundPalette = listOf(
    Color(0xFFFFF7C7),
    Color(0xFFDFF4FF),
    Color(0xFFE4FFD8),
    Color(0xFFFFE0EA),
    Color(0xFFEFE3FF),
    Color(0xFFE0FFF6),
    Color(0xFFFFF0D6),
    Color(0xFFF2F4FF)
)

private fun captionPreviewBackgroundColor(textColorHex: String, shadowColorHex: String): Color {
    val excluded = listOf(parseHexColor(textColorHex), parseHexColor(shadowColorHex))
    val scored = CaptionPreviewBackgroundPalette.map { candidate ->
        candidate to excluded.minOf { foreground -> colorContrastRatio(candidate, foreground) }
    }
    val bestScore = scored.maxOfOrNull { it.second } ?: return CaptionPreviewBackgroundPalette.first()
    return scored.filter { it.second >= bestScore * 0.85f }.randomOrNull()?.first
        ?: CaptionPreviewBackgroundPalette.first()
}

private fun colorContrastRatio(first: Color, second: Color): Float {
    val firstLuminance = relativeLuminance(first)
    val secondLuminance = relativeLuminance(second)
    val lighter = maxOf(firstLuminance, secondLuminance)
    val darker = minOf(firstLuminance, secondLuminance)
    return (lighter + 0.05f) / (darker + 0.05f)
}

private fun relativeLuminance(color: Color): Float {
    fun convert(component: Float): Float = if (component <= 0.03928f) {
        component / 12.92f
    } else {
        ((component + 0.055f) / 1.055f).pow(2.4f)
    }
    return 0.2126f * convert(color.red) +
        0.7152f * convert(color.green) +
        0.0722f * convert(color.blue)
}

private enum class CaptionStylePreset(
    val title: String,
    val fontName: String,
    val previewTextColorHex: String,
    private val shadowColorHex: String,
    private val fontSize: WatermarkFontSize,
    private val lineSpacing: WatermarkLineSpacing = WatermarkLineSpacing.Normal,
    private val lineSpacingScale: Double = WatermarkLineSpacing.DefaultScale,
    private val shadowOpacity: Double = 0.5
) {
    Readable(
        title = "가독성",
        fontName = "pretendard",
        previewTextColorHex = "#FFFFFF",
        shadowColorHex = "#000000",
        fontSize = WatermarkFontSize.Large,
        shadowOpacity = 0.45
    ),
    Lovely(
        title = "러블리",
        fontName = "ddulgi_mayo",
        previewTextColorHex = "#FF6FAE",
        shadowColorHex = "#7A3FFF",
        fontSize = WatermarkFontSize.Large
    ),
    Strong(
        title = "강력한",
        fontName = "tenada",
        previewTextColorHex = "#FFE600",
        shadowColorHex = "#000000",
        fontSize = WatermarkFontSize.ExtraLarge
    ),
    Fresh(
        title = "청량",
        fontName = "gowun_dodum",
        previewTextColorHex = "#FFFFFF",
        shadowColorHex = "#18A8FF",
        fontSize = WatermarkFontSize.Large
    ),
    Travel(
        title = "여행",
        fontName = "gowun_batang",
        previewTextColorHex = "#FFF3D6",
        shadowColorHex = "#3F6F63",
        fontSize = WatermarkFontSize.Large,
        lineSpacing = WatermarkLineSpacing.Wide,
        lineSpacingScale = WatermarkLineSpacing.Wide.scale
    ),
    Cinema(
        title = "시네마",
        fontName = "black_han_sans",
        previewTextColorHex = "#F8F3E7",
        shadowColorHex = "#141414",
        fontSize = WatermarkFontSize.ExtraLarge,
        lineSpacing = WatermarkLineSpacing.Tight,
        lineSpacingScale = WatermarkLineSpacing.Tight.scale
    ),
    Daily(
        title = "데일리",
        fontName = "do_hyeon",
        previewTextColorHex = "#FFFFFF",
        shadowColorHex = "#FF7A3D",
        fontSize = WatermarkFontSize.Large
    ),
    Sentimental(
        title = "감성",
        fontName = "gowun_batang",
        previewTextColorHex = "#FFE9F0",
        shadowColorHex = "#6E5BFF",
        fontSize = WatermarkFontSize.Normal
    ),
    GreenGolf(
        title = "그린골프",
        fontName = "do_hyeon",
        previewTextColorHex = "#FFFFFF",
        shadowColorHex = "#10B85A",
        fontSize = WatermarkFontSize.ExtraLarge
    ),
    Magazine(
        title = "매거진",
        fontName = "paperlogy_bold",
        previewTextColorHex = "#FFF4D6",
        shadowColorHex = "#D94A32",
        fontSize = WatermarkFontSize.ExtraLarge,
        shadowOpacity = 0.55
    ),
    Sports(
        title = "스포츠",
        fontName = "paperlogy_bold",
        previewTextColorHex = "#D8FF3E",
        shadowColorHex = "#10223A",
        fontSize = WatermarkFontSize.ExtraLarge,
        shadowOpacity = 0.7
    ),
    Clean(
        title = "클린",
        fontName = "nexon_lv1_gothic",
        previewTextColorHex = "#FFFFFF",
        shadowColorHex = "#1B4D89",
        fontSize = WatermarkFontSize.Large,
        shadowOpacity = 0.35
    ),
    Neon(
        title = "네온",
        fontName = "nexon_lv1_gothic",
        previewTextColorHex = "#7DF9FF",
        shadowColorHex = "#6C2BFF",
        fontSize = WatermarkFontSize.Large,
        shadowOpacity = 0.8
    ),
    Vlog(
        title = "VLOG",
        fontName = "poppins",
        previewTextColorHex = "#FFFFFF",
        shadowColorHex = "#FF6B5E",
        fontSize = WatermarkFontSize.Large,
        shadowOpacity = 0.55
    ),
    Pop(
        title = "POP",
        fontName = "poppins",
        previewTextColorHex = "#FFE45C",
        shadowColorHex = "#642BFF",
        fontSize = WatermarkFontSize.ExtraLarge,
        shadowOpacity = 0.75
    );

    val defaultAppearance: CaptionPresetAppearance
        get() = CaptionPresetAppearance(
            textColorHex = previewTextColorHex,
            shadowColorHex = shadowColorHex,
            shadowOpacity = shadowOpacity,
            fontSize = fontSize,
            lineSpacing = lineSpacing,
            lineSpacingScale = lineSpacingScale
        )

    fun applyTo(
        settings: WatermarkSettings,
        appearance: CaptionPresetAppearance = defaultAppearance
    ): WatermarkSettings {
        return settings.copy(
            isEnabled = true,
            fontName = fontName,
            textColorHex = appearance.textColorHex,
            shadowEnabled = appearance.shadowOpacity > 0.0,
            shadowOpacity = appearance.shadowOpacity,
            shadowColorHex = appearance.shadowColorHex,
            lineSpacing = appearance.lineSpacing,
            lineSpacingScale = appearance.lineSpacingScale,
            fontSize = appearance.fontSize
        )
    }

    fun matches(
        settings: WatermarkSettings,
        appearance: CaptionPresetAppearance = defaultAppearance
    ): Boolean {
        return settings.fontName == fontName &&
            settings.textColorHex.equals(appearance.textColorHex, ignoreCase = true) &&
            settings.shadowColorHex.equals(appearance.shadowColorHex, ignoreCase = true) &&
            kotlin.math.abs(settings.shadowOpacity - appearance.shadowOpacity) < 0.001 &&
            settings.lineSpacing == appearance.lineSpacing &&
            kotlin.math.abs(settings.lineSpacingScale - appearance.lineSpacingScale) < 0.001 &&
            settings.fontSize == appearance.fontSize
    }
}

private data class CaptionPresetAppearance(
    val textColorHex: String,
    val shadowColorHex: String,
    val shadowOpacity: Double,
    val fontSize: WatermarkFontSize,
    val lineSpacing: WatermarkLineSpacing,
    val lineSpacingScale: Double
) {
    companion object {
        fun from(settings: WatermarkSettings) = CaptionPresetAppearance(
            textColorHex = settings.textColorHex,
            shadowColorHex = settings.shadowColorHex,
            shadowOpacity = settings.shadowOpacity.coerceIn(0.0, 1.0),
            fontSize = settings.fontSize,
            lineSpacing = settings.lineSpacing,
            lineSpacingScale = WatermarkLineSpacing.normalize(settings.lineSpacingScale)
        )
    }
}

private const val CaptionPresetAppearancesKey = "caption_preset_appearances"

private fun loadCaptionPresetAppearances(
    context: android.content.Context
): Map<CaptionStylePreset, CaptionPresetAppearance> {
    val raw = context.getSharedPreferences("hanclip_caption", android.content.Context.MODE_PRIVATE)
        .getString(CaptionPresetAppearancesKey, null) ?: return emptyMap()
    return runCatching {
        val root = JSONObject(raw)
        CaptionStylePreset.entries.mapNotNull { preset ->
            val value = root.optJSONObject(preset.name) ?: return@mapNotNull null
            preset to CaptionPresetAppearance(
                textColorHex = value.optString("textColorHex", preset.previewTextColorHex),
                shadowColorHex = value.optString("shadowColorHex", preset.defaultAppearance.shadowColorHex),
                shadowOpacity = value.optDouble("shadowOpacity", preset.defaultAppearance.shadowOpacity)
                    .coerceIn(0.0, 1.0),
                fontSize = runCatching {
                    WatermarkFontSize.valueOf(value.getString("fontSize"))
                }.getOrDefault(preset.defaultAppearance.fontSize),
                lineSpacing = runCatching {
                    WatermarkLineSpacing.valueOf(value.getString("lineSpacing"))
                }.getOrDefault(preset.defaultAppearance.lineSpacing),
                lineSpacingScale = WatermarkLineSpacing.normalize(
                    value.optDouble("lineSpacingScale", preset.defaultAppearance.lineSpacingScale)
                )
            )
        }.toMap()
    }.getOrDefault(emptyMap())
}

private fun saveCaptionPresetAppearances(
    context: android.content.Context,
    values: Map<CaptionStylePreset, CaptionPresetAppearance>
) {
    val preferences = context.getSharedPreferences("hanclip_caption", android.content.Context.MODE_PRIVATE)
    if (values.isEmpty()) {
        preferences.edit().remove(CaptionPresetAppearancesKey).apply()
        return
    }
    val root = JSONObject()
    values.forEach { (preset, appearance) ->
        root.put(preset.name, JSONObject().apply {
            put("textColorHex", appearance.textColorHex)
            put("shadowColorHex", appearance.shadowColorHex)
            put("shadowOpacity", appearance.shadowOpacity)
            put("fontSize", appearance.fontSize.name)
            put("lineSpacing", appearance.lineSpacing.name)
            put("lineSpacingScale", appearance.lineSpacingScale)
        })
    }
    preferences.edit().putString(CaptionPresetAppearancesKey, root.toString()).apply()
}

private fun mediaDateRangeCaptionText(createdAtMillis: List<Long>): String {
    val dates = createdAtMillis
        .map { millis -> Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate() }
        .sorted()
    val first = dates.firstOrNull() ?: LocalDate.now()
    val last = dates.lastOrNull() ?: first
    val formatter = DateTimeFormatter.ofPattern("yy.MM.dd(E)", Locale.KOREAN)
    val firstText = first.format(formatter)
    return if (first == last) firstText else "$firstText - ${last.format(formatter)}"
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
