package com.hanclip.android.feature.editor

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
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
    onDismiss: () -> Unit,
    onImport: (List<Uri>) -> Unit
) {
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
    var selectedUris by remember { mutableStateOf<List<Uri>>(emptyList()) }
    var pendingBulkImportUris by remember { mutableStateOf<List<Uri>?>(null) }
    var sortOrder by remember { mutableStateOf(MediaSortOrder.NewestFirst) }
    val monthItems by produceState<List<CalendarMediaItem>>(emptyList(), visibleMonth) {
        value = CalendarMediaRepository.loadMonth(context, visibleMonth)
    }
    val itemsByDate = remember(monthItems) { monthItems.groupBy { it.date } }
    val selectedItems = remember(monthItems, selectedDates, sortOrder) {
        selectedDates
            .flatMap { date -> itemsByDate[date].orEmpty() }
            .sortedBySortOrder(sortOrder)
    }
    val visibleItems = remember(pickerMode, monthItems, selectedItems, sortOrder) {
        when (pickerMode) {
            MediaPickerSheetMode.Recent -> monthItems.sortedBySortOrder(sortOrder)
            MediaPickerSheetMode.Videos -> monthItems
                .filter { it.kind == ClipMediaKind.Video }
                .sortedBySortOrder(sortOrder)
            MediaPickerSheetMode.Calendar -> selectedItems
        }
    }

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp),
        color = palette.panel
    ) {
        Column(
            modifier = Modifier
                .background(palette.background)
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            CalendarSheetHeader(
                title = title,
                mode = pickerMode,
                sortOrder = sortOrder,
                palette = palette,
                visibleMonth = visibleMonth,
                onPrevious = {
                    val newMonth = visibleMonth.minusMonths(1)
                    visibleMonth = newMonth
                    selectedDates = setOf(newMonth.atDay(1))
                    selectedUris = emptyList()
                },
                onNext = {
                    val newMonth = visibleMonth.plusMonths(1)
                    visibleMonth = newMonth
                    selectedDates = setOf(newMonth.atDay(1))
                    selectedUris = emptyList()
                },
                onDismiss = onDismiss
            )
            if (pickerMode == MediaPickerSheetMode.Calendar) {
                CalendarMonthGrid(
                    palette = palette,
                    visibleMonth = visibleMonth,
                    selectedDates = selectedDates,
                    itemCountsByDate = itemsByDate.mapValues { it.value.size },
                    onResetToToday = {
                        visibleMonth = YearMonth.now()
                        selectedDates = setOf(LocalDate.now())
                        selectedUris = emptyList()
                    },
                    onClearExtraDates = {
                        selectedDates = setOf(selectedDates.minOrNull() ?: LocalDate.now())
                        selectedUris = emptyList()
                    },
                    onToggleDate = { date ->
                        selectedDates = if (date in selectedDates && selectedDates.size > 1) {
                            selectedDates - date
                        } else {
                            selectedDates + date
                        }
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
                onToggleSortOrder = {
                    sortOrder = sortOrder.next()
                    selectedUris = emptyList()
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
            MediaSelectionSummary(
                palette = palette,
                items = visibleItems,
                selectedUris = selectedUris
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                OutlinedButton(
                    modifier = Modifier.weight(1f).height(48.dp),
                    onClick = onDismiss,
                    border = BorderStroke(1.dp, palette.border),
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = palette.panel,
                        contentColor = palette.text
                    )
                ) {
                    Text("닫기")
                }
                Button(
                    modifier = Modifier.weight(1f).height(48.dp),
                    enabled = selectedUris.isNotEmpty(),
                    onClick = {
                        val orderedUris = selectedUris.mapNotNull { selectedUri ->
                            visibleItems.firstOrNull { it.uri == selectedUri }?.uri
                        }
                        if (orderedUris.size >= BulkImportConfirmationThreshold) {
                            pendingBulkImportUris = orderedUris
                        } else {
                            onImport(orderedUris)
                        }
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = palette.primary,
                        contentColor = Color.White,
                        disabledContainerColor = palette.chip,
                        disabledContentColor = palette.subText
                    )
                ) {
                    Icon(Icons.Outlined.MovieCreation, contentDescription = null)
                    Text(
                        if (selectedUris.isEmpty()) "선택 후 가져오기" else "HanClip 완성본으로 가져오기",
                        fontWeight = FontWeight.Bold
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
                        containerColor = palette.panel,
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
                        onImport(uris)
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
            shape = RoundedCornerShape(8.dp),
            containerColor = palette.panel,
            titleContentColor = palette.text,
            textContentColor = palette.subText,
            title = { Text("HanClip 클립 순서 확인") },
            text = {
                Text(
                    "${selectedMediaSummaryText(visibleItems, uris)}를 선택했습니다. " +
                        "표시된 번호순으로 배치하고, 영상은 스윙 타격점 기준 자동 컷을 준비합니다."
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

private enum class MediaSortOrder(val label: String) {
    NewestFirst("최신순"),
    OldestFirst("오래된순");

    fun next(): MediaSortOrder {
        return if (this == NewestFirst) OldestFirst else NewestFirst
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
            shape = RoundedCornerShape(8.dp),
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
    onResetToToday: () -> Unit,
    onClearExtraDates: () -> Unit,
    onToggleDate: (LocalDate) -> Unit
) {
    val firstDayOffset = (visibleMonth.atDay(1).dayOfWeek.value % 7)
    val days = buildList {
        repeat(firstDayOffset) { add(null) }
        for (day in 1..visibleMonth.lengthOfMonth()) add(visibleMonth.atDay(day))
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = if (selectedDates.size == 1) "선택한 날짜 1일" else "선택한 날짜 ${selectedDates.size}일",
                color = palette.text,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "날짜를 탭해 추가 선택",
                color = palette.subText,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            OutlinedButton(
                modifier = Modifier.height(32.dp),
                onClick = onResetToToday,
                border = BorderStroke(1.dp, palette.border),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = palette.panel,
                    contentColor = palette.text
                )
            ) {
                Text("오늘", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
            }
            OutlinedButton(
                modifier = Modifier.height(32.dp),
                onClick = onClearExtraDates,
                enabled = selectedDates.size > 1,
                border = BorderStroke(1.dp, palette.border),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = palette.panel,
                    contentColor = palette.text,
                    disabledContainerColor = palette.chip,
                    disabledContentColor = palette.subText
                )
            ) {
                Text("선택 해제", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            listOf("일", "월", "화", "수", "목", "금", "토").forEach { label ->
                Text(
                    text = label,
                    modifier = Modifier.weight(1f),
                    color = palette.subText,
                    style = MaterialTheme.typography.labelMedium,
                    textAlign = TextAlign.Center
                )
            }
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(7),
            modifier = Modifier.height(246.dp),
            userScrollEnabled = false,
            verticalArrangement = Arrangement.spacedBy(6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
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
        shape = RoundedCornerShape(8.dp),
        color = if (selected) palette.primary else palette.panel,
        border = BorderStroke(1.dp, if (selected) palette.primary else palette.border)
    ) {
        Box(Modifier.padding(4.dp)) {
            Text(
                text = date.dayOfMonth.toString(),
                color = if (selected) Color.White else palette.text,
                fontWeight = if (date == LocalDate.now()) FontWeight.Black else FontWeight.SemiBold,
                modifier = Modifier.align(Alignment.TopStart)
            )
            if (count > 0) {
                Surface(
                    modifier = Modifier.align(Alignment.BottomEnd),
                    shape = CircleShape,
                    color = if (selected) Color.White.copy(alpha = 0.92f) else palette.chip
                ) {
                    Text(
                        text = count.coerceAtMost(99).toString(),
                        modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp),
                        color = if (selected) palette.primary else palette.subText,
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold
                    )
                }
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
    onToggleSortOrder: () -> Unit,
    onSelectAll: () -> Unit,
    onClearSelection: () -> Unit,
    onToggle: (Uri) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = mediaStripTitle(
                    mode = mode,
                    visibleMonth = visibleMonth,
                    selectedDates = selectedDates,
                    items = items
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
                            containerColor = palette.panel,
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
                            containerColor = palette.panel,
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
        val gridHeight = if (mode == MediaPickerSheetMode.Recent || mode == MediaPickerSheetMode.Videos) {
            374.dp
        } else {
            118.dp
        }
        if (items.isEmpty()) {
            EmptyMediaStrip(
                mode = mode,
                palette = palette,
                modifier = Modifier.height(gridHeight)
            )
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(4),
                modifier = Modifier.height(gridHeight),
                contentPadding = PaddingValues(bottom = 4.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(items, key = { it.uri.toString() }) { item ->
                    CalendarMediaThumb(
                        palette = palette,
                        item = item,
                        selectedOrder = selectedUris.indexOf(item.uri)
                            .takeIf { it >= 0 }
                            ?.plus(1),
                        onClick = { onToggle(item.uri) }
                    )
                }
            }
        }
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
        shape = RoundedCornerShape(8.dp),
        color = if (selectedUris.isEmpty()) palette.panel else palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp)
        ) {
            Text(
                text = if (selectedUris.isEmpty()) {
                    "사진이나 영상을 고르면 HanClip 완성본 순서가 표시됩니다."
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
    palette: HanClipPalette,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = palette.chip,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = if (mode == MediaPickerSheetMode.Videos) {
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
                text = if (mode == MediaPickerSheetMode.Videos) {
                    "이번 달 기본 사진첩에는 영상이 없습니다."
                } else {
                    "이번 달 기본 사진첩에는 사진이나 영상이 없습니다."
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
    items: List<CalendarMediaItem>
): String {
    val photoCount = items.count { it.kind != ClipMediaKind.Video }
    val videoCount = items.count { it.kind == ClipMediaKind.Video }
    val count = items.size
    if (mode == MediaPickerSheetMode.Recent) {
        return if (count == 0) {
            "${visibleMonth.monthValue}월 기본 사진첩에는 사진이나 영상이 없습니다."
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

@Composable
private fun CalendarMediaThumb(
    palette: HanClipPalette,
    item: CalendarMediaItem,
    selectedOrder: Int?,
    onClick: () -> Unit
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
        modifier = Modifier
            .aspectRatio(1f)
            .clip(RoundedCornerShape(8.dp))
            .background(palette.chip)
            .clickable(onClick = onClick)
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
                shape = RoundedCornerShape(6.dp),
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
                            add(
                                CalendarMediaItem(
                                    uri = ContentUris.withAppendedId(collection, id),
                                    date = date,
                                    kind = kind,
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
