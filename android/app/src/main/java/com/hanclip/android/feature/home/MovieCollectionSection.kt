package com.hanclip.android.feature.home

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.hanclip.android.core.project.CollectedMovie
import com.hanclip.android.core.project.MovieCollectionStore
import com.hanclip.android.core.theme.HanClipPalette
import java.text.SimpleDateFormat
import java.io.File
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

internal fun LazyListScope.movieCollectionItems(
    palette: HanClipPalette,
    movies: List<CollectedMovie>,
    isImporting: Boolean,
    importCompletedCount: Int,
    importTotalCount: Int,
    onImport: () -> Unit,
    onCancelImport: () -> Unit,
    onOpen: (CollectedMovie) -> Unit,
    onRename: (CollectedMovie, String) -> Unit,
    onRemove: (CollectedMovie) -> Unit
) {
    item(key = "collection-header", contentType = "collection-header") {
        CollectionHeader(movies.size, palette)
    }

    val cells = buildList<CollectedMovie?> {
        addAll(movies)
        add(null)
        if (size % 2 != 0) add(CollectionSpacer)
    }
    items(
        items = cells.chunked(2),
        key = { row -> "collection-row:${row.joinToString { it?.id ?: "add" }}" },
        contentType = { "collection-row" }
    ) { row ->
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            row.forEach { movie ->
                when {
                    movie === CollectionSpacer -> Spacer(Modifier.weight(1f))
                    movie == null -> CollectionImportCard(
                        modifier = Modifier.weight(1f),
                        isImporting = isImporting,
                        onClick = onImport,
                        palette = palette
                    )
                    else -> CollectionMovieCard(
                        modifier = Modifier.weight(1f),
                        movie = movie,
                        onOpen = { onOpen(movie) },
                        onRename = { onRename(movie, it) },
                        onRemove = { onRemove(movie) },
                        palette = palette
                    )
                }
            }
        }
    }

    if (isImporting) {
        item(key = "collection-import-progress", contentType = "collection-progress") {
            CollectionImportProgress(
                completed = importCompletedCount,
                total = importTotalCount,
                onCancel = onCancelImport,
                palette = palette
            )
        }
    }

    item(key = "collection-shelf-edge", contentType = "collection-shelf-edge") {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 2.dp, vertical = 3.dp)
                .height(9.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(
                    Brush.horizontalGradient(
                        listOf(
                            palette.primary.copy(alpha = 0.76f),
                            palette.secondary.copy(alpha = 0.50f),
                            palette.primary.copy(alpha = 0.70f)
                        )
                    )
                )
        )
    }
}

private val CollectionSpacer = CollectedMovie(
    id = "__spacer__",
    title = "",
    videoFilename = "",
    posterFilename = "",
    createdAtMillis = 0,
    durationSeconds = 0.0,
    madeAtMillis = null,
    shootingStartAtMillis = null,
    shootingEndAtMillis = null,
    locationName = null
)

