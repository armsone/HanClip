package com.hanclip.android.feature.editor

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.MovieCreation
import androidx.compose.material.icons.outlined.Photo
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.hanclip.android.core.media.MediaImportReader
import com.hanclip.android.core.model.ClipMediaKind
import com.hanclip.android.core.theme.HanClipPalette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun CalendarMediaPickerSheet(
    title: String = "사진첩 날짜별",
    palette: HanClipPalette,
    initialSelectedUris: List<Uri> = emptyList(),
    onDismiss: () -> Unit,
    onImport: (selectedUris: List<Uri>, deselectionScopeUris: Set<Uri>) -> Unit
) {
    FullScreenDialogSystemBars(palette.solidPanel)
    val context = LocalContext.current
    val pickerMode = remember(title) {
        when (title) {
            "기본 사진첩",
            "사진첩 전체" -> MediaPickerSheetMode.Recent
            "영상만" -> MediaPickerSheetMode.Videos
            else -> MediaPickerSheetMode.Calendar
        }
    }
    var visibleMonth by remember { mutableStateOf(YearMonth.now()) }
    var selectedDates by remember { mutableStateOf(setOf(LocalDate.now())) }
    var selectedUris by remember(title, initialSelectedUris) {
        mutableStateOf(
            if (pickerMode == MediaPickerSheetMode.Recent) {
                initialSelectedUris.distinctBy(Uri::toString)
            } else {
                emptyList()
            }
        )
    }
    var hasAppliedInitialSelection by remember(title) {
        mutableStateOf(pickerMode == MediaPickerSheetMode.Recent)
    }
    var recentScopeUris by remember(title) { mutableStateOf<Set<Uri>>(emptySet()) }
    var recentKnownItems by remember(title) {
        mutableStateOf<Map<Uri, CalendarMediaItem>>(emptyMap())
    }
    var pendingRecentDate by remember(title) { mutableStateOf<LocalDate?>(null) }
    var pendingBulkImportUris by remember { mutableStateOf<List<Uri>?>(null) }
    var sortOrder by remember { mutableStateOf(MediaSortOrder.NewestFirst) }
    var recentFilter by remember { mutableStateOf(RecentMediaFilter.Photo) }
    val loadedMonthItems by produceState<Pair<YearMonth, List<CalendarMediaItem>>?>(null, visibleMonth) {
        value = visibleMonth to CalendarMediaRepository.loadMonth(context, visibleMonth)
    }
    val monthItems = loadedMonthItems
        ?.takeIf { (loadedMonth) -> loadedMonth == visibleMonth }
        ?.second
        .orEmpty()
    val itemsByDate = remember(monthItems) { monthItems.groupBy { it.date } }
    val selectedItems = remember(monthItems, selectedDates, sortOrder) {
        selectedDates
            .flatMap { date -> itemsByDate[date].orEmpty() }
            .sortedBySortOrder(sortOrder)
    }
    val visibleItems = remember(pickerMode, monthItems, selectedItems, sortOrder, recentFilter) {
        when (pickerMode) {
            MediaPickerSheetMode.Recent -> monthItems
                .filter(recentFilter::accepts)
                .sortedBySortOrder(sortOrder)
            MediaPickerSheetMode.Videos -> monthItems
                .filter { it.kind == ClipMediaKind.Video }
                .sortedBySortOrder(sortOrder)
            MediaPickerSheetMode.Calendar -> selectedItems
        }
    }
    LaunchedEffect(pickerMode, visibleItems, initialSelectedUris) {
        if (pickerMode == MediaPickerSheetMode.Calendar) {
            selectedUris = visibleItems.map { it.uri }
        } else if (!hasAppliedInitialSelection && visibleItems.isNotEmpty()) {
            val visibleUriStrings = visibleItems.mapTo(mutableSetOf()) { it.uri.toString() }
            selectedUris = initialSelectedUris
                .distinctBy(Uri::toString)
                .filter { it.toString() in visibleUriStrings }
            hasAppliedInitialSelection = true
        }
    }
    LaunchedEffect(pickerMode, loadedMonthItems, recentFilter) {
        if (pickerMode == MediaPickerSheetMode.Recent) {
            recentScopeUris = recentScopeUris + visibleItems.map { it.uri }
            recentKnownItems = recentKnownItems + visibleItems.associateBy { it.uri }
            if (loadedMonthItems?.first == visibleMonth) {
                pendingRecentDate?.let { targetDate ->
                    selectedUris = visibleItems
                        .filter { it.date == targetDate }
                        .map { it.uri }
                    pendingRecentDate = null
                }
            }
        }
    }
    fun deselectionScopeUris(): Set<Uri> = if (pickerMode == MediaPickerSheetMode.Recent) {
        recentScopeUris
    } else {
        emptySet()
    }
    fun requestImport() {
        val orderedUris = if (pickerMode == MediaPickerSheetMode.Recent) {
            selectedUris
        } else {
            selectedUris.mapNotNull { selectedUri ->
                visibleItems.firstOrNull { it.uri == selectedUri }?.uri
            }
        }
        if (orderedUris.size >= BulkImportConfirmationThreshold) {
            pendingBulkImportUris = orderedUris
        } else {
            onImport(orderedUris, deselectionScopeUris())
        }
    }

    Surface(
        modifier = Modifier.fillMaxSize(),
        shape = RoundedCornerShape(0.dp),
        color = palette.solidPanel
    ) {
        Column(
            modifier = Modifier
                .background(palette.background)
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            val moveToPreviousMonth = {
                val newMonth = visibleMonth.minusMonths(1)
                visibleMonth = newMonth
                selectedDates = setOf(newMonth.atDay(1))
                if (pickerMode != MediaPickerSheetMode.Recent) selectedUris = emptyList()
            }
            val moveToNextMonth = {
                val newMonth = visibleMonth.plusMonths(1)
                visibleMonth = newMonth
                selectedDates = setOf(newMonth.atDay(1))
                if (pickerMode != MediaPickerSheetMode.Recent) selectedUris = emptyList()
            }
            if (pickerMode == MediaPickerSheetMode.Calendar) {
                CalendarTopActions(
                    palette = palette,
                    selectedCount = selectedUris.size,
                    onCancel = onDismiss,
                    onToday = {
                        visibleMonth = YearMonth.now()
                        selectedDates = setOf(LocalDate.now())
                        selectedUris = emptyList()
                    },
                    onConfirm = ::requestImport
                )
                CalendarMonthNavigation(
                    palette = palette,
                    visibleMonth = visibleMonth,
                    onPrevious = moveToPreviousMonth,
                    onNext = moveToNextMonth
                )
            } else if (pickerMode == MediaPickerSheetMode.Recent) {
                RecentPickerHeader(
                    palette = palette,
                    selectedCount = selectedUris.size,
                    canApplyEmptySelection = initialSelectedUris.isNotEmpty(),
                    filter = recentFilter,
                    onFilterChange = {
                        recentFilter = it
                        selectedUris = emptyList()
                        hasAppliedInitialSelection = false
                    },
                    onCancel = onDismiss,
                    onConfirm = ::requestImport
                )
                RecentMonthNavigation(
                    palette = palette,
                    visibleMonth = visibleMonth,
                    onPrevious = moveToPreviousMonth,
                    onNext = moveToNextMonth
                )
            } else {
                CalendarSheetHeader(
                    title = title,
                    mode = pickerMode,
                    sortOrder = sortOrder,
                    palette = palette,
                    visibleMonth = visibleMonth,
                    onPrevious = moveToPreviousMonth,
                    onNext = moveToNextMonth,
                    onDismiss = onDismiss
                )
            }
            if (pickerMode == MediaPickerSheetMode.Calendar) {
                CalendarMonthGrid(
                    palette = palette,
                    visibleMonth = visibleMonth,
                    selectedDates = selectedDates,
                    itemCountsByDate = itemsByDate.mapValues { it.value.size },
                    onToggleDate = { date ->
                        selectedDates = if (date in selectedDates && selectedDates.size > 1) {
                            selectedDates - date
                        } else {
                            selectedDates + date
                        }
                        selectedUris = emptyList()
                    }
                )
                CalendarSelectionSummary(
                    palette = palette,
                    selectedDateCount = selectedDates.size,
                    selectedMediaCount = visibleItems.size,
                    onClear = {
                        selectedDates = emptySet()
                        selectedUris = emptyList()
                    }
                )
            }
            CalendarMediaStrip(
                palette = palette,
                mode = pickerMode,
                visibleMonth = visibleMonth,
                selectedDates = selectedDates,
                items = visibleItems,
                selectedUris = selectedUris,
                sortOrder = sortOrder,
                recentFilter = recentFilter,
                onToggleSortOrder = {
                    sortOrder = sortOrder.next()
                },
                onSelectAll = {
                    selectedUris = visibleItems.map { it.uri }
                },
                onClearSelection = {
                    selectedUris = emptyList()
                },
                onToggle = { uri ->
                    selectedUris = if (uri in selectedUris) {
                        selectedUris.filterNot { it == uri }
                    } else {
                        selectedUris + uri
                    }
                }
            )
            when (pickerMode) {
                MediaPickerSheetMode.Calendar -> Unit
                MediaPickerSheetMode.Recent -> {
                    RecentSelectionPreview(
                        palette = palette,
                        items = recentKnownItems.values.toList(),
                        selectedUris = selectedUris,
                        onRemove = { uri ->
                            selectedUris = selectedUris.filterNot { it == uri }
                        }
                    )
                    RecentDayActions(
                        palette = palette,
                        canClear = selectedUris.isNotEmpty(),
                        onPreviousDay = {
                            val anchor = selectedUris.firstOrNull()
                                ?.let { uri -> recentKnownItems[uri]?.date }
                                ?: LocalDate.now()
                            val target = anchor.minusDays(1)
                            val targetMonth = YearMonth.from(target)
                            if (targetMonth != visibleMonth) {
                                pendingRecentDate = target
                                visibleMonth = targetMonth
                            } else {
                                selectedUris = visibleItems.filter { it.date == target }.map { it.uri }
                            }
                        },
                        onToday = {
                            val today = LocalDate.now()
                            val currentMonth = YearMonth.from(today)
                            if (currentMonth != visibleMonth) {
                                pendingRecentDate = today
                                visibleMonth = currentMonth
                            } else {
                                selectedUris = visibleItems.filter { it.date == today }.map { it.uri }
                            }
                        },
                        onClear = { selectedUris = emptyList() }
                    )
                }
                MediaPickerSheetMode.Videos -> {
                    MediaSelectionSummary(
                        palette = palette,
                        items = visibleItems,
                        selectedUris = selectedUris
                    )
                    StandardPickerBottomActions(
                        palette = palette,
                        selectedCount = selectedUris.size,
                        onDismiss = onDismiss,
                        onImport = ::requestImport
                    )
                }
            }
        }
    }
    pendingBulkImportUris?.let { uris ->
        AlertDialog(
            onDismissRequest = { pendingBulkImportUris = null },
            dismissButton = {
                OutlinedButton(
                    onClick = { pendingBulkImportUris = null },
                    border = BorderStroke(1.dp, palette.border),
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = palette.solidPanel,
                        contentColor = palette.text
                    )
                ) {
                    Text("취소")
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        pendingBulkImportUris = null
                        onImport(uris, deselectionScopeUris())
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = palette.primary,
                        contentColor = Color.White
                    )
                ) {
                    Icon(Icons.Outlined.MovieCreation, contentDescription = null)
                    Text("HanClip에 넣기")
                }
            },
            shape = RoundedCornerShape(16.dp),
            containerColor = palette.solidPanel,
            titleContentColor = palette.text,
            textContentColor = palette.subText,
            title = { Text("HanClip 클립 순서 확인") },
            text = {
                Text(
                    "${selectedMediaSummaryText(
                        if (pickerMode == MediaPickerSheetMode.Recent) {
                            recentKnownItems.values.toList()
                        } else {
                            visibleItems
                        },
                        uris
                    )}를 선택했습니다. " +
                        "기본 사진첩에서 고른 번호순 그대로 배치하고, 영상은 스윙 타격점 기준 자동 컷을 준비합니다."
                )
            }
        )
    }
}

