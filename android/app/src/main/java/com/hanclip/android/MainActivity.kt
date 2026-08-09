package com.hanclip.android

import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.hanclip.android.core.navigation.HanClipQuickAction
import com.hanclip.android.core.theme.HanClipTheme
import com.hanclip.android.feature.browser.BrowserFavoritesStore

class MainActivity : ComponentActivity() {
    private var sharedMediaUris by mutableStateOf<List<Uri>>(emptyList())
    private var sharedBrowserFavorites by mutableStateOf<List<String>>(emptyList())
    private var sharedBrowserFavoritesImportAttempted by mutableStateOf(false)
    private var quickAction by mutableStateOf<HanClipQuickAction?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.WHITE
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }
        sharedMediaUris = extractSharedMediaUris()
        sharedBrowserFavoritesImportAttempted = hasBrowserFavoritesArchiveIntent()
        sharedBrowserFavorites = extractSharedBrowserFavorites()
        quickAction = intent.extractQuickAction()
        setContent {
            HanClipTheme {
                HanClipApp(
                    sharedMediaUris = sharedMediaUris,
                    sharedBrowserFavorites = sharedBrowserFavorites,
                    sharedBrowserFavoritesImportAttempted = sharedBrowserFavoritesImportAttempted,
                    quickAction = quickAction,
                    onSharedBrowserFavoritesHandled = {
                        sharedBrowserFavorites = emptyList()
                        sharedBrowserFavoritesImportAttempted = false
                    },
                    onQuickActionHandled = ::clearHandledQuickAction,
                    onKeepScreenOnChanged = ::setKeepScreenOn
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sharedMediaUris = extractSharedMediaUris()
        sharedBrowserFavoritesImportAttempted = hasBrowserFavoritesArchiveIntent()
        sharedBrowserFavorites = extractSharedBrowserFavorites()
        quickAction = intent.extractQuickAction()
            ?: if (intent.isLauncherLaunch()) HanClipQuickAction.Open else null
    }

    private fun clearHandledQuickAction() {
        quickAction = null
        if (intent.extractQuickAction() != null) {
            setIntent(
                Intent(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_LAUNCHER)
                    .setClass(this, MainActivity::class.java)
            )
        }
    }

    private fun setKeepScreenOn(shouldKeepScreenOn: Boolean) {
        if (shouldKeepScreenOn) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onDestroy() {
        setKeepScreenOn(false)
        super.onDestroy()
    }
}

private fun Intent?.extractQuickAction(): HanClipQuickAction? {
    if (this?.action != Intent.ACTION_VIEW) return null
    return HanClipQuickAction.fromUri(data)
}

private fun Intent?.isLauncherLaunch(): Boolean {
    return this?.action == Intent.ACTION_MAIN && hasCategory(Intent.CATEGORY_LAUNCHER)
}

private fun MainActivity.extractSharedMediaUris(): List<Uri> {
    val intent = intent ?: return emptyList()
    if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
        return emptyList()
    }
    return intent.extractSharedUris()
        .filterNot { uri -> isBrowserFavoritesArchive(uri) }
}

private fun MainActivity.extractSharedBrowserFavorites(): List<String> {
    val intent = intent ?: return emptyList()
    if (intent.action == Intent.ACTION_VIEW && intent.data != null) {
        val uri = intent.data ?: return emptyList()
        if (!isBrowserFavoritesArchive(uri)) return emptyList()
        return runCatching {
            BrowserFavoritesStore.parseArchive(this, uri)
        }.getOrDefault(emptyList())
    }
    if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
        return emptyList()
    }
    return intent.extractSharedUris()
        .filter(::isBrowserFavoritesArchive)
        .flatMap { uri ->
            runCatching {
                BrowserFavoritesStore.parseArchive(this, uri)
            }.getOrDefault(emptyList())
        }
        .distinct()
}

private fun MainActivity.hasBrowserFavoritesArchiveIntent(): Boolean {
    val intent = intent ?: return false
    if (intent.action == Intent.ACTION_VIEW && intent.data != null) {
        return isBrowserFavoritesArchive(intent.data ?: return false)
    }
    if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
        return false
    }
    return intent.extractSharedUris().any(::isBrowserFavoritesArchive)
}

private fun MainActivity.isBrowserFavoritesArchive(uri: Uri): Boolean {
    val type = contentResolver.getType(uri).orEmpty()
    return type == BrowserFavoritesStore.ArchiveMimeType ||
        uri.lastPathSegment.orEmpty().endsWith(".hanclipfavorites", ignoreCase = true)
}

private fun Intent.extractSharedUris(): List<Uri> {
    val uris = mutableListOf<Uri>()
    clipData?.let { data ->
        for (index in 0 until data.itemCount) {
            data.getItemAt(index).uri?.let(uris::add)
        }
    }
    getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
    getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::addAll)
    return uris.distinct()
}