@Composable
private fun CollectionHeader(count: Int, palette: HanClipPalette) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 10.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Surface(
            modifier = Modifier.size(27.dp),
            shape = RoundedCornerShape(7.dp),
            color = palette.primary
        ) {
            Icon(
                Icons.Outlined.FolderOpen,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.padding(6.dp)
            )
        }
        Text(
            text = "컬렉션",
            color = palette.text,
            fontWeight = FontWeight.Bold,
            fontSize = 14.sp
        )
        Surface(shape = RoundedCornerShape(50), color = palette.chip) {
            Text(
                text = count.toString(),
                modifier = Modifier.padding(horizontal = 9.dp, vertical = 4.dp),
                color = palette.primary,
                fontWeight = FontWeight.Bold,
                fontSize = 11.sp
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CollectionImportCard(
    modifier: Modifier,
    isImporting: Boolean,
    onClick: () -> Unit,
    palette: HanClipPalette
) {
    val shape = RoundedCornerShape(12.dp)
    Box(
        modifier = modifier
            .aspectRatio(1f / 1.38f)
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(
                        palette.solidPanel,
                        palette.secondary.copy(alpha = 0.15f),
                        palette.primary.copy(alpha = 0.18f)
                    )
                )
            )
            .border(1.dp, palette.secondary.copy(alpha = 0.40f), shape)
            .combinedClickable(enabled = !isImporting, onClick = onClick, onLongClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                "HANCLIP",
                color = palette.secondary,
                fontWeight = FontWeight.Bold,
                fontSize = 9.sp,
                letterSpacing = 3.sp
            )
            Box(
                Modifier
                    .width(58.dp)
                    .height(1.dp)
                    .background(palette.secondary.copy(alpha = 0.46f))
            )
            Icon(
                Icons.Outlined.Add,
                contentDescription = null,
                tint = palette.secondary,
                modifier = Modifier.size(34.dp)
            )
            Text(
                if (isImporting) "IMPORTING" else "ADD A FILM",
                color = palette.secondary,
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp,
                letterSpacing = 1.1.sp
            )
            Text(
                "COLLECTION",
                color = palette.secondary.copy(alpha = 0.72f),
                fontWeight = FontWeight.SemiBold,
                fontSize = 8.sp,
                letterSpacing = 2.2.sp
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CollectionMovieCard(
    modifier: Modifier,
    movie: CollectedMovie,
    onOpen: () -> Unit,
    onRename: (String) -> Unit,
    onRemove: () -> Unit,
    palette: HanClipPalette
) {
    val context = LocalContext.current
    var showActions by remember { mutableStateOf(false) }
    var showRename by remember { mutableStateOf(false) }
    var showRemove by remember { mutableStateOf(false) }
    var titleDraft by remember(movie.id, movie.title) { mutableStateOf(movie.title) }
    val posterFile = MovieCollectionStore.posterFile(context, movie)
    val targetLongEdgePx = with(LocalDensity.current) { 240.dp.roundToPx() }
    val poster by produceState<android.graphics.Bitmap?>(
        initialValue = null,
        movie.id,
        movie.posterFilename,
        posterFile.lastModified(),
        targetLongEdgePx
    ) {
        value = withContext(Dispatchers.IO) {
            decodeSampledPoster(posterFile, targetLongEdgePx)
        }
    }
    val shape = RoundedCornerShape(12.dp)

    Box(
        modifier = modifier
            .aspectRatio(1f / 1.38f)
            .clip(shape)
            .background(palette.solidPanel)
            .border(1.dp, Color.White.copy(alpha = 0.34f), shape)
            .combinedClickable(onClick = onOpen, onLongClick = { showActions = true })
    ) {
        poster?.let { posterBitmap ->
            androidx.compose.foundation.Image(
                bitmap = posterBitmap.asImageBitmap(),
                contentDescription = movie.title,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
        }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Black.copy(alpha = 0.70f),
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.18f),
                            Color.Black.copy(alpha = 0.90f)
                        )
                    )
                )
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(8.dp),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = movie.title,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 14.sp,
                lineHeight = 17.sp,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                movie.madeAtMillis?.let {
                    PosterMetadata(Icons.Outlined.AutoAwesome, "제작 ${collectionDateTime(it)}")
                }
                shootingPeriod(movie)?.let {
                    PosterMetadata(Icons.Outlined.CalendarMonth, it)
                }
                movie.locationName?.takeIf(String::isNotBlank)?.let {
                    PosterMetadata(Icons.Outlined.LocationOn, it, maxLines = 2)
                }
                PosterMetadata(Icons.Outlined.PlayArrow, collectionDuration(movie.durationSeconds))
            }
        }
        IconButton(
            onClick = { showActions = true },
            modifier = Modifier.align(Alignment.TopEnd).size(38.dp)
        ) {
            Icon(Icons.Outlined.MoreVert, contentDescription = "컬렉션 메뉴", tint = Color.White)
        }
        DropdownMenu(
            expanded = showActions,
            onDismissRequest = { showActions = false },
            shape = RoundedCornerShape(16.dp),
            containerColor = palette.solidPanel
        ) {
            DropdownMenuItem(
                text = { Text("제목 수정") },
                leadingIcon = { Icon(Icons.Outlined.Edit, contentDescription = null) },
                onClick = { showActions = false; showRename = true }
            )
            DropdownMenuItem(
                text = { Text("공유") },
                leadingIcon = { Icon(Icons.Outlined.Share, contentDescription = null) },
                onClick = { showActions = false; shareMovie(context, movie) }
            )
            DropdownMenuItem(
                text = { Text("컬렉션에서 제거") },
                leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null) },
                onClick = { showActions = false; showRemove = true }
            )
        }
    }

    if (showRename) {
        AlertDialog(
            onDismissRequest = { showRename = false },
            shape = RoundedCornerShape(20.dp),
            containerColor = palette.solidPanel,
            title = { Text("포스터 제목") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("포스터에 표시할 제목을 입력하세요.", color = palette.subText)
                    TextField(
                        value = titleDraft,
                        onValueChange = { titleDraft = it.take(120) },
                        minLines = 2,
                        maxLines = 5
                    )
                }
            },
            dismissButton = {
                OutlinedButton(onClick = { showRename = false }) { Text("취소") }
            },
            confirmButton = {
                Button(
                    enabled = titleDraft.isNotBlank(),
                    onClick = { onRename(titleDraft); showRename = false },
                    colors = ButtonDefaults.buttonColors(containerColor = palette.primary)
                ) { Text("저장") }
            }
        )
    }
    if (showRemove) {
        AlertDialog(
            onDismissRequest = { showRemove = false },
            shape = RoundedCornerShape(20.dp),
            containerColor = palette.solidPanel,
            title = { Text("컬렉션에서 제거") },
            text = { Text("앱 컬렉션에 보관한 영상과 포스터를 삭제합니다. 원래 사진첩이나 파일의 영상은 삭제하지 않습니다.") },
            dismissButton = {
                OutlinedButton(onClick = { showRemove = false }) { Text("취소") }
            },
            confirmButton = {
                Button(
                    onClick = { showRemove = false; onRemove() },
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE45D42))
                ) { Text("제거") }
            }
        )
    }
}

