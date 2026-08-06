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
    title: String = "날짜별",
    palette: HanClipPalette,
    onDismiss: () -> Unit,
    onImport: (List<Uri>) -> Unit
) {
    val context = LocalContext.current
    val pickerMode = remember(title) {
        when (title) {
            "기본 사진첩" -> MediaPickerSheetMode.Recent
            "영상만" -> MediaPickerSheetMode.Videos
            else -> MediaPickerSheetMode.Calendar
        }
    }
    var visibleMonth by remember { mutableStateOf(YearMonth.now()) }
    var selectedDate by remember { mutableStateOf(LocalDate.now()) }
    var selectedUris by remember { mutableStateOf<List<Uri>>(emptyList()) }
    var pendingBulkImportUris by remember { mutableStateOf<List<Uri>?>(null) }
    var sortOrder by remember { mutableStateOf(MediaSortOrder.NewestFirst) }
    val monthItems by produceState<List<CalendarMediaItem>>(emptyList(), visibleMonth) {
        value = CalendarMediaRepository.loadMonth(context, visibleMonth)
    }
    val itemsByDate = remember(monthItems) { monthItems.groupBy { it.date } }
    val selectedItems = remember(monthItems, selectedDate, sortOrder) {
        itemsByDate[selectedDate].orEmpty().sortedBySortOrder(sortOrder)
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
                    selectedDate = newMonth.atDay(1)
                    selectedUris = emptyList()
                },
                onNext = {
                    val newMonth = visibleMonth.plusMonths(1)
                    visibleMonth = newMonth
                    selectedDate = newMonth.atDay(1)
                    selectedUris = emptyList()
                },
                onDismiss = onDismiss
            )
            if (pickerMode == MediaPickerSheetMode.Calendar) {
                CalendarMonthGrid(
                    palette = palette,
                    visibleMonth = visibleMonth,
                    selectedDate = selectedDate,
                    itemCountsByDate = itemsByDate.mapValues { it.value.size },
                    onSelectDate = {
                        selectedDate = it
                        selectedUris = emptyList()
                    }
                )
            }
            CalendarMediaStrip(
                palette = palette,
                mode = pickerMode,
                visibleMonth = visibleMonth,
                selectedDate = selectedDate,
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
                    Text("가져오기 ${selectedUris.size}개", fontWeight = FontWeight.Bold)
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
                    Text("가져오기")
                }
            },
            shape = RoundedCornerShape(8.dp),
            containerColor = palette.panel,
            titleContentColor = palette.text,
            textContentColor = palette.subText,
            title = { Text("많은 미디어 가져오기") },
            text = { Text("${uris.size}개를 선택했습니다. 선택한 순서대로 클립을 만들까요?") }
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
                    "${visibleMonth.format(DateTimeFormatter.ofPattern("yyyy년 M월", Locale.KOREAN))} ${sortOrder.label}"
                } else {
                    visibleMonth.format(DateTimeFormatter.ofPattern("yyyy년 M월", Locale.KOREAN))
                },
                color = palette.subText,
                style = MaterialTheme.typography.bodySmall
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
    selectedDate: LocalDate,
    itemCountsByDate: Map<LocalDate, Int>,
    onSelectDate: (LocalDate) -> Unit
) {
    val firstDayOffset = (visibleMonth.atDay(1).dayOfWeek.value % 7)
    val days = buildList {
        repeat(firstDayOffset) { add(null) }
        for (day in 1..visibleMonth.lengthOfMonth()) add(visibleMonth.atDay(day))
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
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
                        selected = date == selectedDate,
                        count = itemCountsByDate[date] ?: 0,
                        onClick = { onSelectDate(date) }
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
    selectedDate: LocalDate,
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
                    selectedDate = selectedDate,
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
                            if (selectedUris.size == items.size) "해제" else "전체 선택",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(4),
            modifier = Modifier.height(
                if (mode == MediaPickerSheetMode.Recent || mode == MediaPickerSheetMode.Videos) {
                    374.dp
                } else {
                    118.dp
                }
            ),
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

private fun mediaStripTitle(
    mode: MediaPickerSheetMode,
    visibleMonth: YearMonth,
    selectedDate: LocalDate,
    items: List<CalendarMediaItem>
): String {
    val photoCount = items.count { it.kind != ClipMediaKind.Video }
    val videoCount = items.count { it.kind == ClipMediaKind.Video }
    val count = items.size
    if (mode == MediaPickerSheetMode.Recent) {
        return if (count == 0) {
            "${visibleMonth.monthValue}월에는 사진이나 영상이 없습니다."
        } else {
            mediaCountText("이번 달", photoCount, videoCount)
        }
    }
    if (mode == MediaPickerSheetMode.Videos) {
        return if (count == 0) {
            "${visibleMonth.monthValue}월에는 영상이 없습니다."
        } else {
            "이번 달 영상 ${videoCount}개"
        }
    }
    return if (count == 0) {
        "이 날짜에는 사진이나 영상이 없습니다."
    } else {
        mediaCountText("${selectedDate.dayOfMonth}일", photoCount, videoCount)
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