private const val BulkImportConfirmationThreshold = 10

private enum class MediaPickerSheetMode {
    Recent,
    Videos,
    Calendar
}

private enum class RecentMediaFilter(val title: String) {
    Photo("사진"),
    LivePhoto("Live"),
    Video("영상");

    fun accepts(item: CalendarMediaItem): Boolean = when (this) {
        Photo -> item.kind == ClipMediaKind.Photo
        LivePhoto -> item.kind == ClipMediaKind.LivePhoto
        Video -> item.kind == ClipMediaKind.Video
    }
}

private enum class MediaSortOrder(val label: String) {
    NewestFirst("최신순"),
    OldestFirst("오래된순");

    fun next(): MediaSortOrder {
        return if (this == NewestFirst) OldestFirst else NewestFirst
    }
}

@Composable
private fun RecentPickerHeader(
    palette: HanClipPalette,
    selectedCount: Int,
    canApplyEmptySelection: Boolean,
    filter: RecentMediaFilter,
    onFilterChange: (RecentMediaFilter) -> Unit,
    onCancel: () -> Unit,
    onConfirm: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        OutlinedButton(
            onClick = onCancel,
            shape = RoundedCornerShape(50),
            border = BorderStroke(1.dp, palette.border),
            colors = ButtonDefaults.outlinedButtonColors(
                containerColor = palette.solidPanel,
                contentColor = palette.text
            )
        ) {
            Icon(Icons.Outlined.Close, contentDescription = null, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(5.dp))
            Text("취소", fontWeight = FontWeight.Bold)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Surface(
                modifier = Modifier.size(36.dp),
                shape = RoundedCornerShape(9.dp),
                color = palette.chip
            ) {
                Icon(
                    Icons.Outlined.Photo,
                    contentDescription = null,
                    tint = palette.primary,
                    modifier = Modifier.padding(8.dp)
                )
            }
            Spacer(Modifier.width(8.dp))
            Text("미디어 선택", color = palette.text, fontWeight = FontWeight.Black)
        }
        Button(
            onClick = onConfirm,
            enabled = selectedCount > 0 || canApplyEmptySelection,
            shape = RoundedCornerShape(50),
            colors = ButtonDefaults.buttonColors(
                containerColor = palette.primary,
                contentColor = Color.White,
                disabledContainerColor = palette.subText.copy(alpha = 0.38f),
                disabledContentColor = Color.White.copy(alpha = 0.72f)
            )
        ) {
            Text(
                if (selectedCount == 0) "선택 적용" else "+ ${selectedCount}개 적용",
                fontWeight = FontWeight.Bold
            )
        }
    }
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(50),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Row(Modifier.padding(3.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            RecentMediaFilter.entries.forEach { candidate ->
                Surface(
                    modifier = Modifier.weight(1f).height(38.dp),
                    shape = RoundedCornerShape(50),
                    color = if (filter == candidate) palette.panel else Color.Transparent,
                    border = BorderStroke(
                        1.dp,
                        if (filter == candidate) palette.primary.copy(alpha = 0.42f) else Color.Transparent
                    ),
                    onClick = { onFilterChange(candidate) }
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            candidate.title,
                            color = if (filter == candidate) palette.text else palette.primary,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RecentMonthNavigation(
    palette: HanClipPalette,
    visibleMonth: YearMonth,
    onPrevious: () -> Unit,
    onNext: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        IconButton(onClick = onPrevious, modifier = Modifier.size(34.dp)) {
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowLeft,
                contentDescription = "이전 달",
                tint = palette.primary
            )
        }
        Surface(
            shape = RoundedCornerShape(50),
            color = palette.chip,
            border = BorderStroke(1.dp, palette.border)
        ) {
            Text(
                visibleMonth.format(DateTimeFormatter.ofPattern("yyyy년 M월", Locale.KOREAN)),
                modifier = Modifier.padding(horizontal = 22.dp, vertical = 6.dp),
                color = palette.text,
                fontWeight = FontWeight.Black,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        IconButton(onClick = onNext, modifier = Modifier.size(34.dp)) {
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = "다음 달",
                tint = palette.primary
            )
        }
    }
}

@Composable
private fun RecentSelectionPreview(
    palette: HanClipPalette,
    items: List<CalendarMediaItem>,
    selectedUris: List<Uri>,
    onRemove: (Uri) -> Unit
) {
    val selectedItems = selectedUris.mapNotNull { uri -> items.firstOrNull { it.uri == uri } }
    val date = selectedItems.firstOrNull()?.date ?: LocalDate.now()
    var previewItem by remember { mutableStateOf<CalendarMediaItem?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Surface(
            shape = RoundedCornerShape(9.dp),
            color = palette.chip
        ) {
            Text(
                date.format(DateTimeFormatter.ofPattern("yyyy년 M월 d일 EEEE", Locale.KOREAN)),
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 7.dp),
                color = palette.text,
                fontWeight = FontWeight.Black
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth().height(76.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            selectedItems.take(8).forEachIndexed { index, item ->
                CalendarMediaThumb(
                    palette = palette,
                    item = item,
                    selectedOrder = index + 1,
                    onClick = {},
                    onLongClick = { previewItem = item },
                    modifier = Modifier.size(76.dp)
                )
            }
            if (selectedItems.isEmpty()) {
                Text(
                    "선택한 미디어가 여기에 순서대로 표시됩니다.",
                    color = palette.subText,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.align(Alignment.CenterVertically)
                )
            }
        }
    }
    previewItem?.let { item ->
        CalendarMediaPreviewDialog(
            palette = palette,
            item = item,
            onDismiss = { previewItem = null },
            onRemove = {
                onRemove(item.uri)
                previewItem = null
            }
        )
    }
}

@UnstableApi
@Composable
private fun CalendarMediaPreviewDialog(
    palette: HanClipPalette,
    item: CalendarMediaItem,
    onDismiss: () -> Unit,
    onRemove: () -> Unit
) {
    val context = LocalContext.current
    val isVideo = item.kind == ClipMediaKind.Video
    val thumbnail by produceState<Bitmap?>(null, item.uri, isVideo) {
        if (!isVideo) {
            value = MediaImportReader.loadThumbnailBitmap(
                context = context,
                uri = item.uri,
                mediaKind = item.kind,
                targetSize = 1200
            )
        }
    }
    val player = remember(item.uri, isVideo) {
        if (isVideo) {
            ExoPlayer.Builder(context).build().apply {
                setMediaItem(MediaItem.fromUri(item.uri))
                repeatMode = Player.REPEAT_MODE_ALL
                playWhenReady = true
                prepare()
            }
        } else {
            null
        }
    }
    DisposableEffect(player) {
        onDispose { player?.release() }
    }
    Dialog(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Button(
                onClick = onRemove,
                modifier = Modifier.fillMaxWidth(0.70f),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = palette.primary)
            ) {
                Icon(Icons.Outlined.Delete, contentDescription = null)
                Spacer(Modifier.width(5.dp))
                Text("선택에서 제거")
            }
            Surface(
                modifier = Modifier
                    .fillMaxWidth(0.70f)
                    .aspectRatio(1f),
                shape = RoundedCornerShape(18.dp),
                color = if (isVideo) Color.Black else palette.solidPanel,
                border = BorderStroke(1.25.dp, palette.border)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    if (isVideo && player != null) {
                        AndroidView(
                            factory = { viewContext ->
                                PlayerView(viewContext).apply {
                                    this.player = player
                                    useController = true
                                    controllerAutoShow = true
                                    contentDescription = "${item.displayName} 영상 미리보기"
                                }
                            },
                            update = { view -> view.player = player },
                            modifier = Modifier.fillMaxSize()
                        )
                    } else if (thumbnail != null) {
                        Image(
                            bitmap = thumbnail!!.asImageBitmap(),
                            contentDescription = "${item.displayName} 크게 보기",
                            modifier = Modifier.fillMaxSize(),
                            contentScale = ContentScale.Fit
                        )
                    } else {
                        CircularProgressIndicator(color = palette.primary)
                    }
                }
            }
        }
    }
}

@Composable
private fun RecentDayActions(
    palette: HanClipPalette,
    canClear: Boolean,
    onPreviousDay: () -> Unit,
    onToday: () -> Unit,
    onClear: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        DayCircleButton("어제", palette, enabled = true, onClick = onPreviousDay)
        DayCircleButton("오늘", palette, enabled = true, onClick = onToday)
        DayCircleButton("해제", palette, enabled = canClear, onClick = onClear)
    }
}