private fun decodeSampledPoster(file: File, targetLongEdgePx: Int): android.graphics.Bitmap? {
    if (!file.isFile) return null
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(file.absolutePath, bounds)
    val sourceLongEdge = maxOf(bounds.outWidth, bounds.outHeight)
    if (sourceLongEdge <= 0) return null
    var sampleSize = 1
    while (sourceLongEdge / (sampleSize * 2) >= targetLongEdgePx) {
        sampleSize *= 2
    }
    return BitmapFactory.decodeFile(
        file.absolutePath,
        BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = android.graphics.Bitmap.Config.RGB_565
        }
    )
}

@Composable
private fun PosterMetadata(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
    maxLines: Int = 1
) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(icon, contentDescription = null, tint = Color.White.copy(alpha = 0.84f), modifier = Modifier.size(12.dp))
        Text(
            text = text,
            color = Color.White.copy(alpha = 0.84f),
            fontSize = 10.sp,
            lineHeight = 12.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = maxLines,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun CollectionImportProgress(
    completed: Int,
    total: Int,
    onCancel: () -> Unit,
    palette: HanClipPalette
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = palette.solidPanel,
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("컬렉션으로 가져오는 중", color = palette.text, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                Text("$completed/$total", color = palette.subText, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(6.dp))
                OutlinedButton(
                    onClick = onCancel,
                    shape = RoundedCornerShape(10.dp),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(
                        horizontal = 10.dp,
                        vertical = 4.dp
                    )
                ) {
                    Text("취소", color = palette.text, fontSize = 12.sp)
                }
            }
            androidx.compose.material3.LinearProgressIndicator(
                progress = { if (total <= 0) 0f else completed.toFloat() / total.toFloat() },
                modifier = Modifier.fillMaxWidth(),
                color = palette.primary,
                trackColor = palette.chip
            )
        }
    }
}

private fun shareMovie(context: Context, movie: CollectedMovie) {
    val file = MovieCollectionStore.videoUri(context, movie).path?.let(::File) ?: return
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "video/*"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "영화 공유"))
}

private fun collectionDateTime(millis: Long): String =
    SimpleDateFormat("yy.M.d HH:mm", Locale.KOREAN).format(Date(millis))

private fun shootingPeriod(movie: CollectedMovie): String? {
    val start = movie.shootingStartAtMillis ?: return null
    val end = movie.shootingEndAtMillis ?: start
    val formatter = SimpleDateFormat("yy.M.d", Locale.KOREAN)
    val startText = formatter.format(Date(start))
    val endText = formatter.format(Date(end))
    return if (startText == endText) "촬영 $startText" else "촬영 $startText–$endText"
}

private fun collectionDuration(durationSeconds: Double): String {
    val seconds = durationSeconds.toInt().coerceAtLeast(0)
    return "%d:%02d".format(Locale.US, seconds / 60, seconds % 60)
}
