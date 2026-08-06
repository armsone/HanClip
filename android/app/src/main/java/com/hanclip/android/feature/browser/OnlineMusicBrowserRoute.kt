package com.hanclip.android.feature.browser

import android.content.Intent
import android.content.Context
import android.content.ClipData
import android.app.DownloadManager
import android.net.Uri
import android.os.Environment
import android.webkit.CookieManager
import android.webkit.URLUtil
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.FileProvider
import com.hanclip.android.core.theme.HanClipThemeStore
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

private const val PixabayMusicUrl = "https://pixabay.com/music/"
private const val MixkitMusicUrl = "https://mixkit.co/free-stock-music/"

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OnlineMusicBrowserRoute(
    onClose: () -> Unit
) {
    val context = LocalContext.current
    val palette = remember { HanClipThemeStore.load(context).palette }
    var favorites by remember { mutableStateOf(BrowserFavoritesStore.load(context)) }
    var isFavoritePanelVisible by remember { mutableStateOf(false) }
    var targetUrl by remember { mutableStateOf(favorites.firstOrNull() ?: PixabayMusicUrl) }
    var addressText by remember { mutableStateOf(targetUrl) }
    var webView by remember { mutableStateOf<WebView?>(null) }
    var canGoBack by remember { mutableStateOf(false) }
    var canGoForward by remember { mutableStateOf(false) }

    fun loadAddress() {
        targetUrl = normalizedBrowserUrl(addressText)
    }

    BackHandler {
        val view = webView
        if (view?.canGoBack() == true) {
            view.goBack()
            canGoBack = view.canGoBack()
            canGoForward = view.canGoForward()
        } else {
            onClose()
        }
    }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = palette.panel
    ) {
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
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                IconButton(onClick = onClose) {
                    Icon(Icons.Outlined.Close, contentDescription = "브라우저 닫기", tint = palette.text)
                }
                Column(Modifier.weight(1f)) {
                    Text(
                        text = "음악 찾기",
                        color = palette.text,
                        fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.titleLarge
                    )
                    Text(
                        text = "다운로드 후 음악/원본 소리에서 내 음악 파일로 적용합니다",
                        color = palette.subText,
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                IconButton(
                    enabled = canGoBack,
                    onClick = {
                        webView?.goBack()
                        canGoBack = webView?.canGoBack() == true
                        canGoForward = webView?.canGoForward() == true
                    }
                ) {
                    Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "이전 페이지", tint = palette.text)
                }
                IconButton(
                    enabled = canGoForward,
                    onClick = {
                        webView?.goForward()
                        canGoBack = webView?.canGoBack() == true
                        canGoForward = webView?.canGoForward() == true
                    }
                ) {
                    Icon(Icons.AutoMirrored.Outlined.ArrowForward, contentDescription = "다음 페이지", tint = palette.text)
                }
            }

            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                AssistChip(
                    onClick = {
                        addressText = favorites.firstOrNull() ?: PixabayMusicUrl
                        targetUrl = addressText
                    },
                    leadingIcon = { Icon(Icons.Outlined.Home, contentDescription = null) },
                    label = { Text("첫 페이지") },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = palette.chip,
                        labelColor = palette.text,
                        leadingIconContentColor = palette.primary
                    ),
                    border = BorderStroke(1.dp, palette.border)
                )
                AssistChip(
                    onClick = {
                        isFavoritePanelVisible = !isFavoritePanelVisible
                    },
                    leadingIcon = { Icon(Icons.Outlined.Public, contentDescription = null) },
                    label = { Text("즐겨찾기") },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = palette.chip,
                        labelColor = palette.text,
                        leadingIconContentColor = palette.primary
                    ),
                    border = BorderStroke(1.dp, palette.border)
                )
                AssistChip(
                    onClick = {
                        val normalized = normalizedBrowserUrl(addressText)
                        val nextFavorites = if (favorites.contains(normalized)) {
                            favorites.filterNot { it == normalized }
                        } else {
                            favorites + normalized
                        }
                        favorites = nextFavorites
                        BrowserFavoritesStore.save(context, nextFavorites)
                    },
                    leadingIcon = { Icon(Icons.Outlined.Download, contentDescription = null) },
                    label = {
                        Text(
                            if (favorites.contains(normalizedBrowserUrl(addressText))) {
                                "즐겨찾기 해제"
                            } else {
                                "즐겨찾기 추가"
                            }
                        )
                    },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = palette.panel,
                        labelColor = palette.text,
                        leadingIconContentColor = palette.secondary
                    ),
                    border = BorderStroke(1.dp, palette.border)
                )
                AssistChip(
                    onClick = {
                        BrowserFavoritesStore.share(context, favorites)
                    },
                    leadingIcon = { Icon(Icons.Outlined.IosShare, contentDescription = null) },
                    label = { Text("공유") },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = palette.panel,
                        labelColor = palette.text,
                        leadingIconContentColor = palette.secondary
                    ),
                    border = BorderStroke(1.dp, palette.border)
                )
            }

            if (isFavoritePanelVisible) {
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    color = palette.chip,
                    border = BorderStroke(1.dp, palette.border)
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(164.dp)
                            .verticalScroll(rememberScrollState())
                            .padding(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        favorites.forEach { favorite ->
                            BrowserFavoriteRow(
                                favorite = favorite,
                                isHome = favorite == favorites.firstOrNull(),
                                onOpen = {
                                    addressText = favorite
                                    targetUrl = favorite
                                    isFavoritePanelVisible = false
                                },
                                onMakeHome = {
                                    val nextFavorites = listOf(favorite) + favorites.filterNot { it == favorite }
                                    favorites = nextFavorites
                                    BrowserFavoritesStore.save(context, nextFavorites)
                                },
                                onRemove = {
                                    val nextFavorites = favorites.filterNot { it == favorite }
                                    favorites = nextFavorites.ifEmpty { BrowserFavoritesStore.DefaultFavorites }
                                    BrowserFavoritesStore.save(context, favorites)
                                }
                            )
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    modifier = Modifier.weight(1f),
                    value = addressText,
                    onValueChange = { addressText = it },
                    singleLine = true,
                    label = { Text("주소 또는 검색어") },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                    keyboardActions = KeyboardActions(onGo = { loadAddress() })
                )
                Button(
                    modifier = Modifier.height(56.dp),
                    onClick = ::loadAddress,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = palette.primary,
                        contentColor = Color.White
                    )
                ) {
                    Icon(Icons.Outlined.Search, contentDescription = null)
                    Text("이동")
                }
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
                        webViewClient = object : WebViewClient() {
                            override fun shouldOverrideUrlLoading(
                                view: WebView,
                                request: WebResourceRequest
                            ): Boolean = false

                            override fun onPageFinished(view: WebView, url: String?) {
                                super.onPageFinished(view, url)
                                url?.let {
                                    addressText = it
                                    targetUrl = it
                                }
                                canGoBack = view.canGoBack()
                                canGoForward = view.canGoForward()
                            }
                        }
                        setDownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
                            runCatching {
                                enqueueBrowserDownload(
                                    context = context,
                                    url = url,
                                    userAgent = userAgent,
                                    contentDisposition = contentDisposition,
                                    mimeType = mimeType
                                )
                                Toast.makeText(
                                    context,
                                    "Downloads/HanClip 폴더에 저장을 시작했습니다. 완료 후 음악/원본 소리에서 내 음악 파일 선택으로 적용하세요.",
                                    Toast.LENGTH_LONG
                                ).show()
                            }.onFailure {
                                Toast.makeText(
                                    context,
                                    "다운로드를 시작하지 못했습니다. 사이트에서 저장한 뒤 음악/원본 소리의 내 음악 파일 선택을 사용하세요.",
                                    Toast.LENGTH_LONG
                                ).show()
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
    }
}

private fun enqueueBrowserDownload(
    context: Context,
    url: String,
    userAgent: String?,
    contentDisposition: String?,
    mimeType: String?
) {
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
    manager.enqueue(request)
}

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
        OutlinedButton(onClick = onMakeHome, enabled = !isHome) {
            Text("홈")
        }
        OutlinedButton(onClick = onRemove) {
            Text("삭제")
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
        val raw = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .getString(FavoritesKey, null)
            .orEmpty()
        return raw
            .split('\n')
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .ifEmpty { DefaultFavorites }
    }

    fun save(context: Context, favorites: List<String>) {
        val normalized = favorites
            .map(::normalizedBrowserUrl)
            .distinct()
            .ifEmpty { DefaultFavorites }
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