@Composable
private fun DayCircleButton(
    title: String,
    palette: HanClipPalette,
    enabled: Boolean,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier.size(64.dp),
        shape = CircleShape,
        color = palette.panel.copy(alpha = if (enabled) 0.94f else 0.42f),
        border = BorderStroke(1.dp, palette.border.copy(alpha = if (enabled) 1f else 0.46f)),
        enabled = enabled,
        onClick = onClick
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                title,
                color = palette.text.copy(alpha = if (enabled) 1f else 0.36f),
                fontWeight = FontWeight.Bold
            )
        }
    }
}

@Composable
private fun StandardPickerBottomActions(
    palette: HanClipPalette,
    selectedCount: Int,
    onDismiss: () -> Unit,
    onImport: () -> Unit
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        OutlinedButton(
            modifier = Modifier.weight(1f).height(48.dp),
            onClick = onDismiss,
            border = BorderStroke(1.dp, palette.border),
            colors = ButtonDefaults.outlinedButtonColors(
                containerColor = palette.solidPanel,
                contentColor = palette.text
            )
        ) { Text("닫기") }
        Button(
            modifier = Modifier.weight(1f).height(48.dp),
            enabled = selectedCount > 0,
            onClick = onImport,
            colors = ButtonDefaults.buttonColors(
                containerColor = palette.primary,
                contentColor = Color.White,
                disabledContainerColor = palette.chip,
                disabledContentColor = palette.subText
            )
        ) {
            Icon(Icons.Outlined.MovieCreation, contentDescription = null)
            Text(if (selectedCount == 0) "선택 후 가져오기" else "HanClip에 가져오기", fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun CalendarTopActions(
    palette: HanClipPalette,
    selectedCount: Int,
    onCancel: () -> Unit,
    onToday: () -> Unit,
    onConfirm: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        OutlinedButton(
            onClick = onCancel,
            shape = RoundedCornerShape(50),
            border = BorderStroke(1.dp, palette.border),
            colors = ButtonDefaults.outlinedButtonColors(containerColor = palette.solidPanel, contentColor = palette.text)
        ) { Text("취소", fontWeight = FontWeight.Bold) }
        OutlinedButton(
            onClick = onToday,
            shape = RoundedCornerShape(50),
            border = BorderStroke(1.dp, palette.border),
            colors = ButtonDefaults.outlinedButtonColors(containerColor = palette.solidPanel, contentColor = palette.text)
        ) { Text("오늘", fontWeight = FontWeight.Bold) }
        OutlinedButton(
            onClick = onConfirm,
            enabled = selectedCount > 0,
            shape = RoundedCornerShape(50),
            border = BorderStroke(1.dp, palette.border),
            colors = ButtonDefaults.outlinedButtonColors(
                containerColor = palette.solidPanel,
                contentColor = palette.primary,
                disabledContainerColor = palette.chip,
                disabledContentColor = palette.subText
            )
        ) { Text("확인", fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun CalendarMonthNavigation(
    palette: HanClipPalette,
    visibleMonth: YearMonth,
    onPrevious: () -> Unit,
    onNext: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            modifier = Modifier.size(48.dp),
            shape = CircleShape,
            color = palette.panel,
            border = BorderStroke(1.dp, palette.border),
            onClick = onPrevious
        ) {
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowLeft,
                contentDescription = "이전 달",
                tint = palette.primary,
                modifier = Modifier.padding(11.dp)
            )
        }
        Text(
            visibleMonth.format(DateTimeFormatter.ofPattern("yyyy년 M월", Locale.KOREAN)),
            color = palette.text,
            fontWeight = FontWeight.Black,
            style = MaterialTheme.typography.headlineSmall
        )
        Surface(
            modifier = Modifier.size(48.dp),
            shape = CircleShape,
            color = palette.panel,
            border = BorderStroke(1.dp, palette.border),
            onClick = onNext
        ) {
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = "다음 달",
                tint = palette.primary,
                modifier = Modifier.padding(11.dp)
            )
        }
    }
}

private fun selectedMediaSummaryText(
    items: List<CalendarMediaItem>,
    selectedUris: List<Uri>
): String {
    val selectedItems = selectedUris.mapNotNull { selectedUri ->
        items.firstOrNull { it.uri == selectedUri }
    }
    val photoCount = selectedItems.count { it.kind != ClipMediaKind.Video }
    val videoCount = selectedItems.count { it.kind == ClipMediaKind.Video }
    val selectedVideoDurationMillis = selectedItems.sumOf { item ->
        item.durationMillis.takeIf { item.kind == ClipMediaKind.Video } ?: 0L
    }
    return listOfNotNull(
        selectedUris.size.takeIf { it > 0 }?.let { "${it}개" },
        photoCount.takeIf { it > 0 }?.let { "사진 ${it}개" },
        videoCount.takeIf { it > 0 }?.let { "영상 ${it}개" },
        selectedVideoDurationMillis.takeIf { it > 0L }?.let { "원본 ${formatDurationBadge(it)}" }
    ).joinToString(" · ").ifBlank { "0개" }
}

@Composable
private fun CalendarSheetHeader(
    title: String,
    mode: MediaPickerSheetMode,
    sortOrder: MediaSortOrder,
    palette: HanClipPalette,
    visibleMonth: YearMonth,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onDismiss: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Surface(
            modifier = Modifier.size(38.dp),
            shape = RoundedCornerShape(16.dp),
            color = palette.primary
        ) {
            Icon(
                when (mode) {
                    MediaPickerSheetMode.Recent -> Icons.Outlined.Photo
                    MediaPickerSheetMode.Videos -> Icons.Outlined.MovieCreation
                    MediaPickerSheetMode.Calendar -> Icons.Outlined.CalendarMonth
                },
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.padding(8.dp)
            )
        }
        Column(Modifier.weight(1f)) {
            Text(title, color = palette.text, fontWeight = FontWeight.Bold)
            Text(
                if (mode == MediaPickerSheetMode.Recent || mode == MediaPickerSheetMode.Videos) {
                    "Android 기본 사진첩 · ${visibleMonth.format(DateTimeFormatter.ofPattern("yyyy년 M월", Locale.KOREAN))} ${sortOrder.label}"
                } else {
                    "Android 기본 사진첩 · ${visibleMonth.format(DateTimeFormatter.ofPattern("yyyy년 M월", Locale.KOREAN))}"
                },
                color = palette.subText,
                style = MaterialTheme.typography.bodySmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        IconButton(onClick = onPrevious) {
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, contentDescription = "이전 달", tint = palette.text)
        }
        IconButton(onClick = onNext) {
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = "다음 달", tint = palette.text)
        }
        IconButton(onClick = onDismiss) {
            Icon(Icons.Outlined.Close, contentDescription = "닫기", tint = palette.text)
        }
    }
}

@Composable
private fun CalendarMonthGrid(
    palette: HanClipPalette,
    visibleMonth: YearMonth,
    selectedDates: Set<LocalDate>,
    itemCountsByDate: Map<LocalDate, Int>,
    onToggleDate: (LocalDate) -> Unit
) {
    val firstDayOffset = (visibleMonth.atDay(1).dayOfWeek.value % 7)
    val days = buildList {
        repeat(firstDayOffset) { add(null) }
        for (day in 1..visibleMonth.lengthOfMonth()) add(visibleMonth.atDay(day))
    }
    val rowCount = (days.size + 6) / 7
    Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(1.dp)) {
            listOf("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT").forEachIndexed { index, label ->
                Surface(
                    modifier = Modifier.weight(1f).height(30.dp),
                    color = when (index) {
                        0 -> palette.primary
                        6 -> palette.secondary
                        else -> palette.subText.copy(alpha = 0.82f)
                    }
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            text = label,
                            color = Color.White,
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Black,
                            textAlign = TextAlign.Center
                        )
                    }
                }
            }
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(7),
            modifier = Modifier.height((rowCount * 34).dp),
            userScrollEnabled = false,
            verticalArrangement = Arrangement.spacedBy(0.dp),
            horizontalArrangement = Arrangement.spacedBy(0.dp)
        ) {
            items(days) { date ->
                if (date == null) {
                    Spacer(Modifier.height(34.dp))
                } else {
                    CalendarDayCell(
                        palette = palette,
                        date = date,
                        selected = date in selectedDates,
                        count = itemCountsByDate[date] ?: 0,
                        onClick = { onToggleDate(date) }
                    )
                }
            }
        }
    }
}

