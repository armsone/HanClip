package com.hanclip.android.feature.home

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.AddPhotoAlternate
import androidx.compose.material.icons.outlined.Flight
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.SportsGolf
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material.icons.outlined.TravelExplore
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import com.hanclip.android.R
import com.hanclip.android.core.model.MoviePreset
import com.hanclip.android.core.model.OutputQualityPreset
import com.hanclip.android.core.project.ExportHistoryStore
import com.hanclip.android.core.project.ExportedMovieSummary
import com.hanclip.android.core.project.hanClipCompletionTitle
import com.hanclip.android.core.settings.SleepPreventionMode
import com.hanclip.android.core.theme.HanClipPalette
import com.hanclip.android.core.theme.HanClipThemeMode
import com.hanclip.android.core.theme.HanClipThemeStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@Composable
fun HomeRoute(
    exportedMovieSummaries: List<ExportedMovieSummary>,
    recentlySavedMovieUriString: String?,
    hasDraftProject: Boolean,
    editableProjectSummaries: List<DraftProjectSummary>,
    sharedInboxCount: Int,
    sleepPreventionMode: SleepPreventionMode,
    onStartPreset: (MoviePreset) -> Unit,
    onOpenProject: () -> Unit,
    onOpenEditableProject: (DraftProjectSummary) -> Unit,
    onRemoveEditableProject: (DraftProjectSummary) -> Unit,
    onToggleEditableProjectPin: (DraftProjectSummary) -> Boolean,
    onUpdateEditableProjectMemo: (DraftProjectSummary, String) -> Unit,
    onOpenExportedMovie: (ExportedMovieSummary) -> Unit,
    onRemoveExportedMovie: (ExportedMovieSummary) -> Unit,
    onToggleExportedMoviePin: (ExportedMovieSummary) -> Boolean,
    onUpdateExportedMovieMemo: (ExportedMovieSummary, String) -> Unit,
    onSleepPreventionModeChange: (SleepPreventionMode) -> Unit
) {
    val context = LocalContext.current
    var themeMode by remember {
        mutableStateOf(HanClipThemeStore.load(context))
    }
    var showThemeSelection by remember { mutableStateOf(false) }
    var showSettingsInfo by remember { mutableStateOf(false) }
    val palette = themeMode.palette
    var removalCandidate by remember { mutableStateOf<ExportedMovieSummary?>(null) }
    var memoCandidate by remember { mutableStateOf<ExportedMovieSummary?>(null) }
    var editableRemovalCandidate by remember { mutableStateOf<DraftProjectSummary?>(null) }
    var editableMemoCandidate by remember { mutableStateOf<DraftProjectSummary?>(null) }
    var memoText by remember { mutableStateOf("") }
    var showPinLimitAlert by remember { mutableStateOf(false) }
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .background(
                Brush.verticalGradient(
                    listOf(
                        Color(0xFFF9FCFB),
                        palette.panel,
                        palette.secondary.copy(alpha = 0.10f)
                    )
                )
            )
            .padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item(key = "home-header") {
            Spacer(Modifier.height(10.dp))
            HomeHeader(
                palette = palette,
                onOpenTheme = { showThemeSelection = true },
                onQuickAdd = { onStartPreset(MoviePreset.NewMovie) }
            )
            Spacer(Modifier.height(8.dp))
        }
        if (sharedInboxCount > 0) {
            item(key = "shared-inbox") {
                SharedInboxBanner(sharedInboxCount, palette)
                Spacer(Modifier.height(8.dp))
            }
        }
        item(key = "preset-grid") {
            PresetGrid(onStartPreset, palette)
            Spacer(Modifier.height(8.dp))
        }
        savedProjectItems(
            summaries = exportedMovieSummaries,
            recentlySavedMovieUriString = recentlySavedMovieUriString,
            hasDraftProject = hasDraftProject,
            editableProjectSummaries = editableProjectSummaries,
            onOpenProject = onOpenProject,
            onOpenEditableProject = onOpenEditableProject,
            onRemoveEditableProject = { editableRemovalCandidate = it },
            onToggleEditableProjectPin = { summary ->
                if (!onToggleEditableProjectPin(summary)) showPinLimitAlert = true
            },
            onEditEditableProjectMemo = {
                editableMemoCandidate = it
                memoText = it.memo
            },
            onOpenExportedMovie = onOpenExportedMovie,
            onRemoveExportedMovie = { removalCandidate = it },
            onToggleExportedMoviePin = { summary ->
                if (!onToggleExportedMoviePin(summary)) {
                    showPinLimitAlert = true
                }
            },
            onEditExportedMovieMemo = {
                memoCandidate = it
                memoText = it.memo
            }
        )
        item(key = "home-info") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center
            ) {
                Surface(
                    modifier = Modifier
                        .size(46.dp)
                        .clickable { showSettingsInfo = true },
                    shape = CircleShape,
                    color = palette.secondary.copy(alpha = 0.18f),
                    border = BorderStroke(1.dp, palette.secondary.copy(alpha = 0.34f))
                ) {
                    Icon(
                        Icons.Outlined.Info,
                        contentDescription = "설정과 기능 안내",
                        tint = palette.primary,
                        modifier = Modifier.padding(11.dp)
                    )
                }
            }
        }
        item(key = "home-bottom-space") {
            Spacer(Modifier.height(36.dp))
        }
    }
    if (showThemeSelection) {
        ThemeSelectionDialog(
            selectedMode = themeMode,
            onSelect = { mode ->
                themeMode = mode
                HanClipThemeStore.save(context, mode)
            },
            onDismiss = { showThemeSelection = false }
        )
    }
    if (showSettingsInfo) {
        SettingsInfoDialog(
            palette = palette,
            sleepPreventionMode = sleepPreventionMode,
            onCycleSleepPrevention = {
                onSleepPreventionModeChange(sleepPreventionMode.next())
            },
            onDismiss = { showSettingsInfo = false }
        )
    }
    removalCandidate?.let { summary ->
        AlertDialog(
            onDismissRequest = { removalCandidate = null },
            dismissButton = {
                OutlinedButton(
                    onClick = { removalCandidate = null },
                    border = BorderStroke(1.dp, HomeBorder),
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = Color.White,
                        contentColor = HomeText
                    )
                ) {
                    Text("취소")
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        removalCandidate = null
                        onRemoveExportedMovie(summary)
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFFE45D42),
                        contentColor = Color.White
                    )
                ) {
                    Text("목록에서 제거")
                }
            },
            shape = RoundedCornerShape(8.dp),
            containerColor = Color.White,
            titleContentColor = HomeText,
            textContentColor = HomeSubText,
            title = { Text("목록에서 제거") },
            text = {
                Text(
                    "${homeProjectDateText(summary.updatedAtMillis)} · ${savedMovieDetailText(summary)}\n\n" +
                        "HanClip 목록에서만 제거합니다. 기본 사진첩이나 파일에 저장된 완성본 MP4는 삭제하지 않습니다."
                )
            }
        )
    }
    memoCandidate?.let { summary ->
        AlertDialog(
            onDismissRequest = { memoCandidate = null },
            dismissButton = {
                OutlinedButton(
                    onClick = { memoCandidate = null },
                    border = BorderStroke(1.dp, HomeBorder),
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = Color.White,
                        contentColor = HomeText
                    )
                ) {
                    Text("취소")
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        onUpdateExportedMovieMemo(summary, memoText)
                        memoCandidate = null
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = palette.primary,
                        contentColor = Color.White
                    )
                ) {
                    Text("저장")
                }
            },
            shape = RoundedCornerShape(8.dp),
            containerColor = palette.panel,
            titleContentColor = palette.text,
            textContentColor = palette.subText,
            title = { Text("메모 편집") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        "저장된 완성본 목록에 표시할 짧은 메모를 남깁니다.",
                        color = palette.subText,
                        style = MaterialTheme.typography.bodySmall
                    )
                    TextField(
                        value = memoText,
                        onValueChange = { memoText = it.take(80) },
                        singleLine = true,
                        placeholder = { Text("메모 추가") }
                    )
                }
            }
        )
    }
    editableRemovalCandidate?.let { summary ->
        AlertDialog(
            onDismissRequest = { editableRemovalCandidate = null },
            dismissButton = {
                OutlinedButton(onClick = { editableRemovalCandidate = null }) { Text("취소") }
            },
            confirmButton = {
                Button(
                    onClick = {
                        onRemoveEditableProject(summary)
                        editableRemovalCandidate = null
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE45D42))
                ) { Text("프로젝트 제거") }
            },
            title = { Text("편집 프로젝트 제거") },
            text = { Text("목록과 자동 저장 정보에서 제거합니다. 갤러리에 저장된 MP4는 삭제하지 않습니다.") }
        )
    }
    editableMemoCandidate?.let { summary ->
        AlertDialog(
            onDismissRequest = { editableMemoCandidate = null },
            dismissButton = {
                OutlinedButton(onClick = { editableMemoCandidate = null }) { Text("취소") }
            },
            confirmButton = {
                Button(onClick = {
                    onUpdateEditableProjectMemo(summary, memoText)
                    editableMemoCandidate = null
                }) { Text("저장") }
            },
            title = { Text("프로젝트 메모") },
            text = {
                TextField(
                    value = memoText,
                    onValueChange = { memoText = it.take(80) },
                    singleLine = true,
                    placeholder = { Text("메모 추가") }
                )
            }
        )
    }
    if (showPinLimitAlert) {
        AlertDialog(
            onDismissRequest = { showPinLimitAlert = false },
            confirmButton = {
                Button(
                    onClick = { showPinLimitAlert = false },
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
            title = { Text("핀 고정 제한") },
            text = {
                Text("핀 고정은 최대 ${ExportHistoryStore.MaxPinnedItems}개까지 가능합니다. 다른 완성본을 해제한 뒤 다시 고정해 주세요.")
            }
        )
    }
}

data class DraftProjectSummary(
    val projectId: String,
    val preset: MoviePreset,
    val presetTitle: String,
    val clipCount: Int,
    val totalDurationSeconds: Double,
    val outputText: String,
    val savedAtMillis: Long,
    val isPinned: Boolean = false,
    val memo: String = "",
    val thumbnailUriString: String? = null,
    val thumbnailUriStrings: List<String> = emptyList(),
    val displayByteCount: Long = 0L
)

private val HomePrimary = Color(0xFF0B7A4E)
private val HomeText = Color(0xFF14221A)
private val HomeSubText = Color(0xFF46564C)
private val HomeBorder = Color(0xFFD4DDD7)
private const val HomeSavedMovieSlotCount = 10
private const val HomeThumbnailCacheSizeKb = 8 * 1024
private const val HomeStripCacheSizeKb = 8 * 1024
private const val HomeFrameLoadDelayMillis = 100L
private const val HomeFrameDecodeScale = 2
private const val HomeThumbnailMinLongEdgePx = 192
private const val HomeThumbnailMaxLongEdgePx = 640
private const val HomeStripMinLongEdgePx = 64
private const val HomeStripMaxLongEdgePx = 192

private object HomeMovieFrameCache {
    private val thumbnails = object : LruCache<String, Bitmap>(HomeThumbnailCacheSizeKb) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.sizeInKilobytes()
    }
    private val strips = object : LruCache<String, List<Bitmap>>(HomeStripCacheSizeKb) {
        override fun sizeOf(key: String, value: List<Bitmap>): Int {
            return value.fold(0L) { total, bitmap ->
                total + bitmap.sizeInKilobytes()
            }.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        }
    }

    fun thumbnail(key: String): Bitmap? = thumbnails.get(key)

    fun putThumbnail(key: String, bitmap: Bitmap?) {
        if (bitmap == null) return
        thumbnails.put(key, bitmap)
    }

    fun strip(key: String): List<Bitmap>? = strips.get(key)

    fun putStrip(key: String, bitmaps: List<Bitmap>) {
        if (bitmaps.isEmpty()) return
        strips.put(key, bitmaps)
    }
}

