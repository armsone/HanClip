package com.hanclip.android.feature.browser

import android.content.Intent
import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import android.app.DownloadManager
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.URLUtil
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Bookmark
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.zIndex
import androidx.core.content.FileProvider
import com.hanclip.android.core.theme.HanClipThemeStore
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlinx.coroutines.delay

private const val PixabayMusicUrl = "https://pixabay.com/music/"
private const val MixkitMusicUrl = "https://mixkit.co/free-stock-music/"

@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
fun OnlineMusicBrowserRoute(
    onClose: () -> Unit
) {
    val context = LocalContext.current
    val hapticFeedback = LocalHapticFeedback.current
    val palette = remember { HanClipThemeStore.load(context).palette }
    var favorites by remember { mutableStateOf(BrowserFavoritesStore.load(context)) }
    var isFavoritePanelVisible by remember { mutableStateOf(false) }
    var isFavoriteManagerVisible by remember { mutableStateOf(false) }
    var targetUrl by remember { mutableStateOf(favorites.firstOrNull() ?: PixabayMusicUrl) }
    var addressText by remember { mutableStateOf(targetUrl) }
    var webView by remember { mutableStateOf<WebView?>(null) }
    var canGoBack by remember { mutableStateOf(false) }
    var canGoForward by remember { mutableStateOf(false) }
    var isPageLoading by remember { mutableStateOf(false) }
    var detectedVideoUrl by remember { mutableStateOf<String?>(null) }
    var dismissedVideoUrl by remember { mutableStateOf<String?>(null) }
    var activeDownload by remember { mutableStateOf<BrowserDownloadTicket?>(null) }
    var downloadProgress by remember { mutableStateOf<BrowserDownloadProgress?>(null) }

    fun beginDownload(
        url: String,
        userAgent: String? = webView?.settings?.userAgentString,
        contentDisposition: String? = null,
        mimeType: String? = null
    ) {
        runCatching {
            enqueueBrowserDownload(
                context = context,
                url = url,
                userAgent = userAgent,
                contentDisposition = contentDisposition,
                mimeType = mimeType
            )
        }.onSuccess { ticket ->
            activeDownload = ticket
            downloadProgress = BrowserDownloadProgress(
                title = ticket.filename,
                downloadedBytes = 0L,
                totalBytes = null,
                status = DownloadManager.STATUS_PENDING
            )
        }.onFailure {
            Toast.makeText(
                context,
                "다운로드를 시작하지 못했습니다. 사이트에서 저장한 뒤 음악/원본 소리의 내 음악 파일 선택을 사용하세요.",
                Toast.LENGTH_LONG
            ).show()
        }
    }

    LaunchedEffect(activeDownload?.id) {
        val ticket = activeDownload ?: return@LaunchedEffect
        val manager = context.getSystemService(DownloadManager::class.java)
            ?: return@LaunchedEffect
        while (activeDownload?.id == ticket.id) {
            val progress = queryBrowserDownload(manager, ticket)
            if (progress != null) downloadProgress = progress
            when (progress?.status) {
                DownloadManager.STATUS_SUCCESSFUL -> {
                    Toast.makeText(
                        context,
                        "Downloads/HanClip에 ${ticket.filename} 저장을 마쳤습니다.",
                        Toast.LENGTH_LONG
                    ).show()
                    activeDownload = null
                }
                DownloadManager.STATUS_FAILED -> {
                    Toast.makeText(context, "다운로드하지 못했습니다.", Toast.LENGTH_LONG).show()
                    activeDownload = null
                }
                else -> delay(300)
            }
        }
    }

    fun loadAddress() {
        targetUrl = normalizedBrowserUrl(addressText)
        isPageLoading = true
    }

    fun closeOrGoBack() {
        val view = webView
        if (view?.canGoBack() == true) {
            view.goBack()
            canGoBack = view.canGoBack()
            canGoForward = view.canGoForward()
        } else {
            onClose()
        }
    }

    fun pasteCopiedAddressAndLoad() {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        val copiedAddress = clipboard
            ?.primaryClip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)
            ?.coerceToText(context)
            ?.toString()
            ?.trim()
            .orEmpty()
        if (copiedAddress.isBlank()) {
            Toast.makeText(context, "복사한 주소가 없습니다.", Toast.LENGTH_SHORT).show()
            return
        }
        addressText = copiedAddress
        targetUrl = normalizedBrowserUrl(copiedAddress)
        isPageLoading = true
    }

    fun toggleCurrentFavorite() {
        val normalized = normalizedBrowserUrl(addressText)
        val isRemoving = normalized in favorites
        favorites = if (isRemoving) {
            favorites.filterNot { it == normalized }
        } else {
            favorites + normalized
        }
        BrowserFavoritesStore.save(context, favorites)
        Toast.makeText(
            context,
            if (isRemoving) "즐겨찾기에서 해제했습니다." else "즐겨찾기에 등록했습니다.",
            Toast.LENGTH_SHORT
        ).show()
    }

    if (isFavoriteManagerVisible) {
        BrowserFavoriteManager(
            favorites = favorites,
            palette = palette,
            onFavoritesChange = { nextFavorites ->
                favorites = nextFavorites
                BrowserFavoritesStore.save(context, nextFavorites)
            },
            onShare = { BrowserFavoritesStore.share(context, favorites) },
            onClose = {
                isFavoriteManagerVisible = false
                isFavoritePanelVisible = false
            }
        )
        return
    }

    BackHandler {
        if (isFavoritePanelVisible) {
            isFavoritePanelVisible = false
        } else {
            val view = webView
            if (view?.canGoBack() == true) {
                view.goBack()
                canGoBack = view.canGoBack()
                canGoForward = view.canGoForward()
            } else {
                onClose()
            }
        }
    }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = palette.solidPanel
    ) {
        BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .combinedClickable(
                            onClick = ::closeOrGoBack,
                            onLongClick = {
                                hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                                onClose()
                            },
                            onLongClickLabel = "브라우저 닫기"
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        if (canGoBack) Icons.AutoMirrored.Outlined.ArrowBack else Icons.Outlined.Close,
                        contentDescription = if (canGoBack) {
                            "이전 페이지, 길게 눌러 브라우저 닫기"
                        } else {
                            "브라우저 닫기"
                        },
                        tint = palette.text
                    )
                }
                OutlinedTextField(
                    modifier = Modifier.weight(1f),
                    value = addressText,
                    onValueChange = { addressText = it },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodySmall,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                    keyboardActions = KeyboardActions(onGo = { loadAddress() })
                )
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .combinedClickable(
                            onClick = {
                                if (isPageLoading) {
                                    webView?.stopLoading()
                                    isPageLoading = false
                                } else {
                                    loadAddress()
                                }
                            },
                            onLongClick = {
                                hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                                pasteCopiedAddressAndLoad()
                            },
                            onLongClickLabel = "복사한 주소로 이동"
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        if (isPageLoading) Icons.Outlined.Close else Icons.AutoMirrored.Outlined.ArrowBack,
                        contentDescription = if (isPageLoading) {
                            "로딩 중지"
                        } else {
                            "주소로 이동, 길게 눌러 복사한 주소로 이동"
                        },
                        tint = palette.text
                    )
                }
                IconButton(onClick = { webView?.reload() }) {
                    Icon(Icons.Outlined.Refresh, contentDescription = "새로고침", tint = palette.text)
                }
                Surface(
                    modifier = Modifier
                        .height(48.dp)
                        .combinedClickable(
                            onClick = { isFavoritePanelVisible = !isFavoritePanelVisible },
                            onLongClick = {
                                hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                                toggleCurrentFavorite()
                            },
                            onLongClickLabel = "현재 주소 즐겨찾기 등록 또는 해제"
                        ),
                    color = Color.Transparent
                ) {
                    Icon(
                        Icons.Outlined.Bookmark,
                        contentDescription = "즐겨찾기 목록, 길게 눌러 현재 주소 등록 또는 해제",
                        tint = if (favorites.contains(normalizedBrowserUrl(addressText))) palette.primary else palette.text
                    )
                }
            }

            detectedVideoUrl?.let { videoUrl ->
                BrowserDetectedVideoPanel(
                    palette = palette,
                    onDownload = {
                        beginDownload(videoUrl, mimeType = "video/mp4")
                        detectedVideoUrl = null
                    },
                    onDismiss = {
                        dismissedVideoUrl = videoUrl
                        detectedVideoUrl = null
                    }
                )
            }
            activeDownload?.let { ticket ->
                BrowserDownloadPanel(
                    title = downloadProgress?.title ?: ticket.filename,
                    downloadedBytes = downloadProgress?.downloadedBytes ?: 0L,
                    totalBytes = downloadProgress?.totalBytes,
                    palette = palette,
                    onCancel = {
                        context.getSystemService(DownloadManager::class.java)?.remove(ticket.id)
                        activeDownload = null
                        downloadProgress = null
                        Toast.makeText(context, "다운로드를 취소했습니다.", Toast.LENGTH_SHORT).show()
                    }
                )
            }

            AndroidView(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                factory = { appContext ->
                    WebView(appContext).apply {
                        webView = this
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.mediaPlaybackRequiresUserGesture = false
                        addJavascriptInterface(
                            BrowserVideoBridge { source ->
                                if (source != dismissedVideoUrl && isDownloadableVideoUrl(source)) {
                                    detectedVideoUrl = source
                                }
                            },
                            "HanClipVideo"
                        )
                        webViewClient = object : WebViewClient() {
                            override fun shouldOverrideUrlLoading(
                                view: WebView,
                                request: WebResourceRequest
                            ): Boolean = false

                            override fun onPageStarted(
                                view: WebView,
                                url: String?,
                                favicon: android.graphics.Bitmap?
                            ) {
                                super.onPageStarted(view, url, favicon)
                                isPageLoading = true
                            }

                            override fun onPageFinished(view: WebView, url: String?) {
                                super.onPageFinished(view, url)
                                isPageLoading = false
                                url?.let {
                                    addressText = it
                                    targetUrl = it
                                }
                                canGoBack = view.canGoBack()
                                canGoForward = view.canGoForward()
                                installBrowserVideoDetection(view)
                            }
                        }
                        setDownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
                            if (isDownloadableVideo(url, mimeType)) {
                                if (url != dismissedVideoUrl) detectedVideoUrl = url
                            } else {
                                beginDownload(url, userAgent, contentDisposition, mimeType)
                            }
                        }
                        loadUrl(targetUrl)
                    }
                },
                update = { view ->
                    if (view.url != targetUrl) {
                        view.loadUrl(targetUrl)
                    }
                }
            )
        }
        if (isFavoritePanelVisible) {
            BrowserFavoritesFloatingPanel(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding()
                    .padding(start = 12.dp, top = 78.dp, end = 12.dp)
                    .zIndex(2f),
                favorites = favorites,
                maxPanelHeight = (maxHeight - 90.dp).coerceAtLeast(136.dp),
                palette = palette,
                onDismiss = { isFavoritePanelVisible = false },
                onManage = { isFavoriteManagerVisible = true },
                onOpen = { favorite ->
                    addressText = favorite
                    targetUrl = favorite
                    isFavoritePanelVisible = false
                },
                onRemove = { favorite ->
                    favorites = favorites.filterNot { it == favorite }
                    BrowserFavoritesStore.save(context, favorites)
                },
                onMakeHome = { favorite ->
                    favorites = listOf(favorite) + favorites.filterNot { it == favorite }
                    BrowserFavoritesStore.save(context, favorites)
                }
            )
        }
        }
    }
}

