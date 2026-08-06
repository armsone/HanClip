package com.hanclip.android

import android.net.Uri
import android.widget.Toast
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.navArgument
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.hanclip.android.core.navigation.HanClipQuickAction
import com.hanclip.android.core.settings.SleepPreventionMode
import com.hanclip.android.core.settings.SleepPreventionStore
import com.hanclip.android.core.model.MoviePreset
import com.hanclip.android.core.project.DraftProjectStore
import com.hanclip.android.core.project.ExportHistoryStore
import com.hanclip.android.core.project.ExportedMoviePinResult
import com.hanclip.android.core.project.ExportedMovieSummary
import com.hanclip.android.feature.aishot.AiShotRoute
import com.hanclip.android.feature.browser.BrowserFavoritesStore
import com.hanclip.android.feature.browser.OnlineMusicBrowserRoute
import com.hanclip.android.feature.editor.EditorImportAction
import com.hanclip.android.feature.editor.EditorRoute
import com.hanclip.android.feature.editor.EditorViewModel
import com.hanclip.android.feature.home.HomeRoute
import com.hanclip.android.feature.preview.PreviewMovieSummary
import com.hanclip.android.feature.preview.PreviewRoute

@Composable
fun HanClipApp(
    sharedMediaUris: List<Uri> = emptyList(),
    sharedBrowserFavorites: List<String> = emptyList(),
    sharedBrowserFavoritesImportAttempted: Boolean = false,
    quickAction: HanClipQuickAction? = null,
    onSharedBrowserFavoritesHandled: () -> Unit = {},
    onQuickActionHandled: () -> Unit = {},
    onKeepScreenOnChanged: (Boolean) -> Unit = {}
) {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val editorViewModel: EditorViewModel = viewModel()
    val editorState by editorViewModel.uiState.collectAsState()
    val context = LocalContext.current
    var sleepPreventionMode by remember { mutableStateOf(SleepPreventionStore.load(context)) }
    var handledSharedSignature by remember { mutableStateOf("") }
    var handledBrowserFavoritesSignature by remember { mutableStateOf("") }
    var pendingSharedCount by remember { mutableStateOf(sharedMediaUris.size) }
    var pendingEditorImportAction by remember { mutableStateOf<EditorImportAction?>(null) }
    var exportedMovieSummaries by remember { mutableStateOf<List<ExportedMovieSummary>>(emptyList()) }
    var previewHistorySummary by remember { mutableStateOf<ExportedMovieSummary?>(null) }
    var hasDraftProject by remember { mutableStateOf(false) }

    LaunchedEffect(sharedMediaUris) {
        val signature = sharedMediaUris.joinToString("|")
        if (sharedMediaUris.isNotEmpty() && signature != handledSharedSignature) {
            handledSharedSignature = signature
            pendingSharedCount = sharedMediaUris.size
            navController.navigate(HanClipDestination.Editor.routeFor(MoviePreset.NewMovie))
            val audioUris = sharedMediaUris.filter { uri ->
                context.contentResolver.getType(uri).orEmpty().startsWith("audio/")
            }
            val visualUris = sharedMediaUris - audioUris.toSet()
            audioUris.firstOrNull()?.let { audioUri ->
                editorViewModel.setBackgroundMusic(context, audioUri)
            }
            if (visualUris.isNotEmpty()) {
                editorViewModel.addPickedMedia(context, visualUris)
            }
            pendingSharedCount = 0
        }
    }

    LaunchedEffect(sharedBrowserFavorites, sharedBrowserFavoritesImportAttempted) {
        val signature = sharedBrowserFavorites.joinToString("|")
        val attemptedSignature = "$sharedBrowserFavoritesImportAttempted|$signature"
        if ((sharedBrowserFavoritesImportAttempted || sharedBrowserFavorites.isNotEmpty()) &&
            attemptedSignature != handledBrowserFavoritesSignature
        ) {
            handledBrowserFavoritesSignature = attemptedSignature
            if (sharedBrowserFavorites.isEmpty()) {
                Toast.makeText(
                    context,
                    "브라우저 즐겨찾기 파일을 읽지 못했습니다.",
                    Toast.LENGTH_LONG
                ).show()
                navController.navigate(HanClipDestination.Browser.route)
                onSharedBrowserFavoritesHandled()
                return@LaunchedEffect
            }
            val result = BrowserFavoritesStore.merge(context, sharedBrowserFavorites)
            val message = when {
                result.addedCount > 0 && result.replacedCount > 0 ->
                    "브라우저 즐겨찾기 ${result.addedCount}개 추가, ${result.replacedCount}개 갱신"
                result.addedCount > 0 ->
                    "브라우저 즐겨찾기 ${result.addedCount}개를 추가했습니다."
                result.replacedCount > 0 ->
                    "브라우저 즐겨찾기 ${result.replacedCount}개를 갱신했습니다."
                else ->
                    "새로 가져올 브라우저 즐겨찾기가 없습니다."
            }
            Toast.makeText(context, message, Toast.LENGTH_LONG).show()
            navController.navigate(HanClipDestination.Browser.route)
            onSharedBrowserFavoritesHandled()
        }
    }

    val activeRoute = navBackStackEntry?.destination?.route

    LaunchedEffect(quickAction) {
        val action = quickAction ?: return@LaunchedEffect
        when (action) {
            HanClipQuickAction.Open -> {
                navController.popBackStack(HanClipDestination.Home.route, false)
            }
            HanClipQuickAction.AiShot -> {
                DraftProjectStore.clear(context)
                editorViewModel.startNewPreset(context, MoviePreset.AiShot)
                navController.navigate(HanClipDestination.AiShot.route) {
                    popUpTo(HanClipDestination.Home.route)
                }
            }
            HanClipQuickAction.Photo -> {
                pendingEditorImportAction = EditorImportAction.Photo
                if (activeRoute?.startsWith("editor/") != true) {
                    navController.navigate(HanClipDestination.Editor.routeFor(MoviePreset.NewMovie))
                }
            }
            HanClipQuickAction.Calendar -> {
                pendingEditorImportAction = EditorImportAction.Calendar
                if (activeRoute?.startsWith("editor/") != true) {
                    navController.navigate(HanClipDestination.Editor.routeFor(MoviePreset.NewMovie))
                }
            }
            HanClipQuickAction.Files -> {
                pendingEditorImportAction = EditorImportAction.Files
                if (activeRoute?.startsWith("editor/") != true) {
                    navController.navigate(HanClipDestination.Editor.routeFor(MoviePreset.NewMovie))
                }
            }
            HanClipQuickAction.Search -> {
                navController.navigate(HanClipDestination.Browser.route)
            }
        }
        onQuickActionHandled()
    }

    LaunchedEffect(editorState.exportedVideoUri) {
        exportedMovieSummaries = ExportHistoryStore.list(context)
        hasDraftProject = DraftProjectStore.hasDraft(context)
    }

    LaunchedEffect(editorState.clips) {
        hasDraftProject = editorState.clips.isNotEmpty() || DraftProjectStore.hasDraft(context)
    }

    val shouldKeepScreenOnForWork = editorState.isExporting ||
        editorState.isImportingMedia ||
        editorState.progressMessage.isNotBlank()
    val shouldKeepScreenOn = when (sleepPreventionMode) {
        SleepPreventionMode.AlwaysOn -> true
        SleepPreventionMode.AlwaysOff -> false
        SleepPreventionMode.Automatic -> activeRoute == HanClipDestination.AiShot.route ||
            shouldKeepScreenOnForWork
    }

    LaunchedEffect(shouldKeepScreenOn) {
        onKeepScreenOnChanged(shouldKeepScreenOn)
    }

    NavHost(
        navController = navController,
        startDestination = HanClipDestination.Home.route
    ) {
        composable(HanClipDestination.Home.route) {
            HomeRoute(
                exportedMovieSummaries = exportedMovieSummaries,
                recentlySavedMovieUriString = editorState.recentlySavedMovieUriString,
                hasDraftProject = hasDraftProject,
                sharedInboxCount = pendingSharedCount,
                sleepPreventionMode = sleepPreventionMode,
                onStartPreset = { preset ->
                    previewHistorySummary = null
                    DraftProjectStore.clear(context)
                    editorViewModel.startNewPreset(context, preset)
                    hasDraftProject = false
                    if (preset == MoviePreset.AiShot) {
                        navController.navigate(HanClipDestination.AiShot.route)
                    } else {
                        navController.navigate(HanClipDestination.Editor.routeFor(preset))
                    }
                },
                onOpenProject = {
                    previewHistorySummary = null
                    val draft = DraftProjectStore.load(context)
                    if (draft != null) {
                        editorViewModel.openDraft(context)
                        navController.navigate(HanClipDestination.Editor.routeFor(draft.preset))
                    } else {
                        navController.navigate(HanClipDestination.Editor.route)
                    }
                },
                onOpenExportedMovie = { summary ->
                    previewHistorySummary = summary
                    editorViewModel.openExportedMovie(Uri.parse(summary.uriString))
                    navController.navigate(HanClipDestination.Preview.route)
                },
                onRemoveExportedMovie = { summary ->
                    ExportHistoryStore.remove(context, summary.uriString)
                    exportedMovieSummaries = ExportHistoryStore.list(context)
                },
                onToggleExportedMoviePin = { summary ->
                    val result = ExportHistoryStore.togglePinned(context, summary.uriString)
                    if (result == ExportedMoviePinResult.Toggled) {
                        exportedMovieSummaries = ExportHistoryStore.list(context)
                    }
                    result == ExportedMoviePinResult.Toggled
                },
                onUpdateExportedMovieMemo = { summary, memo ->
                    ExportHistoryStore.updateMemo(context, summary.uriString, memo)
                    exportedMovieSummaries = ExportHistoryStore.list(context)
                },
                onSleepPreventionModeChange = { mode ->
                    sleepPreventionMode = mode
                    SleepPreventionStore.save(context, mode)
                }
            )
        }
        composable(
            route = HanClipDestination.Editor.routePattern,
            arguments = listOf(
                navArgument(HanClipDestination.Editor.presetArgument) {
                    type = NavType.StringType
                    defaultValue = MoviePreset.NewMovie.routeValue
                }
            )
        ) { entry ->
            EditorRoute(
                preset = MoviePreset.fromRouteValue(
                    entry.arguments?.getString(HanClipDestination.Editor.presetArgument)
                ),
                onBackHome = { navController.popBackStack() },
                onPreview = {
                    previewHistorySummary = null
                    navController.navigate(HanClipDestination.Preview.route)
                },
                onOpenBrowser = { navController.navigate(HanClipDestination.Browser.route) },
                sleepPreventionMode = sleepPreventionMode,
                onSleepPreventionModeChange = { mode ->
                    sleepPreventionMode = mode
                    SleepPreventionStore.save(context, mode)
                },
                initialImportAction = pendingEditorImportAction,
                onInitialImportActionConsumed = { pendingEditorImportAction = null },
                viewModel = editorViewModel
            )
        }
        composable(HanClipDestination.Preview.route) {
            PreviewRoute(
                exportedVideoUri = editorState.exportedVideoUri,
                movieSummary = previewHistorySummary?.let { summary ->
                    PreviewMovieSummary.fromHistory(summary)
                } ?: PreviewMovieSummary(
                    presetTitle = editorState.preset.title,
                    clipCount = editorState.renderableClips.size,
                    totalDurationSeconds = editorState.totalDurationSeconds,
                    outputAspectRatio = editorState.outputAspectRatio,
                    outputQualityPreset = editorState.outputQualityPreset,
                    hasBackgroundMusic = editorState.backgroundMusicUri != null ||
                        editorState.backgroundMusicSampleId != null,
                    watermarkSettings = editorState.watermarkSettings
                ),
                canReturnToEditor = previewHistorySummary == null,
                onEdit = {
                    if (previewHistorySummary == null) {
                        navController.popBackStack()
                    } else {
                        previewHistorySummary = null
                        navController.popBackStack(HanClipDestination.Home.route, false)
                    }
                },
                onDone = {
                    previewHistorySummary = null
                    navController.popBackStack(HanClipDestination.Home.route, false)
                },
                onSavedMovie = { uri ->
                    editorViewModel.recordSavedMovie(context, uri)
                    exportedMovieSummaries = ExportHistoryStore.list(context)
                    previewHistorySummary = exportedMovieSummaries.firstOrNull {
                        it.uriString == uri.toString()
                    }
                }
            )
        }
        composable(HanClipDestination.AiShot.route) {
            AiShotRoute(
                onClose = { navController.popBackStack() },
                onClipReady = { uri ->
                    editorViewModel.addPickedMedia(context, listOf(uri))
                },
                onOpenEditor = {
                    navController.navigate(HanClipDestination.Editor.routeFor(MoviePreset.AiShot)) {
                        popUpTo(HanClipDestination.Home.route)
                    }
                }
            )
        }
        composable(HanClipDestination.Browser.route) {
            OnlineMusicBrowserRoute(
                onClose = { navController.popBackStack() }
            )
        }
    }
}

sealed class HanClipDestination(val route: String) {
    data object Home : HanClipDestination("home")
    data object Editor : HanClipDestination("editor/newMovie") {
        const val presetArgument = "preset"
        const val routePattern = "editor/{$presetArgument}"

        fun routeFor(preset: MoviePreset): String = "editor/${preset.routeValue}"
    }
    data object Preview : HanClipDestination("preview")
    data object AiShot : HanClipDestination("aishot")
    data object Browser : HanClipDestination("browser")
}