private fun Bitmap.sizeInKilobytes(): Int {
    return ((allocationByteCount.toLong() + 1023L) / 1024L)
        .coerceIn(1L, Int.MAX_VALUE.toLong())
        .toInt()
}

private fun MediaMetadataRetriever.loadScaledFrameAtTime(
    positionUs: Long,
    targetLongEdgePx: Int
): Bitmap? {
    val targetSize = videoFrameTargetSize(targetLongEdgePx)
    val decoded = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1 && targetSize != null) {
        getScaledFrameAtTime(
            positionUs,
            MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            targetSize.first,
            targetSize.second
        ) ?: getFrameAtTime(positionUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
    } else {
        getFrameAtTime(positionUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
    }
    return decoded?.scaledDownToLongEdge(targetLongEdgePx)
}

private fun MediaMetadataRetriever.videoFrameTargetSize(targetLongEdgePx: Int): Pair<Int, Int>? {
    val sourceWidth = extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
        ?.toIntOrNull()
        ?.takeIf { it > 0 }
        ?: return null
    val sourceHeight = extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
        ?.toIntOrNull()
        ?.takeIf { it > 0 }
        ?: return null
    val scale = min(
        1.0,
        targetLongEdgePx.toDouble() / max(sourceWidth, sourceHeight).toDouble()
    )
    return max(1, (sourceWidth * scale).roundToInt()) to
        max(1, (sourceHeight * scale).roundToInt())
}

private fun Bitmap.scaledDownToLongEdge(targetLongEdgePx: Int): Bitmap {
    val longEdge = max(width, height)
    if (longEdge <= targetLongEdgePx) return this
    val scale = targetLongEdgePx.toDouble() / longEdge.toDouble()
    val scaled = Bitmap.createScaledBitmap(
        this,
        max(1, (width * scale).roundToInt()),
        max(1, (height * scale).roundToInt()),
        true
    )
    if (scaled !== this) recycle()
    return scaled
}

@Composable
private fun ThemeSelectionDialog(
    selectedMode: HanClipThemeMode,
    onSelect: (HanClipThemeMode) -> Unit,
    onDismiss: () -> Unit
) {
    val selectedPalette = selectedMode.palette
    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = RoundedCornerShape(24.dp),
            color = selectedPalette.panel,
            border = BorderStroke(1.dp, selectedPalette.border),
            shadowElevation = 10.dp
        ) {
            Column(
                modifier = Modifier.padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    "테마 선택",
                    color = selectedPalette.text,
                    fontWeight = FontWeight.SemiBold,
                    style = MaterialTheme.typography.titleMedium
                )
                ThemePaletteSummary(selectedMode)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    HanClipThemeMode.visibleModes.forEach { mode ->
                        ThemeSelectionRow(
                            mode = mode,
                            selected = mode == selectedMode,
                            textColor = selectedPalette.text,
                            onClick = { onSelect(mode) }
                        )
                    }
                }
                Button(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = selectedPalette.primary,
                        contentColor = Color.White
                    )
                ) {
                    Text("확인", fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun ThemePaletteSummary(mode: HanClipThemeMode) {
    val palette = mode.palette
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    "색상 구성",
                    color = palette.subText,
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.labelSmall
                )
                Text(
                    mode.displayName,
                    color = palette.subText,
                    fontWeight = FontWeight.SemiBold,
                    style = MaterialTheme.typography.labelSmall
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ThemePaletteChip("주색", "선택/실행", palette.primary, palette)
                ThemePaletteChip("보조", "구조/그룹", palette.secondary, palette)
                ThemePaletteChip("배경", "화면", palette.chip, palette)
                ThemePaletteChip("글자", "정보", palette.text, palette)
            }
        }
    }
}