@Composable
private fun BrowserFavoritesFloatingPanel(
    modifier: Modifier,
    favorites: List<String>,
    maxPanelHeight: androidx.compose.ui.unit.Dp,
    palette: com.hanclip.android.core.theme.HanClipPalette,
    onDismiss: () -> Unit,
    onManage: () -> Unit,
    onOpen: (String) -> Unit,
    onRemove: (String) -> Unit,
    onMakeHome: (String) -> Unit
) {
    val listState = rememberLazyListState()
    val desiredHeight = 64.dp + if (favorites.isEmpty()) 72.dp else (58 * favorites.size).dp
    val panelHeight = minOf(desiredHeight, maxPanelHeight)
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .height(panelHeight),
        shape = androidx.compose.foundation.shape.RoundedCornerShape(20.dp),
        color = palette.solidPanel,
        border = BorderStroke(1.dp, palette.border),
        shadowElevation = 16.dp
    ) {
        Column {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(64.dp)
                    .padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(Icons.Outlined.Bookmark, contentDescription = null, tint = palette.primary)
                    Text(
                        "즐겨찾기 ${favorites.size}개",
                        color = palette.text,
                        fontWeight = FontWeight.Black
                    )
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    OutlinedButton(onClick = onManage) {
                        Text("관리")
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(
                            Icons.Outlined.Close,
                            contentDescription = "즐겨찾기 닫기",
                            tint = palette.text
                        )
                    }
                }
            }
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
            ) {
                if (favorites.isEmpty()) {
                    Text(
                        "등록된 즐겨찾기가 없습니다.",
                        modifier = Modifier
                            .align(Alignment.CenterStart)
                            .padding(horizontal = 14.dp),
                        color = palette.subText
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(start = 8.dp, end = 12.dp, bottom = 8.dp),
                        state = listState,
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        items(favorites, key = { it }) { favorite ->
                            BrowserFavoriteRow(
                                favorite = favorite,
                                isHome = favorite == favorites.firstOrNull(),
                                onOpen = { onOpen(favorite) },
                                onRemove = { onRemove(favorite) },
                                onMakeHome = { onMakeHome(favorite) }
                            )
                        }
                    }
                    if (listState.canScrollBackward || listState.canScrollForward) {
                        BrowserFavoritesScrollbar(
                            modifier = Modifier
                                .align(Alignment.CenterEnd)
                                .fillMaxHeight()
                                .width(5.dp),
                            state = listState,
                            totalItems = favorites.size,
                            trackColor = palette.border.copy(alpha = 0.42f),
                            thumbColor = palette.primary.copy(alpha = 0.78f)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun BrowserFavoritesScrollbar(
    modifier: Modifier,
    state: androidx.compose.foundation.lazy.LazyListState,
    totalItems: Int,
    trackColor: Color,
    thumbColor: Color
) {
    val visibleItems = state.layoutInfo.visibleItemsInfo
    val visibleCount = visibleItems.size.coerceAtLeast(1)
    val scrollableItems = (totalItems - visibleCount).coerceAtLeast(1)
    val firstItemSize = visibleItems.firstOrNull()?.size?.coerceAtLeast(1) ?: 1
    val progress = (
        state.firstVisibleItemIndex + state.firstVisibleItemScrollOffset.toFloat() / firstItemSize
    ).div(scrollableItems).coerceIn(0f, 1f)
    Canvas(modifier = modifier.padding(vertical = 5.dp)) {
        val thumbHeight = (size.height * visibleCount / totalItems.coerceAtLeast(1))
            .coerceAtLeast(24.dp.toPx())
            .coerceAtMost(size.height)
        val thumbTop = (size.height - thumbHeight) * progress
        drawRoundRect(trackColor, cornerRadius = CornerRadius(size.width, size.width))
        drawRoundRect(
            color = thumbColor,
            topLeft = Offset(0f, thumbTop),
            size = Size(size.width, thumbHeight),
            cornerRadius = CornerRadius(size.width, size.width)
        )
    }
}

private data class BrowserDownloadTicket(
    val id: Long,
    val filename: String
)

private data class BrowserDownloadProgress(
    val title: String,
    val downloadedBytes: Long,
    val totalBytes: Long?,
    val status: Int
)

private class BrowserVideoBridge(
    private val onDetected: (String) -> Unit
) {
    private val mainHandler = Handler(Looper.getMainLooper())

    @JavascriptInterface
    fun report(source: String) {
        val normalized = source.trim()
        if (normalized.isNotEmpty()) mainHandler.post { onDetected(normalized) }
    }
}

private fun installBrowserVideoDetection(webView: WebView) {
    webView.evaluateJavascript(
        """
        (() => {
          const report = () => {
            const videos = Array.from(document.querySelectorAll('video'));
            const video = videos.find(item =>
              item.currentSrc || item.src || item.querySelector('source')?.src
            );
            if (!video) return;
            const source = video.currentSrc || video.src ||
              video.querySelector('source')?.src || '';
            if (source) HanClipVideo.report(source);
          };
          report();
          document.addEventListener('loadedmetadata', report, true);
          if (!window.__hanclipVideoObserver) {
            window.__hanclipVideoObserver = new MutationObserver(report);
            window.__hanclipVideoObserver.observe(document.documentElement, {
              childList: true,
              subtree: true,
              attributes: true,
              attributeFilter: ['src']
            });
          }
        })();
        """.trimIndent(),
        null
    )
}

private fun isDownloadableVideo(url: String, mimeType: String?): Boolean =
    mimeType?.lowercase()?.let { it.startsWith("video/") && !it.contains("mpegurl") } == true ||
        isDownloadableVideoUrl(url)

private fun isDownloadableVideoUrl(url: String): Boolean {
    val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return false
    if (uri.scheme !in setOf("http", "https")) return false
    return uri.lastPathSegment
        ?.substringBefore('?')
        ?.substringAfterLast('.', "")
        ?.lowercase() in setOf("mp4", "mov", "m4v", "webm")
}

private fun queryBrowserDownload(
    manager: DownloadManager,
    ticket: BrowserDownloadTicket
): BrowserDownloadProgress? {
    return manager.query(DownloadManager.Query().setFilterById(ticket.id))?.use { cursor ->
        if (!cursor.moveToFirst()) return@use null
        val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
        val downloaded = cursor.getLong(
            cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
        ).coerceAtLeast(0L)
        val rawTotal = cursor.getLong(
            cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
        )
        BrowserDownloadProgress(
            title = ticket.filename,
            downloadedBytes = downloaded,
            totalBytes = rawTotal.takeIf { it > 0L },
            status = status
        )
    }
}

@Composable
private fun BrowserDetectedVideoPanel(
    palette: com.hanclip.android.core.theme.HanClipPalette,
    onDownload: () -> Unit,
    onDismiss: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = androidx.compose.foundation.shape.RoundedCornerShape(8.dp),
        color = palette.solidPanel,
        border = BorderStroke(1.dp, palette.secondary.copy(alpha = 0.22f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp).height(52.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(Icons.Outlined.Download, contentDescription = null, tint = palette.text)
            Text("영상", color = palette.text, fontWeight = FontWeight.Black)
            Spacer(Modifier.weight(1f))
            Button(onClick = onDownload, shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp)) {
                Text("받기")
            }
            OutlinedButton(onClick = onDismiss, shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp)) {
                Text("닫기")
            }
        }
    }
}

@Composable
private fun BrowserDownloadPanel(
    title: String,
    downloadedBytes: Long,
    totalBytes: Long?,
    palette: com.hanclip.android.core.theme.HanClipPalette,
    onCancel: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = androidx.compose.foundation.shape.RoundedCornerShape(10.dp),
        color = palette.solidPanel,
        border = BorderStroke(1.dp, palette.secondary.copy(alpha = 0.32f))
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(9.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "가져오는 중 · $title",
                    modifier = Modifier.weight(1f),
                    color = palette.text,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                IconButton(onClick = onCancel, modifier = Modifier.size(36.dp)) {
                    Icon(Icons.Outlined.Close, contentDescription = "다운로드 취소", tint = palette.primary)
                }
            }
            if (totalBytes != null) {
                LinearProgressIndicator(
                    progress = { (downloadedBytes.toFloat() / totalBytes).coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth(),
                    color = palette.primary,
                    trackColor = palette.secondary.copy(alpha = 0.24f)
                )
            } else {
                LinearProgressIndicator(
                    modifier = Modifier.fillMaxWidth(),
                    color = palette.primary,
                    trackColor = palette.secondary.copy(alpha = 0.24f)
                )
            }
        }
    }
}

private fun enqueueBrowserDownload(
    context: Context,
    url: String,
    userAgent: String?,
    contentDisposition: String?,
    mimeType: String?
): BrowserDownloadTicket {
    val uri = Uri.parse(url)
    val filename = URLUtil.guessFileName(url, contentDisposition, mimeType)
        .ifBlank { "HanClip-download" }
    val request = DownloadManager.Request(uri)
        .setTitle(filename)
        .setDescription("HanClip 브라우저 다운로드")
        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
        .setDestinationInExternalPublicDir(
            Environment.DIRECTORY_DOWNLOADS,
            "HanClip/$filename"
        )
        .setAllowedOverMetered(true)
        .setAllowedOverRoaming(true)
    if (!mimeType.isNullOrBlank()) {
        request.setMimeType(mimeType)
    }
    if (!userAgent.isNullOrBlank()) {
        request.addRequestHeader("User-Agent", userAgent)
    }
    CookieManager.getInstance().getCookie(url)
        ?.takeIf { it.isNotBlank() }
        ?.let { request.addRequestHeader("Cookie", it) }
    val manager = context.getSystemService(DownloadManager::class.java)
        ?: error("다운로드 관리자를 사용할 수 없습니다.")
    return BrowserDownloadTicket(
        id = manager.enqueue(request),
        filename = filename
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BrowserFavoriteRow(
    favorite: String,
    isHome: Boolean,
    onOpen: () -> Unit,
    onMakeHome: () -> Unit,
    onRemove: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Icon(
            Icons.Outlined.Public,
            contentDescription = "짧게 눌러 삭제, 길게 눌러 홈페이지 지정",
            modifier = Modifier.combinedClickable(
                onClick = onRemove,
                onLongClick = onMakeHome,
                onLongClickLabel = "홈페이지로 지정"
            )
        )
        Button(
            modifier = Modifier.weight(1f),
            onClick = onOpen,
            colors = ButtonDefaults.buttonColors(
                containerColor = if (isHome) Color(0xFF0B7A4E) else Color.White,
                contentColor = if (isHome) Color.White else Color(0xFF14221A)
            )
        ) {
            Text(
                text = browserFavoriteTitle(favorite),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        if (isHome) Icon(Icons.Outlined.Home, contentDescription = "홈페이지")
    }
}

@Composable
private fun BrowserFavoriteManager(
    favorites: List<String>,
    palette: com.hanclip.android.core.theme.HanClipPalette,
    onFavoritesChange: (List<String>) -> Unit,
    onShare: () -> Unit,
    onClose: () -> Unit
) {
    BackHandler(onBack = onClose)
    Surface(modifier = Modifier.fillMaxSize(), color = palette.solidPanel) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("즐겨찾기 관리", color = palette.text, fontWeight = FontWeight.Black)
                IconButton(onClick = onClose) {
                    Icon(Icons.Outlined.Close, contentDescription = "즐겨찾기 관리 닫기", tint = palette.text)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { onFavoritesChange(emptyList()) },
                    enabled = favorites.isNotEmpty()
                ) {
                    Icon(Icons.Outlined.Delete, contentDescription = null)
                    Text("전체삭제")
                }
                OutlinedButton(onClick = onShare, enabled = favorites.isNotEmpty()) {
                    Icon(Icons.Outlined.IosShare, contentDescription = null)
                    Text("파일로 저장")
                }
            }
            if (favorites.isEmpty()) {
                Text(
                    "등록된 즐겨찾기가 없습니다.",
                    modifier = Modifier.padding(vertical = 28.dp),
                    color = palette.subText
                )
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    favorites.forEachIndexed { index, favorite ->
                        Surface(
                            modifier = Modifier.fillMaxWidth(),
                            shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp),
                            color = palette.panel,
                            border = BorderStroke(1.dp, palette.border)
                        ) {
                            Row(
                                modifier = Modifier.padding(8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        browserFavoriteTitle(favorite),
                                        color = palette.text,
                                        fontWeight = FontWeight.Bold,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    Text(
                                        favorite,
                                        color = palette.subText,
                                        style = MaterialTheme.typography.labelSmall,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                                IconButton(
                                    onClick = {
                                        val next = favorites.toMutableList()
                                        next.add(index - 1, next.removeAt(index))
                                        onFavoritesChange(next)
                                    },
                                    enabled = index > 0
                                ) {
                                    Icon(Icons.Outlined.KeyboardArrowUp, contentDescription = "위로 이동")
                                }
                                IconButton(
                                    onClick = {
                                        val next = favorites.toMutableList()
                                        next.add(index + 1, next.removeAt(index))
                                        onFavoritesChange(next)
                                    },
                                    enabled = index < favorites.lastIndex
                                ) {
                                    Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = "아래로 이동")
                                }
                                IconButton(onClick = {
                                    onFavoritesChange(favorites.filterNot { it == favorite })
                                }) {
                                    Icon(Icons.Outlined.Delete, contentDescription = "삭제")
                                }
                            }
                        }
                    }
                }
            }
            Text(
                "첫 항목이 브라우저 홈페이지입니다. 위·아래 버튼으로 순서를 바꿀 수 있습니다.",
                color = palette.subText,
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

object BrowserFavoritesStore {
    private const val PreferencesName = "hanclip_browser_preferences"
    private const val FavoritesKey = "favorites"
    const val ArchiveMimeType = "application/vnd.hanclip.browser-favorites+json"
    private const val ArchiveExtension = "hanclipfavorites"
    val DefaultFavorites = listOf(
        PixabayMusicUrl,
        MixkitMusicUrl,
        "https://intosharp.com/"
    )

    fun load(context: Context): List<String> {
        val preferences = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
        if (!preferences.contains(FavoritesKey)) return DefaultFavorites
        val raw = preferences.getString(FavoritesKey, "").orEmpty()
        return raw
            .split('\n')
            .map { it.trim() }
            .filter { it.isNotBlank() }
    }

    fun save(context: Context, favorites: List<String>) {
        val normalized = favorites
            .map(::normalizedBrowserUrl)
            .distinct()
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .putString(FavoritesKey, normalized.joinToString("\n"))
            .apply()
    }

    fun merge(context: Context, importedFavorites: List<String>): BrowserFavoritesMergeResult {
        val merged = mutableListOf<String>()
        val indexByAddress = mutableMapOf<String, Int>()

        load(context).forEach { value ->
            val normalized = normalizedBrowserUrl(value)
            val key = browserFavoriteAddressKey(normalized) ?: return@forEach
            indexByAddress[key] = merged.size
            merged.add(normalized)
        }

        var addedCount = 0
        var replacedCount = 0
        importedFavorites.forEach { value ->
            val normalized = normalizedBrowserUrl(value)
            val key = browserFavoriteAddressKey(normalized) ?: return@forEach
            val existingIndex = indexByAddress[key]
            if (existingIndex == null) {
                indexByAddress[key] = merged.size
                merged.add(normalized)
                addedCount += 1
            } else {
                if (merged[existingIndex] != normalized) {
                    replacedCount += 1
                }
                merged[existingIndex] = normalized
            }
        }

        save(context, merged)
        return BrowserFavoritesMergeResult(
            addedCount = addedCount,
            replacedCount = replacedCount,
            totalCount = merged.size
        )
    }

    fun parseArchive(context: Context, uri: Uri): List<String> {
        val text = if (uri.scheme == "file") {
            uri.path?.let { path ->
                runCatching { File(path).readText() }.getOrNull()
            }
        } else {
            context.contentResolver.openInputStream(uri)?.use { input ->
                input.bufferedReader().use { it.readText() }
            }
        }.orEmpty()
        if (text.isBlank()) return emptyList()
        val json = JSONObject(text)
        val favorites = json.optJSONArray("favorites") ?: JSONArray()
        return List(favorites.length()) { index ->
            favorites.optString(index)
        }.filter { it.isNotBlank() }
    }

    fun share(context: Context, favorites: List<String>) {
        val archive = JSONObject()
            .put("version", 1)
            .put("favorites", JSONArray().also { array ->
                favorites.map(::normalizedBrowserUrl).distinct().forEach(array::put)
            })
            .toString(2)
        val directory = File(context.cacheDir, "browser-favorites").apply { mkdirs() }
        val file = File(directory, "HanClip-Favorites.$ArchiveExtension")
        file.writeText(archive)
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file
        )
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = ArchiveMimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newUri(context.contentResolver, "HanClip Favorites", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "HanClip 즐겨찾기 공유"))
    }
}

data class BrowserFavoritesMergeResult(
    val addedCount: Int,
    val replacedCount: Int,
    val totalCount: Int
)

private fun normalizedBrowserUrl(raw: String): String {
    val trimmed = raw.trim()
    if (trimmed.isBlank()) return PixabayMusicUrl
    if (URLUtil.isNetworkUrl(trimmed)) return trimmed
    if (trimmed.contains(".") && !trimmed.contains(" ")) return "https://$trimmed"
    return "https://www.google.com/search?q=" + Uri.encode("$trimmed free music")
}

private fun browserFavoriteTitle(url: String): String {
    val uri = Uri.parse(url)
    val host = uri.host.orEmpty().ifBlank { return url }
    val path = uri.path.orEmpty().trim('/')
    return if (path.isBlank()) host else "$host/$path"
}

private fun browserFavoriteAddressKey(url: String): String? {
    val normalized = normalizedBrowserUrl(url)
    val uri = Uri.parse(normalized)
    val scheme = uri.scheme?.lowercase()?.takeIf { it == "http" || it == "https" }
        ?: return null
    val host = uri.host?.lowercase()?.removePrefix("www.") ?: return null
    val path = uri.path.orEmpty().trimEnd('/').ifBlank { "/" }
    return "$scheme://$host$path"
}