@Composable
private fun CalendarDayCell(
    palette: HanClipPalette,
    date: LocalDate,
    selected: Boolean,
    count: Int,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier
            .height(34.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(0.dp),
        color = if (selected) palette.primary else palette.panel,
        border = BorderStroke(1.dp, if (selected) palette.primary else palette.border)
    ) {
        Box(contentAlignment = Alignment.Center) {
            Surface(
                modifier = Modifier.size(if (count > 0) 27.dp else 1.dp),
                shape = CircleShape,
                color = when {
                    count == 0 -> Color.Transparent
                    selected -> Color.White.copy(alpha = 0.28f)
                    else -> palette.chip
                }
            ) {}
            Text(
                text = date.dayOfMonth.toString(),
                color = if (selected) Color.White else palette.text,
                fontWeight = if (count > 0 || date == LocalDate.now()) FontWeight.Black else FontWeight.Medium
            )
        }
    }
}

@Composable
private fun CalendarSelectionSummary(
    palette: HanClipPalette,
    selectedDateCount: Int,
    selectedMediaCount: Int,
    onClear: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(50),
        color = palette.panel,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Row(
            modifier = Modifier.height(44.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "선택 ${selectedDateCount}일 · 미디어 ${selectedMediaCount}개",
                modifier = Modifier.weight(2f).padding(start = 16.dp),
                color = if (selectedDateCount == 0) palette.subText else palette.secondary,
                fontWeight = FontWeight.Bold
            )
            Box(
                modifier = Modifier.width(1.dp).height(24.dp).background(palette.border)
            )
            Row(
                modifier = Modifier
                    .weight(1f)
                    .height(44.dp)
                    .clickable(enabled = selectedDateCount > 0, onClick = onClear),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Outlined.Delete,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = if (selectedDateCount == 0) palette.subText else palette.secondary
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    text = "지우기",
                    color = if (selectedDateCount == 0) palette.subText else palette.secondary,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

@Composable
private fun CalendarMediaStrip(
    palette: HanClipPalette,
    mode: MediaPickerSheetMode,
    visibleMonth: YearMonth,
    selectedDates: Set<LocalDate>,
    items: List<CalendarMediaItem>,
    selectedUris: List<Uri>,
    sortOrder: MediaSortOrder,
    recentFilter: RecentMediaFilter,
    onToggleSortOrder: () -> Unit,
    onSelectAll: () -> Unit,
    onClearSelection: () -> Unit,
    onToggle: (Uri) -> Unit
) {
    var previewItem by remember { mutableStateOf<CalendarMediaItem?>(null) }
    val screenWidthDp = LocalConfiguration.current.screenWidthDp
    val mediaColumnCount = when {
        screenWidthDp >= 1_200 -> 12
        screenWidthDp >= 840 -> 10
        screenWidthDp >= 600 -> 8
        else -> 5
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (mode != MediaPickerSheetMode.Calendar) Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = mediaStripTitle(
                    mode = mode,
                    visibleMonth = visibleMonth,
                    selectedDates = selectedDates,
                    items = items,
                    recentFilter = recentFilter
                ),
                color = palette.subText,
                style = MaterialTheme.typography.bodySmall
            )
            if (items.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    OutlinedButton(
                        modifier = Modifier.height(34.dp),
                        onClick = onToggleSortOrder,
                        border = BorderStroke(1.dp, palette.border),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = palette.solidPanel,
                            contentColor = palette.text
                        )
                    ) {
                        Text(
                            sortOrder.label,
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    OutlinedButton(
                        modifier = Modifier.height(34.dp),
                        onClick = if (selectedUris.size == items.size) onClearSelection else onSelectAll,
                        border = BorderStroke(1.dp, palette.border),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = palette.solidPanel,
                            contentColor = palette.text
                        )
                    ) {
                        Text(
                            if (selectedUris.size == items.size) "전체 해제" else "전체 ${items.size}개 선택",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
        val gridHeight = when (mode) {
            MediaPickerSheetMode.Recent, MediaPickerSheetMode.Videos -> 374.dp
            MediaPickerSheetMode.Calendar -> 260.dp
        }
        if (items.isEmpty()) {
            EmptyMediaStrip(
                mode = mode,
                recentFilter = recentFilter,
                palette = palette,
                modifier = Modifier.height(gridHeight)
            )
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(mediaColumnCount),
                modifier = Modifier.height(gridHeight),
                contentPadding = PaddingValues(bottom = 4.dp),
                verticalArrangement = Arrangement.spacedBy(5.dp),
                horizontalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                items(items, key = { it.uri.toString() }) { item ->
                    CalendarMediaThumb(
                        palette = palette,
                        item = item,
                        selectedOrder = selectedUris.indexOf(item.uri)
                            .takeIf { it >= 0 }
                            ?.plus(1),
                        onClick = { onToggle(item.uri) },
                        onLongClick = if (item.uri in selectedUris) {
                            { previewItem = item }
                        } else {
                            null
                        }
                    )
                }
            }
        }
    }
    previewItem?.let { item ->
        CalendarMediaPreviewDialog(
            palette = palette,
            item = item,
            onDismiss = { previewItem = null },
            onRemove = {
                if (item.uri in selectedUris) onToggle(item.uri)
                previewItem = null
            }
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MediaSelectionSummary(
    palette: HanClipPalette,
    items: List<CalendarMediaItem>,
    selectedUris: List<Uri>
) {
    val selectedItems = selectedUris.mapNotNull { selectedUri ->
        items.firstOrNull { it.uri == selectedUri }
    }
    val photoCount = selectedItems.count { it.kind != ClipMediaKind.Video }
    val videoCount = selectedItems.count { it.kind == ClipMediaKind.Video }
    val selectedVideoDurationMillis = selectedItems.sumOf { item ->
        item.durationMillis.takeIf { item.kind == ClipMediaKind.Video } ?: 0L
    }
    val selectionEdgeText = remember(selectedItems) { selectionEdgeText(selectedItems) }
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = if (selectedUris.isEmpty()) palette.panel else palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp)
        ) {
            Text(
                text = if (selectedUris.isEmpty()) {
                    "기본 사진첩에서 사진과 영상을 한 번에 고르면 HanClip 완성본 순서가 표시됩니다."
                } else {
                    "선택 ${selectedUris.size}개 · 선택한 순서 그대로 완성본 배치"
                },
                color = if (selectedUris.isEmpty()) palette.subText else palette.primary,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.bodySmall
            )
            selectionEdgeText?.let {
                Text(
                    text = it,
                    color = palette.subText,
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (selectedUris.isEmpty()) {
                MediaSelectionSummaryPill("Android 기본 사진첩", palette, active = false)
                MediaSelectionSummaryPill("여러 사진/영상 한 번에 선택", palette, active = false)
            } else {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    photoCount.takeIf { it > 0 }?.let {
                        MediaSelectionSummaryPill("사진 ${it}개", palette, active = true)
                    }
                    videoCount.takeIf { it > 0 }?.let {
                        MediaSelectionSummaryPill("영상 ${it}개", palette, active = true)
                        MediaSelectionSummaryPill("타격점 자동 컷", palette, active = true)
                    }
                    selectedVideoDurationMillis.takeIf { it > 0L }?.let {
                        MediaSelectionSummaryPill("원본 ${formatDurationBadge(it)}", palette, active = true)
                    }
                    selectedUris.size.takeIf { it > 1 }?.let {
                        MediaSelectionSummaryPill("1-${it} 번호순 연결", palette, active = true)
                    }
                }
            }
        }
    }
}

private fun selectionEdgeText(selectedItems: List<CalendarMediaItem>): String? {
    if (selectedItems.size <= 1) return null
    val first = selectedItems.first()
    val last = selectedItems.last()
    return "처음 ${first.selectionLabel()} → 마지막 ${last.selectionLabel()}"
}

private fun CalendarMediaItem.selectionLabel(): String {
    val type = if (kind == ClipMediaKind.Video) "영상" else "사진"
    val dateText = date.format(DateTimeFormatter.ofPattern("M월 d일", Locale.KOREAN))
    return "$type · $dateText"
}

@Composable
private fun MediaSelectionSummaryPill(
    text: String,
    palette: HanClipPalette,
    active: Boolean
) {
    Surface(
        shape = RoundedCornerShape(50),
        color = if (active) palette.panel else palette.chip,
        border = BorderStroke(1.dp, if (active) palette.primary.copy(alpha = 0.42f) else palette.border)
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 9.dp, vertical = 5.dp),
            color = if (active) palette.text else palette.subText,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun EmptyMediaStrip(
    mode: MediaPickerSheetMode,
    recentFilter: RecentMediaFilter,
    palette: HanClipPalette,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = if (
                    mode == MediaPickerSheetMode.Videos || recentFilter == RecentMediaFilter.Video
                ) {
                    Icons.Outlined.MovieCreation
                } else {
                    Icons.Outlined.Photo
                },
                contentDescription = null,
                tint = palette.primary,
                modifier = Modifier.size(30.dp)
            )
            Spacer(Modifier.height(10.dp))
            Text(
                text = when {
                    mode == MediaPickerSheetMode.Videos || recentFilter == RecentMediaFilter.Video ->
                        "이번 달 기본 사진첩에는 영상이 없습니다."
                    mode == MediaPickerSheetMode.Recent && recentFilter == RecentMediaFilter.LivePhoto ->
                        "이번 달 기본 사진첩에는 Live Photo가 없습니다."
                    else -> "이번 달 기본 사진첩에는 사진이나 영상이 없습니다."
                },
                color = palette.text,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
            Text(
                text = "상단 화살표로 다른 달을 보거나, 파일 선택으로 폰에 있는 항목을 직접 가져오세요.",
                color = palette.subText,
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center
            )
        }
    }
}

private fun mediaStripTitle(
    mode: MediaPickerSheetMode,
    visibleMonth: YearMonth,
    selectedDates: Set<LocalDate>,
    items: List<CalendarMediaItem>,
    recentFilter: RecentMediaFilter
): String {
    val photoCount = items.count { it.kind != ClipMediaKind.Video }
    val videoCount = items.count { it.kind == ClipMediaKind.Video }
    val count = items.size
    if (mode == MediaPickerSheetMode.Recent) {
        return if (count == 0) {
            when (recentFilter) {
                RecentMediaFilter.Photo -> "${visibleMonth.monthValue}월 기본 사진첩에는 사진이 없습니다."
                RecentMediaFilter.LivePhoto -> "${visibleMonth.monthValue}월 기본 사진첩에는 Live Photo가 없습니다."
                RecentMediaFilter.Video -> "${visibleMonth.monthValue}월 기본 사진첩에는 영상이 없습니다."
            }
        } else {
            mediaCountText("이번 달", photoCount, videoCount)
        }
    }
    if (mode == MediaPickerSheetMode.Videos) {
        return if (count == 0) {
            "${visibleMonth.monthValue}월 기본 사진첩에는 영상이 없습니다."
        } else {
            "이번 달 영상 ${videoCount}개"
        }
    }
    val selectedDateText = if (selectedDates.size == 1) {
        "${selectedDates.first().dayOfMonth}일"
    } else {
        "선택 ${selectedDates.size}일"
    }
    return if (count == 0) {
        "${selectedDateText} 기본 사진첩에는 사진이나 영상이 없습니다."
    } else {
        mediaCountText(selectedDateText, photoCount, videoCount)
    }
}

private fun mediaCountText(prefix: String, photoCount: Int, videoCount: Int): String {
    val parts = buildList {
        if (photoCount > 0) add("사진 ${photoCount}장")
        if (videoCount > 0) add("영상 ${videoCount}개")
    }
    return "$prefix ${parts.joinToString(" · ")}"
}

private fun List<CalendarMediaItem>.sortedBySortOrder(sortOrder: MediaSortOrder): List<CalendarMediaItem> {
    return when (sortOrder) {
        MediaSortOrder.NewestFirst -> sortedByDescending { it.takenMillis }
        MediaSortOrder.OldestFirst -> sortedBy { it.takenMillis }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CalendarMediaThumb(
    palette: HanClipPalette,
    item: CalendarMediaItem,
    selectedOrder: Int?,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val thumbnail by produceState<Bitmap?>(null, item.uri) {
        value = MediaImportReader.loadThumbnailBitmap(
            context = context,
            uri = item.uri,
            mediaKind = item.kind,
            targetSize = 220
        )
    }
    Box(
        modifier = modifier
            .aspectRatio(1f)
            .clip(RoundedCornerShape(16.dp))
            .background(palette.chip)
            .then(
                if (onLongClick == null) {
                    Modifier.clickable(onClick = onClick)
                } else {
                    Modifier.combinedClickable(
                        onClick = onClick,
                        onLongClick = onLongClick,
                        onLongClickLabel = "미디어 크게 보기"
                    )
                }
            )
    ) {
        if (thumbnail == null) {
            CircularProgressIndicator(
                modifier = Modifier
                    .size(24.dp)
                    .align(Alignment.Center),
                strokeWidth = 2.dp,
                color = palette.primary
            )
        } else {
            Image(
                bitmap = thumbnail!!.asImageBitmap(),
                contentDescription = item.displayName,
                modifier = Modifier.matchParentSize(),
                contentScale = ContentScale.Crop
            )
        }
        if (item.kind == ClipMediaKind.Video) {
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(6.dp),
                shape = RoundedCornerShape(10.dp),
                color = Color.Black.copy(alpha = 0.58f)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Outlined.MovieCreation,
                        contentDescription = "영상",
                        tint = Color.White,
                        modifier = Modifier.size(13.dp)
                    )
                    item.durationMillis?.let { durationMillis ->
                        Spacer(Modifier.width(3.dp))
                        Text(
                            formatDurationBadge(durationMillis),
                            color = Color.White,
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
        if (selectedOrder != null) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .background(palette.primary.copy(alpha = 0.34f))
            )
            Surface(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .size(26.dp),
                shape = CircleShape,
                color = palette.primary,
                border = BorderStroke(2.dp, Color.White.copy(alpha = 0.92f))
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        selectedOrder.coerceAtMost(99).toString(),
                        color = Color.White,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Black
                    )
                }
            }
        }
    }
}

data class CalendarMediaItem(
    val uri: Uri,
    val date: LocalDate,
    val kind: ClipMediaKind,
    val takenMillis: Long,
    val displayName: String,
    val durationMillis: Long? = null
)

private fun formatDurationBadge(durationMillis: Long): String {
    val totalSeconds = (durationMillis / 1000).coerceAtLeast(0)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return if (minutes >= 60) {
        val hours = minutes / 60
        val remainingMinutes = minutes % 60
        "%d:%02d:%02d".format(hours, remainingMinutes, seconds)
    } else {
        "%d:%02d".format(minutes, seconds)
    }
}

private object CalendarMediaRepository {
    suspend fun loadMonth(context: Context, month: YearMonth): List<CalendarMediaItem> =
        withContext(Dispatchers.IO) {
            val start = month.atDay(1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
            val end = month.plusMonths(1).atDay(1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
            (queryCollection(context, MediaStore.Images.Media.EXTERNAL_CONTENT_URI, ClipMediaKind.Photo, start, end) +
                queryCollection(context, MediaStore.Video.Media.EXTERNAL_CONTENT_URI, ClipMediaKind.Video, start, end))
                .sortedByDescending { it.takenMillis }
        }

    private fun queryCollection(
        context: Context,
        collection: Uri,
        kind: ClipMediaKind,
        startMillis: Long,
        endMillis: Long
    ): List<CalendarMediaItem> {
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.MediaColumns.DURATION
        )
        val startSeconds = startMillis / 1000
        val endSeconds = endMillis / 1000
        val selection = """
            (${MediaStore.MediaColumns.DATE_TAKEN} >= ? AND ${MediaStore.MediaColumns.DATE_TAKEN} < ?)
            OR ((${MediaStore.MediaColumns.DATE_TAKEN} IS NULL OR ${MediaStore.MediaColumns.DATE_TAKEN} = 0)
                AND ${MediaStore.MediaColumns.DATE_ADDED} >= ? AND ${MediaStore.MediaColumns.DATE_ADDED} < ?)
            OR ((${MediaStore.MediaColumns.DATE_TAKEN} IS NULL OR ${MediaStore.MediaColumns.DATE_TAKEN} = 0)
                AND (${MediaStore.MediaColumns.DATE_ADDED} IS NULL OR ${MediaStore.MediaColumns.DATE_ADDED} = 0)
                AND ${MediaStore.MediaColumns.DATE_MODIFIED} >= ? AND ${MediaStore.MediaColumns.DATE_MODIFIED} < ?)
        """.trimIndent()
        val selectionArgs = arrayOf(
            startMillis.toString(),
            endMillis.toString(),
            startSeconds.toString(),
            endSeconds.toString(),
            startSeconds.toString(),
            endSeconds.toString()
        )
        val sortOrder = "${MediaStore.MediaColumns.DATE_TAKEN} DESC"

        return runCatching {
            context.contentResolver.query(collection, projection, selection, selectionArgs, sortOrder)
                ?.use { cursor ->
                    val idColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                    val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                    val takenColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_TAKEN)
                    val addedColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
                    val modifiedColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
                    val durationColumn = cursor.getColumnIndex(MediaStore.MediaColumns.DURATION)
                    buildList {
                        while (cursor.moveToNext()) {
                            val id = cursor.getLong(idColumn)
                            val takenMillis = cursor.getLong(takenColumn).takeIf { it > 0L }
                                ?: cursor.getLong(addedColumn).takeIf { it > 0L }?.times(1000)
                                ?: cursor.getLong(modifiedColumn).takeIf { it > 0L }?.times(1000)
                                ?: continue
                            if (takenMillis !in startMillis until endMillis) continue
                            val date = Instant.ofEpochMilli(takenMillis)
                                .atZone(ZoneId.systemDefault())
                                .toLocalDate()
                            val itemUri = ContentUris.withAppendedId(collection, id)
                            val resolvedKind = if (
                                kind == ClipMediaKind.Photo &&
                                MediaImportReader.isMotionPhoto(context, itemUri)
                            ) {
                                ClipMediaKind.LivePhoto
                            } else {
                                kind
                            }
                            add(
                                CalendarMediaItem(
                                    uri = itemUri,
                                    date = date,
                                    kind = resolvedKind,
                                    takenMillis = takenMillis,
                                    displayName = cursor.getString(nameColumn)
                                        ?.takeIf { it.isNotBlank() }
                                        ?: if (kind == ClipMediaKind.Video) "영상" else "사진",
                                    durationMillis = if (kind == ClipMediaKind.Video && durationColumn >= 0) {
                                        cursor.getLong(durationColumn).takeIf { it > 0L }
                                    } else {
                                        null
                                    }
                                )
                            )
                        }
                    }
                }.orEmpty()
        }.getOrDefault(emptyList())
    }
}