@Composable
private fun RowScope.ThemePaletteChip(
    title: String,
    description: String,
    color: Color,
    palette: HanClipPalette
) {
    Column(
        modifier = Modifier.weight(1f),
        verticalArrangement = Arrangement.spacedBy(5.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(28.dp)
                .clip(RoundedCornerShape(9.dp))
                .background(color)
        )
        Text(
            title,
            color = palette.text,
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1
        )
        Text(
            description,
            color = palette.subText,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun ThemeSelectionRow(
    mode: HanClipThemeMode,
    selected: Boolean,
    textColor: Color,
    onClick: () -> Unit
) {
    val palette = mode.palette
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 4.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Surface(
            modifier = Modifier.size(20.dp),
            shape = CircleShape,
            color = if (selected) palette.primary else Color.Transparent,
            border = BorderStroke(2.dp, palette.primary)
        ) {
            if (selected) {
                Box(
                    modifier = Modifier.padding(5.dp).background(Color.White, CircleShape)
                )
            }
        }
        Text(
            mode.displayName,
            modifier = Modifier.weight(1f),
            color = textColor,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        ThemeColorSwatch(palette.primary)
        ThemeColorSwatch(palette.secondary)
    }
}

@Composable
private fun ThemeColorSwatch(color: Color) {
    Box(
        modifier = Modifier
            .size(26.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(color)
    )
}

@Composable
private fun HomeHeader(
    palette: HanClipPalette,
    onOpenTheme: () -> Unit,
    onQuickAdd: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(modifier = Modifier.clickable(onClick = onOpenTheme)) {
            HanClipBrandCapsule()
        }
        Surface(
            modifier = Modifier
                .size(58.dp)
                .clickable(onClick = onQuickAdd),
            shape = CircleShape,
            color = palette.chip.copy(alpha = 0.62f),
            border = BorderStroke(1.dp, palette.secondary.copy(alpha = 0.28f))
        ) {
            Icon(
                imageVector = Icons.Outlined.AddPhotoAlternate,
                contentDescription = "미디어 추가",
                tint = Color(0xFF07323A),
                modifier = Modifier.padding(15.dp)
            )
        }
    }
}

@Composable
private fun HanClipBrandCapsule() {
    val brandColor = Color(0xFF07323A)
    Surface(
        shape = RoundedCornerShape(34.dp),
        color = Color(0xFFF7FAF8),
        border = BorderStroke(1.dp, Color(0xFFD6E1DE))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Image(
                painter = painterResource(R.drawable.logo_mark),
                contentDescription = null,
                modifier = Modifier.size(36.dp),
                contentScale = ContentScale.Fit,
                colorFilter = ColorFilter.tint(brandColor)
            )
            Text(
                text = "HanClip",
                style = MaterialTheme.typography.headlineLarge,
                fontFamily = FontFamily(Font(R.font.pretendard_bold)),
                fontWeight = FontWeight.Black,
                color = brandColor,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun SettingsInfoDialog(
    palette: HanClipPalette,
    sleepPreventionMode: SleepPreventionMode,
    onCycleSleepPrevention: () -> Unit,
    onDismiss: () -> Unit
) {
    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = RoundedCornerShape(24.dp),
            color = palette.panel,
            border = BorderStroke(1.dp, palette.border),
            shadowElevation = 10.dp
        ) {
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item {
                    Spacer(Modifier.height(18.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                "설정",
                                color = palette.text,
                                fontWeight = FontWeight.Bold,
                                style = MaterialTheme.typography.titleLarge
                            )
                            Text(
                                "HanClip 기능 안내와 작업 중 화면 유지",
                                color = palette.subText,
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Outlined.Settings, contentDescription = "설정 닫기", tint = palette.primary)
                        }
                    }
                }
                item {
                    SleepPreventionInfoCard(
                        palette = palette,
                        mode = sleepPreventionMode,
                        onCycle = onCycleSleepPrevention
                    )
                }
                importantInfoItems().forEach { item ->
                    item {
                        ImportantInfoRow(
                            title = item.first,
                            body = item.second,
                            palette = palette
                        )
                    }
                }
                item {
                    Button(
                        onClick = onDismiss,
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = palette.primary,
                            contentColor = Color.White
                        )
                    ) {
                        Text("확인", fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.height(18.dp))
                }
            }
        }
    }
}

@Composable
private fun SleepPreventionInfoCard(
    palette: HanClipPalette,
    mode: SleepPreventionMode,
    onCycle: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
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
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(Icons.Outlined.LightMode, contentDescription = null, tint = palette.primary)
                    Text("작업 중 화면 유지", color = palette.text, fontWeight = FontWeight.Bold)
                }
                AssistChip(
                    onClick = onCycle,
                    label = { Text(mode.title, fontWeight = FontWeight.SemiBold) },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = palette.panel,
                        labelColor = palette.primary
                    ),
                    border = BorderStroke(1.dp, palette.primary.copy(alpha = 0.45f))
                )
            }
            Text(
                mode.detail,
                color = palette.subText,
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

@Composable
private fun ImportantInfoRow(
    title: String,
    body: String,
    palette: HanClipPalette
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = palette.panel,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(title, color = palette.text, fontWeight = FontWeight.Bold)
            Text(
                body,
                color = palette.subText,
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

private fun importantInfoItems(): List<Pair<String, String>> = listOf(
    "첫 화면" to "앱 실행 후 내 사진과 영상을 한 번에 골라 HanClip 완성본을 시작하는 홈 화면입니다.",
    "고마운 분들" to "HanClip 제작과 테스트를 도와준 사용자와 골프 영상을 더 쉽게 만들고 싶은 사람들을 위한 감사 안내입니다.",
    "기능 안내" to "첫 화면의 설정 버튼에서 HanClip 기능 안내와 작업 중 화면 유지 상태를 확인합니다.",
    "완성본 프리셋" to "골프 완성본, 새 완성본, AiShot, 여행 완성본 중 원하는 흐름으로 사진과 영상을 골라 시작합니다.",
    "AiShot" to "필요한 순간을 자동으로 찾아 클립에 담는 카메라입니다. 감도, 샷 길이, 줌, 전면/후면 카메라 선택을 기억합니다.",
    "Ai 버전" to "현재 Ai 버전은 0.2.1입니다. 798 영상 보정 Ai 기준으로 소리의 피크와 이어지는 반응을 함께 참고합니다.",
    "클립 리스트" to "선택한 사진과 영상이 순서대로 표시됩니다. 썸네일, 시간, 단일 컷/자동 컷, 길이 조절 버튼으로 빠르게 편집합니다.",
    "단일 컷 / 자동 컷" to "영상을 하나의 구간으로 쓰거나, Ai가 찾은 타격점 후보 기준으로 여러 자클립으로 나눕니다.",
    "자막" to "영상 위에 문구, 폰트, 색상, 그림자, 위치를 설정하고 최종 MP4에 합성합니다.",
    "HanClip 로고" to "로고 워터마크의 표시 여부, 위치, 색상, 그림자 설정을 저장하고 최종 영상에 반영합니다.",
    "시사회" to "완성본 만들기 완료 후 전체 영상을 확인하고 폰 기본 사진첩의 HanClip 앨범 저장, 파일 저장, 공유를 실행합니다. 저장 중에는 화면을 유지합니다.",
    "음악 찾기" to "외부 무료 음악 사이트를 앱 안에서 열어 배경음악을 찾는 화면입니다. 즐겨찾기 추가/삭제와 첫 페이지 지정을 저장하며, 다운로드한 파일은 음악 설정의 내 음악 파일 선택으로 가져옵니다.",
    "외부 호출 주소" to "iOS와 같은 주소를 Android에서도 받습니다. Ai hanclip://aishot, 파일 hanclip://files, 달력 hanclip://calendar, 사진 hanclip://photo, 검색 hanclip://search, 첫 화면 hanclip://open 흐름을 빠르게 엽니다.",
    "샘플 음악" to "HanClip에 포함된 샘플 음악은 앱 기능 검증과 사용자의 영상 배경음악을 위해 제공됩니다."
)

@Composable
private fun SharedInboxBanner(
    sharedInboxCount: Int,
    palette: HanClipPalette
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = palette.chip,
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(1.dp, palette.border),
        tonalElevation = 0.dp
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector = Icons.Outlined.Collections,
                contentDescription = null,
                tint = palette.primary
            )
            Column(Modifier.weight(1f)) {
                Text(
                    text = "공유 파일 ${sharedInboxCount}개 대기",
                    fontWeight = FontWeight.SemiBold,
                    color = palette.text
                )
                Text(
                    text = "기본 사진첩이나 다른 앱에서 보낸 파일을 바로 완성본으로 엽니다.",
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.subText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Surface(
                shape = RoundedCornerShape(50),
                color = palette.panel,
                border = BorderStroke(1.dp, palette.border)
            ) {
                Text(
                    text = "연결됨",
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                    color = palette.primary,
                    fontWeight = FontWeight.SemiBold,
                    style = MaterialTheme.typography.labelMedium,
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
private fun PresetGrid(onStartPreset: (MoviePreset) -> Unit, palette: HanClipPalette) {
    val orderedPresets = listOf(
        MoviePreset.NewMovie,
        MoviePreset.AiShot,
        MoviePreset.Travel,
        MoviePreset.Golf
    )
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        HomeSectionTitle("영화 프리셋", Icons.Outlined.Collections, palette)
        orderedPresets.chunked(2).forEach { rowPresets ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                rowPresets.forEach { preset ->
                    PresetTile(
                        modifier = Modifier.weight(1f),
                        preset = preset,
                        icon = when (preset) {
                            MoviePreset.NewMovie -> Icons.Outlined.Movie
                            MoviePreset.AiShot -> null
                            MoviePreset.Travel -> Icons.Outlined.Flight
                            MoviePreset.Golf -> Icons.Outlined.SportsGolf
                        },
                        palette = palette,
                        onClick = { onStartPreset(preset) }
                    )
                }
                if (rowPresets.size == 1) {
                    Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun PresetTile(
    modifier: Modifier,
    preset: MoviePreset,
    icon: ImageVector?,
    palette: HanClipPalette,
    onClick: () -> Unit
) {
    Surface(
        modifier = modifier
            .height(132.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(10.dp),
        color = Color.Transparent,
        border = BorderStroke(1.dp, palette.secondary.copy(alpha = 0.32f)),
        shadowElevation = 1.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.linearGradient(
                        listOf(
                            palette.panel.copy(alpha = 0.98f),
                            palette.chip.copy(alpha = 0.72f),
                            palette.secondary.copy(alpha = 0.08f)
                        )
                    )
                )
                .padding(horizontal = 10.dp, vertical = 15.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(46.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(
                        Brush.linearGradient(
                            listOf(palette.primary, palette.secondary)
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                if (preset == MoviePreset.AiShot) {
                    Image(
                        painter = painterResource(R.drawable.aishot_icon),
                        contentDescription = null,
                        modifier = Modifier.size(29.dp)
                    )
                } else if (icon != null) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(23.dp)
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                text = preset.title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = palette.text,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = preset.detail,
                style = MaterialTheme.typography.bodySmall,
                color = palette.subText,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun HomeSectionTitle(
    title: String,
    icon: ImageVector,
    palette: HanClipPalette
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            modifier = Modifier.size(24.dp),
            shape = RoundedCornerShape(7.dp),
            color = palette.secondary.copy(alpha = 0.14f)
        ) {
            Icon(icon, contentDescription = null, tint = palette.secondary, modifier = Modifier.padding(5.dp))
        }
        Spacer(Modifier.size(7.dp))
        Text(title, color = palette.subText, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun PresetRecommendationBadge(palette: HanClipPalette) {
    Surface(
        shape = RoundedCornerShape(50),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.primary.copy(alpha = 0.26f))
    ) {
        Text(
            text = "대표",
            modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp),
            color = palette.primary,
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1
        )
    }
}

private fun LazyListScope.savedProjectItems(
    summaries: List<ExportedMovieSummary>,
    recentlySavedMovieUriString: String?,
    hasDraftProject: Boolean,
    editableProjectSummaries: List<DraftProjectSummary>,
    onOpenProject: () -> Unit,
    onOpenEditableProject: (DraftProjectSummary) -> Unit,
    onRemoveEditableProject: (DraftProjectSummary) -> Unit,
    onToggleEditableProjectPin: (DraftProjectSummary) -> Unit,
    onEditEditableProjectMemo: (DraftProjectSummary) -> Unit,
    onOpenExportedMovie: (ExportedMovieSummary) -> Unit,
    onRemoveExportedMovie: (ExportedMovieSummary) -> Unit,
    onToggleExportedMoviePin: (ExportedMovieSummary) -> Unit,
    onEditExportedMovieMemo: (ExportedMovieSummary) -> Unit
) {
    val aiShotProjects = editableProjectSummaries.filter { it.preset == MoviePreset.AiShot }
    val standardProjects = editableProjectSummaries.filterNot { it.preset == MoviePreset.AiShot }
    item(
        key = "saved-project-header",
        contentType = "saved-project-header"
    ) {
        SavedProjectHeader(
            hasDraftProject = hasDraftProject,
            onOpenProject = onOpenProject
        )
    }
    item(key = "aishot-category-header", contentType = "saved-category-header") {
        SavedProjectCategoryHeader(title = "AiShot", count = aiShotProjects.size, icon = null)
    }
    item(key = "aishot-project-grid", contentType = "aishot-project-grid") {
        AiShotProjectGrid(
            summaries = aiShotProjects,
            onOpenProject = onOpenEditableProject,
            onRemoveProject = onRemoveEditableProject,
            onTogglePin = onToggleEditableProjectPin,
            onEditMemo = onEditEditableProjectMemo
        )
    }
    item(key = "standard-category-header", contentType = "saved-category-header") {
        SavedProjectCategoryHeader(title = "일반 영화", count = standardProjects.size, icon = Icons.Outlined.Movie)
    }
    items(
        items = standardProjects,
        key = { "editable-project:${it.projectId}" },
        contentType = { "editable-project" }
    ) { project ->
        DraftProjectRow(
            summary = project,
            onClick = { onOpenEditableProject(project) },
            onRemove = { onRemoveEditableProject(project) },
            onTogglePin = { onToggleEditableProjectPin(project) },
            onEditMemo = { onEditEditableProjectMemo(project) }
        )
    }
    items(
        count = (HomeSavedMovieSlotCount - 2 - standardProjects.size).coerceAtLeast(0),
        key = { index -> "empty-standard-project:$index" },
        contentType = { "empty-standard-project" }
    ) {
        EmptyStandardMovieRow()
    }
    if (summaries.isNotEmpty()) {
        item(key = "completed-mp4-header", contentType = "saved-category-header") {
            SavedProjectCategoryHeader(title = "완성 MP4", count = summaries.size, icon = Icons.Outlined.Movie)
        }
        items(
            items = summaries,
            key = { summary -> "saved-movie:${summary.uriString}" },
            contentType = { "saved-movie" }
        ) { summary ->
            SavedProjectRow(
                summary = summary,
                isRecentlySaved = summary.uriString == recentlySavedMovieUriString,
                onClick = { onOpenExportedMovie(summary) },
                onRemove = { onRemoveExportedMovie(summary) },
                onTogglePin = { onToggleExportedMoviePin(summary) },
                onEditMemo = { onEditExportedMovieMemo(summary) }
            )
        }
    }
}

@Composable
private fun SavedProjectHeader(
    hasDraftProject: Boolean,
    onOpenProject: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Spacer(Modifier.weight(1f))
        Surface(
            modifier = Modifier.size(24.dp),
            shape = RoundedCornerShape(7.dp),
            color = Color(0xFFDCEDE9)
        ) {
            Icon(Icons.Outlined.FolderOpen, contentDescription = null, tint = HomeSubText, modifier = Modifier.padding(5.dp))
        }
        Spacer(Modifier.size(7.dp))
        Text("영화 목록", color = HomeSubText, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun AiShotMovieGrid(
    summaries: List<ExportedMovieSummary>,
    recentlySavedMovieUriString: String?,
    onOpenExportedMovie: (ExportedMovieSummary) -> Unit,
    onRemoveExportedMovie: (ExportedMovieSummary) -> Unit,
    onToggleExportedMoviePin: (ExportedMovieSummary) -> Unit,
    onEditExportedMovieMemo: (ExportedMovieSummary) -> Unit
) {
    val cells = summaries.take(2).map { it as ExportedMovieSummary? } +
        List((2 - summaries.size).coerceAtLeast(0)) { null }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        cells.forEach { summary ->
            if (summary == null) {
                EmptyAiShotMovieCard(Modifier.weight(1f))
            } else {
                AiShotMovieCard(
                    summary = summary,
                    isRecentlySaved = summary.uriString == recentlySavedMovieUriString,
                    modifier = Modifier.weight(1f),
                    onClick = { onOpenExportedMovie(summary) },
                    onRemove = { onRemoveExportedMovie(summary) },
                    onTogglePin = { onToggleExportedMoviePin(summary) },
                    onEditMemo = { onEditExportedMovieMemo(summary) }
                )
            }
        }
    }
}

@Composable
private fun AiShotProjectGrid(
    summaries: List<DraftProjectSummary>,
    onOpenProject: (DraftProjectSummary) -> Unit,
    onRemoveProject: (DraftProjectSummary) -> Unit,
    onTogglePin: (DraftProjectSummary) -> Unit,
    onEditMemo: (DraftProjectSummary) -> Unit
) {
    val cells = summaries.take(2).map { it as DraftProjectSummary? } +
        List((2 - summaries.size).coerceAtLeast(0)) { null }
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        cells.forEach { summary ->
            if (summary == null) {
                EmptyAiShotMovieCard(Modifier.weight(1f))
            } else {
                AiShotProjectCard(
                    summary = summary,
                    modifier = Modifier.weight(1f),
                    onClick = { onOpenProject(summary) },
                    onRemove = { onRemoveProject(summary) },
                    onTogglePin = { onTogglePin(summary) },
                    onEditMemo = { onEditMemo(summary) }
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun AiShotProjectCard(
    summary: DraftProjectSummary,
    modifier: Modifier,
    onClick: () -> Unit,
    onRemove: () -> Unit,
    onTogglePin: () -> Unit,
    onEditMemo: () -> Unit
) {
    var showActions by remember { mutableStateOf(false) }
    Surface(
        modifier = modifier
            .height(88.dp)
            .combinedClickable(onClick = onClick, onLongClick = { showActions = true }),
        shape = RoundedCornerShape(16.dp),
        color = Color.White,
        border = BorderStroke(1.dp, HomeBorder)
    ) {
        Box {
            Row(
                modifier = Modifier.padding(9.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                EditableProjectThumbnail(summary, Modifier.size(52.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        homeAiShotDateText(summary.savedAtMillis),
                        color = HomeText,
                        fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.labelMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        editableProjectDetailText(summary, includeByteCount = false),
                        color = HomeSubText,
                        style = MaterialTheme.typography.labelSmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    EditableProjectThumbnailStrip(summary, maxFrames = 2, frameWidth = 24, frameHeight = 20)
                }
            }
            DropdownMenu(expanded = showActions, onDismissRequest = { showActions = false }) {
                DropdownMenuItem(
                    text = { Text(if (summary.memo.isBlank()) "메모 추가" else "메모 편집") },
                    onClick = { showActions = false; onEditMemo() },
                    leadingIcon = { Icon(Icons.Outlined.Edit, contentDescription = null) }
                )
                DropdownMenuItem(
                    text = { Text(if (summary.isPinned) "핀 해제" else "핀 고정") },
                    onClick = { showActions = false; onTogglePin() },
                    leadingIcon = { Icon(Icons.Outlined.PushPin, contentDescription = null) }
                )
                DropdownMenuItem(
                    text = { Text("프로젝트 삭제") },
                    onClick = { showActions = false; onRemove() },
                    leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null) }
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun AiShotMovieCard(
    summary: ExportedMovieSummary,
    isRecentlySaved: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    onRemove: () -> Unit,
    onTogglePin: () -> Unit,
    onEditMemo: () -> Unit
) {
    var showActions by remember { mutableStateOf(false) }
    Surface(
        modifier = modifier
            .height(88.dp)
            .combinedClickable(
                onClick = onClick,
                onLongClick = { showActions = true }
            ),
        shape = RoundedCornerShape(16.dp),
        color = Color.White,
        border = BorderStroke(
            width = if (isRecentlySaved) 1.5.dp else 1.dp,
            color = if (isRecentlySaved) HomePrimary.copy(alpha = 0.52f) else HomeBorder
        )
    ) {
        Box {
            Row(
                modifier = Modifier.padding(9.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ExportedMovieThumbnail(
                    summary = summary,
                    displayLongEdgeDp = 64,
                    modifier = Modifier.size(64.dp)
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        homeAiShotDateText(summary.updatedAtMillis),
                        modifier = Modifier.weight(1f, fill = false),
                        color = HomeText,
                        fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.labelMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (isRecentlySaved) {
                        NewSavedMovieBadge()
                    }
                    if (summary.isPinned) {
                        PinnedSavedMovieBadge()
                    }
                }
                Text(
                    compactSavedMovieDetailText(summary, includeByteCount = false),
                    color = HomeSubText,
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                ExportedMovieThumbnailStrip(
                    summary = summary,
                    maxFrames = 2,
                    frameWidth = 24,
                    frameHeight = 20,
                    rowHeight = 20
                )
                }
            }
            DropdownMenu(expanded = showActions, onDismissRequest = { showActions = false }) {
                DropdownMenuItem(
                    text = { Text(if (summary.memo.isBlank()) "메모 추가" else "메모 편집") },
                    onClick = { showActions = false; onEditMemo() },
                    leadingIcon = { Icon(Icons.Outlined.Edit, contentDescription = null) }
                )
                DropdownMenuItem(
                    text = { Text(if (summary.isPinned) "핀 해제" else "핀 고정") },
                    onClick = { showActions = false; onTogglePin() },
                    leadingIcon = { Icon(Icons.Outlined.PushPin, contentDescription = null) }
                )
                DropdownMenuItem(
                    text = { Text("목록에서 제거") },
                    onClick = { showActions = false; onRemove() },
                    leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null) }
                )
            }
        }
    }
}

@Composable
private fun EmptyAiShotMovieCard(modifier: Modifier = Modifier) {
    val placeholder = HomePrimary.copy(alpha = 0.10f)
    Surface(
        modifier = modifier.height(88.dp),
        shape = RoundedCornerShape(16.dp),
        color = Color.White.copy(alpha = 0.72f),
        border = BorderStroke(1.dp, HomeBorder.copy(alpha = 0.72f))
    ) {
        Row(
            modifier = Modifier.padding(9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(52.dp)
                    .clip(RoundedCornerShape(11.dp))
                    .background(placeholder)
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(0.76f)
                        .height(10.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(placeholder)
                )
                Box(
                    modifier = Modifier
                        .fillMaxWidth(0.56f)
                        .height(8.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(HomePrimary.copy(alpha = 0.07f))
                )
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    repeat(3) {
                        Box(
                            modifier = Modifier
                                .size(width = 20.dp, height = 18.dp)
                                .clip(RoundedCornerShape(4.dp))
                                .background(HomePrimary.copy(alpha = 0.06f))
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MiniAiShotAction(
    onClick: () -> Unit,
    icon: @Composable () -> Unit
) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(26.dp)
    ) {
        Box(
            modifier = Modifier
                .size(22.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(Color(0xFFEAF5F0)),
            contentAlignment = Alignment.Center
        ) {
            icon()
        }
    }
}

@Composable
private fun SavedProjectCategoryHeader(
    title: String,
    count: Int,
    icon: ImageVector?
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Surface(
            modifier = Modifier.size(26.dp),
            shape = RoundedCornerShape(7.dp),
            color = if (title == "AiShot") Color(0xFFE6F3EF) else HomePrimary,
            border = if (title == "AiShot") BorderStroke(1.dp, HomeBorder) else null
        ) {
            if (title == "AiShot") {
                Image(
                    painter = painterResource(R.drawable.aishot_icon),
                    contentDescription = null,
                    modifier = Modifier.padding(5.dp)
                )
            } else if (icon != null) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.padding(6.dp)
                )
            }
        }
        Text(
            text = title,
            color = HomeText,
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.titleMedium
        )
        Surface(
            shape = CircleShape,
            color = Color(0xFFEAF5F0),
            border = BorderStroke(1.dp, HomeBorder)
        ) {
            Text(
                text = "$count",
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                color = HomePrimary,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.labelMedium
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DraftProjectRow(
    summary: DraftProjectSummary,
    onClick: () -> Unit,
    onRemove: () -> Unit,
    onTogglePin: () -> Unit,
    onEditMemo: () -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = onRemove),
        shape = RoundedCornerShape(16.dp),
        color = Color.White,
        border = BorderStroke(1.dp, HomeBorder)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(9.dp)
        ) {
            EditableProjectThumbnail(summary, Modifier.size(56.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    homeProjectDateText(summary.savedAtMillis),
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.titleMedium,
                    color = HomeText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    editableProjectDetailText(summary, includeByteCount = true),
                    style = MaterialTheme.typography.bodySmall,
                    color = HomeSubText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                EditableProjectThumbnailStrip(summary, maxFrames = 8, frameWidth = 18, frameHeight = 18)
            }
            CompactSavedMovieIconButton(
                onClick = onEditMemo
            ) {
                Icon(
                    Icons.Outlined.Edit,
                    contentDescription = if (summary.memo.isBlank()) "메모 추가" else "메모 편집",
                    tint = HomeSubText,
                    modifier = Modifier.size(18.dp)
                )
            }
            CompactSavedMovieIconButton(
                onClick = onTogglePin
            ) {
                Icon(
                    Icons.Outlined.PushPin,
                    contentDescription = if (summary.isPinned) "핀 해제" else "핀 고정",
                    tint = if (summary.isPinned) HomePrimary else HomeSubText,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
    }
}

@Composable
private fun EditableProjectThumbnail(
    summary: DraftProjectSummary,
    modifier: Modifier = Modifier.size(54.dp)
) {
    val cacheKey = remember(summary.projectId, summary.savedAtMillis, summary.thumbnailUriString) {
        "editable|${summary.projectId}|${summary.savedAtMillis}|${summary.thumbnailUriString}"
    }
    var bitmap by remember(cacheKey) { mutableStateOf(HomeMovieFrameCache.thumbnail(cacheKey)) }
    LaunchedEffect(cacheKey) {
        if (bitmap != null) return@LaunchedEffect
        bitmap = withContext(Dispatchers.IO) {
            summary.thumbnailUriString
                ?.let(Uri::parse)
                ?.path
                ?.let(BitmapFactory::decodeFile)
                ?.scaledDownToLongEdge(160)
        }.also { HomeMovieFrameCache.putThumbnail(cacheKey, it) }
    }
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(7.dp))
            .background(Color.White),
        contentAlignment = Alignment.Center
    ) {
        bitmap?.let {
            Image(
                bitmap = it.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
        } ?: Icon(
            imageVector = Icons.Outlined.Movie,
            contentDescription = null,
            tint = HomePrimary
        )
    }
}

@Composable
private fun EditableProjectThumbnailStrip(
    summary: DraftProjectSummary,
    maxFrames: Int,
    frameWidth: Int,
    frameHeight: Int
) {
    val frameUris = summary.thumbnailUriStrings.drop(1).take(maxFrames)
    if (frameUris.isEmpty()) return
    Row(
        modifier = Modifier.height(frameHeight.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        frameUris.forEach { uriString ->
            EditableProjectFrame(uriString, Modifier.size(frameWidth.dp, frameHeight.dp))
        }
        if (summary.clipCount > frameUris.size + 1) {
            Text(
                "·",
                color = HomeSubText,
                fontWeight = FontWeight.Black,
                style = MaterialTheme.typography.labelLarge
            )
        }
    }
}

@Composable
private fun EditableProjectFrame(uriString: String, modifier: Modifier) {
    val cacheKey = remember(uriString) { "editable-frame|$uriString" }
    var bitmap by remember(cacheKey) { mutableStateOf(HomeMovieFrameCache.thumbnail(cacheKey)) }
    LaunchedEffect(cacheKey) {
        if (bitmap != null) return@LaunchedEffect
        bitmap = withContext(Dispatchers.IO) {
            Uri.parse(uriString).path?.let(BitmapFactory::decodeFile)?.scaledDownToLongEdge(96)
        }.also { HomeMovieFrameCache.putThumbnail(cacheKey, it) }
    }
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(4.dp))
            .background(HomePrimary.copy(alpha = 0.10f))
    ) {
        bitmap?.let {
            Image(
                bitmap = it.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
        }
    }
}

@Composable
private fun DraftInfoPill(text: String) {
    Surface(
        shape = RoundedCornerShape(50),
        color = Color.White,
        border = BorderStroke(1.dp, HomeBorder)
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            color = HomePrimary,
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

private fun draftSummaryText(summary: DraftProjectSummary): String {
    return "${homeProjectDateText(summary.savedAtMillis)} 저장 · 완성본 만들기 전 상태 보관 · 사진/영상, 순서, 자막, 음악 · ${summary.outputText}"
}

private fun editableProjectDetailText(
    summary: DraftProjectSummary,
    includeByteCount: Boolean
): String {
    return buildList {
        add("클립 ${summary.clipCount}개")
        add(movieDurationText(summary.totalDurationSeconds))
        if (includeByteCount && summary.displayByteCount > 0L) add(fileSizeText(summary.displayByteCount))
    }.joinToString(" · ")
}

@Composable
private fun EmptySavedProjectRow() {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = Color.White,
        border = BorderStroke(1.dp, HomeBorder)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector = Icons.Outlined.FolderOpen,
                contentDescription = null,
                tint = HomeSubText
            )
            Column(Modifier.weight(1f)) {
                Text("최근 항목 없음", fontWeight = FontWeight.SemiBold, color = HomeText)
                Text(
                    "사진과 영상을 골라 완성본을 만들면 HanClip 앨범 저장 이력이 여기에 표시됩니다.",
                    style = MaterialTheme.typography.bodySmall,
                    color = HomeSubText
                )
            }
        }
    }
}

@Composable
private fun EmptyStandardMovieRow() {
    val placeholder = HomePrimary.copy(alpha = 0.10f)
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = Color.White.copy(alpha = 0.72f),
        border = BorderStroke(1.dp, HomeBorder.copy(alpha = 0.72f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(RoundedCornerShape(11.dp))
                    .background(placeholder)
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(7.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(width = 112.dp, height = 13.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(placeholder)
                )
                Box(
                    modifier = Modifier
                        .size(width = 154.dp, height = 10.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(HomePrimary.copy(alpha = 0.08f))
                )
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    repeat(3) {
                        Box(
                            modifier = Modifier
                                .size(width = 18.dp, height = 18.dp)
                                .clip(RoundedCornerShape(3.dp))
                                .background(HomePrimary.copy(alpha = 0.07f))
                        )
                    }
                }
            }
            Icon(
                imageVector = Icons.Outlined.Edit,
                contentDescription = null,
                tint = HomeSubText.copy(alpha = 0.28f),
                modifier = Modifier.size(22.dp)
            )
            Icon(
                imageVector = Icons.Outlined.PushPin,
                contentDescription = null,
                tint = HomeSubText.copy(alpha = 0.26f),
                modifier = Modifier.size(22.dp)
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SavedProjectRow(
    summary: ExportedMovieSummary,
    isRecentlySaved: Boolean,
    onClick: () -> Unit,
    onRemove: () -> Unit,
    onTogglePin: () -> Unit,
    onEditMemo: () -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = onRemove),
        shape = RoundedCornerShape(8.dp),
        color = Color.White,
        border = BorderStroke(
            width = if (isRecentlySaved) 1.5.dp else 1.dp,
            color = if (isRecentlySaved) HomePrimary.copy(alpha = 0.52f) else HomeBorder
        )
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ExportedMovieThumbnail(
                summary = summary,
                displayLongEdgeDp = 64,
                modifier = Modifier.size(64.dp)
            )
            Column(Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        homeProjectDateText(summary.updatedAtMillis),
                        modifier = Modifier.weight(1f, fill = false),
                        fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.titleMedium,
                        color = HomeText,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (isRecentlySaved) {
                        NewSavedMovieBadge()
                    }
                    if (summary.isPinned) {
                        PinnedSavedMovieBadge()
                    }
                }
                Text(
                    compactSavedMovieDetailText(summary, includeByteCount = true),
                    style = MaterialTheme.typography.bodySmall,
                    color = HomeSubText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                ExportedMovieThumbnailStrip(
                    summary = summary,
                    maxFrames = 8,
                    frameWidth = 18,
                    frameHeight = 18,
                    rowHeight = 19
                )
                if (summary.memo.isNotBlank()) {
                    Text(
                        summary.memo,
                        style = MaterialTheme.typography.bodySmall,
                        color = HomePrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                } else if (isRecentlySaved) {
                    Text(
                        "방금 만든 완성본 · HanClip 앨범 저장 · 탭해서 시사회 열기",
                        style = MaterialTheme.typography.bodySmall,
                        color = HomePrimary,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            CompactSavedMovieIconButton(onClick = onEditMemo) {
                Icon(
                    imageVector = Icons.Outlined.Edit,
                    contentDescription = if (summary.memo.isBlank()) "메모 추가" else "메모 편집",
                    tint = if (summary.memo.isBlank()) HomeSubText else HomePrimary,
                    modifier = Modifier.size(19.dp)
                )
            }
            CompactSavedMovieIconButton(onClick = onTogglePin) {
                Icon(
                    imageVector = Icons.Outlined.PushPin,
                    contentDescription = if (summary.isPinned) "핀 해제" else "핀 고정",
                    tint = if (summary.isPinned) HomePrimary else HomeSubText,
                    modifier = Modifier.size(19.dp)
                )
            }
        }
    }
}

@Composable
private fun CompactSavedMovieIconButton(
    onClick: () -> Unit,
    icon: @Composable () -> Unit
) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(32.dp)
    ) {
        icon()
    }
}

@Composable
private fun NewSavedMovieBadge() {
    Surface(
        shape = RoundedCornerShape(50),
        color = Color(0xFFEB3B45).copy(alpha = 0.13f),
        border = BorderStroke(1.dp, Color(0xFFEB3B45).copy(alpha = 0.32f))
    ) {
        Text(
            text = "방금 완성",
            modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp),
            color = Color(0xFFC8212C),
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1
        )
    }
}

@Composable
private fun PinnedSavedMovieBadge() {
    Surface(
        shape = RoundedCornerShape(50),
        color = HomePrimary.copy(alpha = 0.12f),
        border = BorderStroke(1.dp, HomePrimary.copy(alpha = 0.28f))
    ) {
        Text(
            text = "고정",
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
            color = HomePrimary,
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1
        )
    }
}

@Composable
private fun ExportedMovieThumbnail(
    summary: ExportedMovieSummary,
    displayLongEdgeDp: Int = 88,
    modifier: Modifier = Modifier.size(width = 88.dp, height = 54.dp)
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    val targetLongEdgePx = remember(density.density, displayLongEdgeDp) {
        with(density) { displayLongEdgeDp.dp.roundToPx() }
            .times(HomeFrameDecodeScale)
            .coerceIn(HomeThumbnailMinLongEdgePx, HomeThumbnailMaxLongEdgePx)
    }
    val cacheKey = remember(summary.uriString, summary.updatedAtMillis, targetLongEdgePx) {
        "thumbnail|${summary.uriString}|${summary.updatedAtMillis}|$targetLongEdgePx"
    }
    var bitmap by remember(cacheKey) {
        mutableStateOf(HomeMovieFrameCache.thumbnail(cacheKey))
    }
    LaunchedEffect(cacheKey) {
        HomeMovieFrameCache.thumbnail(cacheKey)?.let { cached ->
            bitmap = cached
            return@LaunchedEffect
        }
        delay(HomeFrameLoadDelayMillis)
        HomeMovieFrameCache.thumbnail(cacheKey)?.let { cached ->
            bitmap = cached
            return@LaunchedEffect
        }
        bitmap = withContext(Dispatchers.IO) {
            runCatching {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(context, Uri.parse(summary.uriString))
                    retriever.loadScaledFrameAtTime(
                        positionUs = 0L,
                        targetLongEdgePx = targetLongEdgePx
                    )
                } finally {
                    retriever.release()
                }
            }.getOrNull()
        }.also { loaded ->
            HomeMovieFrameCache.putThumbnail(cacheKey, loaded)
        }
    }
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(Color(0xFFEAF5F0)),
        contentAlignment = Alignment.Center
    ) {
        bitmap?.let {
            Image(
                bitmap = it.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
        } ?: Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Icon(
                imageVector = Icons.Outlined.Movie,
                contentDescription = null,
                tint = HomePrimary,
                modifier = Modifier.size(20.dp)
            )
            Text(
                "HanClip",
                color = HomePrimary,
                fontWeight = FontWeight.Black,
                style = MaterialTheme.typography.labelSmall,
                maxLines = 1
            )
        }
    }
}

@Composable
private fun ExportedMovieThumbnailStrip(
    summary: ExportedMovieSummary,
    maxFrames: Int = 4,
    frameWidth: Int = 20,
    frameHeight: Int = 20,
    rowHeight: Int = 22
) {
    if (summary.clipCount <= 1) return
    val context = LocalContext.current
    val density = LocalDensity.current
    val targetLongEdgePx = remember(density.density, frameWidth, frameHeight) {
        with(density) { max(frameWidth, frameHeight).dp.roundToPx() }
            .times(HomeFrameDecodeScale)
            .coerceIn(HomeStripMinLongEdgePx, HomeStripMaxLongEdgePx)
    }
    val cacheKey = remember(
        summary.uriString,
        summary.updatedAtMillis,
        summary.clipCount,
        summary.totalDurationSeconds,
        maxFrames,
        targetLongEdgePx
    ) {
        "strip|${summary.uriString}|${summary.updatedAtMillis}|${summary.clipCount}|" +
            "${summary.totalDurationSeconds}|$maxFrames|$targetLongEdgePx"
    }
    var bitmaps by remember(cacheKey) {
        mutableStateOf(HomeMovieFrameCache.strip(cacheKey).orEmpty())
    }
    LaunchedEffect(cacheKey) {
        HomeMovieFrameCache.strip(cacheKey)?.let { cached ->
            bitmaps = cached
            return@LaunchedEffect
        }
        delay(HomeFrameLoadDelayMillis)
        HomeMovieFrameCache.strip(cacheKey)?.let { cached ->
            bitmaps = cached
            return@LaunchedEffect
        }
        bitmaps = withContext(Dispatchers.IO) {
            runCatching {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(context, Uri.parse(summary.uriString))
                    val count = summary.clipCount.coerceAtMost(maxFrames)
                    val safeDurationUs = (summary.totalDurationSeconds.coerceAtLeast(0.1) * 1_000_000L).toLong()
                    List(count) { index ->
                        val positionUs = (((index + 0.5) / count) * safeDurationUs).toLong()
                        retriever.loadScaledFrameAtTime(
                            positionUs = positionUs,
                            targetLongEdgePx = targetLongEdgePx
                        )
                    }.filterNotNull()
                } finally {
                    retriever.release()
                }
            }.getOrDefault(emptyList())
        }.also { loaded ->
            HomeMovieFrameCache.putStrip(cacheKey, loaded)
        }
    }
    if (bitmaps.isEmpty()) return
    Row(
        modifier = Modifier.height(rowHeight.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        bitmaps.forEach { bitmap ->
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier
                    .size(width = frameWidth.dp, height = frameHeight.dp)
                    .clip(RoundedCornerShape(4.dp)),
                contentScale = ContentScale.Crop
            )
        }
        if (summary.clipCount > bitmaps.size) {
            Text(
                "....",
                color = HomeSubText.copy(alpha = 0.62f),
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1
            )
        }
    }
}

private fun homeProjectDateText(updatedAtMillis: Long): String {
    if (updatedAtMillis <= 0L) return "방금"
    return SimpleDateFormat("M월 d일 a h:mm", Locale.KOREAN).format(Date(updatedAtMillis))
}

private fun homeAiShotDateText(updatedAtMillis: Long): String {
    if (updatedAtMillis <= 0L) return "방금"
    return SimpleDateFormat("M/d a h:mm", Locale.KOREAN).format(Date(updatedAtMillis))
}

private fun compactSavedMovieDetailText(
    summary: ExportedMovieSummary,
    includeByteCount: Boolean
): String {
    return buildList {
        add("클립 ${summary.clipCount}개")
        add(movieDurationText(summary.totalDurationSeconds))
        if (includeByteCount && summary.byteCount > 0L) {
            add(fileSizeText(summary.byteCount))
        }
    }.joinToString(" · ")
}

private fun fileSizeText(byteCount: Long): String {
    val megabytes = byteCount.coerceAtLeast(0L) / (1024.0 * 1024.0)
    return when {
        megabytes < 0.1 -> "${(byteCount / 1024.0).coerceAtLeast(0.0).roundToInt()} KB"
        megabytes < 10.0 -> "%.1f MB".format(megabytes)
        else -> "%.0f MB".format(megabytes)
    }
}

private fun savedMovieDetailText(summary: ExportedMovieSummary): String {
    val parts = buildList {
        hanClipCompletionTitle(summary.title)
            .takeIf { it.isNotBlank() }
            ?.let(::add)
        add("${summary.clipCount}개")
        add(movieDurationText(summary.totalDurationSeconds))
        summary.outputAspectRatio?.let { add(it.title) }
        summary.outputQualityPreset?.let { add(it.chipTitle) }
        add("HanClip MP4")
        if (summary.hasBackgroundMusic == true) add("음악")
        overlayDetailParts(summary).forEach(::add)
    }
    return parts.joinToString(" · ")
}

private fun overlayDetailParts(summary: ExportedMovieSummary): List<String> {
    val hasText = summary.hasTextOverlay
    val hasLogo = summary.hasLogoOverlay
    return when {
        hasText == true && hasLogo == true -> listOf("자막", "로고")
        hasText == true -> listOf("자막")
        hasLogo == true -> listOf("로고")
        hasText == null && hasLogo == null && summary.hasWatermark == true -> listOf("자막/로고")
        else -> emptyList()
    }
}

private fun movieDurationText(durationSeconds: Double): String {
    val totalSeconds = durationSeconds.coerceAtLeast(0.0)
    val minutes = (totalSeconds / 60).toInt()
    val seconds = totalSeconds - minutes * 60
    return if (minutes > 0) {
        "%d분 %.1f초".format(minutes, seconds)
    } else {
        "%.1f초".format(seconds)
    }
}
