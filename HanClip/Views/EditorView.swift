import AVFoundation
import AVKit
import CoreTransferable
import CoreLocation
import CoreText
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

enum HanClipAudioSession {
    @discardableResult
    static func activatePlayback() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .playback || session.mode != .moviePlayback {
                try session.setCategory(
                    .playback,
                    mode: .moviePlayback,
                    options: []
                )
            }
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }
}

private enum SleepPreventionMode: String, CaseIterable, Identifiable {
    case alwaysOn = "alwaysOn"
    case alwaysOff = "alwaysOff"
    case automatic = "automatic"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alwaysOn:
            "항상켜짐"
        case .alwaysOff:
            "끔"
        case .automatic:
            "오토"
        }
    }

    var detail: String {
        switch self {
        case .alwaysOn:
            "화면이 꺼지지 않게 항상 유지합니다."
        case .alwaysOff:
            "시스템 설정(자동 잠금)에 맞게 동작하게 둡니다."
        case .automatic:
            "렌더링, 사진/파일 가져오기, 저장 중에만 유지합니다."
        }
    }
    static let defaultValue = SleepPreventionMode.automatic
}

private struct HomeLaunchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.045 : 0)
            .animation(
                .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

struct EditorView: View {
    private struct SelectAllClipSnapshot: Equatable {
        let id: UUID
        let duration: Double
        let photoDuration: Double
        let livePhotoDuration: Double?
        let livePhotoMode: LivePhotoMode
        let sourceDuration: Double?
        let trimStart: Double
        let videoSegmentMode: VideoSegmentMode
        let isVideoSegmentParent: Bool
        let isVideoSegmentSelected: Bool
    }

    @StateObject private var model = EditorViewModel()
    @StateObject private var movieCollection = MovieCollectionStore.shared
    @State private var isReordering = false
    @State private var showResetConfirmation = false
    @State private var showHeaderExitConfirmation = false
    @State private var showThemeSelection = false
    @State private var showImportantInfo = false
    @State private var showTextOverlaySettings = false
    @State private var showEndingInfoSettings = false
    @State private var showBackgroundMusicSettings = false
    @State private var shouldReturnToQuickDurationPicker = false
    @State private var isAddingQuickMedia = false
    @State private var showOnlineMusicBrowser = false
    @State private var showAiShotCamera = false
    @State private var isAiShotRestartPending = false
    @State private var isAiShotCoverDismissedForRestart = false
    @State private var showAspectRatioPicker = false
    @State private var didLongPressCloseButton = false
    @State private var themeNotice: String?
    @State private var importSelectionNotice: String?
    @State private var segmentResetNotice: String?
    @State private var pendingSegmentResetClipID: UUID?
    @State private var selectedClipID: UUID?
    @State private var videoSegmentPreviewParentID: UUID?
    @State private var shouldAutoplaySelectedClip = false
    @State private var isAutoAdvancingPreview = false
    @State private var isLoopingPreviewAutoAdvance = false
    @State private var draggedClipID: UUID?
    @State private var draggedCustomThemeMode: HanClipThemeMode?
    @State private var isDeleteDropTargeted = false
    @State private var isSharedInboxBannerDismissed = false
    @State private var bulkLivePhotoMode = LivePhotoMode.motion
    @State private var bulkSimilarPhotoGroupMode = VideoSegmentMode.single
    @State private var isClipSettingsExpanded = false
    @State private var selectAllSnapshot: [UUID: SelectAllClipSnapshot] = [:]
    @State private var selectAllAppliedSignature: [SelectAllClipSnapshot] = []
    @State private var isSelectAllChecked = false
    @State private var expandedMemoProjectID: UUID?
    @State private var selectedCollectionMovie: CollectedMovie?
    @State private var collectionMediaSelectionIdentifiers: [String] = []
    @State private var isCollectionMediaPickerPresented = false
    @State private var isCollectionCalendarPickerPresented = false
    @State private var isCollectionFileImporterPresented = false
    @State private var isImportingCollectionMovie = false
    @State private var collectionImportProgress = 0.0
    @State private var collectionImportCompletedCount = 0
    @State private var collectionImportTotalCount = 0
    @State private var collectionMovieBeingRenamed: CollectedMovie?
    @State private var collectionMovieBeingCompressed: CollectedMovie?
    @State private var isCompressingCollectionMovie = false
    @State private var collectionCompressionProgress = 0.0
    @State private var collectionCompressionMovieTitle = ""
    @State private var collectionCompressionTask: Task<Void, Never>?
    @State private var isCollectionBulkCompressionExpanded = false
    @State private var collectionTitleDraft = ""
    @State private var isCollectionTitleEditorPresented = false
    @State private var collectionTitleEditorHeight: CGFloat = 56
    @State private var collectionPosterCandidateMovie: CollectedMovie?
    @State private var collectionPosterCandidates: [CollectionPosterCandidate] = []
    @State private var rejectedCollectionPosterCandidates:
        [CollectionPosterCandidate] = []
    @State private var isLoadingCollectionPosterCandidates = false
    @State private var collectionPosterCandidateGeneration = 0
    @FocusState private var focusedMemoProjectID: UUID?

    private let aspectRatioPickerAnimation = Animation.snappy
    @AppStorage("hanClipThemeMode") private var themeModeRaw =
        HanClipThemeMode.automatic.rawValue
    @AppStorage("hanClipCustomThemeOrder") private var customThemeOrderRaw =
        "blossomGlow,grayscalePlay,pixelPop"
    @AppStorage(WatermarkSettings.logoEnabledStorageKey)
    private var logoWatermarkEnabled = WatermarkSettings.defaultIsEnabled
    @AppStorage(WatermarkSettings.enabledStorageKey)
    private var watermarkEnabled = WatermarkSettings.defaultTextIsEnabled
    @AppStorage(WatermarkSettings.textStorageKey)
    private var watermarkText = WatermarkSettings.defaultText
    @AppStorage(WatermarkSettings.addressStorageKey)
    private var watermarkAddress = WatermarkSettings.defaultAddress
    @AppStorage(WatermarkSettings.platformStorageKey)
    private var watermarkPlatformRaw =
        WatermarkSettings.defaultPlatform.rawValue
    @AppStorage(WatermarkSettings.positionStorageKey)
    private var watermarkPositionRaw =
        WatermarkSettings.defaultPosition.rawValue
    @AppStorage(WatermarkSettings.copyrightPositionStorageKey)
    private var copyrightPositionRaw =
        WatermarkSettings.defaultCopyrightPosition.rawValue
    @AppStorage(WatermarkSettings.fontNameStorageKey)
    private var watermarkFontName = WatermarkSettings.defaultFontName
    @AppStorage(WatermarkSettings.fontSizeStorageKey)
    private var watermarkFontSizeRaw =
        WatermarkSettings.defaultFontSize.rawValue
    @AppStorage(WatermarkSettings.textColorStorageKey)
    private var watermarkTextColorHex =
        WatermarkSettings.defaultTextColor
    @AppStorage(WatermarkSettings.copyrightTextColorStorageKey)
    private var copyrightTextColorHex =
        WatermarkSettings.defaultCopyrightTextColor
    @AppStorage(WatermarkSettings.shadowEnabledStorageKey)
    private var watermarkShadowEnabled =
        WatermarkSettings.defaultShadowEnabled
    @AppStorage(WatermarkSettings.shadowOpacityStorageKey)
    private var watermarkShadowOpacity =
        WatermarkSettings.defaultShadowOpacity
    @AppStorage(WatermarkSettings.shadowColorStorageKey)
    private var watermarkShadowColorHex =
        WatermarkSettings.defaultShadowColor
    @AppStorage(WatermarkSettings.copyrightShadowColorStorageKey)
    private var copyrightShadowColorHex =
        WatermarkSettings.defaultCopyrightShadowColor
    @AppStorage(WatermarkSettings.copyrightShadowOpacityStorageKey)
    private var copyrightShadowOpacity =
        WatermarkSettings.defaultCopyrightShadowOpacity
    @AppStorage(WatermarkSettings.copyrightIconColorModeStorageKey)
    private var copyrightIconColorModeRaw =
        WatermarkSettings.defaultCopyrightIconColorMode.rawValue
    @AppStorage(WatermarkSettings.copyrightIconColorStorageKey)
    private var copyrightIconColorHex =
        WatermarkSettings.defaultCopyrightIconColor
    @EnvironmentObject private var quickActionRouter:
        HanClipQuickActionRouter
    @EnvironmentObject private var purchaseManager:
        CopyrightPurchaseManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("hanClipSleepPreventionMode") private var sleepPreventionModeRaw =
        SleepPreventionMode.defaultValue.rawValue

    private var adaptiveContentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 920 : nil
    }

    private var themeMode: HanClipThemeMode {
        if themeModeRaw == "readableComfort" {
            return .light
        }
        if themeModeRaw == "rosyBrown" || themeModeRaw == "electricCobalt" {
            return .automatic
        }
        return HanClipThemeMode(rawValue: themeModeRaw) ?? .automatic
    }

    private var orderedCustomThemeModes: [HanClipThemeMode] {
        let savedModes = customThemeOrderRaw
            .split(separator: ",")
            .compactMap { HanClipThemeMode(rawValue: String($0)) }
            .filter { HanClipThemeMode.customModes.contains($0) }
        let missingModes = HanClipThemeMode.customModes.filter {
            !savedModes.contains($0)
        }
        return savedModes + missingModes
    }

    private var visibleThemeModes: [HanClipThemeMode] {
        HanClipThemeMode.baseModes + orderedCustomThemeModes
    }

    private var isSharedInboxBannerVisible: Bool {
        !model.isProjectOpen
            && !model.isImportingSharedItems
            && model.pendingSharedItemCount > 0
            && !isSharedInboxBannerDismissed
    }

    private var sleepPreventionMode: SleepPreventionMode {
        SleepPreventionMode(rawValue: sleepPreventionModeRaw) ?? .automatic
    }

    private var shouldKeepScreenOnForBackgroundWork: Bool {
        model.isExporting
            || model.isPreviewRendering
            || model.isImportingSharedItems
            || model.isImportingCalendarMedia
            || model.isImportingFiles
            || model.isImportingPhotoLibraryMedia
    }

    private var shouldDisableIdleTimer: Bool {
        if showAiShotCamera {
            return true
        }

        switch sleepPreventionMode {
        case .alwaysOn:
            return true
        case .alwaysOff:
            return false
        case .automatic:
            return shouldKeepScreenOnForBackgroundWork
        }
    }

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled =
            scenePhase == .active && shouldDisableIdleTimer
    }

    var body: some View {
        lifecycleConfiguredView
    }

    private var rootEditorContent: AnyView {
        AnyView(
            ZStack {
                HanClipTheme.backgroundGradient
                    .ignoresSafeArea()

                activeRootContent
                    .frame(maxWidth: adaptiveContentMaxWidth)
                    .frame(maxWidth: .infinity)

                if !model.isProjectOpen {
                    homeEdgeFades
                }
            }
        )
    }

    private var activeRootContent: AnyView {
        if model.isProjectOpen {
            return AnyView(clipEditor)
        }
        return emptyState
    }

    private var homeEdgeFades: AnyView {
        AnyView(
            VStack(spacing: 0) {
                homeTopEdgeFade
                Spacer(minLength: 0)
                homeBottomEdgeFade
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var rootEditorSurface: some View {
        rootEditorContent
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                rootTopHeader
            }
            .safeAreaInset(edge: .bottom) {
                if !model.clips.isEmpty {
                    makeButton
                } else if !model.isProjectOpen {
                    importantInfoButton
                }
            }
            .blur(
                radius: isBusyOverlayVisible || isSharedInboxBannerVisible || pendingSegmentResetClipID != nil
                    ? 2
                    : 0
            )
            .animation(
                .easeInOut(duration: 0.20),
                value: isBusyOverlayVisible
            )
            .animation(
                .easeInOut(duration: 0.20),
                value: isSharedInboxBannerVisible
            )
            .animation(
                .easeInOut(duration: 0.20),
                value: pendingSegmentResetClipID
            )
            .overlay {
                if isSharedInboxBannerVisible {
                    HanClipTheme.secondary
                        .opacity(0.05)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissSharedInboxBanner()
                        }
                }
            }
            .overlay(alignment: .top) {
                if let themeNotice {
                    Text(themeNotice)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(HanClipTheme.primary, in: Capsule())
                        .padding(.top, 70)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay {
                if let importSelectionNotice {
                    ZStack {
                        Color.black
                            .opacity(0.08)
                            .ignoresSafeArea()
                            .transition(.opacity)

                        topActionNoticeBadge(importSelectionNotice)
                            .padding(.horizontal, 32)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .overlay {
                if let segmentResetNotice {
                    Text(segmentResetNotice)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(HanClipTheme.primary, in: Capsule())
                        .shadow(
                            color: Color.black.opacity(0.18),
                            radius: 8,
                            y: 4
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay {
                if pendingSegmentResetClipID != nil {
                    ZStack {
                        Color.black.opacity(0.08)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.snappy) {
                                    pendingSegmentResetClipID = nil
                                }
                            }

                        segmentResetConfirmBar
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 102)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if isSharedInboxBannerVisible {
                    GeometryReader { proxy in
                        sharedInboxBanner
                            .frame(maxWidth: 720)
                            .frame(
                                height: min(
                                    max(proxy.size.height * 0.50, 360),
                                    455
                                ),
                                alignment: .top
                            )
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .top
                            )
                    }
                    .transition(
                        .move(edge: .top).combined(with: .opacity)
                    )
                }
            }
            .overlay {
                if isBusyOverlayVisible {
                    progressOverlay
                        .transition(.identity)
                        .zIndex(100)
                }
            }
    }

    private var rootNavigationView: some View {
        NavigationStack {
            rootEditorSurface
        }
    }

    private var modalOverlayConfiguredView: some View {
        rootNavigationView
        .blur(
            radius: showResetConfirmation
                || showHeaderExitConfirmation
                || showThemeSelection
                || (
                    showAspectRatioPicker
                    && model.isProjectOpen
                    && !model.clips.isEmpty
                )
                || selectedClipID != nil
                ? 2
                : 0
        )
        .animation(
            .easeInOut(duration: 0.20),
            value: showResetConfirmation
        )
        .animation(
            .easeInOut(duration: 0.20),
            value: showHeaderExitConfirmation
        )
        .animation(
            .easeInOut(duration: 0.20),
            value: showThemeSelection
        )
        .animation(
            .easeInOut(duration: 0.20),
            value: selectedClipID != nil
        )
        .onChange(of: selectAllCurrentSignature) { _, signature in
            clearSelectAllSnapshotIfNeeded(currentSignature: signature)
        }
        .onChange(of: model.isProjectOpen) { _, isProjectOpen in
            if !isProjectOpen {
                showAspectRatioPicker = false
                model.removeExcessAiShotProjects()
            }
        }
        .preferredColorScheme(themeMode.colorScheme)
        .overlay {
            GeometryReader { proxy in
                if showResetConfirmation || showHeaderExitConfirmation || showThemeSelection {
                    ZStack {
                        Color.black.opacity(0.20)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.snappy) {
                                    showResetConfirmation = false
                                    showHeaderExitConfirmation = false
                                    showThemeSelection = false
                                }
                            }

                        if showResetConfirmation {
                            resetConfirmationPopup
                                .frame(
                                    width: min(proxy.size.width, 760)
                                )
                                .frame(
                                    maxHeight: .infinity,
                                    alignment: .bottom
                                )
                                .offset(y: 18)
                                .transition(
                                    .move(edge: .bottom)
                                        .combined(with: .opacity)
                                )
                        } else if showHeaderExitConfirmation {
                            headerExitConfirmationPopup
                                .frame(
                                    width: min(proxy.size.width, 760)
                                )
                                .frame(
                                    maxHeight: .infinity,
                                    alignment: .top
                                )
                                .padding(.top, 0)
                                .transition(
                                    .move(edge: .top)
                                        .combined(with: .opacity)
                                )
                        } else {
                            themeSelectionPopup
                                .frame(
                                    width: min(
                                        proxy.size.width * 0.92,
                                        620
                                    )
                                )
                                .frame(
                                    maxHeight: .infinity,
                                    alignment: .top
                                )
                                .transition(
                                    .move(edge: .top)
                                        .combined(with: .opacity)
                                )
                        }
                    }
                }
            }
        }
        .overlay {
            GeometryReader { proxy in
                if showAspectRatioPicker
                    && model.isProjectOpen
                    && !model.clips.isEmpty
                    && !showResetConfirmation
                    && !showHeaderExitConfirmation
                    && !showThemeSelection
                {
                    ZStack {
                        Color.black.opacity(0.20)
                            .ignoresSafeArea()
                            .transition(.identity)
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(aspectRatioPickerAnimation) {
                                    showAspectRatioPicker = false
                                }
                            }

                        VStack(spacing: 12) {
                            Button {
                                withAnimation(aspectRatioPickerAnimation) {
                                    showAspectRatioPicker = false
                                }
                            } label: {
                                if #available(iOS 26.0, *) {
                                    floatingCancelIcon
                                        .background(
                                            Color.white.opacity(0.78),
                                            in: Circle()
                                        )
                                        .glassEffect(
                                            .regular
                                                .tint(Color.white.opacity(0.32))
                                                .interactive(),
                                            in: Circle()
                                        )
                                        .overlay {
                                            Circle()
                                                .stroke(
                                                    Color.white.opacity(0.72),
                                                    lineWidth: 1
                                                )
                                        }
                                } else {
                                    floatingCancelIcon
                                        .background(
                                            Color.white.opacity(0.88),
                                            in: Circle()
                                        )
                                        .background(.ultraThinMaterial, in: Circle())
                                        .overlay {
                                            Circle()
                                                .stroke(
                                                    Color.white.opacity(0.72),
                                                    lineWidth: 1
                                                )
                                        }
                                }
                            }
                            .shadow(
                                color: Color.black.opacity(0.18),
                                radius: 8,
                                y: 4
                            )
                            .buttonStyle(.plain)
                            .accessibilityLabel("비율 선택 닫기")

                            aspectRatioPicker
                                .frame(
                                    width: min(
                                        max(proxy.size.width - 28, 0),
                                        920
                                    )
                                )
                        }
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottom
                        )
                        .offset(y: 27)
                        .padding(.bottom, 33)
                        .transition(
                            .move(edge: .bottom).combined(with: .opacity)
                        )
                    }
                    .allowsHitTesting(true)
                }
            }
        }
    }

    private var presentationConfiguredView: some View {
        modalOverlayConfiguredView
        .fullScreenCover(isPresented: $model.isPickerPresented) {
            ZStack {
                if model.isCalendarPickerPresented {
                    CalendarMediaPickerView(
                        initialMonth: model.initialCalendarMonth,
                        initialMediaDates: model.initialCalendarMediaDates,
                        initialMediaCounts: model.initialCalendarMediaCounts,
                        initialSelectionIdentifiers: model.mediaPickerSelectionIdentifiers,
                        onCancel: cancelMediaPicker,
                        onShowPhotos: model.switchCalendarPickerToPhotos,
                        onConfirm: { dates, excludedAssetIdentifiers in
                            model.mediaPickerSelectionIdentifiers = []
                            model.importMediaFromCalendarDates(
                                dates,
                                excluding: excludedAssetIdentifiers
                            )
                        }
                    )
                    .transition(.opacity)
                } else {
                    photoPicker
                        .transition(.opacity)
                }
            }
            .animation(
                .easeInOut(duration: 0.11),
                value: model.isCalendarPickerPresented
            )
        }
        .fullScreenCover(isPresented: $model.isQuickDurationPickerPresented) {
            QuickMovieDurationPicker(
                recommendedDuration: model.quickRecommendedDuration,
                mediaCount: model.selectedSourceMediaCount,
                textSettings: model.textOverlaySettings,
                textEnabled: textOverlayBinding(\.isEnabled),
                endingInfoEnabled: textOverlayBinding(
                    \.includesEndingInfoCard
                ),
                endingInfoDuration: textOverlayBinding(
                    \.endingInfoCardDuration
                ),
                musicSettings: model.backgroundMusicSettings,
                musicEnabled: backgroundMusicBinding(\.isEnabled),
                aspectRatio: Binding(
                    get: { model.outputAspectRatio },
                    set: { model.selectOutputAspectRatio($0) }
                ),
                onSelectText: openQuickTextSettings,
                onSelectEndingInfo: openQuickEndingInfoSettings,
                onSelectMusic: openQuickMusicSettings,
                onAddPhoto: openQuickMediaPicker,
                onAddFile: openQuickFilePicker,
                onMake: model.confirmQuickMovieDuration,
                onCancel: model.cancelQuickMovieDurationSelection
            )
            .interactiveDismissDisabled()
        }
        .onChange(of: model.isQuickDurationPickerPresented) { _, isPresented in
            if isPresented {
                isAddingQuickMedia = false
            }
        }
        .fullScreenCover(item: $selectedCollectionMovie) { movie in
            CollectionMoviePlayerView(
                movie: movie,
                url: movieCollection.videoURL(for: movie)
            )
        }
        .fileImporter(
            isPresented: $isCollectionFileImporterPresented,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else {
                if case .failure(let error) = result {
                    model.alertMessage = error.localizedDescription
                }
                return
            }
            importCollectionFiles(urls)
        }
        .fullScreenCover(isPresented: $isCollectionMediaPickerPresented) {
            collectionMediaPicker
        }
        .sheet(isPresented: $isCollectionTitleEditorPresented) {
            collectionTitleEditorSheet
        }
        .sheet(item: $collectionMovieBeingCompressed) { movie in
            CollectionVideoSizeOptionsSheet(
                movie: movie,
                onSelect: { option in
                    collectionMovieBeingCompressed = nil
                    beginCollectionCompression(movie, option: option)
                }
            )
        }
        .fullScreenCover(item: $collectionPosterCandidateMovie) { movie in
            collectionPosterCandidateSheet(movie)
        }
        .fullScreenCover(isPresented: $model.isFileImporterPresented) {
            FilePicker(
                allowedContentTypes: [.movie],
                allowsMultipleSelection: true
            ) { result in
                model.isFileImporterPresented = false
                switch result {
                case .success(let urls):
                    model.importFiles(urls)
                case .failure(let error):
                    if isAddingQuickMedia {
                        restoreQuickDurationPickerAfterMediaCancellation()
                    } else {
                        model.alertMessage = error.localizedDescription
                    }
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(
            isPresented: $model.isBackgroundMusicImporterPresented
        ) {
            FilePicker(
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                model.isBackgroundMusicImporterPresented = false
                switch result {
                case .success(let urls):
                    model.importBackgroundMusic(urls)
                    if model.backgroundMusicSettings.hasMusicFile {
                        showBackgroundMusicSettings = true
                    }
                case .failure(let error):
                    model.alertMessage = error.localizedDescription
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showOnlineMusicBrowser) {
            OnlineMusicBrowserView { url, kind in
                showOnlineMusicBrowser = false
                if kind == .video {
                    model.importFiles([url])
                } else if model.queueBrowserDownloadAsSharedItem(url) {
                    isSharedInboxBannerDismissed = false
                    model.handlePendingSharedItemsOnActivation()
                }
            }
        }
        .fullScreenCover(
            isPresented: $showAiShotCamera,
            onDismiss: {
                if isAiShotRestartPending {
                    isAiShotCoverDismissedForRestart = true
                    restartAiShotAfterInterruption()
                } else {
                    model.discardEmptyAiShotProject()
                }
            }
        ) {
            AiShotCameraView(projectID: model.activeProjectID) {
                url, triggerTime in
                model.addAiShotVideo(url: url, triggerTime: triggerTime)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { selectedClipID != nil },
                set: {
                    if !$0 {
                        closeClipPreview()
                    }
                }
            )
        ) {
            if let id = selectedClipID,
               let index = currentPreviewClips.firstIndex(where: {
                   $0.id == id
               }) {
                let presentedClip = currentPreviewClips[index]
                VStack(spacing: 0) {
                    previewHeaderIdentity
                        .background(previewTopBackground)

                    previewTitleLine

                    VideoTrimEditor(
                        clip: bindingForClip(id: id, fallback: presentedClip),
                        previewAspectRatio: model.outputRenderSize.width
                            / max(1, model.outputRenderSize.height),
                        currentPosition: index + 1,
                        totalClipCount: currentPreviewClips.count,
                        defaultDuration: model.defaultDuration,
                        totalDurationText: model.totalDurationText,
                        autoplayOnLoad: shouldAutoplaySelectedClip,
                        onAutoplayConsumed: {
                            shouldAutoplaySelectedClip = false
                        },
                        autoAdvanceEnabled: $isAutoAdvancingPreview,
                        autoAdvanceLoops: $isLoopingPreviewAutoAdvance,
                        canGoPrevious: index > currentPreviewClips.startIndex,
                        canGoNext: index < currentPreviewClips.index(
                            before: currentPreviewClips.endIndex
                        ),
                        onPrevious: {
                            guard index > currentPreviewClips.startIndex
                            else { return }
                            shouldAutoplaySelectedClip = false
                            selectedClipID = currentPreviewClips[
                                currentPreviewClips.index(before: index)
                            ].id
                        },
                        onNext: {
                            guard index < currentPreviewClips.index(
                                before: currentPreviewClips.endIndex
                            ) else { return }
                            shouldAutoplaySelectedClip = false
                            selectedClipID = currentPreviewClips[
                                currentPreviewClips.index(after: index)
                            ].id
                        },
                        onAutoNext: {
                            guard index < currentPreviewClips.index(
                                before: currentPreviewClips.endIndex
                            ) else { return }
                            shouldAutoplaySelectedClip = true
                            selectedClipID = currentPreviewClips[
                                currentPreviewClips.index(after: index)
                            ].id
                        },
                        onFirst: {
                            guard let firstClip = currentPreviewClips.first
                            else { return }
                            shouldAutoplaySelectedClip = false
                            selectedClipID = firstClip.id
                        },
                        onAutoFirst: {
                            guard let firstClip = currentPreviewClips.first
                            else { return }
                            shouldAutoplaySelectedClip = true
                            selectedClipID = firstClip.id
                        },
                        onDelete: {
                            deleteClipFromEditor(id: id)
                        },
                        onPreview: {
                            closeClipPreview()
                            Task { @MainActor in
                                try? await Task.sleep(
                                    for: .milliseconds(300)
                                )
                                model.saveProjectAndOpenPreview()
                            }
                        },
                        bottomThumbnailStrip: AnyView(
                            previewThumbnailStrip()
                        )
                    )
                }
                .background(previewDragRevealBackground.ignoresSafeArea())
                .id(id)
                .ignoresSafeArea(edges: videoSegmentPreviewParentID != nil ? [] : [])
            }
        }
        .fullScreenCover(
            isPresented: $model.showPreview,
            onDismiss: model.previewDidDismiss
        ) {
            if let url = model.exportedURL {
                VideoPreviewView(
                    url: url,
                    onEdit: model.editLastSavedProject,
                    onSaveToPhotos:
                        model.saveToPhotosFromPreview(albumName:),
                    onSaveToFiles: model.saveToFilesFromPreview
                )
            }
        }
        .fullScreenCover(isPresented: $showImportantInfo) {
            importantInfoSheet
        }
        .fullScreenCover(
            isPresented: $showTextOverlaySettings,
            onDismiss: restoreQuickDurationPickerIfNeeded
        ) {
            TextOverlaySettingsSheet(
                textEnabled: textOverlayBinding(\.isEnabled),
                text: textOverlayBinding(\.text),
                position: textOverlayBinding(\.position),
                fontName: textOverlayBinding(\.fontName),
                textColorHex: textOverlayBinding(\.textColorHex),
                shadowEnabled: textOverlayBinding(\.shadowEnabled),
                shadowOpacity: textOverlayBinding(\.shadowOpacity),
                shadowColorHex: textOverlayBinding(\.shadowColorHex),
                lineSpacing: textOverlayBinding(\.lineSpacing),
                lineSpacingScale: textOverlayBinding(\.lineSpacingScale),
                fontSize: textOverlayBinding(\.fontSize),
                mediaDateRange: model.selectedMediaDateRange,
                mediaCount: model.selectedSourceMediaCount,
                includesEndingInfoCard: textOverlayBinding(
                    \.includesEndingInfoCard
                ),
                endingInfoCardDuration: textOverlayBinding(
                    \.endingInfoCardDuration
                ),
                endingInfoCardTheme: textOverlayBinding(
                    \.endingInfoCardTheme
                ),
                endingInfoCardVariation: textOverlayBinding(
                    \.endingInfoCardVariation
                ),
                hasEndingInfo: model.hasEndingInfoData,
                loadEndingInfoPreview: {
                    await model.endingInfoPreviewData()
                },
                renderEndingInfoPreview: { data, theme in
                    model.endingInfoPreviewImage(data, theme: theme)
                }
            )
        }
        .fullScreenCover(
            isPresented: $showBackgroundMusicSettings,
            onDismiss: restoreQuickDurationPickerIfNeeded
        ) {
            BackgroundMusicSettingsSheet(
                settings: $model.backgroundMusicSettings,
                isEnabled: backgroundMusicBinding(\.isEnabled),
                musicVolume: backgroundMusicBinding(\.musicVolume),
                originalAudioVolume: backgroundMusicBinding(
                    \.originalAudioVolume
                ),
                loopsToFillVideo: backgroundMusicBinding(\.loopsToFillVideo),
                fadeInEnabled: backgroundMusicBinding(\.fadeInEnabled),
                fadeOutEnabled: backgroundMusicBinding(\.fadeOutEnabled),
                onUseSampleMusic: { sampleTrack in
                    model.useSampleBackgroundMusic(sampleTrack)
                },
                onPickMusic: {
                    showBackgroundMusicSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        model.openBackgroundMusicPicker()
                    }
                },
                onImportDownloadedMusic: { url in
                    model.importBackgroundMusic([url])
                },
                onImportDownloadedVideo: { url in
                    showBackgroundMusicSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        model.importFiles([url])
                    }
                }
            )
        }
        .fullScreenCover(
            isPresented: $showEndingInfoSettings,
            onDismiss: restoreQuickDurationPickerIfNeeded
        ) {
            EndingInfoSettingsSheet(
                isEnabled: textOverlayBinding(\.includesEndingInfoCard),
                duration: textOverlayBinding(\.endingInfoCardDuration),
                theme: textOverlayBinding(\.endingInfoCardTheme),
                variation: textOverlayBinding(\.endingInfoCardVariation),
                fontName: textOverlayBinding(\.fontName),
                textColorHex: textOverlayBinding(\.textColorHex),
                shadowEnabled: textOverlayBinding(\.shadowEnabled),
                shadowOpacity: textOverlayBinding(\.shadowOpacity),
                shadowColorHex: textOverlayBinding(\.shadowColorHex),
                fontSize: textOverlayBinding(\.fontSize),
                lineSpacing: textOverlayBinding(\.lineSpacing),
                lineSpacingScale: textOverlayBinding(\.lineSpacingScale),
                loadPreview: {
                    await model.endingInfoPreviewData()
                },
                renderPreview: { data, theme in
                    model.endingInfoPreviewImage(data, theme: theme)
                }
            )
        }
    }

    private var lifecycleConfiguredView: some View {
        presentationConfiguredView
        .fileExporter(
            isPresented: $model.showFileExporter,
            document: model.fileDocument,
            contentType: .mpeg4Movie,
            defaultFilename: "HanClip-\(formattedDate).mp4"
        ) { result in
            switch result {
            case .success:
                model.alertMessage = "선택한 위치에 개봉했습니다."
            case .failure(let error):
                model.alertMessage = error.localizedDescription
            }
        }
        .alert(
            "HanClip",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onAppear {
            _ = FontRegistry.registerBundledCaptionFonts()
            model.removeExcessAiShotProjects()
            model.handlePendingSharedItemsOnActivation()
            isSharedInboxBannerDismissed = false
            handlePendingQuickAction()
            updateIdleTimerState()
        }
        .onOpenURL { url in
            guard url.scheme == "hanclip" else { return }

            model.handlePendingSharedItemsOnActivation()
            isSharedInboxBannerDismissed = false

            if let action = HanClipQuickAction(url: url) {
                handleQuickAction(action)
            } else {
                _ = quickActionRouter.handle(url)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.handlePendingSharedItemsOnActivation()
                isSharedInboxBannerDismissed = false
                handlePendingQuickAction()
                updateIdleTimerState()
                restartAiShotAfterInterruption()
            } else {
                UIApplication.shared.isIdleTimerDisabled = false
                if showAiShotCamera {
                    isAiShotRestartPending = true
                    isAiShotCoverDismissedForRestart = false
                    showAiShotCamera = false
                }
            }
        }
        .onChange(of: sleepPreventionModeRaw) { _, _ in
            updateIdleTimerState()
        }
        .onChange(of: showAiShotCamera) { _, _ in
            updateIdleTimerState()
        }
        .onChange(of: shouldKeepScreenOnForBackgroundWork) { _, _ in
            updateIdleTimerState()
        }
        .onChange(of: quickActionRouter.pendingAction) { _, action in
            guard let action else { return }
            handleQuickAction(action)
            quickActionRouter.clear(action)
        }
        .onChange(of: model.pendingSharedItemCount) { _, count in
            if count > 0 {
                isSharedInboxBannerDismissed = false
            }
        }
    }

    private var photoPicker: some View {
        PhotoPicker(
            initialSelectionIdentifiers: model.mediaPickerSelectionIdentifiers,
            excludedImportIdentifiers: Set(
                model.currentPhotoAssetIdentifiers
            ),
            onComplete: handlePhotoPickerComplete,
            onStart: model.startPhotoLibraryImport,
            onProgress: { progress, message in
                model.updatePhotoLibraryImportProgress(
                    progress,
                    message: message
                )
            },
            onRegisterCancellation:
                model.registerPhotoLibraryImportCancellation,
            onCancel: cancelMediaPicker,
            onDismiss: {
                model.closeMediaPicker()
            },
            onShowCalendar: model.switchPhotoPickerToCalendar
        )
        .ignoresSafeArea()
    }

    private var collectionMediaPicker: some View {
        ZStack {
            if isCollectionCalendarPickerPresented {
                CalendarMediaPickerView(
                    initialMonth: Date(),
                    initialMediaDates: [],
                    initialMediaCounts: [:],
                    initialSelectionIdentifiers:
                        collectionMediaSelectionIdentifiers,
                    videoOnly: true,
                    onCancel: closeCollectionMediaPicker,
                    onShowPhotos: { identifiers in
                        collectionMediaSelectionIdentifiers = identifiers
                        isCollectionCalendarPickerPresented = false
                    },
                    onConfirm: { dates, excludedIdentifiers in
                        let identifiers = collectionVideoIdentifiers(
                            on: dates,
                            excluding: excludedIdentifiers
                        )
                        finishCollectionMediaSelection(identifiers)
                    }
                )
                .transition(.opacity)
            } else {
                PhotoPicker(
                    initialSelectionIdentifiers:
                        collectionMediaSelectionIdentifiers,
                    excludedImportIdentifiers: [],
                    videoOnly: true,
                    onSelectionIdentifiers: {
                        finishCollectionMediaSelection($0)
                    },
                    onComplete: { _, _ in },
                    onStart: {},
                    onProgress: { _, _ in },
                    onRegisterCancellation: { _ in },
                    onCancel: closeCollectionMediaPicker,
                    onDismiss: {},
                    onShowCalendar: { identifiers in
                        collectionMediaSelectionIdentifiers = identifiers
                        isCollectionCalendarPickerPresented = true
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(
            .easeInOut(duration: 0.11),
            value: isCollectionCalendarPickerPresented
        )
    }

    private func closeCollectionMediaPicker() {
        collectionMediaSelectionIdentifiers = []
        isCollectionCalendarPickerPresented = false
        isCollectionMediaPickerPresented = false
    }

    private func finishCollectionMediaSelection(_ identifiers: [String]) {
        closeCollectionMediaPicker()
        guard !identifiers.isEmpty else { return }
        importCollectionAssetIdentifiers(identifiers)
    }

    private func collectionVideoIdentifiers(
        on dates: Set<Date>,
        excluding excludedIdentifiers: Set<String>
    ) -> [String] {
        PhotoLibraryService.mediaAssets(
            on: dates,
            calendar: .current,
            mediaType: .video
        )
        .map(\.localIdentifier)
        .filter { !excludedIdentifiers.contains($0) }
    }

    private var rootTopHeader: some View {
        HStack {
            HanClipHeaderPill {
                HanClipLogoLabel()
                    .fixedSize(horizontal: true, vertical: false)
            }
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.6)
                    .exclusively(before: TapGesture())
                    .onEnded { result in
                        switch result {
                        case .first(true):
                            withAnimation(.snappy) {
                                showThemeSelection = true
                            }
                        case .second:
                            handleLogoTap()
                        default:
                            break
                        }
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("HanClip")

            Spacer()

            rootHeaderTrailingAction
        }
        .frame(height: 58)
        .padding(.top, 6)
        .padding(.horizontal, 14)
        .frame(maxWidth: adaptiveContentMaxWidth)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            if model.isProjectOpen {
                topHeaderScrim
            }
        }
        .accessibilityHint(
            "첫 화면에서 누르면 테마가 바뀌고, 길게 누르면 테마 선택창을 엽니다."
        )
    }

    private var topHeaderScrim: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(topHeaderScrimMask)

            LinearGradient(
                stops: [
                    .init(
                        color: HanClipTheme.background.opacity(0.98),
                        location: 0.00
                    ),
                    .init(
                        color: HanClipTheme.background.opacity(0.96),
                        location: 0.62
                    ),
                    .init(
                        color: HanClipTheme.background.opacity(0.52),
                        location: 0.86
                    ),
                    .init(color: .clear, location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: 150)
        .offset(y: -58)
        .allowsHitTesting(false)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var topHeaderScrimMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.00),
                .init(color: .black, location: 0.62),
                .init(color: .black.opacity(0.62), location: 0.86),
                .init(color: .clear, location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private var rootHeaderTrailingAction: some View {
        if isBusyOverlayVisible {
            if model.isPreviewRendering {
                Button {
                    model.cancelPreviewGeneration()
                } label: {
                    HanClipHeaderActionCluster {
                        Image(systemName: "xmark")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("제작 취소")
            } else {
                HanClipHeaderActionCluster {
                    Image(systemName: "photo.badge.plus")
                }
                .opacity(0)
                .accessibilityHidden(true)
            }
        } else {
            if model.isProjectOpen {
                mediaImportMenu {
                    HanClipHeaderActionCluster {
                        Image(systemName: "photo.badge.plus")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(HanClipTheme.primary)
                    }
                }
            } else {
                mediaImportMenu {
                    HanClipHeaderActionCluster {
                        Image(systemName: "photo.badge.plus")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(HanClipTheme.primary)
                    }
                }
            }
        }
    }

    private var importantInfoSheet: some View {
        ImportantInfoSheet(
            sleepPreventionModeRaw: $sleepPreventionModeRaw,
            copyrightEnabled: $logoWatermarkEnabled,
            purchaseManager: purchaseManager,
            platformRaw: $watermarkPlatformRaw,
            address: $watermarkAddress,
            positionRaw: $copyrightPositionRaw,
            textColorHex: $copyrightTextColorHex,
            shadowColorHex: $copyrightShadowColorHex,
            shadowOpacity: $copyrightShadowOpacity,
            iconColorModeRaw: $copyrightIconColorModeRaw,
            iconColorHex: $copyrightIconColorHex
        )
    }

    private func handlePhotoPickerComplete(
        _ items: [ClipItem],
        selectedIdentifiers: [String]
    ) {
        model.mediaPickerSelectionIdentifiers = []
        let importedIDs = Set(items.map(\.id))
        let thumbnailRefreshTask = model.addPickedItems(items)
        let completionTask = Task { @MainActor in
            if let thumbnailRefreshTask {
                await thumbnailRefreshTask.value
            }
            guard !Task.isCancelled else { return }
            model.retainPhotoLibraryItems(
                selectedIdentifiers: selectedIdentifiers
            )
            await model.refreshPresetCaptionAfterMediaImport()
            guard !Task.isCancelled else { return }
            model.finishPhotoLibraryImport()
            isAddingQuickMedia = false
            model.startQuickMovieIfNeeded()
        }
        model.registerPhotoLibraryImportCancellation {
            thumbnailRefreshTask?.cancel()
            completionTask.cancel()
            model.rollbackPhotoLibraryImport(importedIDs)
        }
    }

    private func handlePendingQuickAction() {
        guard let action = quickActionRouter.pendingAction else { return }

        handleQuickAction(action)
        quickActionRouter.clear(action)
    }

    private func handleQuickAction(_ action: HanClipQuickAction) {
        showResetConfirmation = false
        showHeaderExitConfirmation = false
        showThemeSelection = false
        closeClipPreview()
        isSharedInboxBannerDismissed = true

        switch action {
        case .open:
            isSharedInboxBannerDismissed = false
        case .aiShot:
            openAiShot()
        case .photo:
            model.openPicker()
        case .quick:
            model.reset()
            model.openMoviePreset(.quick)
        case .calendar:
            model.openCalendarPicker()
        case .files:
            model.openFilePicker()
        case .search:
            showOnlineMusicBrowser = true
        }
    }

    private func closeClipPreview() {
        selectedClipID = nil
        videoSegmentPreviewParentID = nil
        shouldAutoplaySelectedClip = false
        isAutoAdvancingPreview = false
        isLoopingPreviewAutoAdvance = false
    }

    private var currentPreviewClips: [ClipItem] {
        if let videoSegmentPreviewParentID {
            return model.renderableClips.filter {
                $0.videoSegmentParentID == videoSegmentPreviewParentID
            }
        }
        return model.renderableClips
    }

    private func previewThumbnailStrip() -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(
                            Array(currentPreviewClips.enumerated()),
                            id: \.element.id
                        ) { index, clip in
                            previewThumbnailCell(index: index, clip: clip)
                                .id(clip.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, videoSegmentPreviewParentID == nil ? 9 : 6)
                    .padding(.bottom, 8)
                }
                .onAppear {
                    if let selectedClipID {
                        proxy.scrollTo(selectedClipID, anchor: .center)
                    }
                }
                .onChange(of: selectedClipID) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .background(
                ZStack {
                    LinearGradient(
                        colors: [
                            HanClipTheme.panelFill.opacity(0.58),
                            HanClipTheme.secondary.opacity(0.08),
                            HanClipTheme.background.opacity(0.48)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                }
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.055))
                    .frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.12),
                        Color.clear
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: 16)
                .allowsHitTesting(false)
            }
        }
    }

    private var previewTopBackground: some View {
        LinearGradient(
            colors: [
                HanClipTheme.background.opacity(0.98),
                HanClipTheme.background.opacity(0.90),
                HanClipTheme.panelFill.opacity(0.48)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var previewPanelBackground: some View {
        LinearGradient(
            colors: [
                HanClipTheme.background.opacity(0.98),
                HanClipTheme.panelFill.opacity(0.50),
                HanClipTheme.background.opacity(0.82)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var previewDragRevealBackground: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    HanClipTheme.background.opacity(0.98),
                    HanClipTheme.background.opacity(0.88),
                    HanClipTheme.panelFill.opacity(0.58),
                    HanClipTheme.background.opacity(0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Color.clear
        }
    }

    private var previewHeaderIdentity: some View {
        HanClipTopHeader(
            logoAccessibilityLabel: "편집 닫기",
            logoAction: {
                closeClipPreview()
            }
        ) {
            HStack(spacing: videoSegmentPreviewParentID != nil ? 54 : 10) {
                if videoSegmentPreviewParentID != nil {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 20, weight: .semibold))

                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                            .padding(4)
                            .background(.ultraThinMaterial, in: Circle())
                            .offset(x: 7, y: 5)
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                HanClipTheme.primary.opacity(0.90),
                                HanClipTheme.secondary.opacity(0.78)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: HanClipTheme.primary.opacity(0.16),
                        radius: 2,
                        y: 1
                    )
                        .frame(width: 38, height: 38)
                        .background(
                            HanClipTheme.background.opacity(0.44),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    HanClipTheme.panelStroke.opacity(0.42),
                                    lineWidth: 1
                                )
                        }
                    .accessibilityLabel("모클립 미리보기")
                }

                HanClipHeaderActionCluster {
                    Button {
                        closeClipPreview()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("닫기")

                    Button {
                        resetClipPreviewToFirst()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("편집 초기화")
                }

            }
        }
    }

    private var previewTitleLine: some View {
        HStack(spacing: 7) {
            Spacer()

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(HanClipTheme.secondaryText.opacity(0.78))
                .frame(width: 18, height: 18)
                .background(
                    HanClipTheme.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .accessibilityHidden(true)

            Text(videoSegmentPreviewParentID == nil ? "편집" : "모클립 편집")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(HanClipTheme.secondaryText.opacity(0.78))
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .background(previewTopBackground)
    }

    private func resetClipPreviewToFirst() {
        guard let firstClip = currentPreviewClips.first else { return }
        shouldAutoplaySelectedClip = true
        selectedClipID = firstClip.id
    }

    @ViewBuilder
    private func previewThumbnailCell(
        index: Int,
        clip: ClipItem
    ) -> some View {
        let cell = Image(uiImage: clip.thumbnail)
            .resizable()
            .scaledToFill()
            .frame(width: selectedClipID == clip.id ? 58 : 54, height: selectedClipID == clip.id ? 58 : 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text("\(index + 1)")
                    .font(
                        .system(
                            size: 10,
                            weight: .bold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(
                        HanClipTheme.primary.opacity(
                            selectedClipID == clip.id ? 0.86 : 0.64
                        ),
                        in: Circle()
                    )
                    .padding(3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        selectedClipID == clip.id
                            ? HanClipTheme.primary
                            : Color.white.opacity(0.42),
                        lineWidth: selectedClipID == clip.id ? 2.5 : 1
                    )
            }
            .shadow(
                color: selectedClipID == clip.id
                    ? HanClipTheme.primary.opacity(0.18)
                    : Color.black.opacity(0.08),
                radius: selectedClipID == clip.id ? 8 : 4,
                y: selectedClipID == clip.id ? 4 : 2
            )
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedClipID = clip.id
            }

        if videoSegmentPreviewParentID != nil {
            cell
                .onDrag {
                    draggedClipID = clip.id
                    return NSItemProvider(
                        object: clip.id.uuidString as NSString
                    )
                } preview: {
                    Image(uiImage: clip.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: VideoSegmentChildOrderDropDelegate(
                        targetID: clip.id,
                        model: model,
                        draggedClipID: $draggedClipID
                    )
                )
        } else {
            cell
        }
    }

    private var sharedInboxBanner: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 31, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                HanClipTheme.primary,
                                HanClipTheme.secondary.opacity(0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .background(
                        Color.white.opacity(0.95),
                        in: RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.42), lineWidth: 1)
                    }
                    .shadow(
                        color: Color.black.opacity(0.16),
                        radius: 14,
                        y: 7
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("공유파일 \(model.pendingSharedItemCount)개 발견")
                        .font(.system(size: 25, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 0)
            }

            sharedInboxThumbnailStrip

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 10) {
                Button {
                    isSharedInboxBannerDismissed = true
                    model.importPendingItemsIntoNewProject()
                } label: {
                    sharedInboxActionButton(
                        title: "새 영화 제작",
                        systemImage: "film.fill",
                        isPrimary: true,
                        accent: Color.white
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityHint("공유 파일로 새 영화를 만듭니다.")

                Button {
                    dismissSharedInboxBanner()
                } label: {
                    sharedInboxActionButton(
                        title: "영화에 추가",
                        systemImage: "folder.badge.plus",
                        isPrimary: false,
                        accent: Color.white.opacity(0.88)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityHint(
                    "알림을 닫고 영화 목록에서 공유 파일을 추가할 영화를 선택합니다."
                )

                Button {
                    withAnimation(.snappy) {
                        model.deletePendingSharedItems()
                        isSharedInboxBannerDismissed = true
                    }
                } label: {
                    sharedInboxActionButton(
                        title: "비우기",
                        systemImage: "trash.fill",
                        isPrimary: false,
                        accent: Color.white.opacity(0.82)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityHint("공유 공간의 대기 파일을 삭제합니다.")
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.primary.opacity(0.96),
                    HanClipTheme.secondary.opacity(0.78),
                    HanClipTheme.primary.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HanClipTheme.panelStroke.opacity(0.72), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 128, weight: .black))
                .foregroundStyle(Color.white.opacity(0.032))
                .padding(.top, 20)
                .padding(.trailing, 18)
                .allowsHitTesting(false)
        }
        .shadow(
            color: HanClipTheme.primary.opacity(0.20),
            radius: 24,
            y: 12
        )
        .contentShape(Rectangle())
    }

    private func sharedInboxActionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        accent: Color
    ) -> some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                HanClipTheme.primary.opacity(
                                    isPrimary ? 0.42 : 0.26
                                ),
                                HanClipTheme.secondary.opacity(
                                    isPrimary ? 0.30 : 0.18
                                )
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)

                Image(systemName: systemImage)
                    .font(.system(size: isPrimary ? 24 : 25, weight: .black))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(accent)
            }
            .overlay(alignment: .bottomTrailing) {
                if isPrimary {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(HanClipTheme.primary, .white)
                        .offset(x: 4, y: 4)
                }
            }
            .frame(height: 46)

            Text(title)
                .font(.system(size: 12, weight: .black))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(isPrimary ? 0.30 : 0.18),
                    HanClipTheme.primary.opacity(isPrimary ? 0.18 : 0.10),
                    Color.white.opacity(isPrimary ? 0.12 : 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isPrimary ? 0.72 : 0.52)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    Color.white.opacity(isPrimary ? 0.64 : 0.38),
                    lineWidth: 1
                )
        }
        .overlay(alignment: .topLeading) {
            if isPrimary {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.white.opacity(isPrimary ? 0.18 : 0.10))
                .frame(width: 34, height: 3)
                .padding(.bottom, 9)
                .allowsHitTesting(false)
        }
        .shadow(
            color: Color.black.opacity(isPrimary ? 0.18 : 0.11),
            radius: isPrimary ? 16 : 10,
            y: isPrimary ? 8 : 5
        )
    }

    private var sharedInboxThumbnailStrip: some View {
        let thumbnails = Array(model.pendingSharedThumbnails.prefix(9))
        let extraCount = max(model.pendingSharedItemCount - thumbnails.count, 0)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: 5
        )

        return GeometryReader { proxy in
            let cellSize = max((proxy.size.width - 32) / 5, 1)
            let visibleCount = thumbnails.count + (extraCount > 0 ? 1 : 0)
            let rowCount = visibleCount > 5 ? 2 : 1
            let gridHeight = CGFloat(rowCount) * cellSize
                + CGFloat(max(rowCount - 1, 0)) * 8

            VStack(spacing: 7) {
                sharedInboxFilmPerforationRow

                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(
                        Array(thumbnails.enumerated()),
                        id: \.offset
                    ) { _, thumbnail in
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cellSize, height: cellSize)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                                .stroke(Color.white.opacity(0.38), lineWidth: 1)
                            }
                            .shadow(
                                color: Color.black.opacity(0.14),
                                radius: 4,
                                y: 2
                            )
                    }

                    if extraCount > 0 {
                        Text("+\(extraCount)")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.white.opacity(0.94))
                            .frame(width: cellSize, height: cellSize)
                            .background(
                                Color.white.opacity(0.18),
                                in: RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                            }
                    }
                }
                .frame(height: gridHeight, alignment: .top)

                sharedInboxFilmPerforationRow
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.22),
                        HanClipTheme.primary.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
        }
        .frame(height: model.pendingSharedItemCount > 5 ? 166 : 106)
    }

    private var sharedInboxFilmPerforationRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<16, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 10, height: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func dismissSharedInboxBanner() {
        withAnimation(.snappy) {
            isSharedInboxBannerDismissed = true
        }
    }

    private func mediaImportMenu<LabelContent: View>(
        @ViewBuilder label: () -> LabelContent
    ) -> some View {
        Menu {
            Button {
                selectMediaImportSource("AiShot") {
                    openAiShot()
                }
            } label: {
                Label("AiShot", image: "AiShotIcon")
            }

            Button {
                selectMediaImportSource("사진") {
                    model.openPicker()
                }
            } label: {
                Label(
                    "사진",
                    systemImage: "photo.on.rectangle"
                )
            }

            Button {
                selectMediaImportSource("달력") {
                    model.openCalendarPicker()
                }
            } label: {
                Label("달력", systemImage: "calendar")
            }

            Button {
                selectMediaImportSource("파일") {
                    model.openFilePicker()
                }
            } label: {
                Label("파일", systemImage: "folder")
            }

        } label: {
            label()
        }
    }

    private func selectMediaImportSource(
        _ title: String,
        action: () -> Void
    ) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        showTopActionNotice("\(title) 선택", duration: .milliseconds(900))

        action()
    }

    private func topActionNoticeBadge(_ notice: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(HanClipTheme.primary)

            Text(notice)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HanClipTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    HanClipTheme.primary.opacity(0.18),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(0.14),
            radius: 14,
            y: 7
        )
    }

    private func showTopActionNotice(
        _ notice: String,
        duration: Duration = .seconds(1.8)
    ) {
        withAnimation(.snappy) {
            importSelectionNotice = notice
        }

        Task {
            try? await Task.sleep(for: duration)
            await MainActor.run {
                guard importSelectionNotice == notice else { return }
                withAnimation(.snappy) {
                    importSelectionNotice = nil
                }
            }
        }
    }

    private func showSegmentResetNotice() {
        let notice = "리셋"

        withAnimation(.snappy) {
            segmentResetNotice = notice
        }

        Task {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                guard segmentResetNotice == notice else { return }
                withAnimation(.snappy) {
                    segmentResetNotice = nil
                }
            }
        }
    }

    private func confirmSegmentReset() {
        guard let clipID = pendingSegmentResetClipID else { return }

        withAnimation(.snappy) {
            model.resetVideoSegments(id: clipID)
            pendingSegmentResetClipID = nil
        }
        showSegmentResetNotice()
    }

    private var segmentResetConfirmBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(HanClipTheme.primary)
                .frame(width: 34, height: 34)
                .background(
                    HanClipTheme.primary.opacity(0.10),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("자클립 초기화?")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HanClipTheme.primaryText)

                Text("편집 내역을 처음 상태로 돌립니다.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HanClipTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                withAnimation(.snappy) {
                    pendingSegmentResetClipID = nil
                }
            } label: {
                Text("취소")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HanClipTheme.secondaryText)
                    .frame(width: 58, height: 34)
                    .background(
                        HanClipTheme.secondary.opacity(0.10),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)

            Button {
                confirmSegmentReset()
            } label: {
                Text("초기화")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 34)
                    .background(HanClipTheme.primary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.background.opacity(0.78),
                    Color.white.opacity(0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(HanClipTheme.primary.opacity(0.18), lineWidth: 1)
        }
        .shadow(
            color: Color.black.opacity(0.16),
            radius: 18,
            y: 8
        )
    }

    private var resetConfirmationPopup: some View {
        VStack(spacing: 12) {
            Button {
                dismissResetConfirmation()
            } label: {
                if #available(iOS 26.0, *) {
                    floatingCancelIcon
                        .background(
                            Color.white.opacity(0.78),
                            in: Circle()
                        )
                        .glassEffect(
                            .regular
                                .tint(Color.white.opacity(0.32))
                                .interactive(),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.72),
                                    lineWidth: 1
                                )
                        }
                } else {
                    floatingCancelIcon
                        .background(
                            Color.white.opacity(0.88),
                            in: Circle()
                        )
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.72),
                                    lineWidth: 1
                                )
                        }
                }
            }
            .shadow(
                color: Color.black.opacity(0.18),
                radius: 8,
                y: 4
            )
            .buttonStyle(.plain)
            .accessibilityLabel("취소")
            .accessibilityHint(
                "첫 화면으로 이동하지 않고 편집 화면으로 돌아갑니다."
            )

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy) {
                            showResetConfirmation = false
                            showHeaderExitConfirmation = false
                            videoSegmentPreviewParentID = nil
                            isReordering = false
                            model.saveProjectAndReturnHome()
                        }
                    } label: {
                        homeActionButtonLabel(
                            title: "저장 후 홈",
                            isPrimary: true
                        ) {
                            FloppyDiskIcon()
                                .frame(width: 17, height: 17)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.snappy) {
                            showResetConfirmation = false
                            showHeaderExitConfirmation = false
                            model.saveProjectOnly()
                        }
                    } label: {
                        homeActionButtonLabel(
                            title: "저장",
                            isPrimary: false
                        ) {
                            FloppyDiskIcon()
                                .frame(width: 18, height: 18)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.snappy) {
                            showResetConfirmation = false
                            showHeaderExitConfirmation = false
                            videoSegmentPreviewParentID = nil
                            selectedClipID = nil
                            draggedClipID = nil
                            isReordering = false
                            model.returnHomeWithoutSaving()
                        }
                    } label: {
                        homeActionButtonLabel(
                            title: "홈",
                            isPrimary: false
                        ) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 18, height: 18)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [
                        HanClipTheme.background.opacity(0.62),
                        Color.white.opacity(0.34)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        HanClipTheme.primary.opacity(0.12),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: Color.black.opacity(0.10),
                radius: 12,
                y: 6
            )
            .contentShape(Rectangle())
            .onTapGesture {
                dismissResetConfirmation()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 22)
    }

    private var headerExitConfirmationPopup: some View {
        VStack(spacing: 12) {
            homeActionButtons

            Button {
                dismissResetConfirmation()
            } label: {
                if #available(iOS 26.0, *) {
                    floatingCancelIcon
                        .background(
                            Color.white.opacity(0.78),
                            in: Circle()
                        )
                        .glassEffect(
                            .regular
                                .tint(Color.white.opacity(0.32))
                                .interactive(),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.72),
                                    lineWidth: 1
                                )
                        }
                } else {
                    floatingCancelIcon
                        .background(
                            Color.white.opacity(0.88),
                            in: Circle()
                        )
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.72),
                                    lineWidth: 1
                                )
                        }
                }
            }
            .shadow(
                color: Color.black.opacity(0.18),
                radius: 8,
                y: 4
            )
            .buttonStyle(.plain)
            .accessibilityLabel("취소")
            .accessibilityHint(
                "첫 화면으로 이동하지 않고 편집 화면으로 돌아갑니다."
            )
        }
        .padding(.horizontal, 14)
    }

    private var homeActionButtons: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) {
                        showResetConfirmation = false
                        showHeaderExitConfirmation = false
                        videoSegmentPreviewParentID = nil
                        isReordering = false
                        model.saveProjectAndReturnHome()
                    }
                } label: {
                    homeActionButtonLabel(
                        title: "저장 후 홈",
                        isPrimary: true
                    ) {
                        FloppyDiskIcon()
                            .frame(width: 17, height: 17)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.snappy) {
                        showResetConfirmation = false
                        showHeaderExitConfirmation = false
                        model.saveProjectOnly()
                    }
                } label: {
                    homeActionButtonLabel(
                        title: "저장",
                        isPrimary: false
                    ) {
                        FloppyDiskIcon()
                            .frame(width: 18, height: 18)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.snappy) {
                        showResetConfirmation = false
                        showHeaderExitConfirmation = false
                        videoSegmentPreviewParentID = nil
                        selectedClipID = nil
                        draggedClipID = nil
                        isReordering = false
                        model.returnHomeWithoutSaving()
                    }
                } label: {
                    homeActionButtonLabel(
                        title: "홈",
                        isPrimary: false
                    ) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.background.opacity(0.62),
                    Color.white.opacity(0.34)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    HanClipTheme.primary.opacity(0.12),
                    lineWidth: 1
                )
        }
        .shadow(
            color: Color.black.opacity(0.10),
            radius: 12,
            y: 6
        )
    }

    private func homeActionButtonLabel<Icon: View>(
        title: String,
        isPrimary: Bool,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 6) {
            icon()
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(
            isPrimary
                ? .white
                : HanClipTheme.primary.opacity(0.96)
        )
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background {
            homeActionButtonBackground(isPrimary: isPrimary)
        }
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(
                    isPrimary
                        ? Color.white.opacity(0.24)
                        : HanClipTheme.primary.opacity(0.32),
                    lineWidth: isPrimary ? 1.5 : 1.2
                )
        }
        .shadow(
            color: isPrimary
                ? HanClipTheme.primary.opacity(0.18)
                : Color.black.opacity(0.08),
            radius: isPrimary ? 8 : 5,
            y: isPrimary ? 4 : 2
        )
    }

    @ViewBuilder
    private func homeActionButtonBackground(isPrimary: Bool) -> some View {
        if isPrimary {
            LinearGradient(
                colors: [
                    HanClipTheme.primary.opacity(0.96),
                    HanClipTheme.secondary.opacity(0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.86),
                    HanClipTheme.background.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var floatingCancelIcon: some View {
        Image(systemName: "xmark")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(HanClipTheme.secondary)
            .frame(width: 52, height: 52)
            .contentShape(Circle())
    }

    private func dismissResetConfirmation() {
        withAnimation(.snappy) {
            showResetConfirmation = false
            showHeaderExitConfirmation = false
        }
    }

    private var themeSelectionPopup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SELECT THEME")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HanClipTheme.text)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            themePaletteSummary
                .padding(.horizontal, 18)

            VStack(spacing: -2) {
                ForEach(
                    Array(visibleThemeModes.enumerated()),
                    id: \.element.rawValue
                ) { index, mode in
                    themeSelectionRow(mode)

                    if index != visibleThemeModes.count - 1 {
                        Divider()
                            .padding(.leading, 50)
                    }
                }
            }

            Button {
                withAnimation(.snappy) {
                    showThemeSelection = false
                }
            } label: {
                Text("확인")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        LinearGradient(
                            colors: [
                                HanClipTheme.primary,
                                HanClipTheme.secondary.opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(
                        color: HanClipTheme.primary.opacity(0.18),
                        radius: 8,
                        y: 4
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 14)
            .accessibilityLabel("테마 선택 확인")
        }
        .background(
            HanClipTheme.background,
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    HanClipTheme.secondary.opacity(0.22),
                    lineWidth: 1
                )
        }
        .shadow(
            color: Color.black.opacity(0.18),
            radius: 18,
            y: 8
        )
    }

    private var themePaletteSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("COLOR SYSTEM")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(HanClipTheme.secondaryText)

                Spacer()

                Text(themeMode.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText)
            }

            HStack(spacing: 8) {
                themePaletteChip(
                    color: HanClipTheme.primary,
                    title: "Main",
                    description: "선택/실행"
                )

                themePaletteChip(
                    color: HanClipTheme.secondary,
                    title: "Sub",
                    description: "구조/그룹"
                )

                themePaletteChip(
                    color: HanClipTheme.backgroundWithBlack,
                    title: "BG",
                    description: "배경"
                )

                themePaletteChip(
                    color: HanClipTheme.primaryText,
                    title: "Text",
                    description: "정보"
                )
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.panelFill,
                    HanClipTheme.secondary.opacity(0.035)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .hanClipGlassPanel(cornerRadius: 16)
    }

    private func themePaletteChip(
        color: Color,
        title: String,
        description: String
    ) -> some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(color)
                .frame(height: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            HanClipTheme.text.opacity(0.12),
                            lineWidth: 1
                        )
                }

            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(HanClipTheme.primaryText)

            Text(description)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(HanClipTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func themeColorSwatch(
        _ color: Color,
        label: String
    ) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .frame(width: 26, height: 26)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        HanClipTheme.text.opacity(0.18),
                        lineWidth: 1
                    )
            }
            .accessibilityLabel(label)
    }

    private func themeSelectionRow(_ mode: HanClipThemeMode) -> some View {
        let isCustomTheme = HanClipThemeMode.customModes.contains(mode)

        return HStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    selectTheme(
                        mode,
                        dismissPanel: false,
                        showNotice: false
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(
                            systemName: themeMode == mode
                                ? "largecircle.fill.circle"
                                : "circle"
                        )
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(HanClipTheme.primary)

                        Text(mode.displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(HanClipTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.displayName) 테마 선택")

                Spacer()

                if let colors = HanClipTheme.previewColors(for: mode) {
                    HStack(spacing: 6) {
                        themeColorSwatch(
                            colors.primary,
                            label: "\(mode.displayName) 메인 색상"
                        )
                        themeColorSwatch(
                            colors.secondary,
                            label: "\(mode.displayName) 보조 색상"
                        )
                    }
                    .contentShape(Rectangle())
                    .onDrag {
                        guard isCustomTheme else { return NSItemProvider() }
                        draggedCustomThemeMode = mode
                        return NSItemProvider(object: mode.rawValue as NSString)
                    }
                    .accessibilityHint(
                        isCustomTheme
                            ? "길게 눌러 끌면 테마 순서를 바꿀 수 있습니다."
                            : "기본 테마는 순서를 바꿀 수 없습니다."
                    )
                }

            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.text],
            delegate: ThemeOrderDropDelegate(
                targetMode: mode,
                draggedMode: $draggedCustomThemeMode,
                customThemeOrderRaw: $customThemeOrderRaw,
                currentOrder: orderedCustomThemeModes
            )
        )
        .accessibilityValue(
            themeMode == mode ? "선택됨" : "선택되지 않음"
        )
    }

    private func selectTheme(
        _ mode: HanClipThemeMode,
        dismissPanel: Bool = true,
        showNotice: Bool = true
    ) {
        UserDefaults.standard.set(mode.rawValue, forKey: "hanClipThemeMode")
        themeModeRaw = mode.rawValue
        let notice = "\(mode.displayName)로 변경했습니다."

        if dismissPanel {
            withAnimation(.snappy) {
                showThemeSelection = false
            }
        }

        guard showNotice else { return }

        withAnimation {
            themeNotice = notice
        }

        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                guard themeNotice == notice else { return }
                withAnimation {
                    themeNotice = nil
                }
            }
        }
    }

    private func handleLogoTap() {
        if model.isProjectOpen {
            if !model.isActiveAiShotProject,
               !model.hasUnsavedProjectChanges {
                closeProjectImmediately()
                return
            }
            withAnimation(.snappy) {
                showHeaderExitConfirmation = true
            }
        } else {
            selectNextTheme()
        }
    }

    private func handleCloseButtonTap() {
        guard !didLongPressCloseButton else { return }

        guard model.isProjectOpen else {
            withAnimation(.snappy) {
                showAspectRatioPicker = false
                showResetConfirmation = true
            }
            return
        }

        if !model.isActiveAiShotProject,
           !model.hasUnsavedProjectChanges {
            closeProjectImmediately()
            return
        }

        withAnimation(.snappy) {
            showAspectRatioPicker = false
            showResetConfirmation = true
        }
    }

    private func handleCloseButtonLongPress() {
        didLongPressCloseButton = true

        withAnimation(.snappy) {
            showAspectRatioPicker = false
            showResetConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            didLongPressCloseButton = false
        }
    }

    private func closeProjectImmediately() {
        withAnimation(.snappy) {
            showAspectRatioPicker = false
            showResetConfirmation = false
            showHeaderExitConfirmation = false
            videoSegmentPreviewParentID = nil
            selectedClipID = nil
            draggedClipID = nil
            isReordering = false
            model.returnHomeWithoutSaving()
        }
    }

    private func selectNextTheme() {
        let modes = visibleThemeModes
        guard !modes.isEmpty else { return }
        let currentIndex = modes.firstIndex(of: themeMode) ?? 0
        let nextIndex = modes.index(
            after: currentIndex
        ) == modes.endIndex
            ? modes.startIndex
            : modes.index(after: currentIndex)
        selectTheme(modes[nextIndex])
    }

    private var emptyState: AnyView {
        AnyView(GeometryReader { proxy in
            ScrollView {
                emptyStateContent(minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in
                        focusedMemoProjectID = nil
                    }
            )
            .scrollIndicators(.hidden)
        }
        .id("home-\(themeModeRaw)"))
    }

    private func emptyStateContent(minHeight: CGFloat) -> AnyView {
        AnyView(
            VStack(spacing: 10) {
                emptyStatePresetSection
                AnyView(savedProjectList)
                Spacer(minLength: 16)
                AnyView(appBuildCaption)
            }
            .frame(minHeight: minHeight, alignment: .top)
            .padding(.bottom, 24)
        )
    }

    private var emptyStatePresetSection: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HanClipTitleLine(
                    "영화 프리셋",
                    systemImage: "square.grid.2x2.fill"
                )
                AnyView(homeMoviePresetGrid)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)
        )
    }

    private var homeTopEdgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: HanClipTheme.background.opacity(0.99), location: 0.00),
                .init(color: HanClipTheme.background.opacity(0.98), location: 0.48),
                .init(color: HanClipTheme.background.opacity(0.68), location: 0.74),
                .init(color: .clear, location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 92)
        .allowsHitTesting(false)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var homeBottomEdgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.00),
                .init(color: HanClipTheme.background.opacity(0.18), location: 0.26),
                .init(color: HanClipTheme.background.opacity(0.84), location: 0.58),
                .init(color: HanClipTheme.background.opacity(1.00), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 104)
        .allowsHitTesting(false)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var appBuildCaption: some View {
        VStack(spacing: 3) {
            Text(appBuildText)
            Text(aiModelText)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(HanClipTheme.secondaryText.opacity(0.9))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("한클립 버전 \(appBuildText), \(aiModelText)")
    }

    private var appBuildText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0.1"
        let buildNumber = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "3.0.1"
        return "HanClip \(version)  Build \(buildNumber)"
    }

    private var aiModelText: String {
        "Ai \(AudioImpactClassifier.modelVersion)"
    }

    private var homeMoviePresetGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 8),
                count: 3
            ),
            spacing: 10
        ) {
            homeQuickStartButton(
                title: "새 영화",
                subtitle: "모든 것의 시작",
                systemImage: "film.stack.fill",
                accent: HanClipTheme.primary,
                secondaryAccent: HanClipTheme.secondary
            ) {
                model.openMoviePreset(.newMovie)
            }

            homeQuickStartButton(
                title: "퀵모드",
                subtitle: "고르면 바로 영화로",
                systemImage: "bolt.fill",
                accent: HanClipTheme.secondary,
                secondaryAccent: HanClipTheme.primary,
                backgroundAccentOpacity: 0.12
            ) {
                model.openMoviePreset(.quick)
            }

            homeQuickStartButton(
                title: "AiShot",
                subtitle: "스마트한 레코딩",
                systemImage: "camera.fill",
                assetImage: "AiShotIcon",
                accent: HanClipTheme.primary,
                secondaryAccent: HanClipTheme.secondary,
                action: openAiShot
            )

            homeQuickStartButton(
                title: "여행 영화",
                subtitle: "여행을 추억으로",
                systemImage: "airplane",
                accent: HanClipTheme.primary.opacity(0.82),
                secondaryAccent: HanClipTheme.secondary.opacity(0.88)
            ) {
                model.openMoviePreset(.travel)
            }

            homeQuickStartButton(
                title: "인생 영화",
                subtitle: "삶의 순간을 한 편으로",
                systemImage: "heart.fill",
                accent: HanClipTheme.primary.opacity(0.88),
                secondaryAccent: HanClipTheme.secondary.opacity(0.92)
            ) {
                model.openMoviePreset(.life)
            }

            homeQuickStartButton(
                title: "골프 영화",
                subtitle: "공도 넣고 기억도 넣고",
                systemImage: "figure.golf",
                accent: HanClipTheme.secondary,
                secondaryAccent: HanClipTheme.primary
            ) {
                model.openMoviePreset(.golf)
            }
        }
        .padding(.horizontal, 14)
    }

    private func homeQuickStartButton(
        title: String,
        subtitle: String,
        systemImage: String,
        assetImage: String? = nil,
        badgeSystemImage: String? = nil,
        accent: Color,
        secondaryAccent: Color,
        backgroundAccentOpacity: Double = 0.07,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    if let assetImage {
                        Image(assetImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 25, height: 25)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 19, weight: .bold))
                    }

                    if let badgeSystemImage {
                        Image(systemName: badgeSystemImage)
                            .font(.system(size: 10, weight: .black))
                            .offset(x: 11, y: -11)
                    }
                }
                .foregroundStyle(HanClipTheme.onSecondary)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: [accent, secondaryAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            HanClipTheme.onSecondary.opacity(0.22),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: accent.opacity(0.16),
                    radius: 5,
                    y: 3
                )

                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(HanClipTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(maxWidth: .infinity)
                    .frame(height: 18)
                    .padding(.top, 7)

                Text(subtitle)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 5)
            .padding(.top, 15)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .background(
                LinearGradient(
                    colors: [
                        HanClipTheme.background.opacity(0.97),
                        HanClipTheme.panelFill.opacity(0.84),
                        accent.opacity(backgroundAccentOpacity)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.30),
                                HanClipTheme.panelStroke.opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: HanClipTheme.text.opacity(0.06),
                radius: 7,
                y: 4
            )
        }
        .buttonStyle(HomeLaunchButtonStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
        .accessibilityHint(subtitle)
    }

    private func openAiShot() {
        guard model.openAiShot(), model.isProjectOpen else { return }

        Task { @MainActor in
            await Task.yield()
            showAiShotCamera = true
        }
    }

    private func openQuickTextSettings() {
        shouldReturnToQuickDurationPicker = true
        model.isQuickDurationPickerPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            showTextOverlaySettings = true
        }
    }

    private func openQuickMusicSettings() {
        shouldReturnToQuickDurationPicker = true
        model.isQuickDurationPickerPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            showBackgroundMusicSettings = true
        }
    }

    private func openQuickEndingInfoSettings() {
        shouldReturnToQuickDurationPicker = true
        model.isQuickDurationPickerPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            showEndingInfoSettings = true
        }
    }

    private func openQuickMediaPicker() {
        isAddingQuickMedia = true
        model.prepareCurrentMediaPickerSelection()
        model.isQuickDurationPickerPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            model.openPicker()
        }
    }

    private func openQuickFilePicker() {
        isAddingQuickMedia = true
        model.isQuickDurationPickerPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            model.openFilePicker()
        }
    }

    private func cancelMediaPicker() {
        guard isAddingQuickMedia else {
            model.cancelMediaPicker()
            return
        }

        isAddingQuickMedia = false
        model.closeMediaPicker()
        restoreQuickDurationPickerAfterMediaCancellation()
    }

    private func restoreQuickDurationPickerAfterMediaCancellation() {
        isAddingQuickMedia = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            model.isQuickDurationPickerPresented = true
        }
    }

    private func restoreQuickDurationPickerIfNeeded() {
        guard shouldReturnToQuickDurationPicker else { return }
        shouldReturnToQuickDurationPicker = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            model.isQuickDurationPickerPresented = true
        }
    }

    private func restartAiShotAfterInterruption() {
        guard scenePhase == .active,
              isAiShotRestartPending,
              isAiShotCoverDismissedForRestart,
              model.isProjectOpen
        else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard scenePhase == .active,
                  isAiShotRestartPending,
                  isAiShotCoverDismissedForRestart,
                  model.isProjectOpen
            else { return }
            isAiShotRestartPending = false
            isAiShotCoverDismissedForRestart = false
            showAiShotCamera = true
        }
    }

    private func resumeAiShotProject(id: UUID) {
        model.loadProject(id: id) { didLoad in
            guard didLoad, model.isProjectOpen else { return }
            Task { @MainActor in
                await Task.yield()
                showAiShotCamera = true
            }
        }
    }

    private var importantInfoButton: some View {
        Text("i")
            .font(.system(size: 18, weight: .bold, design: .serif))
            .foregroundStyle(HanClipTheme.secondary)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .onTapGesture {
                showImportantInfo = true
            }
            .onLongPressGesture(minimumDuration: 0.55) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showOnlineMusicBrowser = true
            }
        .background {
            if #available(iOS 26.0, *) {
                Circle()
                    .fill(HanClipTheme.panelFill.opacity(0.72))
                    .glassEffect(
                        .regular
                            .tint(HanClipTheme.secondary.opacity(0.16))
                            .interactive(),
                        in: Circle()
                    )
            } else {
                Circle()
                    .fill(HanClipTheme.panelFill.opacity(0.78))
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .overlay {
            Circle()
                .stroke(HanClipTheme.panelStroke.opacity(0.72), lineWidth: 1)
        }
        .shadow(
            color: HanClipTheme.secondary.opacity(0.18),
            radius: 10,
            y: 4
        )
        .padding(.bottom, 8)
        .id("important-info-\(themeModeRaw)")
        .accessibilityLabel("카피라이터")
        .accessibilityHint("한 번 누르면 설정 창을 열고, 길게 누르면 브라우저를 엽니다.")
    }

    private var savedProjectList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text("\(model.savedProjects.count)/\(ProjectStore.maximumProjectCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText)

                Spacer()

                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(HanClipTheme.primary.opacity(0.72))
                    .frame(width: 18, height: 18)
                    .background(
                        HanClipTheme.secondary.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 5,
                            style: .continuous
                        )
                    )
                    .accessibilityHidden(true)

                Text("영화 목록")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(HanClipTheme.primaryText.opacity(0.76))
            }
            .padding(.horizontal, 18)

            savedProjectRows(model.savedProjects)
            standardEmptyProjectRows(
                count: max(0, 2 - model.savedProjects.count)
            )

            HStack(spacing: 7) {
                Text(
                    "\(movieCollection.movies.count)/"
                        + "\(MovieCollectionStore.maximumMovieCount)"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HanClipTheme.secondaryText)

                Spacer()

                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(HanClipTheme.primary.opacity(0.72))
                    .frame(width: 18, height: 18)
                    .background(
                        HanClipTheme.secondary.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 5,
                            style: .continuous
                        )
                    )
                    .accessibilityHidden(true)

                Text("컬렉션")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(HanClipTheme.primaryText.opacity(0.76))
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            movieCollectionShelf
        }
    }

    private var movieCollectionShelf: some View {
        VStack(spacing: 10) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .center,
                spacing: 12
            ) {
                ForEach(movieCollection.movies) { movie in
                    collectionPosterGridCell(movie)
                }

                if movieCollection.movies.count
                    < MovieCollectionStore.maximumMovieCount {
                    GeometryReader { proxy in
                        collectionImportCard(width: proxy.size.width)
                    }
                    .aspectRatio(1 / 1.38, contentMode: .fit)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)

            if isImportingCollectionMovie {
                collectionImportProgressPanel
                    .padding(.horizontal, 18)
            }

            if isCompressingCollectionMovie {
                collectionCompressionProgressPanel
                    .padding(.horizontal, 18)
            }

            if movieCollection.aiPosterTotalCount > 0 {
                collectionAIPosterProgressPanel
                    .padding(.horizontal, 18)
            }

            collectionShelfEdge

            collectionBulkCompressionControls
                .padding(.horizontal, 18)
        }
    }

    private var collectionBulkCompressionControls: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.snappy) {
                    isCollectionBulkCompressionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox")
                    Text("컬렉션 용량 줄이기")
                    Image(
                        systemName: isCollectionBulkCompressionExpanded
                            ? "chevron.up"
                            : "chevron.down"
                    )
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(HanClipTheme.secondaryText.opacity(0.82))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    HanClipTheme.panelFill.opacity(0.62),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            HanClipTheme.panelStroke.opacity(0.45),
                            lineWidth: 1
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(movieCollection.movies.isEmpty)

            if isCollectionBulkCompressionExpanded {
                HStack(spacing: 10) {
                    collectionBulkCompressionButton(
                        title: "720p 일괄 변환",
                        option: .saver720
                    )
                    collectionBulkCompressionButton(
                        title: "540p 일괄 변환",
                        option: .minimum540
                    )
                }

                Text("선택한 해상도 이하인 영상은 그대로 둡니다.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(HanClipTheme.secondaryText.opacity(0.72))
            }
        }
        .padding(.top, 2)
    }

    private func collectionBulkCompressionButton(
        title: String,
        option: CollectionVideoSizeOption
    ) -> some View {
        Button {
            beginCollectionBulkCompression(option: option)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(HanClipTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    HanClipTheme.primary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(
                            HanClipTheme.primary.opacity(0.30),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(isCompressingCollectionMovie || movieCollection.movies.isEmpty)
    }

    private func collectionPosterGridCell(
        _ movie: CollectedMovie
    ) -> some View {
        let posterCell = GeometryReader { proxy in
            let cardWidth = proxy.size.width
            let cardHeight = cardWidth * 1.38
            ZStack(alignment: .top) {
                collectionMovieCard(movie, width: cardWidth)
                    .allowsHitTesting(false)

                Button {
                    guard let currentMovie = movieCollection.movies.first(
                        where: { $0.id == movie.id }
                    ) else { return }
                    selectedCollectionMovie = currentMovie
                } label: {
                    Color.clear
                        .frame(width: cardWidth, height: cardHeight)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    collectionMovieContextMenu(movie)
                }

                Button {
                    withAnimation(.snappy) {
                        movieCollection.togglePin(for: movie)
                    }
                } label: {
                    if movie.isPinned == true {
                        Image("CollectionPin")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 51, height: 51)
                            .brightness(0.10)
                            .saturation(1.10)
                            .shadow(
                                color: Color.black.opacity(0.34),
                                radius: 4,
                                y: 3
                            )
                            .frame(width: 64, height: 64)
                            .contentShape(Rectangle())
                    } else {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.black.opacity(0.98),
                                            Color.black.opacity(0.82),
                                            Color.black.opacity(0.58)
                                        ],
                                        center: .center,
                                        startRadius: 1,
                                        endRadius: 9
                                    )
                                )

                            Circle()
                                .stroke(
                                    Color.white.opacity(0.32),
                                    lineWidth: 0.8
                                )
                                .padding(1)
                        }
                        .frame(width: 18, height: 18)
                        .shadow(
                            color: Color.black.opacity(0.30),
                            radius: 2,
                            y: 1
                        )
                        .frame(width: 44, height: 44, alignment: .top)
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .offset(y: movie.isPinned == true ? -26 : 12)
                .accessibilityLabel(
                    movie.isPinned == true ? "컬렉션 핀 해제" : "컬렉션 핀 고정"
                )
            }
            .frame(width: cardWidth, height: cardHeight, alignment: .top)
            .contentShape(Rectangle())
        }

        return Group {
            if movie.isPinned == true {
                posterCell
                    .draggable(movie.id.uuidString) {
                        collectionMovieCard(movie, width: 132)
                            .frame(width: 132, height: 182)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                            )
                    }
                    .dropDestination(for: String.self) { identifiers, _ in
                        guard let value = identifiers.first,
                              let sourceID = UUID(uuidString: value)
                        else { return false }
                        withAnimation(.snappy) {
                            movieCollection.movePinnedMovie(
                                sourceID: sourceID,
                                onto: movie.id
                            )
                        }
                        return true
                    }
            } else {
                posterCell
            }
        }
        .aspectRatio(1 / 1.38, contentMode: .fit)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func collectionMovieContextMenu(
        _ movie: CollectedMovie
    ) -> some View {
            Button {
                withAnimation(.snappy) {
                    movieCollection.togglePin(for: movie)
                }
            } label: {
                Label(
                    movie.isPinned == true ? "핀 해제" : "핀 고정",
                    systemImage: movie.isPinned == true ? "pin.slash" : "pin"
                )
            }

            Button {
                beginRenamingCollectionMovie(movie)
            } label: {
                Label("제목 수정", systemImage: "pencil")
            }

            Button {
                collectionPosterCandidates = []
                rejectedCollectionPosterCandidates = []
                isLoadingCollectionPosterCandidates = true
                collectionPosterCandidateGeneration = 0
                collectionPosterCandidateMovie = movie
            } label: {
                Label("썸네일 AI 재선택", systemImage: "sparkles")
            }

            Button {
                collectionMovieBeingCompressed = movie
            } label: {
                Label("파일 용량 줄이기", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .disabled(isCompressingCollectionMovie)

            ShareLink(item: movieCollection.videoURL(for: movie)) {
                Label("공유", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                withAnimation(.snappy) {
                    movieCollection.remove(movie)
                }
            } label: {
                Label("컬렉션에서 제거", systemImage: "trash")
            }
    }

    private var collectionImportProgressPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(HanClipTheme.primary)
                Text("컬렉션으로 가져오는 중")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HanClipTheme.primaryText)
                Spacer()
                Text("\(collectionImportCompletedCount)/\(collectionImportTotalCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(HanClipTheme.secondaryText)
            }

            ProgressView(value: collectionImportProgress)
                .tint(HanClipTheme.primary)
        }
        .padding(11)
        .background(
            HanClipTheme.panelFill,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HanClipTheme.panelStroke.opacity(0.62), lineWidth: 1)
        }
    }

    private var collectionCompressionProgressPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(HanClipTheme.primary)
                Text("\(collectionCompressionMovieTitle) 용량 줄이는 중")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HanClipTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(Int((collectionCompressionProgress * 100).rounded()))%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(HanClipTheme.secondaryText)
                Button("취소") {
                    collectionCompressionTask?.cancel()
                }
                .font(.system(size: 10, weight: .bold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ProgressView(value: collectionCompressionProgress)
                .tint(HanClipTheme.primary)
        }
        .padding(11)
        .background(
            HanClipTheme.panelFill,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HanClipTheme.panelStroke.opacity(0.62), lineWidth: 1)
        }
    }

    private var collectionAIPosterProgressPanel: some View {
        let total = max(movieCollection.aiPosterTotalCount, 1)
        let completed = movieCollection.aiPosterCompletedCount
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HanClipTheme.primary)
                Text("AI가 컬렉션의 최고 순간을 고르는 중")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HanClipTheme.primaryText)
                Spacer()
                Text("\(completed)/\(total)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(HanClipTheme.secondaryText)
            }

            ProgressView(value: Double(completed), total: Double(total))
                .tint(HanClipTheme.primary)
        }
        .padding(11)
        .background(
            HanClipTheme.panelFill,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HanClipTheme.panelStroke.opacity(0.62), lineWidth: 1)
        }
    }

    private var collectionShelfEdge: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [
                            HanClipTheme.primary.opacity(0.76),
                            HanClipTheme.secondary.opacity(0.50),
                            HanClipTheme.primary.opacity(0.70)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 9)

            Rectangle()
                .fill(Color.black.opacity(0.16))
                .frame(height: 2)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 5, y: 4)
        .padding(.horizontal, 12)
    }

    private func collectionImportCard(width: CGFloat) -> some View {
        Menu {
            Button {
                collectionMediaSelectionIdentifiers = []
                isCollectionCalendarPickerPresented = false
                isCollectionMediaPickerPresented = true
            } label: {
                Label("사진", systemImage: "photo.on.rectangle")
            }

            Button {
                isCollectionFileImporterPresented = true
            } label: {
                Label("파일", systemImage: "folder")
            }
        } label: {
            ZStack {
                LinearGradient(
                    colors: [
                        HanClipTheme.panelFill,
                        HanClipTheme.secondary.opacity(0.12),
                        HanClipTheme.primary.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 11) {
                    Text("HANCLIP")
                        .font(.system(size: 9, weight: .bold, design: .serif))
                        .tracking(3)

                    Rectangle()
                        .fill(HanClipTheme.secondary.opacity(0.46))
                        .frame(width: width * 0.42, height: 1)

                    Image(systemName: isImportingCollectionMovie ? "hourglass" : "plus")
                        .font(.system(size: 31, weight: .light))

                    Text(isImportingCollectionMovie ? "IMPORTING" : "ADD A FILM")
                        .font(.custom("MaruBuri-Regular", size: 15))
                        .tracking(1.2)

                    Text("COLLECTION")
                        .font(.system(size: 8, weight: .semibold, design: .serif))
                        .tracking(2.4)
                        .opacity(0.72)
                }
                .foregroundStyle(HanClipTheme.secondary)
            }
            .frame(width: width, height: width * 1.38)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        HanClipTheme.secondary.opacity(0.34),
                        style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                    )
            }
            .shadow(color: Color.black.opacity(0.12), radius: 5, y: 3)
        }
        .disabled(isImportingCollectionMovie)
    }

    private func collectionMovieCard(
        _ movie: CollectedMovie,
        width: CGFloat,
        posterOverride: UIImage? = nil
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let poster = posterOverride
                    ?? movieCollection.poster(for: movie) {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "film.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(HanClipTheme.secondary)
                }
            }
            .frame(width: width, height: width * 1.38)
            .background(HanClipTheme.panelFill)
            .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.70),
                    .clear,
                    .black.opacity(0.16),
                    .black.opacity(0.90)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(movie.title)
                    .font(.custom("Cafe24Ssurround", size: 14))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 34)

                Spacer(minLength: 24)

                if let location = movie.locationName, !location.isEmpty {
                    collectionPosterMetadata(
                        location,
                        systemImage: "mappin.and.ellipse",
                        lineLimit: 2
                    )
                }
                if let text = collectionMadeAtText(movie) {
                    collectionPosterMetadata(text, systemImage: "sparkles")
                }
                if let text = collectionShootingPeriodText(movie) {
                    collectionPosterMetadata(text, systemImage: "calendar")
                }
                if let fileSize = collectionFileSize(movie) {
                    collectionPosterMetadata(
                        fileSize,
                        systemImage: "internaldrive.fill"
                    )
                }
                collectionPosterMetadata(
                    collectionDuration(movie.duration),
                    systemImage: "play.fill"
                )
            }
            .padding(8)
        }
        .frame(width: width, height: width * 1.38)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 5, y: 3)
    }

    private func collectionPosterCandidateSheet(
        _ movie: CollectedMovie
    ) -> some View {
        let deviceCandidates = collectionPosterCandidates.filter {
            $0.engine == .deviceAI
        }
        let hanClipCandidates = collectionPosterCandidates.filter {
            $0.engine == .hanClipAI
        }
        let rowCount = max(deviceCandidates.count, hanClipCandidates.count)

        return NavigationStack {
            ZStack {
                HanClipTheme.backgroundGradient.ignoresSafeArea()

                if isLoadingCollectionPosterCandidates
                    && collectionPosterCandidates.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(HanClipTheme.primary)
                        Text("두 AI가 서로 다른 장면 16개를 고르는 중")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(HanClipTheme.primaryText)
                    }
                } else if collectionPosterCandidates.isEmpty {
                    ContentUnavailableView(
                        "썸네일 후보를 만들지 못했습니다",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("영상을 다시 확인한 뒤 시도해 주세요.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                collectionPosterEngineHeader(
                                    "디바이스 AI",
                                    systemImage: "iphone.gen3"
                                )
                                collectionPosterEngineHeader(
                                    "한클립 AI",
                                    systemImage: "sparkles"
                                )
                            }

                            ForEach(0..<rowCount, id: \.self) { index in
                                HStack(alignment: .top, spacing: 12) {
                                    if deviceCandidates.indices.contains(index) {
                                        collectionPosterCandidateButton(
                                            deviceCandidates[index],
                                            movie: movie,
                                            number: index + 1
                                        )
                                    } else {
                                        Color.clear
                                    }

                                    if hanClipCandidates.indices.contains(index) {
                                        collectionPosterCandidateButton(
                                            hanClipCandidates[index],
                                            movie: movie,
                                            number: index + 1
                                        )
                                    } else {
                                        Color.clear
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                    .overlay {
                        if isLoadingCollectionPosterCandidates {
                            ZStack {
                                Color.black.opacity(0.34)
                                    .ignoresSafeArea()

                                VStack(spacing: 12) {
                                    ProgressView()
                                        .controlSize(.large)
                                        .tint(.white)
                                    Text("이전 장면을 제외하고 다시 찾는 중")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .padding(22)
                                .background(.ultraThinMaterial, in: RoundedRectangle(
                                    cornerRadius: 18,
                                    style: .continuous
                                ))
                            }
                        }
                    }
                }
            }
            .navigationTitle("AI 썸네일 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") {
                        closeCollectionPosterCandidatePicker()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        regenerateCollectionPosterCandidates(for: movie)
                    } label: {
                        Label("재생성", systemImage: "arrow.clockwise")
                    }
                    .disabled(
                        isLoadingCollectionPosterCandidates
                            || collectionPosterCandidates.isEmpty
                    )
                }
            }
        }
        .task(id: movie.id) {
            collectionPosterCandidates = await movieCollection
                .posterCandidatesWithAI(
                    for: movie,
                    generation: collectionPosterCandidateGeneration
                )
            isLoadingCollectionPosterCandidates = false
        }
    }

    private func collectionPosterEngineHeader(
        _ title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(HanClipTheme.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(HanClipTheme.panelFill, in: Capsule())
            .overlay {
                Capsule().stroke(HanClipTheme.secondary.opacity(0.55), lineWidth: 1)
            }
    }

    private func collectionPosterCandidateButton(
        _ candidate: CollectionPosterCandidate,
        movie: CollectedMovie,
        number: Int
    ) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Button {
                applyCollectionPosterCandidate(candidate, to: movie)
            } label: {
                collectionPosterCandidateCard(
                    movie,
                    imageData: candidate.imageData,
                    width: width,
                    number: number
                )
            }
            .buttonStyle(.plain)
        }
        .aspectRatio(1 / 1.48, contentMode: .fit)
    }

    private func regenerateCollectionPosterCandidates(
        for movie: CollectedMovie
    ) {
        let rejected = rejectedCollectionPosterCandidates
            + collectionPosterCandidates
        rejectedCollectionPosterCandidates = Array(rejected.suffix(64))
        collectionPosterCandidateGeneration += 1
        isLoadingCollectionPosterCandidates = true
        Task {
            let regenerated = await movieCollection.posterCandidatesWithAI(
                for: movie,
                excluding: rejectedCollectionPosterCandidates,
                generation: collectionPosterCandidateGeneration
            )
            if !regenerated.isEmpty {
                collectionPosterCandidates = regenerated
            }
            isLoadingCollectionPosterCandidates = false
        }
    }

    private func closeCollectionPosterCandidatePicker() {
        collectionPosterCandidateMovie = nil
        collectionPosterCandidates = []
        rejectedCollectionPosterCandidates = []
        isLoadingCollectionPosterCandidates = false
    }

    private func collectionPosterCandidateCard(
        _ movie: CollectedMovie,
        imageData: Data,
        width: CGFloat,
        number: Int
    ) -> some View {
        ZStack(alignment: .top) {
            collectionMovieCard(
                movie,
                width: width,
                posterOverride: UIImage(data: imageData)
            )
            .padding(.top, 16)

            if movie.isPinned == true {
                Image("CollectionPin")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .brightness(0.10)
                    .saturation(1.10)
                    .shadow(color: .black.opacity(0.34), radius: 4, y: 3)
            } else {
                Circle()
                    .fill(Color.black.opacity(0.82))
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.32), lineWidth: 0.8)
                    }
                    .frame(width: 14, height: 14)
                    .padding(.top, 27)
            }

            Text("\(number)")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(HanClipTheme.primary, in: Circle())
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .bottomTrailing)
                .padding(.trailing, 8)
                .padding(.bottom, 8)
        }
    }

    private func applyCollectionPosterCandidate(
        _ candidate: CollectionPosterCandidate,
        to movie: CollectedMovie
    ) {
        do {
            try movieCollection.applyPosterCandidate(
                candidate.imageData,
                to: movie
            )
            closeCollectionPosterCandidatePicker()
        } catch {
            model.alertMessage = error.localizedDescription
        }
    }

    private func collectionPosterMetadata(
        _ text: String,
        systemImage: String,
        lineLimit: Int = 1
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).frame(width: 11)
            Text(text)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.58)
        }
        .font(.system(size: 11.25, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.84))
    }

    private func collectionMadeAtText(_ movie: CollectedMovie) -> String? {
        guard let date = movie.madeAt else { return nil }
        return "제작 " + Self.collectionDateTimeFormatter.string(from: date)
    }

    private func collectionShootingPeriodText(
        _ movie: CollectedMovie
    ) -> String? {
        guard let start = movie.shootingStartAt else { return nil }
        let end = movie.shootingEndAt ?? start
        if let madeAt = movie.madeAt {
            let calendar = Calendar.current
            if calendar.isDate(start, inSameDayAs: madeAt),
               calendar.isDate(end, inSameDayAs: madeAt) {
                return nil
            }
        }
        let startText = Self.collectionDateFormatter.string(from: start)
        let endText = Self.collectionDateFormatter.string(from: end)
        return startText == endText
            ? "촬영 \(startText)"
            : "촬영 \(startText)–\(endText)"
    }

    private static let collectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yy.M.d"
        return formatter
    }()

    private static let collectionDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yy.M.d HH:mm"
        return formatter
    }()

    private func beginRenamingCollectionMovie(_ movie: CollectedMovie) {
        collectionMovieBeingRenamed = movie
        collectionTitleDraft = movie.title
        collectionTitleEditorHeight = 56
        isCollectionTitleEditorPresented = true
    }

    private var collectionTitleEditorSheet: some View {
        NavigationStack {
            GeometryReader { proxy in
                let maximumEditorHeight = max(56, proxy.size.height - 170)

                VStack(alignment: .leading, spacing: 12) {
                    Text("포스터에 표시할 제목을 입력하세요.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HanClipTheme.secondaryText)

                    GrowingCollectionTitleTextView(
                        text: $collectionTitleDraft,
                        measuredHeight: $collectionTitleEditorHeight,
                        maximumHeight: maximumEditorHeight
                    )
                    .frame(
                        height: min(
                            max(56, collectionTitleEditorHeight),
                            maximumEditorHeight
                        )
                    )
                    .padding(.horizontal, 12)
                    .background(
                        HanClipTheme.panelFill,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(HanClipTheme.panelStroke, lineWidth: 1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .navigationTitle("포스터 제목")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        collectionMovieBeingRenamed = nil
                        isCollectionTitleEditorPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        guard let movie = collectionMovieBeingRenamed else {
                            return
                        }
                        movieCollection.updateTitle(
                            collectionTitleDraft,
                            for: movie
                        )
                        collectionMovieBeingRenamed = nil
                        isCollectionTitleEditorPresented = false
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func collectionDuration(_ duration: Double) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func collectionFileSize(_ movie: CollectedMovie) -> String? {
        guard let bytes = movieCollection.fileSizeInBytes(for: movie) else {
            return nil
        }
        return collectionByteCount(bytes)
    }

    private func collectionByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = bytes >= 1_000_000_000 ? [.useGB] : [.useMB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    private func beginCollectionCompression(
        _ movie: CollectedMovie,
        option: CollectionVideoSizeOption
    ) {
        collectionCompressionTask?.cancel()
        collectionCompressionMovieTitle = movie.title
        collectionCompressionProgress = 0
        isCompressingCollectionMovie = true

        collectionCompressionTask = Task { @MainActor in
            defer {
                isCompressingCollectionMovie = false
                collectionCompressionTask = nil
            }
            do {
                let result = try await movieCollection.reduceFileSize(
                    for: movie,
                    option: option
                ) { progress in
                    collectionCompressionProgress = progress
                }
                model.alertMessage = "파일 용량을 줄였습니다. \(collectionByteCount(result.originalBytes)) → \(collectionByteCount(result.compressedBytes))"
            } catch is CancellationError {
                return
            } catch {
                model.alertMessage = error.localizedDescription
            }
        }
    }

    private func beginCollectionBulkCompression(
        option: CollectionVideoSizeOption
    ) {
        let movies = movieCollection.movies
        guard !movies.isEmpty else { return }

        collectionCompressionTask?.cancel()
        collectionCompressionMovieTitle = "컬렉션 준비 중"
        collectionCompressionProgress = 0
        isCompressingCollectionMovie = true

        collectionCompressionTask = Task { @MainActor in
            var convertedCount = 0
            var skippedCount = 0
            var failedCount = 0
            var originalBytes: Int64 = 0
            var compressedBytes: Int64 = 0
            let totalCount = movies.count

            defer {
                isCompressingCollectionMovie = false
                collectionCompressionTask = nil
            }

            do {
                for (index, movie) in movies.enumerated() {
                    try Task.checkCancellation()
                    collectionCompressionMovieTitle =
                        "\(index + 1)/\(totalCount)  \(movie.title)"

                    guard let info = await movieCollection.compressionInfo(
                        for: movie
                    ) else {
                        failedCount += 1
                        collectionCompressionProgress =
                            Double(index + 1) / Double(totalCount)
                        continue
                    }

                    if info.isAtOrBelow(option) {
                        skippedCount += 1
                        collectionCompressionProgress =
                            Double(index + 1) / Double(totalCount)
                        continue
                    }

                    do {
                        let result = try await movieCollection.reduceFileSize(
                            for: movie,
                            option: option
                        ) { progress in
                            collectionCompressionProgress =
                                (Double(index) + progress)
                                / Double(totalCount)
                        }
                        convertedCount += 1
                        originalBytes += result.originalBytes
                        compressedBytes += result.compressedBytes
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        failedCount += 1
                    }

                    collectionCompressionProgress =
                        Double(index + 1) / Double(totalCount)
                }

                var summary = "일괄 변환 완료: \(convertedCount)개 변환"
                if skippedCount > 0 {
                    summary += ", \(skippedCount)개 유지"
                }
                if failedCount > 0 {
                    summary += ", \(failedCount)개 실패"
                }
                if convertedCount > 0 {
                    summary += "\n\(collectionByteCount(originalBytes)) → \(collectionByteCount(compressedBytes))"
                }
                model.alertMessage = summary
            } catch is CancellationError {
                model.alertMessage = "컬렉션 일괄 변환을 취소했습니다. 완료된 영상은 그대로 유지됩니다."
            } catch {
                model.alertMessage = error.localizedDescription
            }
        }
    }

    private func importCollectionFiles(_ urls: [URL]) {
        Task {
            beginCollectionImport(totalCount: urls.count)
            isImportingCollectionMovie = true
            defer { finishCollectionImport() }
            do {
                for (index, url) in urls.enumerated() {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessed { url.stopAccessingSecurityScopedResource() }
                    }
                    try await movieCollection.importMovie(from: url)
                    updateCollectionImportProgress(
                        completedCount: index + 1
                    )
                }
            } catch {
                model.alertMessage = "컬렉션으로 가져오지 못했습니다. \(error.localizedDescription)"
            }
        }
    }

    private func importCollectionAssetIdentifiers(_ identifiers: [String]) {
        Task {
            beginCollectionImport(totalCount: identifiers.count)
            isImportingCollectionMovie = true
            defer { finishCollectionImport() }
            do {
                var importedCount = 0
                for identifier in identifiers {
                    let source = try await photoLibraryVideoSource(
                        identifier: identifier
                    )
                    try await movieCollection.importMovie(
                        from: source.url,
                        madeAt: source.creationDate,
                        shootingRange: source.creationDate.map { $0...$0 },
                        location: source.location
                    )
                    importedCount += 1
                    updateCollectionImportProgress(
                        completedCount: importedCount
                    )
                }
                if importedCount == 0 {
                    throw CocoaError(.fileReadNoSuchFile)
                }
            } catch {
                model.alertMessage = "컬렉션으로 가져오지 못했습니다. \(error.localizedDescription)"
            }
        }
    }

    private func beginCollectionImport(totalCount: Int) {
        collectionImportTotalCount = max(1, totalCount)
        collectionImportCompletedCount = 0
        collectionImportProgress = 0.03
    }

    private func updateCollectionImportProgress(completedCount: Int) {
        collectionImportCompletedCount = completedCount
        collectionImportProgress = min(
            1,
            Double(completedCount) / Double(max(1, collectionImportTotalCount))
        )
    }

    private func finishCollectionImport() {
        isImportingCollectionMovie = false
        if collectionImportCompletedCount >= collectionImportTotalCount {
            collectionImportProgress = 1
        }
    }

    private func photoLibraryVideoSource(
        identifier: String
    ) async throws -> (url: URL, creationDate: Date?, location: CLLocation?) {
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        )
        guard let asset = assets.firstObject else {
            throw CocoaError(.fileNoSuchFile)
        }
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let avAsset = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<AVAsset, Error>) in
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { asset, _, info in
                if let asset {
                    continuation.resume(returning: asset)
                } else {
                    let error = info?[PHImageErrorKey] as? Error
                        ?? CocoaError(.fileReadUnknown)
                    continuation.resume(throwing: error)
                }
            }
        }
        guard let urlAsset = avAsset as? AVURLAsset else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return (urlAsset.url, asset.creationDate, asset.location)
    }

    private var aiShotProjects: [SavedProjectSummary] {
        model.savedProjects.filter { $0.kind == .aiShot }
    }

    private var standardProjects: [SavedProjectSummary] {
        model.savedProjects.filter { $0.kind == .standard }
    }

    private func projectCategoryHeader(
        title: String,
        count: Int,
        systemImage: String,
        assetImage: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Group {
                if let assetImage {
                    Image(assetImage)
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                }
            }
                .foregroundStyle(HanClipTheme.onSecondary)
                .frame(width: 26, height: 26)
                .background(
                    LinearGradient(
                        colors: [
                            HanClipTheme.primary,
                            HanClipTheme.secondary
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 7)
                )

            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(HanClipTheme.primaryText)

            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(HanClipTheme.secondary)
                .frame(minWidth: 22, minHeight: 22)
                .background(
                    HanClipTheme.secondary.opacity(0.10),
                    in: Circle()
                )

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
    }

    private func savedProjectRows(
        _ projects: [SavedProjectSummary]
    ) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(projects) { project in
                SwipeToDeleteRow {
                    withAnimation {
                        model.deleteProject(id: project.id)
                    }
                } content: {
                    savedProjectRow(project)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func aiShotProjectGrid(
        _ projects: [SavedProjectSummary]
    ) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 8),
                count: 2
            ),
            spacing: 8
        ) {
            ForEach(projects) { project in
                SwipeToDeleteRow(
                    cornerRadius: 16,
                    onDelete: {
                        withAnimation {
                            model.deleteProject(id: project.id)
                        }
                    }
                ) {
                    aiShotProjectCard(project)
                }
            }

            ForEach(
                0..<max(
                    0,
                    ProjectStore.maximumAiShotProjectCount - projects.count
                ),
                id: \.self
            ) { _ in
                emptyAiShotProjectCard
            }
        }
        .padding(.horizontal, 16)
    }

    private func standardEmptyProjectRows(count: Int) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { _ in
                emptyProjectPlaceholder(isAiShot: false)
            }
        }
    }

    private func aiShotProjectCard(
        _ project: SavedProjectSummary
    ) -> some View {
        let secondaryThumbnails = Array(
            ProjectStore.thumbnailImages(for: project).prefix(3)
        )

        return HStack(spacing: 8) {
            Group {
                if let thumbnail = ProjectStore.thumbnailImage(for: project) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image("AiShotIcon")
                        .resizable()
                        .scaledToFit()
                        .padding(13)
                        .foregroundStyle(HanClipTheme.secondary)
                }
            }
            .frame(width: 58, height: 58)
            .background(HanClipTheme.panelFill)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(compactHomeProjectDateText(project.updatedAt))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HanClipTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(
                    "클립 \(project.clipCount)개 · "
                        + projectDurationText(project.totalDuration)
                )
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(HanClipTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

                HStack(spacing: 4) {
                    ForEach(
                        Array(secondaryThumbnails.enumerated()),
                        id: \.offset
                    ) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 20, height: 18)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 4,
                                    style: .continuous
                                )
                            )
                    }
                }
                .frame(height: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.panelFill.opacity(0.96),
                    HanClipTheme.secondary.opacity(0.10),
                    Color.white.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HanClipTheme.panelStroke, lineWidth: 1)
        }
        .shadow(
            color: HanClipTheme.secondary.opacity(0.08),
            radius: 10,
            y: 5
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            resumeAiShotProject(id: project.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("한 번 누르면 AiShot을 계속합니다.")
    }

    private var emptyAiShotProjectCard: some View {
        let placeholderColor = HanClipTheme.secondary.opacity(0.12)

        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(placeholderColor)
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(placeholderColor)
                    .frame(height: 10)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(placeholderColor.opacity(0.72))
                    .frame(height: 8)

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(placeholderColor.opacity(0.65))
                            .frame(width: 20, height: 18)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.panelFill.opacity(0.72),
                    HanClipTheme.secondary.opacity(0.065),
                    Color.white.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HanClipTheme.panelStroke.opacity(0.68), lineWidth: 1)
        }
        .opacity(0.35)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func emptyProjectPlaceholder(isAiShot: Bool) -> some View {
        let placeholderColor = HanClipTheme.secondary.opacity(
            isAiShot ? 0.13 : 0.085
        )

        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(placeholderColor)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(placeholderColor)
                    .frame(width: 112, height: 12)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(placeholderColor.opacity(0.78))
                    .frame(width: 152, height: 9)

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(placeholderColor.opacity(0.68))
                            .frame(width: 20, height: 14)
                    }
                }
            }

            Spacer()

            HStack(spacing: 0) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText.opacity(0.42))
                    .frame(width: 32, height: 32)

                Image(systemName: "pin")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(HanClipTheme.secondaryText.opacity(0.38))
                    .frame(width: 32, height: 32)
            }
        }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(
                LinearGradient(
                    colors: [
                        HanClipTheme.panelFill.opacity(0.72),
                        HanClipTheme.secondary.opacity(isAiShot ? 0.065 : 0.025),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(HanClipTheme.panelStroke.opacity(0.68), lineWidth: 1)
            }
            .shadow(
                color: HanClipTheme.secondary.opacity(0.045),
                radius: 10,
                y: 5
            )
            .opacity(0.35)
            .padding(.horizontal, 16)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func savedProjectRow(
        _ project: SavedProjectSummary
    ) -> some View {
        let isMemoExpanded = expandedMemoProjectID == project.id

        return VStack(spacing: isMemoExpanded ? 7 : 0) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                Group {
                    if let thumbnail = ProjectStore.thumbnailImage(for: project) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        if project.kind == .aiShot {
                            Image("AiShotIcon")
                                .resizable()
                                .scaledToFit()
                                .padding(14)
                                .foregroundStyle(HanClipTheme.secondary)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(HanClipTheme.secondary)
                        }
                    }
                }
                .frame(width: 56, height: 56)
                .background(HanClipTheme.panelFill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                }
                .shadow(
                    color: Color.black.opacity(0.07),
                    radius: 6,
                    y: 3
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(homeProjectDateText(project.updatedAt))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HanClipTheme.primaryText)
                        .lineLimit(1)

                        if model.newlySavedProjectID == project.id {
                            Text("NEW")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(red: 0.78, green: 0.13, blue: 0.18))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Color(red: 0.92, green: 0.20, blue: 0.24)
                                        .opacity(0.13),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            Color(red: 0.92, green: 0.20, blue: 0.24)
                                                .opacity(0.32),
                                            lineWidth: 1
                                        )
                                }
                                .fixedSize()
                        }
                    }

                    HStack(spacing: 4) {
                        Text("클립 \(project.clipCount)개 ·")

                        Image(
                            systemName: project.initialMoviePreset?.systemImage
                                ?? (project.kind == .aiShot
                                    ? "camera.fill"
                                    : "film")
                        )
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(HanClipTheme.primary.opacity(0.78))
                        .accessibilityHidden(true)

                        Text(
                            projectDurationText(project.totalDuration)
                                + projectFileSizeSuffix(
                                    project.storedByteCount
                                )
                        )
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(HanClipTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                    projectThumbnailStrip(project)
                }
                .frame(maxHeight: 56, alignment: .center)

                Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if project.kind == .aiShot {
                        resumeAiShotProject(id: project.id)
                    } else {
                        model.loadProjectAndImportPending(id: project.id)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint(
                    project.kind == .aiShot
                        ? "한 번 누르면 AiShot을 계속합니다."
                        : "한 번 누르면 영화를 엽니다."
                )

                if project.kind == .aiShot {
                    Button {
                        resumeAiShotProject(id: project.id)
                    } label: {
                        Image("AiShotIcon")
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .foregroundStyle(HanClipTheme.onSecondary)
                            .frame(width: 34, height: 34)
                            .background(
                                LinearGradient(
                                    colors: [
                                        HanClipTheme.primary,
                                        HanClipTheme.secondary
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("AiShot 계속")
                } else {
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.snappy) {
                                if isMemoExpanded {
                                    focusedMemoProjectID = nil
                                    expandedMemoProjectID = nil
                                } else {
                                    expandedMemoProjectID = project.id
                                    DispatchQueue.main.async {
                                        focusedMemoProjectID = project.id
                                    }
                                }
                            }
                        } label: {
                            Image(
                                systemName: project.memo.isEmpty
                                    ? "square.and.pencil"
                                    : "note.text"
                            )
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                project.memo.isEmpty
                                    ? HanClipTheme.secondaryText.opacity(0.42)
                                    : HanClipTheme.secondary
                            )
                            .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            isMemoExpanded ? "메모 닫기" : "메모 편집"
                        )

                        Button {
                            withAnimation {
                                model.toggleProjectPin(id: project.id)
                            }
                        } label: {
                            Image(systemName: project.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(
                                    project.isPinned
                                        ? HanClipTheme.primary
                                        : HanClipTheme.secondaryText.opacity(0.38)
                                )
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(project.isPinned ? "핀 해제" : "핀 고정")
                        .accessibilityHint(
                            "이 영화를 영화 목록 상단에 고정하거나 해제합니다."
                        )
                    }
                }
            }
            .frame(height: 56)

            if isMemoExpanded {
                ProjectMemoField(
                    projectID: project.id,
                    memo: project.memo,
                    focusedMemoProjectID: $focusedMemoProjectID
                ) { memo in
                    model.updateProjectMemo(id: project.id, memo: memo)
                }
                .frame(height: 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: isMemoExpanded ? 107 : 72)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.panelFill.opacity(0.96),
                    HanClipTheme.secondary.opacity(
                        project.kind == .aiShot ? 0.10 : 0.045
                    ),
                    Color.white.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    HanClipTheme.panelStroke,
                    lineWidth: 1
                )
        }
        .shadow(
            color: HanClipTheme.secondary.opacity(0.08),
            radius: 12,
            y: 6
        )
        .contentShape(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func projectThumbnailStrip(
        _ project: SavedProjectSummary
    ) -> some View {
        let images = ProjectStore.thumbnailImages(for: project)

        return HStack(spacing: 3) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            if project.clipCount > 9 {
                Text("....")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HanClipTheme.text.opacity(0.62))
            }
        }
        .frame(height: 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func projectDurationText(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = duration - Double(minutes * 60)
        if minutes > 0 {
            return String(format: "%d분 %.1f초", minutes, seconds)
        }
        return String(format: "%.1f초", seconds)
    }

    private func homeProjectDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm"
        return formatter.string(from: date)
    }

    private func compactHomeProjectDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d a h:mm"
        return formatter.string(from: date)
    }

    private func projectFileSizeSuffix(_ byteCount: Int64?) -> String {
        guard let byteCount else { return "" }
        let formatted = ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
        return " · \(formatted)"
    }

    private func deleteClipFromEditor(id: UUID) {
        let editableClips = currentPreviewClips
        guard let index = editableClips.firstIndex(where: { $0.id == id })
        else {
            closeClipPreview()
            return
        }

        if videoSegmentPreviewParentID != nil {
            guard editableClips.count > 1 else { return }
            let nextIndex = editableClips.index(after: index)
            let nextClipID: UUID
            if nextIndex < editableClips.endIndex {
                nextClipID = editableClips[nextIndex].id
            } else {
                nextClipID = editableClips[
                    editableClips.index(before: index)
                ].id
            }

            withAnimation(.snappy) {
                selectedClipID = nextClipID
                model.setVideoSegmentIncluded(id: id, isIncluded: false)
            }
            return
        }

        let nextIndex = editableClips.index(after: index)
        let nextClipID: UUID?
        if nextIndex < editableClips.endIndex {
            nextClipID = editableClips[nextIndex].id
        } else if index > editableClips.startIndex {
            nextClipID = editableClips[editableClips.index(before: index)].id
        } else {
            nextClipID = nil
        }

        withAnimation(.snappy) {
            if let nextClipID {
                selectedClipID = nextClipID
            } else {
                closeClipPreview()
            }
            model.removeClip(id: id)
        }
    }

    private func bindingForClip(
        id: UUID,
        fallback: ClipItem
    ) -> Binding<ClipItem> {
        Binding(
            get: {
                model.clips.first(where: { $0.id == id }) ?? fallback
            },
            set: { updatedClip in
                guard let index = model.clips.firstIndex(
                    where: { $0.id == id }
                ) else { return }
                model.clips[index] = updatedClip
            }
        )
    }

    private var clipEditor: some View {
        VStack(spacing: 0) {
            if isReordering {
                ScrollView {
                    VStack(spacing: 0) {
                        clipEditorSettings

                        clipModeHeader

                        reorderGrid
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                }
                .scrollIndicators(.hidden)
                .background(
                    HanClipTheme.panelFill
                )
            } else {
                clipList
            }
        }
        .id(themeModeRaw)
    }

    private var clipList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                clipEditorSettings

                clipModeHeader

                ForEach($model.clips) { $clip in
                    if model.shouldDisplayClip(clip) {
                        SwipeToDeleteRow(
                            accessibilityLabel: "클립 삭제",
                            cornerRadius: 0
                        ) {
                            if clip.isVideoSegmentChild {
                                model.setVideoSegmentIncluded(
                                    id: clip.id,
                                    isIncluded: false
                                )
                            } else {
                                model.removeClip(id: clip.id)
                            }
                        } content: {
                            VStack(spacing: 0) {
                                ClipRow(
                                    position: clipPosition(for: clip.id),
                                    clip: $clip,
                                    defaultDuration: model.defaultDuration,
                                    childSegmentCount: clip.isSimilarPhotoGroupParent
                                        ? model.similarPhotoGroupPreviewItems(
                                            for: clip.id
                                        ).filter(\.isIncluded).count
                                        : model.childSegmentCount(for: clip.id),
                                    childSegmentDuration: clip.isSimilarPhotoGroupParent
                                        ? model.similarPhotoGroupDuration(
                                            for: clip.id
                                        )
                                        : model.childSegmentDuration(for: clip.id),
                                    canShowVideoSegmentSwitch: model
                                        .canUseMultipleVideoSegments(for: clip.id),
                                    isSimilarPhotoGroupExpanded: model
                                        .isSimilarPhotoGroupExpanded(for: clip),
                                    onSelectVideoSegmentMode: { mode in
                                        withAnimation(.snappy) {
                                            model.setVideoSegmentMode(
                                                id: clip.id,
                                                mode: mode
                                            )
                                        }
                                    },
                                    onSelectSimilarPhotoGroupMode: { mode in
                                        withAnimation(.snappy) {
                                            model.setSimilarPhotoGroupMode(
                                                id: clip.id,
                                                mode: mode
                                            )
                                        }
                                    },
                                    onResetVideoSegments: {
                                        withAnimation(.snappy) {
                                            pendingSegmentResetClipID = clip.id
                                        }
                                    },
                                    onSelectParentClipPreview: {
                                        if clip.isSimilarPhotoGroupParent {
                                            isAutoAdvancingPreview = false
                                            isLoopingPreviewAutoAdvance = false
                                            videoSegmentPreviewParentID = nil
                                            selectedClipID = clip.id
                                            return
                                        }
                                        let childClips = model.renderableClips.filter {
                                            $0.videoSegmentParentID == clip.id
                                        }
                                        guard let firstChildClip = childClips.first
                                        else { return }
                                        isAutoAdvancingPreview = false
                                        isLoopingPreviewAutoAdvance = false
                                        videoSegmentPreviewParentID = clip.id
                                        selectedClipID = firstChildClip.id
                                    },
                                    onToggleSimilarPhotoGroup: {
                                        withAnimation(.snappy) {
                                            model.toggleSimilarPhotoGroup(
                                                for: clip.id
                                            )
                                        }
                                    },
                                    onSetVideoSegmentIncluded: { isIncluded in
                                        withAnimation(.snappy) {
                                            model.setVideoSegmentIncluded(
                                                id: clip.id,
                                                isIncluded: isIncluded
                                            )
                                        }
                                    },
                                    onSetSimilarPhotoIncluded: { isIncluded in
                                        withAnimation(.snappy) {
                                            model.setSimilarPhotoIncluded(
                                                id: clip.id,
                                                isIncluded: isIncluded
                                            )
                                        }
                                    },
                                    similarPhotoGroupPreviewItems: clip
                                        .isSimilarPhotoGroupParent
                                        ? model.similarPhotoGroupPreviewItems(
                                            for: clip.id
                                        )
                                        : clip.isVideoSegmentParent
                                            ? model.videoSegmentPreviewItems(
                                                for: clip.id
                                            )
                                        : [],
                                    displayAsSimilarPhotoChild: false,
                                    onSelect: {
                                        if clip.isSimilarPhotoGroupParent {
                                            isAutoAdvancingPreview = false
                                            isLoopingPreviewAutoAdvance = false
                                            videoSegmentPreviewParentID = nil
                                            selectedClipID = clip.id
                                            return
                                        }
                                        if clip.isVideoSegmentParent {
                                            let childClips = model.renderableClips.filter {
                                                $0.videoSegmentParentID == clip.id
                                            }
                                            guard let firstChildClip = childClips.first
                                            else { return }
                                            isAutoAdvancingPreview = false
                                            isLoopingPreviewAutoAdvance = false
                                            videoSegmentPreviewParentID = nil
                                            selectedClipID = firstChildClip.id
                                            return
                                        }
                                        isAutoAdvancingPreview = false
                                        isLoopingPreviewAutoAdvance = false
                                        videoSegmentPreviewParentID = nil
                                        selectedClipID = clip.id
                                    }
                                )
                                .padding(clipRowInsets(for: clip.id))
                                .background(clipRowFill(for: clip))
                                .background(alignment: .leading) {
                                    clipRowRoleAccent(for: clip)
                                }
                                .overlay(alignment: .top) {
                                    clipRowTopDivider(for: clip)
                                }
                                .overlay(alignment: .bottom) {
                                    clipRowBottomDivider(for: clip)
                                }
                                .accessibilityHint(
                                    "눌러서 편집을 열고, 순서 변경 버튼에서 위치를 바꿉니다."
                                )

                                if clip.isSimilarPhotoGroupParent
                                    && model.isSimilarPhotoGroupExpanded(for: clip) {
                                    ForEach(
                                        model.similarPhotoGroupClipIDs(
                                            for: clip.id
                                        ),
                                        id: \.self
                                    ) { childID in
                                        if let childIndex = model.clips
                                            .firstIndex(where: { $0.id == childID }) {
                                            ClipRow(
                                                position: clipPosition(for: childID),
                                                clip: $model.clips[childIndex],
                                                defaultDuration: model.defaultDuration,
                                                childSegmentCount: 0,
                                                childSegmentDuration: 0,
                                                canShowVideoSegmentSwitch: false,
                                                isSimilarPhotoGroupExpanded: false,
                                                onSelectVideoSegmentMode: { _ in },
                                                onSelectSimilarPhotoGroupMode: { _ in },
                                                onResetVideoSegments: {},
                                                onSelectParentClipPreview: {
                                                    selectedClipID = childID
                                                },
                                                onToggleSimilarPhotoGroup: {},
                                                onSetVideoSegmentIncluded: { _ in },
                                                onSetSimilarPhotoIncluded: {
                                                    isIncluded in
                                                    withAnimation(.snappy) {
                                                        model.setSimilarPhotoIncluded(
                                                            id: childID,
                                                            isIncluded: isIncluded
                                                        )
                                                    }
                                                },
                                                similarPhotoGroupPreviewItems: [],
                                                displayAsSimilarPhotoChild: true,
                                                onSelect: {
                                                    isAutoAdvancingPreview = false
                                                    isLoopingPreviewAutoAdvance = false
                                                    videoSegmentPreviewParentID = nil
                                                    selectedClipID = childID
                                                }
                                            )
                                            .padding(clipRowInsets(for: childID))
                                            .background(
                                                HanClipTheme.secondary.opacity(
                                                    themeMode == .dark ? 0.030 : 0.044
                                                )
                                            )
                                            .background(alignment: .leading) {
                                                Rectangle()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [
                                                                HanClipTheme.primary
                                                                    .opacity(0.026),
                                                                HanClipTheme.secondary
                                                                    .opacity(0.010),
                                                                Color.clear
                                                            ],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                                    .frame(width: 118)
                                            }
                                            .overlay(alignment: .bottom) {
                                                Rectangle()
                                                    .fill(
                                                        HanClipTheme.secondary
                                                            .opacity(0.12)
                                                    )
                                                    .frame(height: 0.8)
                                                    .padding(.leading, 70)
                                                    .padding(.trailing, 14)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                clipListFooterControls
                    .padding(
                        EdgeInsets(
                            top: 10,
                            leading: 0,
                            bottom: 18,
                            trailing: 0
                        )
                    )
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private var summaryControlRowFill: Color {
        HanClipTheme.secondary.opacity(themeMode == .dark ? 0.034 : 0.032)
    }

    private func clipRowFill(for clip: ClipItem) -> Color {
        if clip.isVideoSegmentParent || clip.isSimilarPhotoGroupParent {
            return HanClipTheme.secondary.opacity(
                themeMode == .dark ? 0.052 : 0.074
            )
        }
        if clip.isVideoSegmentChild || clip.isSimilarPhotoGroupChild {
            return HanClipTheme.secondary.opacity(
                themeMode == .dark ? 0.030 : 0.044
            )
        }
        return HanClipTheme.secondary.opacity(
            themeMode == .dark ? 0.020 : 0.022
        )
    }

    @ViewBuilder
    private func clipRowRoleAccent(for clip: ClipItem) -> some View {
        if clip.isVideoSegmentParent || clip.isSimilarPhotoGroupParent {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            HanClipTheme.primary.opacity(0.052),
                            HanClipTheme.secondary.opacity(0.018),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 118)
        } else if clip.isVideoSegmentChild || clip.isSimilarPhotoGroupChild {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            HanClipTheme.primary.opacity(0.026),
                            HanClipTheme.secondary.opacity(0.010),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 92)
        }
    }

    private func clipRowTopDivider(for clip: ClipItem) -> some View {
        Rectangle()
            .fill(
                clip.isVideoSegmentChild
                    ? HanClipTheme.primary.opacity(0.08)
                    : HanClipTheme.secondary.opacity(0.10)
            )
            .frame(height: clip.isVideoSegmentChild ? 0.5 : 0.7)
            .padding(.leading, clip.isVideoSegmentChild ? 70 : 14)
            .padding(.trailing, 14)
    }

    private func clipRowBottomDivider(for clip: ClipItem) -> some View {
        Rectangle()
            .fill(
                clip.isVideoSegmentParent
                    ? HanClipTheme.primary.opacity(0.13)
                    : HanClipTheme.secondary.opacity(0.10)
            )
            .frame(height: clip.isVideoSegmentParent ? 0.9 : 0.7)
            .padding(.leading, clip.isVideoSegmentChild ? 70 : 14)
            .padding(.trailing, 14)
    }

    private var clipEditorSettings: some View {
        VStack(spacing: 0) {
            clipSettingsHeader

            clipSettingsSectionTitle
                .padding(.top, 2)
                .padding(.bottom, isClipSettingsExpanded ? 4 : 10)

            if isClipSettingsExpanded {
                defaultDurationPanel
                    .padding(.horizontal, 14)
                    .padding(.top, 0)
                    .padding(.bottom, 10)
                    .transition(
                        .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .animation(.snappy, value: isClipSettingsExpanded)
    }

    private var clipSettingsHeader: some View {
        HanClipTitleLine(
            "영화 제작",
            systemImage: "film.stack",
            leadingInset: 18,
            trailingInset: 20
        )
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private var clipSettingsSectionTitle: some View {
        Button {
            isClipSettingsExpanded.toggle()
        } label: {
            ZStack {
                HStack(spacing: 9) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(HanClipTheme.primary.opacity(0.86))
                        .frame(width: 28, height: 28)
                        .background(
                            HanClipTheme.secondary.opacity(0.10),
                            in: RoundedRectangle(
                                cornerRadius: 8,
                                style: .continuous
                            )
                        )
                        .accessibilityHidden(true)

                    Text("클립 설정")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(
                            HanClipTheme.secondaryText.opacity(0.90)
                        )

                    Spacer()

                    HStack(spacing: 6) {
                        Image(
                            systemName: model.activeMoviePreset?.systemImage
                                ?? "film"
                        )
                        .accessibilityHidden(true)

                        Text(
                            model.activeMoviePreset?.displayTitle
                                ?? "기존 영화"
                        )
                        .lineLimit(1)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(width: 112, height: 34)
                    .background(
                        HanClipTheme.secondary.opacity(0.10),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                HanClipTheme.secondary.opacity(0.28),
                                lineWidth: 1
                            )
                    }
                }

                Image(
                    systemName: isClipSettingsExpanded
                        ? "chevron.up"
                        : "chevron.down"
                )
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(HanClipTheme.secondaryText.opacity(0.78))
                .frame(width: 32, height: 48, alignment: .center)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48, alignment: .center)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("클립 설정")
        .accessibilityValue(
            "\(model.activeMoviePreset?.displayTitle ?? "기존 영화"), "
                + (isClipSettingsExpanded ? "펼쳐짐" : "접힘")
        )
        .accessibilityHint("두 번 탭하여 클립 설정을 펼치거나 접습니다.")
    }

    private var clipListFooterControls: some View {
        HStack(spacing: 12) {
            mediaImportMenu {
                circularMediaAddControl(systemImage: "plus")
            }
            .accessibilityLabel("미디어 추가")
            .accessibilityHint(
                "현재 영화의 마지막에 사진이나 영상을 추가합니다."
            )

            if model.clips.isEmpty {
                Button {
                    withAnimation(.snappy) {
                        videoSegmentPreviewParentID = nil
                        selectedClipID = nil
                        draggedClipID = nil
                        isReordering = false
                        model.reset()
                    }
                } label: {
                    circularMediaAddControl(systemImage: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("첫 화면으로 이동")
                .accessibilityHint("현재 빈 영화를 닫고 첫 화면으로 돌아갑니다.")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func clipPosition(for id: UUID) -> Int? {
        guard let index = model.renderableClips.firstIndex(where: {
            $0.id == id
        }) else {
            return nil
        }
        return index + 1
    }

    private func clipRowInsets(for id: UUID) -> EdgeInsets {
        let clipIndex = model.clips.firstIndex { $0.id == id }
        let isChildRow = clipIndex.map {
            model.clips[$0].isVideoSegmentChild
                || model.clips[$0].isSimilarPhotoGroupChild
        } ?? false
        let isFollowedByChildRow = clipIndex.map { index in
            let nextIndex = model.clips.index(after: index)
            return nextIndex < model.clips.endIndex
                && (model.clips[nextIndex].isVideoSegmentChild
                    || model.clips[nextIndex].isSimilarPhotoGroupChild)
        } ?? false
        return EdgeInsets(
            top: isChildRow
                ? 0
                : model.clips.first?.id == id ? 12 : 3,
            leading: 14,
            bottom: clipRowBottomInset(
                id: id,
                isVideoSegmentChild: isChildRow,
                isFollowedByVideoSegmentChild: isFollowedByChildRow
            ),
            trailing: 14
        )
    }

    private func clipRowBottomInset(
        id: UUID,
        isVideoSegmentChild: Bool,
        isFollowedByVideoSegmentChild: Bool
    ) -> CGFloat {
        if isVideoSegmentChild {
            return isFollowedByVideoSegmentChild ? 0 : 4
        }
        if isFollowedByVideoSegmentChild {
            return 0
        }
        return model.clips.last?.id == id ? 14 : 3
    }

    private var clipModeHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(HanClipTheme.primary.opacity(0.86))
                .frame(width: 28, height: 28)
                .background(
                    HanClipTheme.secondary.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 8,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)

            Text("클립 \(model.renderableClips.count)개")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HanClipTheme.secondaryText.opacity(0.90))

            Spacer()

            Button {
                withAnimation {
                    draggedClipID = nil
                    isReordering.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    if isReordering {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "square.grid.2x2")
                            .accessibilityHidden(true)
                    }

                    Text(isReordering ? "완료" : "순서 변경")
                }
                .padding(.horizontal, 12)
                .frame(width: 112, height: 34)
                .background(
                    isReordering
                        ? HanClipTheme.primary
                        : HanClipTheme.secondary.opacity(0.10),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            isReordering
                                ? Color.white.opacity(0.28)
                                : HanClipTheme.secondary.opacity(0.28),
                            lineWidth: 1
                        )
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(
                isReordering ? Color.white : HanClipTheme.secondaryText
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 9)
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.background.opacity(0.36),
                    HanClipTheme.secondary.opacity(0.050)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HanClipTheme.secondary.opacity(0.16))
                .frame(height: 0.8)
                .padding(.horizontal, 14)
        }
    }

    private var defaultDurationPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText.opacity(0.78))
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)

                Text("영상 길이")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText)

                Spacer()

                VideoRangeSegmentedControl(
                    usesFullVideo: Binding(
                        get: { isSelectAllChecked },
                        set: { usesFullVideo in
                            guard usesFullVideo != isSelectAllChecked else {
                                return
                            }
                            toggleSelectAllFullRange()
                        }
                    ),
                    tint: HanClipTheme.secondary,
                    width: 112,
                    height: 24
                )
                .accessibilityLabel("모든 영상 길이")
                .accessibilityValue(
                    isSelectAllChecked ? "전체영상" : "선택구간"
                )
                .accessibilityHint(
                    "모든 영상의 선택 구간만 쓰거나 전체 길이를 사용합니다."
                )
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: 48)

            settingsPanelDivider

            HStack(spacing: 8) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText.opacity(0.78))
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)

                Text("기본시간")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 52, alignment: .leading)

                HStack(spacing: 0) {
                        Button {
                            adjustDefaultDuration(by: -0.1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 40, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.defaultDuration <= 0.1)
                        .accessibilityLabel("기본시간 줄이기")

                        Text("\(model.defaultDuration, specifier: "%.1f")초")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 38)
                            .accessibilityLabel(
                                "기본시간 \(model.defaultDuration, specifier: "%.1f")초"
                            )

                        Button {
                            adjustDefaultDuration(by: 0.1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 40, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.defaultDuration >= 30)
                        .accessibilityLabel("기본시간 늘리기")
                }
                .foregroundStyle(HanClipTheme.secondaryText)
                .frame(width: 118, height: 44)
                    .background {
                        Capsule()
                            .fill(HanClipTheme.secondary.opacity(0.09))
                            .frame(height: 24)
                    }
                    .overlay {
                        Capsule()
                            .stroke(
                                HanClipTheme.secondary.opacity(0.20),
                                lineWidth: 1
                            )
                            .frame(height: 24)
                    }
                Spacer(minLength: 4)

                Button {
                        model.applyDefaultDurationToAll()
                        UIImpactFeedbackGenerator(style: .light)
                            .impactOccurred()
                        showTopActionNotice("전체 클립에 적용했습니다")
                    } label: {
                        Text("적용")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 112, height: 44)
                            .contentShape(Rectangle())
                            .background {
                                LinearGradient(
                                    colors: [
                                        HanClipTheme.primary.opacity(0.94),
                                        HanClipTheme.secondary.opacity(0.82)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(height: 26)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 8,
                                        style: .continuous
                                    )
                                )
                            }
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 8,
                                    style: .continuous
                                )
                                .stroke(
                                    Color.white.opacity(0.42),
                                    lineWidth: 1
                                )
                                .frame(height: 26)
                            }
                            .shadow(
                                color: HanClipTheme.primary.opacity(0.16),
                                radius: 6,
                                y: 2
                            )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("기본시간 전체 적용")
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: 48)

            settingsPanelDivider

            HStack(spacing: 8) {
                Image(systemName: "livephoto")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText.opacity(0.78))
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)

                Text("라이브포토")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText)

                Spacer()

                LivePhotoModeSegmentedControl(
                    mode: Binding(
                        get: { bulkLivePhotoMode },
                        set: { mode in
                            bulkLivePhotoMode = mode
                            model.applyLivePhotoModeToAll(mode)
                        }
                    ),
                    tint: HanClipTheme.secondary,
                    width: 112,
                    height: 24
                )
                .accessibilityLabel("모든 라이브포토 사용 방식")
                .accessibilityValue(
                    bulkLivePhotoMode == .still ? "사진" : "영상"
                )
                .accessibilityHint(
                    "모든 라이브포토 클립을 사진 또는 영상으로 전환합니다."
                )
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: 48)

            settingsPanelDivider

            HStack(spacing: 8) {
                Image(systemName: "film.stack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText.opacity(0.78))
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)

                Text("영상")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText)

                Spacer()

                VideoSegmentModeSegmentedControl(
                    mode: Binding(
                        get: { model.defaultVideoSegmentMode },
                        set: { mode in
                            model.applyVideoSegmentModeToAll(mode)
                            UIImpactFeedbackGenerator(style: .light)
                                .impactOccurred()
                            showTopActionNotice(
                                mode == .single
                                    ? "전체 영상을 한컷으로 바꿨습니다"
                                    : "전체 영상을 분할로 바꿨습니다"
                            )
                        }
                    ),
                    tint: HanClipTheme.secondary,
                    width: 112,
                    height: 24
                )
                .accessibilityLabel("모든 영상 선택 방식")
                .accessibilityValue(
                    model.defaultVideoSegmentMode == .single
                        ? "한컷"
                        : "분할"
                )
                .accessibilityHint(
                    "모든 영상을 한컷 또는 분할 방식으로 전환합니다."
                )
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: 48)

            settingsPanelDivider

            HStack(spacing: 8) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText.opacity(0.78))
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)

                Text("묶음사진")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText)
                    .frame(width: 52, alignment: .leading)

                HStack(spacing: 0) {
                    Button {
                        model.setSimilarPhotoRepresentativeInterval(
                            model.similarPhotoRepresentativeInterval - 1
                        )
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 40, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.similarPhotoRepresentativeInterval <= 1)
                    .accessibilityLabel("대표사진 간격 줄이기")

                    Text(
                        "1/\(model.similarPhotoRepresentativeInterval)"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 38)
                    .accessibilityLabel(
                        "\(model.similarPhotoRepresentativeInterval)장 중 1장"
                    )

                    Button {
                        model.setSimilarPhotoRepresentativeInterval(
                            model.similarPhotoRepresentativeInterval + 1
                        )
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 40, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.similarPhotoRepresentativeInterval >= 20)
                    .accessibilityLabel("대표사진 간격 늘리기")
                }
                .foregroundStyle(HanClipTheme.secondaryText)
                .frame(width: 118, height: 44)
                .background {
                    Capsule()
                        .fill(HanClipTheme.secondary.opacity(0.09))
                        .frame(height: 24)
                }
                .overlay {
                    Capsule()
                        .stroke(
                            HanClipTheme.secondary.opacity(0.20),
                            lineWidth: 1
                        )
                        .frame(height: 24)
                }
                Spacer(minLength: 4)

                SimilarPhotoGroupModeSegmentedControl(
                    mode: Binding(
                        get: { bulkSimilarPhotoGroupMode },
                        set: { mode in
                            bulkSimilarPhotoGroupMode = mode
                            model.applySimilarPhotoGroupModeToAll(mode)
                        }
                    ),
                    tint: HanClipTheme.secondary,
                    width: 112,
                    height: 24
                )
                .accessibilityLabel("모든 묶음사진 선택 방식")
                .accessibilityValue(bulkSimilarPhotoGroupModeTitle)
                .accessibilityHint(
                    "모든 묶음사진을 자동, 수동 또는 전체 선택으로 전환합니다."
                )
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: 48)

            if model.isProjectOpen {
                settingsPanelDivider

                projectGlobalControls
            }
        }
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.panelFill.opacity(0.82),
                    HanClipTheme.secondary.opacity(0.052),
                    Color.white.opacity(themeMode == .dark ? 0.015 : 0.10)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .hanClipGlassPanel(
            cornerRadius: 14,
            fillOpacity: 0.020,
            strokeOpacity: 0.26,
            shadowOpacity: 0.070
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            HanClipTheme.primary.opacity(0.30),
                            HanClipTheme.secondary.opacity(0.18),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )
        }
    }

    private var projectGlobalControls: some View {
        VStack(spacing: 0) {
            TextOverlaySummaryRow(
                settings: model.textOverlaySettings,
                isEnabled: textOverlayBinding(\.isEnabled),
                onSelect: {
                    showTextOverlaySettings = true
                }
            )
            .padding(
                EdgeInsets(
                    top: 0,
                    leading: 16,
                    bottom: 0,
                    trailing: 12
                )
            )

            settingsPanelDivider

            BackgroundMusicSummaryRow(
                settings: model.backgroundMusicSettings,
                isEnabled: backgroundMusicBinding(\.isEnabled),
                onSelect: {
                    showBackgroundMusicSettings = true
                }
            )
            .padding(
                EdgeInsets(
                    top: 0,
                    leading: 16,
                    bottom: 0,
                    trailing: 12
                )
            )

            settingsPanelDivider

            EndingInfoSummaryRow(
                isEnabled: textOverlayBinding(\.includesEndingInfoCard),
                duration: textOverlayBinding(\.endingInfoCardDuration),
                theme: model.textOverlaySettings.endingInfoCardTheme,
                onSelect: {
                    showEndingInfoSettings = true
                }
            )
            .padding(
                EdgeInsets(
                    top: 0,
                    leading: 16,
                    bottom: 0,
                    trailing: 12
                )
            )
        }
    }

    private var bulkSimilarPhotoGroupModeTitle: String {
        switch bulkSimilarPhotoGroupMode {
        case .single: "자동"
        case .multiple: "수동"
        case .all: "전체"
        }
    }

    private func adjustDefaultDuration(by change: Double) {
        let currentTenths = Int((model.defaultDuration * 10).rounded())
        let allowedTenths =
            Array(1...10)
            + Array(stride(from: 15, through: 100, by: 5))
            + Array(stride(from: 110, through: 300, by: 10))

        let adjustedTenths: Int?
        if change < 0 {
            adjustedTenths = allowedTenths.last(where: { $0 < currentTenths })
        } else {
            adjustedTenths = allowedTenths.first(where: { $0 > currentTenths })
        }

        guard let adjustedTenths else { return }
        model.defaultDuration = Double(adjustedTenths) / 10
    }

    private var settingsPanelDivider: some View {
        Rectangle()
            .fill(settingsPanelDividerColor)
            .frame(height: 0.8)
    }

    private var settingsPanelDividerColor: Color {
        HanClipTheme.secondary.opacity(0.16)
    }

    private var selectAllCurrentSignature: [SelectAllClipSnapshot] {
        model.clips
            .map(selectAllSnapshot(for:))
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func selectAllSnapshot(
        for clip: ClipItem
    ) -> SelectAllClipSnapshot {
        SelectAllClipSnapshot(
            id: clip.id,
            duration: clip.duration,
            photoDuration: clip.photoDuration,
            livePhotoDuration: clip.livePhotoDuration,
            livePhotoMode: clip.livePhotoMode,
            sourceDuration: clip.sourceDuration,
            trimStart: clip.trimStart,
            videoSegmentMode: clip.videoSegmentMode,
            isVideoSegmentParent: clip.isVideoSegmentParent,
            isVideoSegmentSelected: clip.isVideoSegmentSelected
        )
    }

    private func toggleSelectAllFullRange() {
        if !selectAllSnapshot.isEmpty {
            restoreSelectAllSnapshot()
            return
        }

        selectAllSnapshot = Dictionary(
            uniqueKeysWithValues: model.clips.map {
                ($0.id, selectAllSnapshot(for: $0))
            }
        )
        model.selectFullRangeForAllVideoClips()
        selectAllAppliedSignature = selectAllCurrentSignature
        isSelectAllChecked = true
    }

    private func restoreSelectAllSnapshot() {
        let snapshot = selectAllSnapshot
        selectAllSnapshot = [:]
        selectAllAppliedSignature = []
        isSelectAllChecked = false

        for index in model.clips.indices {
            guard let stored = snapshot[model.clips[index].id] else {
                continue
            }

            model.clips[index].duration = stored.duration
            model.clips[index].photoDuration = stored.photoDuration
            model.clips[index].livePhotoDuration = stored.livePhotoDuration
            model.clips[index].livePhotoMode = stored.livePhotoMode
            model.clips[index].sourceDuration = stored.sourceDuration
            model.clips[index].trimStart = stored.trimStart
            model.clips[index].videoSegmentMode = stored.videoSegmentMode
            model.clips[index].isVideoSegmentParent = stored.isVideoSegmentParent
            model.clips[index].isVideoSegmentSelected =
                stored.isVideoSegmentSelected
        }
    }

    private func clearSelectAllSnapshotIfNeeded(
        currentSignature: [SelectAllClipSnapshot]
    ) {
        guard !selectAllSnapshot.isEmpty
        else { return }

        isSelectAllChecked = currentSignature == selectAllAppliedSignature
    }

    private var reorderGridItems: [(offset: Int, element: ClipItem)] {
        Array(
            model.clips
                .filter { !$0.isVideoSegmentChild }
                .filter { !$0.isSimilarPhotoGroupChild }
                .enumerated()
        )
    }

    private var reorderGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 7),
                count: 4
            ),
            spacing: 9
        ) {
            ForEach(reorderGridItems, id: \.element.id) { item in
                reorderGridCell(index: item.offset, clip: item.element)
            }

            mediaImportMenu {
                reorderMediaAddTile
            }
            .accessibilityLabel("미디어 추가")
            .accessibilityHint(
                "현재 영화의 마지막에 사진이나 영상을 추가합니다."
            )

            reorderMediaDeleteTile
                .onDrop(
                    of: [UTType.text],
                    isTargeted: $isDeleteDropTargeted
                ) { _ in
                    guard let draggedClipID else { return false }

                    withAnimation(.snappy) {
                        model.removeClip(id: draggedClipID)
                        self.draggedClipID = nil
                    }
                    return true
                }
                .accessibilityLabel("클립 삭제")
                .accessibilityHint(
                    "삭제할 썸네일을 이곳으로 끌어다 놓습니다."
                )

            reorderMediaDoneTile
        }
        .animation(.snappy, value: model.clips.map(\.id))
        .accessibilityLabel("순서변경 상태")
    }

    private func reorderGridCell(index: Int, clip: ClipItem) -> some View {
        reorderGridCellVisual(index: index, clip: clip)
            .contentShape(Rectangle())
            .onDrag {
                draggedClipID = clip.id
                return NSItemProvider(
                    object: clip.id.uuidString as NSString
                )
            } preview: {
                reorderMediaThumbnail(
                    for: clip,
                    size: CGSize(width: 72, height: 72)
                )
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .onDrop(
                of: [UTType.text],
                delegate: ClipReorderDropDelegate(
                    targetID: clip.id,
                    clips: $model.clips,
                    draggedClipID: $draggedClipID
                )
            )
            .onTapGesture {
                openReorderGridClip(clip)
            }
            .accessibilityLabel(
                "\(index + 1)번째 \(reorderMediaTitle(for: clip))"
            )
            .accessibilityHint(
                "한 번 누르면 편집을 열고, 누른 뒤 끌면 순서를 변경합니다."
            )
    }

    private func reorderGridCellVisual(
        index: Int,
        clip: ClipItem
    ) -> some View {
        reorderGridThumbnailLayer(for: clip)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topLeading) {
                reorderGridIndexBadge(index + 1)
            }
            .overlay(alignment: .topTrailing) {
                reorderGridTitleBadge(for: clip)
            }
            .overlay(alignment: .bottom) {
                reorderGridDurationBadge(for: clip)
            }
            .overlay(alignment: .bottomTrailing) {
                reorderGridCountBadge(for: clip)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.7)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
    }

    private func reorderGridThumbnailLayer(for clip: ClipItem) -> some View {
        GeometryReader { proxy in
            ZStack {
                reorderMediaThumbnail(for: clip, size: proxy.size)

                if clip.isVideoSegmentParent || clip.isSimilarPhotoGroupParent {
                    LinearGradient(
                        colors: [
                            HanClipTheme.secondary.opacity(0.16),
                            HanClipTheme.primary.opacity(0.08),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.multiply)

                    HanClipTheme.secondary.opacity(0.08)
                }

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.22),
                        Color.clear,
                        Color.black.opacity(0.30)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func reorderGridIndexBadge(_ position: Int) -> some View {
        Text("\(position)")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: 23, height: 23)
            .background(Color.black.opacity(0.36), in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.34), lineWidth: 0.8)
            }
            .padding(5)
    }

    private func reorderGridTitleBadge(for clip: ClipItem) -> some View {
        Text(reorderMediaTitle(for: clip))
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(Color.black.opacity(0.34), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
            }
            .multilineTextAlignment(.trailing)
            .padding(5)
    }

    private func reorderGridDurationBadge(for clip: ClipItem) -> some View {
        Text(reorderMediaDurationText(for: clip))
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.34),
                        Color.black.opacity(0.12)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
    }

    @ViewBuilder
    private func reorderGridCountBadge(for clip: ClipItem) -> some View {
        if let count = reorderMediaGroupCount(for: clip) {
            Text("\(count)")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(Color.black.opacity(0.38), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.30), lineWidth: 0.8)
                }
                .padding(5)
        }
    }

    private func openReorderGridClip(_ clip: ClipItem) {
        isAutoAdvancingPreview = false
        isLoopingPreviewAutoAdvance = false
        videoSegmentPreviewParentID = nil

        if clip.isVideoSegmentParent {
            let firstChildClip = model.renderableClips.first {
                $0.videoSegmentParentID == clip.id
            }
            guard let firstChildClip else { return }
            selectedClipID = firstChildClip.id
        } else {
            selectedClipID = clip.id
        }
    }

    @ViewBuilder
    private func reorderMediaThumbnail(
        for clip: ClipItem,
        size: CGSize
    ) -> some View {
        if clip.isSimilarPhotoGroupParent || clip.isVideoSegmentParent {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.62),
                                HanClipTheme.secondary.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                let items = clip.isSimilarPhotoGroupParent
                    ? model.similarPhotoGroupPreviewItems(for: clip.id)
                    : model.videoSegmentPreviewItems(for: clip.id)
                let visibleItems = Array(items.prefix(3).enumerated())
                ForEach(visibleItems, id: \.element.id) { offset, item in
                    let centerOffset = CGFloat(visibleItems.count - 1) / 2
                    Image(uiImage: item.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: size.width * 0.58,
                            height: size.height * 0.58
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 8,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    item.isIncluded
                                        ? HanClipTheme.primary.opacity(0.56)
                                        : Color.white.opacity(0.52),
                                    lineWidth: item.isIncluded ? 1.1 : 0.7
                                )
                        }
                        .offset(
                            x: (CGFloat(offset) - centerOffset) * 10,
                            y: CGFloat(offset) * -3
                        )
                        .rotationEffect(.degrees(Double(offset - 1) * 3))
                        .zIndex(Double(offset))
                }

                Image(
                    systemName: clip.isSimilarPhotoGroupParent
                        ? "photo.on.rectangle.angled"
                        : "film.stack"
                )
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(HanClipTheme.primary.opacity(0.58))
            }
            .frame(width: size.width, height: size.height)
        } else {
            Image(uiImage: clip.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }

    private func reorderMediaDurationText(for clip: ClipItem) -> String {
        if clip.isSimilarPhotoGroupParent {
            return projectDurationText(
                model.similarPhotoGroupDuration(for: clip.id)
            )
        }
        return projectDurationText(clip.duration)
    }

    private func reorderMediaGroupCount(for clip: ClipItem) -> Int? {
        if clip.isSimilarPhotoGroupParent {
            return max(
                1,
                model.similarPhotoGroupPreviewItems(for: clip.id)
                    .filter(\.isIncluded).count
            )
        }
        if clip.isVideoSegmentParent {
            return model.childSegmentCount(for: clip.id)
        }
        return nil
    }

    @ViewBuilder
    private func circularMediaAddControl(systemImage: String) -> some View {
        if #available(iOS 26.0, *) {
            mediaCircleIcon(systemImage: systemImage)
                .background(
                    Color.white.opacity(0.42),
                    in: Circle()
                )
                .glassEffect(
                    .regular
                        .tint(HanClipTheme.secondary.opacity(0.16))
                        .interactive(),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            Color.white.opacity(0.68),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(0.14),
                    radius: 8,
                    y: 4
                )
        } else {
            mediaCircleIcon(systemImage: systemImage)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .fill(Color.white.opacity(0.26))
                        .allowsHitTesting(false)
                }
                .overlay {
                    Circle()
                        .stroke(
                            HanClipTheme.secondary.opacity(0.34),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(0.14),
                    radius: 8,
                    y: 4
                )
        }
    }

    private func mediaCircleIcon(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(HanClipTheme.secondary)
            .frame(width: 52, height: 52)
            .contentShape(Circle())
    }

    @ViewBuilder
    private var reorderMediaAddTile: some View {
        if #available(iOS 26.0, *) {
            reorderMediaAddTileContent
                .glassEffect(
                    .regular
                        .tint(HanClipTheme.secondary.opacity(0.10))
                        .interactive(),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            Color.white.opacity(0.56),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(0.12),
                    radius: 5,
                    y: 3
                )
        } else {
            reorderMediaAddTileContent
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            HanClipTheme.secondary.opacity(0.24),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(0.12),
                    radius: 5,
                    y: 3
                )
        }
    }

    private var reorderMediaAddTileContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(HanClipTheme.secondary.opacity(0.075))

            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(HanClipTheme.primary.opacity(0.88))
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var reorderMediaDeleteTile: some View {
        if #available(iOS 26.0, *) {
            reorderMediaDeleteTileContent
                .glassEffect(
                    .regular
                        .tint(
                            isDeleteDropTargeted
                                ? Color.red.opacity(0.28)
                                : HanClipTheme.secondary.opacity(0.10)
                        )
                        .interactive(),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isDeleteDropTargeted
                                ? Color.red.opacity(0.80)
                                : Color.white.opacity(0.56),
                            lineWidth: isDeleteDropTargeted ? 2 : 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(0.12),
                    radius: 5,
                    y: 3
                )
        } else {
            reorderMediaDeleteTileContent
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isDeleteDropTargeted
                                ? Color.red.opacity(0.80)
                                : HanClipTheme.secondary.opacity(0.24),
                            lineWidth: isDeleteDropTargeted ? 2 : 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(0.12),
                    radius: 5,
                    y: 3
                )
        }
    }

    private var reorderMediaDeleteTileContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isDeleteDropTargeted
                        ? Color.red.opacity(0.18)
                        : HanClipTheme.secondary.opacity(0.075)
                )

            Image(systemName: "minus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(
                    isDeleteDropTargeted
                        ? Color.red
                        : HanClipTheme.primary.opacity(0.80)
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .scaleEffect(isDeleteDropTargeted ? 1.04 : 1)
        .animation(.easeInOut(duration: 0.16), value: isDeleteDropTargeted)
    }

    @ViewBuilder
    private var reorderMediaDoneTile: some View {
        Button {
            withAnimation(.snappy) {
                draggedClipID = nil
                isReordering = false
            }
        } label: {
            reorderMediaDoneTileContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel("순서변경 완료")
    }

    private var reorderMediaDoneTileContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(HanClipTheme.primary.opacity(0.16))

            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(HanClipTheme.primary)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(HanClipTheme.primary.opacity(0.30), lineWidth: 1)
        }
        .shadow(
            color: Color.black.opacity(0.12),
            radius: 5,
            y: 3
        )
    }

    private func reorderMediaTitle(for clip: ClipItem) -> String {
        if clip.isSimilarPhotoGroupParent {
            return "묶음"
        }
        if clip.isVideoClip {
            return model.canUseMultipleVideoSegments(for: clip.id)
                ? "분할"
                : "영상"
        }
        if clip.isLivePhoto {
            return "라이브"
        }
        return "사진"
    }

    @ViewBuilder
    private var aspectRatioPicker: some View {
        if #available(iOS 26.0, *) {
            aspectRatioButtons
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(5)
                .padding(.horizontal, 9)
                .glassEffect(
                    .regular
                        .tint(HanClipTheme.secondary.opacity(0.16))
                        .interactive(),
                    in: Capsule()
                )
                .shadow(
                    color: HanClipTheme.primary.opacity(0.10),
                    radius: 6,
                    y: 2
                )
                .id("aspect-ratio-picker-\(themeModeRaw)")
        } else {
            aspectRatioButtons
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(5)
                .padding(.horizontal, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(
                            HanClipTheme.secondary.opacity(0.32),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: HanClipTheme.primary.opacity(0.08),
                    radius: 5,
                    y: 2
                )
                .id("aspect-ratio-picker-\(themeModeRaw)")
        }
    }

    private var aspectRatioButtons: some View {
        GeometryReader { proxy in
            HStack(spacing: 4) {
                Button {
                    selectOutputAspectRatioAndHide(nil)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                            model.outputAspectRatio == nil
                                    ? HanClipTheme.primary.opacity(0.14)
                                    : Color.clear
                            )

                        Text("첫\n사진")
                            .font(.system(size: 10, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineSpacing(0)
                            .foregroundStyle(
                                model.outputAspectRatio == nil
                                    ? HanClipTheme.primary
                                    : HanClipTheme.secondary
                            )
                    }
                    .frame(width: 32, height: 32)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                model.outputAspectRatio == nil
                                    ? HanClipTheme.primary
                                    : HanClipTheme.secondary.opacity(0.72),
                                lineWidth: model.outputAspectRatio == nil ? 2 : 1
                            )
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id("automatic-aspect-ratio-\(themeModeRaw)")

                ForEach(OutputAspectRatio.allCases) { ratio in
                    Button {
                        selectOutputAspectRatioAndHide(ratio)
                    } label: {
                        AspectRatioIcon(
                            ratio: ratio,
                            isSelected: model.outputAspectRatio == ratio,
                            themeModeRaw: themeModeRaw
                        )
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ratio.accessibilityTitle)
                    .accessibilityAddTraits(
                        model.outputAspectRatio == ratio
                            ? .isSelected
                            : []
                    )
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        selectAspectRatio(
                            at: value.location.x,
                            totalWidth: proxy.size.width
                        )
                    }
                    .onEnded { value in
                        selectAspectRatio(
                            at: value.location.x,
                            totalWidth: proxy.size.width,
                            shouldHidePicker: true
                        )
                    }
            )
        }
        .frame(height: 32)
    }

    private func selectAspectRatio(
        at horizontalPosition: CGFloat,
        totalWidth: CGFloat,
        shouldHidePicker: Bool = false
    ) {
        let ratios = OutputAspectRatio.allCases
        let selectionCount = ratios.count + 1
        guard totalWidth > 0, selectionCount > 0 else { return }

        let itemWidth = totalWidth / CGFloat(selectionCount)
        let clampedPosition = min(
            max(horizontalPosition, 0),
            totalWidth - 0.001
        )
        let selectedIndex = min(
            Int(clampedPosition / itemWidth),
            selectionCount - 1
        )

        if selectedIndex == 0 {
            model.selectOutputAspectRatio(nil)
        } else {
            model.selectOutputAspectRatio(ratios[selectedIndex - 1])
        }

        if shouldHidePicker {
            withAnimation(aspectRatioPickerAnimation) {
                showAspectRatioPicker = false
            }
        }
    }

    private func selectOutputAspectRatioAndHide(_ ratio: OutputAspectRatio?) {
        model.selectOutputAspectRatio(ratio)
        withAnimation(aspectRatioPickerAnimation) {
            showAspectRatioPicker = false
        }
    }

    private var makeButton: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(
                            colors: [
                                HanClipTheme.primary,
                                HanClipTheme.primary.opacity(0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    }
                    .shadow(
                        color: HanClipTheme.primary.opacity(0.16),
                        radius: 8,
                        y: 4
                    )
                    .contentShape(Circle())
                    .gesture(
                        ExclusiveGesture(
                            LongPressGesture(minimumDuration: 0.7),
                            TapGesture()
                        )
                        .onEnded { value in
                            switch value {
                            case .first:
                                handleCloseButtonLongPress()
                            case .second:
                                handleCloseButtonTap()
                            }
                        }
                    )
                .accessibilityLabel("닫기")

                Button {
                    withAnimation(aspectRatioPickerAnimation) {
                        showAspectRatioPicker.toggle()
                    }
                } label: {
                    currentAspectRatioButtonContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel("영상 비율")
                .accessibilityValue(currentAspectRatioTitle)

                Button {
                    model.saveProjectAndOpenPreview()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                        Text(model.totalDurationText)
                            .font(
                                .system(
                                    size: 16,
                                    weight: .semibold,
                                    design: .monospaced
                                )
                            )
                        Text("만들기")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [
                                HanClipTheme.primary,
                                HanClipTheme.primary.opacity(0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    }
                    .shadow(
                        color: HanClipTheme.primary.opacity(0.16),
                        radius: 8,
                        y: 4
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.isExporting)
            }
            .frame(maxWidth: adaptiveContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(alignment: .bottom) {
            bottomActionScrim
        }
    }

    private var bottomActionScrim: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(bottomActionScrimMask)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(
                        color: HanClipTheme.background.opacity(0.18),
                        location: 0.34
                    ),
                    .init(
                        color: HanClipTheme.background.opacity(0.78),
                        location: 0.66
                    ),
                    .init(
                        color: HanClipTheme.background.opacity(0.98),
                        location: 1.00
                    )
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: 128)
        .offset(y: 34)
        .allowsHitTesting(false)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var bottomActionScrimMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.00),
                .init(color: .black.opacity(0.18), location: 0.34),
                .init(color: .black.opacity(0.78), location: 0.66),
                .init(color: .black, location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var currentAspectRatioButtonContent: some View {
        ZStack {
            Circle()
                .fill(HanClipTheme.secondary.opacity(0.10))
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(HanClipTheme.secondary.opacity(0.34), lineWidth: 1)
                }
                .shadow(
                    color: HanClipTheme.secondary.opacity(0.10),
                    radius: 6,
                    y: 2
                )

            if let ratio = model.outputAspectRatio {
                AspectRatioIcon(
                    ratio: ratio,
                    isSelected: false,
                    usesPrimaryShapeColor: true,
                    themeModeRaw: themeModeRaw
                )
                .frame(width: 34, height: 34)
            } else {
                Text("첫\n사진")
                    .font(.system(size: 10, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(0)
                    .foregroundStyle(HanClipTheme.primary)
                    .frame(width: 34, height: 34)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(HanClipTheme.primary, lineWidth: 2)
                    }
            }
        }
        .frame(width: 52, height: 52)
    }

    private var currentAspectRatioTitle: String {
        model.outputAspectRatio?.title ?? "첫 사진"
    }

    private var progressOverlay: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            HanClipTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if model.isPreviewRendering {
                    HanClipTopHeader(
                        logoAccessibilityLabel: "제작 취소",
                        logoAction: {
                            model.cancelPreviewGeneration()
                        }
                    ) {
                        HanClipHeaderActionCluster {
                            Button {
                                model.cancelPreviewGeneration()
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel("취소")
                        }
                    }

                    HanClipTitleLine(
                        "개봉 준비",
                        systemImage: "hourglass",
                        leadingInset: 18,
                        trailingInset: 18
                    )
                    .padding(.top, 8)
                } else {
                    Spacer(minLength: 64)
                }

                Spacer(minLength: model.isPreviewRendering ? 42 : 54)

                VStack(spacing: 18) {
                    if model.isPreviewRendering,
                       let thumbnail = model.previewThumbnail {
                        generationProgressThumbnail(thumbnail)
                            .padding(.bottom, 2)
                    } else if model.isImportingSharedItems,
                              let thumbnail = model.sharedImportThumbnail {
                        generationProgressThumbnail(thumbnail)
                            .padding(.bottom, 2)
                    } else {
                        ZStack {
                            Circle()
                                .fill(HanClipTheme.secondary.opacity(0.12))
                                .frame(width: 86, height: 86)

                            ProgressView()
                                .controlSize(.large)
                                .tint(HanClipTheme.primary)
                        }
                    }

                    VStack(spacing: 6) {
                        Text(
                            model.isPreviewRendering
                                ? "개봉 준비 중"
                                : model.isLoadingProject
                                    ? "영화 불러오는 중"
                                : model.isSavingProject
                                    ? "영화 저장 중"
                                : model.isImportingPhotoLibraryMedia
                                    ? "미디어 불러오는 중"
                                : model.isImportingSharedItems
                                    ? "공유 미디어 불러오는 중"
                                    : "준비하고 있습니다"
                        )
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(HanClipTheme.primaryText)

                        Text(model.progressMessage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(HanClipTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        if model.isPreviewRendering {
                            HStack(spacing: 10) {
                                Text(
                                    progressTimeText(
                                        model.previewProgress
                                            * model.totalDuration
                                    )
                                )
                                .frame(width: 52, alignment: .trailing)

                                ProgressView(
                                    value: model.previewProgress,
                                    total: 1
                                )
                                .progressViewStyle(.linear)
                                .tint(HanClipTheme.primary)

                                Text(progressTimeText(model.totalDuration))
                                    .frame(width: 52, alignment: .leading)
                            }
                            .font(
                                .system(
                                    size: 12,
                                    weight: .semibold,
                                    design: .monospaced
                                )
                            )
                            .foregroundStyle(HanClipTheme.primaryText)
                        } else if model.isLoadingProject {
                            ProgressView(value: model.projectLoadProgress, total: 1)
                                .progressViewStyle(.linear)
                                .tint(HanClipTheme.primary)
                        } else if model.isSavingProject {
                            ProgressView(value: model.projectSaveProgress, total: 1)
                                .progressViewStyle(.linear)
                                .tint(HanClipTheme.primary)
                        } else if model.isImportingPhotoLibraryMedia {
                            ProgressView(
                                value: model.photoLibraryImportProgress,
                                total: 1
                            )
                            .progressViewStyle(.linear)
                            .tint(HanClipTheme.primary)
                        } else if model.isImportingSharedItems {
                            ProgressView(value: model.sharedImportProgress, total: 1)
                                .progressViewStyle(.linear)
                                .tint(HanClipTheme.primary)
                        } else if model.isLoadingCalendarPicker {
                            ProgressView(
                                value: model.calendarPickerLoadProgress,
                                total: 1
                            )
                            .progressViewStyle(.linear)
                            .tint(HanClipTheme.primary)
                        } else if model.isImportingCalendarMedia {
                            ProgressView(value: model.calendarImportProgress, total: 1)
                                .progressViewStyle(.linear)
                                .tint(HanClipTheme.primary)
                        } else {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .tint(HanClipTheme.primary)
                        }

                        Text("\(Int((activeProgressValue * 100).rounded()))%")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(HanClipTheme.primary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(
                        HanClipTheme.secondary.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.36), lineWidth: 1)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.vertical, 24)
                .background(
                    HanClipTheme.panelFill,
                    in: RoundedRectangle(cornerRadius: 34, style: .continuous)
                )
                .background(
                    LinearGradient(
                        colors: [
                            HanClipTheme.panelFill.opacity(0.96),
                            HanClipTheme.secondary.opacity(0.06),
                            Color.white.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 34, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.50), lineWidth: 1)
                }
                .shadow(
                    color: HanClipTheme.primary.opacity(0.14),
                    radius: 28,
                    y: 14
                )

                Spacer(minLength: 30)

                if model.isPreviewRendering
                    || model.isImportingCalendarMedia
                    || model.isImportingPhotoLibraryMedia
                    || model.isImportingSharedItems
                    || model.isSavingProject
                    || model.isLoadingProject {
                    Button(role: .cancel) {
                        if model.isPreviewRendering {
                            model.cancelPreviewGeneration()
                        } else if model.isLoadingProject {
                            model.cancelProjectLoad()
                        } else if model.isSavingProject {
                            model.cancelProjectSave()
                        } else if model.isImportingSharedItems {
                            model.cancelSharedItemImport()
                        } else if model.isImportingPhotoLibraryMedia {
                            model.cancelPhotoLibraryImport()
                        } else {
                            model.cancelCalendarMediaImport()
                        }
                    } label: {
                        Text("취소")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(HanClipTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                HanClipTheme.secondary.opacity(0.10),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        HanClipTheme.secondary.opacity(0.12),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 22)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 22)
        }
    }

    private var activeProgressValue: Double {
        if model.isPreviewRendering {
            return model.previewProgress
        }
        if model.isLoadingProject {
            return model.projectLoadProgress
        }
        if model.isSavingProject {
            return model.projectSaveProgress
        }
        if model.isImportingSharedItems {
            return model.sharedImportProgress
        }
        if model.isImportingPhotoLibraryMedia {
            return model.photoLibraryImportProgress
        }
        if model.isLoadingCalendarPicker {
            return model.calendarPickerLoadProgress
        }
        if model.isImportingCalendarMedia {
            return model.calendarImportProgress
        }
        return 0
    }

    private var isBusyOverlayVisible: Bool {
        model.isExporting
            || model.isLoadingProject
            || model.isImportingPhotoLibraryMedia
            || model.isImportingSharedItems
            || model.isLoadingCalendarPicker
            || model.isImportingCalendarMedia
    }

    private func generationProgressThumbnail(
        _ thumbnail: UIImage
    ) -> some View {
        let thumbnailSize = generationProgressThumbnailSize

        return GeometryReader { proxy in
            let progress = CGFloat(
                max(0, min(1, model.previewProgress))
            )

            ZStack(alignment: .leading) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .opacity(0.50)

                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(
                                width: proxy.size.width * progress
                            )
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        Color.white.opacity(0.38),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: HanClipTheme.secondary.opacity(0.10),
                radius: 10,
                y: 5
            )
        }
        .frame(
            width: thumbnailSize.width,
            height: thumbnailSize.height
        )
    }

    private var generationProgressThumbnailSize: CGSize {
        let renderSize = model.outputRenderSize
        let safeWidth = max(1, renderSize.width)
        let safeHeight = max(1, renderSize.height)
        let aspectRatio = safeWidth / safeHeight
        let maximumDimension: CGFloat = 260

        if aspectRatio >= 1 {
            return CGSize(
                width: maximumDimension,
                height: maximumDimension / aspectRatio
            )
        }

        return CGSize(
            width: maximumDimension * aspectRatio,
            height: maximumDimension
        )
    }

    private func progressTimeText(_ seconds: Double) -> String {
        let tenths = max(Int((seconds * 10).rounded()), 0)
        let minutes = tenths / 600
        let remainingSeconds = Double(tenths % 600) / 10
        return String(
            format: "%d:%04.1f",
            minutes,
            remainingSeconds
        )
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private func textOverlayBinding<Value>(
        _ keyPath: WritableKeyPath<WatermarkSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.textOverlaySettings[keyPath: keyPath] },
            set: { newValue in
                var settings = model.textOverlaySettings
                settings[keyPath: keyPath] = newValue
                model.textOverlaySettings = settings
            }
        )
    }

    private func backgroundMusicBinding<Value>(
        _ keyPath: WritableKeyPath<BackgroundMusicSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.backgroundMusicSettings[keyPath: keyPath] },
            set: { newValue in
                var settings = model.backgroundMusicSettings
                settings[keyPath: keyPath] = newValue
                model.backgroundMusicSettings = settings
            }
        )
    }
}

private extension View {
    func calendarActionButtonStyle() -> some View {
        modifier(CalendarActionButtonStyle())
    }

    func dismissKeyboardOnDrag() -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { _ in
                    UIApplication.shared.dismissKeyboard()
                }
        )
    }

    func textOverlaySectionStyle() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                HanClipTheme.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}

private extension UIApplication {
    func dismissKeyboard() {
        sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

struct HanClipLogoLabel: View {
    @AppStorage("hanClipThemeMode") private var themeModeRaw =
        HanClipThemeMode.automatic.rawValue

    var iconSize: CGFloat = 35.2
    var textSize: CGFloat = 26
    var width: CGFloat = 154

    var body: some View {
        HStack(spacing: 6) {
            Image("LogoMarkV2")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)

            Text("HanClip")
                .font(.system(size: textSize, weight: .semibold))
        }
        .frame(width: width, alignment: .leading)
        .foregroundStyle(HanClipTheme.primary)
        .id(themeModeRaw)
    }
}

struct HanClipLogoButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    init(
        accessibilityLabel: String = "닫기",
        action: @escaping () -> Void
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HanClipLogoLabel()
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct HanClipHeaderPill<Content: View>: View {
    @AppStorage("hanClipThemeMode") private var themeModeRaw =
        HanClipThemeMode.automatic.rawValue

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .background(
                HanClipTheme.panelFill.opacity(0.72),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        HanClipTheme.panelStroke.opacity(0.62),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: HanClipTheme.secondary.opacity(0.08),
                radius: 12,
                y: 5
            )
            .id(themeModeRaw)
    }
}

struct HanClipHeaderActionCluster<Content: View>: View {
    @AppStorage("hanClipThemeMode") private var themeModeRaw =
        HanClipThemeMode.automatic.rawValue

    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 14) {
            content()
        }
        .font(.system(size: 25, weight: .semibold))
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(HanClipTheme.primary)
        .tint(HanClipTheme.primary)
        .frame(height: 58)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: Capsule())
        .background(
            HanClipTheme.panelFill.opacity(0.72),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    HanClipTheme.panelStroke.opacity(0.62),
                    lineWidth: 1
                )
        }
        .shadow(
            color: HanClipTheme.secondary.opacity(0.08),
            radius: 12,
            y: 5
        )
        .id(themeModeRaw)
    }
}

struct HanClipTopHeader<RightContent: View>: View {
    let logoAccessibilityLabel: String
    let logoAction: () -> Void
    @ViewBuilder let rightContent: () -> RightContent

    var body: some View {
        HStack {
            Button {
                logoAction()
            } label: {
                HanClipHeaderPill {
                    HanClipLogoLabel()
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(logoAccessibilityLabel)

            Spacer()

            rightContent()
        }
        .frame(height: 58)
        .padding(.top, 6)
        .padding(.horizontal, 14)
    }
}

struct HanClipTitleLine: View {
    let title: String
    var systemImage: String?
    var leadingInset: CGFloat = 18
    var trailingInset: CGFloat = 18
    var titleFontSize: CGFloat = 12

    init(
        _ title: String,
        systemImage: String? = nil,
        leadingInset: CGFloat = 18,
        trailingInset: CGFloat = 18,
        titleFontSize: CGFloat = 12
    ) {
        self.title = title
        self.systemImage = systemImage
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        self.titleFontSize = titleFontSize
    }

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(HanClipTheme.primary.opacity(0.72))
                    .frame(width: 18, height: 18)
                    .background(
                        HanClipTheme.secondary.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 5,
                            style: .continuous
                        )
                    )
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.system(size: titleFontSize, weight: .black))
                .foregroundStyle(HanClipTheme.primaryText.opacity(0.76))
        }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
    }
}

private enum SpecialThanksInfo {
    static let title = "Special Thanks"
    static let body = "(주)한통, 한병기, 송기원, 한지우"
}

private extension Color {
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6,
              let value = Int(hex, radix: 16)
        else { return nil }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String? {
        let color = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        else { return nil }

        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}

private struct CollectionVideoSizeOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let movie: CollectedMovie
    let onSelect: (CollectionVideoSizeOption) -> Void
    @State private var compressionInfo: CollectionVideoCompressionInfo?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(movie.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(HanClipTheme.primaryText)
                        .lineLimit(2)
                    if let compressionInfo {
                        Text(currentVideoDescription(compressionInfo))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(HanClipTheme.secondaryText)
                    } else {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("현재 영상 정보를 확인하는 중")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HanClipTheme.secondaryText)
                    }
                }
                .padding(.bottom, 2)

                ForEach(CollectionVideoSizeOption.allCases) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: optionIcon(option))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(HanClipTheme.primary)
                                .frame(width: 38, height: 38)
                                .background(
                                    HanClipTheme.primary.opacity(0.10),
                                    in: Circle()
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(HanClipTheme.primaryText)
                                Text(option.detail)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(HanClipTheme.secondaryText)
                            }

                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 4) {
                                if let compressionInfo {
                                    Text(
                                        "예상 약 \(byteCount(compressionInfo.estimatedBytes(for: option)))"
                                    )
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(HanClipTheme.primary)
                                    .lineLimit(1)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(HanClipTheme.secondary)
                            }
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            HanClipTheme.panelFill,
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(HanClipTheme.panelStroke, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(compressionInfo == nil)
                }

                Text("예상 용량은 영상 장면에 따라 달라질 수 있습니다. 결과가 원본보다 크면 원본을 유지합니다.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HanClipTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
            .padding(18)
            .background(HanClipTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("파일 용량 줄이기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .task(id: movie.id) {
            compressionInfo = await MovieCollectionStore.shared
                .compressionInfo(for: movie)
        }
    }

    private func optionIcon(_ option: CollectionVideoSizeOption) -> String {
        switch option {
        case .high1080: return "rectangle.inset.filled"
        case .saver720: return "rectangle.compress.vertical"
        case .minimum540: return "arrow.down.right.and.arrow.up.left"
        }
    }

    private func currentVideoDescription(
        _ info: CollectionVideoCompressionInfo
    ) -> String {
        let seconds = max(Int(info.duration.rounded()), 0)
        let duration = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return "현재  \(info.width)×\(info.height) · \(duration) · \(byteCount(info.fileSizeBytes))"
    }

    private func byteCount(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "알 수 없음" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = bytes >= 1_000_000_000 ? [.useGB] : [.useMB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }
}

private struct ImportantInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WatermarkSettings.customCopyrightIconPathStorageKey)
    private var customIconPath =
        WatermarkSettings.defaultCustomCopyrightIconPath
    @Binding var sleepPreventionModeRaw: String
    @Binding var copyrightEnabled: Bool
    @ObservedObject var purchaseManager: CopyrightPurchaseManager
    @Binding var platformRaw: String
    @Binding var address: String
    @Binding var positionRaw: String
    @Binding var textColorHex: String
    @Binding var shadowColorHex: String
    @Binding var shadowOpacity: Double
    @Binding var iconColorModeRaw: String
    @Binding var iconColorHex: String
    @State private var customIconPickerItem: PhotosPickerItem?
    @State private var customIconRefreshID = UUID()
    @State private var isWatermarkSettingsExpanded = false

    private let items: [(title: String, body: String)] = [
        (SpecialThanksInfo.title, SpecialThanksInfo.body),
        ("카피라이터", "첫 화면 하단의 i 원형 유리 버튼입니다. 카피라이터 설정과 설정 정보를 보여주는 창입니다."),
        ("로고", "상단의 앱 심볼과 HanClip 글자 부분입니다. 화면에 따라 닫기, 첫 화면 이동, 테마 선택 같은 동작의 기준점이 됩니다."),
        ("첫 화면", "앱 실행 후 영화 프리셋과 저장된 영화 목록이 보이는 홈 화면입니다."),
        ("iPad 지원", "iPad에서 세로·가로 방향과 분할 화면 크기에 맞춰 사용할 수 있습니다. 넓은 화면에서는 편집 콘텐츠의 읽기 좋은 폭을 유지하며 사진 선택, 공유 확장과 잠금 화면 위젯도 함께 사용할 수 있습니다."),
        ("영화 프리셋", "첫 화면 상단에서 새 영화, 퀵모드, AiShot, 여행 영화, 인생 영화, 골프 영화 중 원하는 설정으로 영화 제작을 시작하는 영역입니다."),
        ("퀵모드", "새 영화의 기본 설정에 음악을 켠 빠른 제작 기능입니다. 미디어를 고르면 30초, 45초, 1분, 2분, 3분, 5분, 추천시간 또는 최소시간을 고릅니다. 추천시간은 미디어당 1초, 최소시간은 미디어당 0.2초로 계산합니다. 선택한 미디어가 많으면 정해진 시간보다 최소시간이 길 때 가능한 최소 시간으로 자동 보정하며, −와 +로 5초씩 조절할 수 있습니다. 시간 화면에서 영화 제작과 같은 자막·음악 패널을 사용할 수 있습니다. 확정하면 선택 시간÷원본 미디어 수로 기본시간을 정해 편집 화면을 거치지 않고 영화를 만들며, 시사회에서 다시 편집을 누르면 퀵모드 영상 길이 화면으로 돌아갑니다. 외부 주소 hanclip://quick으로 바로 실행할 수 있습니다."),
        ("여행 영화", "기본시간 1초, 라이브포토 영상, 영상 분할, 묶음사진 1/6 자동, 여행 서체와 여행의 설렘 음악을 적용합니다. 촬영 기간과 많이 촬영한 지역 최대 두 곳을 자막에 넣고, 마지막 엔딩 카드는 보물지도를 기본으로 사용합니다."),
        ("인생 영화", "기본시간 2초, 라이브포토 영상, 영상 분할, 묶음사진 1/3 자동과 오늘 날짜 자막을 적용해 삶의 기록을 영화로 만드는 프리셋입니다."),
        ("Ai", """
        한클립 안에서 가장 행복하고, 가장 흥분되고, 꼭 기억하고 싶은 순간을 더 잘 찾기 위해 계속 개발하고 있는 판단 능력입니다.

        Ai는 AiShot 촬영뿐 아니라 여러 영상의 자클립 선택, 사진 묶음의 대표 컷 선택처럼 한클립 안에서 자동으로 좋은 순간을 고르는 기능들에 함께 쓰입니다. 골프 영상에만 머물지 않고 생활 영상과 여행 영상에서도 더 자연스럽게 좋은 장면을 찾는 방향으로 키우고 있습니다.

        현재 Ai 버전은 \(AudioImpactClassifier.modelVersion)입니다.

        0.1.0 - 소리를 중심으로 티샷, 박수, 갑자기 좋아지는 순간과 이어지는 반응을 찾아내는 첫 기준입니다.

        0.2.0 - 소리를 중심으로 보면서 AiShot 촬영 중 화면의 움직임과 밝기 변화도 함께 참고합니다.

        0.2.1 - 맥에 있는 798개 영상 공부 결과를 반영한 보정판입니다. 큰 소리 자체보다 그 뒤에 이어지는 반응과 화면 변화를 더 차분하게 함께 봅니다.

        새 Ai가 마음에 들지 않으면 이전 Ai 버전으로 되돌릴 수 있도록 버전별 특징을 남겨 둡니다.
        """),
        ("AiShot", "필요한 순간을 자동으로 찾아 클립에 담는 실시간 촬영 기능입니다. 촬영을 닫을 때까지 계속 살피며, 만들어진 클립은 Ai 영화에 차례로 추가됩니다.\n\n감지 중, 감지 됨, 저장 중으로 촬영 상태를 보여줍니다. 주변 환경에 맞춰 시끄러움, 일반, 조용함, 자동 감도를 선택할 수 있으며 기본값인 자동은 주변 상황에 맞춰 감도를 조절합니다. 샷 시간은 짧게(앞뒤 2초), 일반(앞 2초·뒤 3초), 길게(앞뒤 5초) 중에서 선택하며 촬영 중 변경하면 다음 촬영부터 적용됩니다.\n\n전면 또는 후면 카메라와 줌 배율을 선택해 3:4 화면 비율로 촬영합니다. 필요한 순간에는 촬영 버튼을 눌러 수동으로 클립을 남길 수 있습니다."),
        ("영화 목록", "첫 화면에 저장된 일반 영화와 AiShot 영화가 한 목록에 표시됩니다. 왼쪽의 숫자는 최대 10개 중 현재 저장된 영화 수이며, 각 행의 시간 앞 아이콘은 영화를 시작할 때 사용한 프리셋 종류를 보여줍니다."),
        ("컬렉션", "완성된 영화를 포스터 형태로 최대 30개까지 보관합니다. 기기 내 Vision AI가 영상 여러 구간의 얼굴·주목 영역·구도·밝기·대비·선명도를 비교해 가장 좋은 순간을 포스터로 선택합니다. 기존 포스터도 새 AI 기준으로 한 번 자동 재생성합니다. 포스터 롱터치 메뉴의 썸네일 AI 재선택은 전체화면에서 디바이스 AI 후보 8개와 한클립 AI 후보 8개를 좌우로 비교합니다. 모든 후보에는 실제 제목·핀·제작·촬영·위치·재생시간이 적용됩니다. 재생성을 누르면 지금까지 거절한 후보의 프레임 시간과 이미지 특징을 제외하고 다른 느낌의 후보 16개를 다시 찾습니다. 핀이 꽂힌 포스터는 길게 누른 채 다른 핀 포스터로 끌어 놓아 순서를 바꿀 수 있습니다. 컬렉션 선반 아래의 숨김 메뉴에서는 전체 영상을 720p 또는 540p로 일괄 변환하며 이미 해당 해상도 이하인 영상은 유지합니다. 포스터를 누르면 한클립 전용 전체화면 플레이어로 재생하며, 기기 회전 잠금과 관계없이 실제 기기 방향을 감지해 영상과 조작 버튼을 세로·가로로 함께 전환합니다. 세로와 가로 모두 핀치로 확대·축소하고 확대 상태에서 한 손가락으로 화면을 이동하며 더블 탭하면 100% 크기로 돌아갑니다."),
        ("테마 선택창", "로고를 길게 눌렀을 때 테마를 선택하는 창입니다."),
        ("첫 화면 이동 팝업", "편집 중 로고를 눌렀을 때 홈 + 저장, 홈으로를 선택하는 창입니다."),
        ("영화 화면", "미디어를 선택한 후 기본 재생 시간, 화면 비율, 클립목록 등을 편집하는 화면입니다."),
        ("영상 시간 필터", "사진 화면의 필터에서 설정한 시간 이상 또는 이하인 영상을 찾는 기능입니다. 시간 필터를 적용하는 동안에는 사진과 라이브포토를 숨기고 영상만 표시합니다. 1분, 3분, 5분, 10분을 빠르게 고르거나 분과 초를 직접 선택할 수 있으며, 필터를 해제하면 이전에 선택했던 미디어 종류가 복원됩니다."),
        ("사진 정렬", "사진 화면의 필터에서 날짜순 또는 추가순을 선택합니다. 선택된 정렬을 다시 누르면 글자 옆 화살표가 바뀌며 오름차순과 내림차순이 전환됩니다. 날짜순은 촬영일을 사용하고, 추가순은 사진 보관함의 추가·변경 시각을 사용합니다. 영화 제작, 퀵모드와 컬렉션의 공용 사진 화면에 동일하게 적용됩니다."),
        ("영화 설정", "영화 화면의 로고 아래에 있는 클립 설정 패널입니다. 처음에는 제목 행만 보이도록 접혀 있으며, 클립 설정 행 어디를 눌러도 펼치거나 다시 접을 수 있습니다. 오른쪽 표시판은 이 영화가 새 영화, 퀵모드, AiShot, 여행 영화, 인생 영화 또는 골프 영화 중 어떤 프리셋으로 시작했는지 보여주며 프로젝트를 다시 불러와도 유지됩니다. 기존 버전에서 저장해 시작 프리셋 정보가 없는 영화는 기존 영화로 표시합니다. 영상 길이, 기본시간, 라이브포토, 영상 분할, 묶음사진, 자막, 음악과 엔딩을 설정합니다."),
        ("클립목록", "선택한 사진, 라이브포토, 영상이 순서대로 표시되는 목록입니다. 묶음사진은 실제 사진이 아니라 비슷한 사진들을 담는 행으로 표시되며, 아래에 들어 있는 자사진에서 실제 사용할 컷을 확인합니다."),
        ("묶음사진", "연속으로 촬영된 사진과 라이브포토 중 촬영 시각, 화면 비율, 밝기와 화면 구도가 모두 비슷한 장면을 하나로 담아 중복을 줄이는 기능입니다. 묶음 행의 숫자는 후보 수가 아니라 영상에 사용하기로 선택된 자사진 수입니다. 클립설정의 ‘1/6’은 6장마다 1장을 자동으로 고른다는 뜻이며, −와 +로 비율을 조절할 수 있습니다. 수동은 묶음을 펼쳐 사용할 사진을 직접 고르며, 전체는 모든 사진을 사용합니다."),
        ("자동 / 수동 / 전체", "묶음사진에서 사용할 사진을 Ai가 고르게 할지, 사용자가 직접 고를지, 모든 사진을 사용할지 정하는 선택입니다."),
        ("사용 / 제외", "수동으로 펼친 자사진 행에서 해당 사진 또는 라이브포토를 영상에 넣을지 뺄지 정하는 상태 버튼입니다."),
        ("사진 / 영상", "라이브포토를 일반 사진으로 쓸지, 짧은 영상으로 쓸지 정하는 선택입니다."),
        ("순서변경 상태", "큰 단위의 순서를 바꾸는 화면입니다. 묶음사진은 안의 자사진을 흩어 놓지 않고 하나의 묶음 타일로 이동하며, 숫자는 선택된 자사진 수를 뜻합니다."),
        ("세그먼트 컨트롤", "자동 / 수동 / 전체, 사진 / 영상, 한컷 / 분할처럼 사용 방식을 고르는 스위치형 컨트롤입니다."),
        ("한컷 / 분할", "영상 클립을 하나의 구간으로 쓸지, Ai가 찾은 피크 기준으로 여러 자클립으로 나눌지 정하는 선택입니다."),
        ("모클립", "다중 분할을 만들 때 원본 역할로 남는 부모 클립입니다."),
        ("자클립", "모클립에서 Ai가 찾은 피크 기준으로 만들어진 하위 클립입니다. 삭제는 원본 삭제가 아니라 비선택으로 처리되며, 비선택된 자클립은 클립목록에서 다시 확인하고 선택할 수 있습니다."),
        ("자사진", "묶음사진 안에 들어 있는 실제 사진 또는 라이브포토입니다. 수동 모드에서 사용 또는 제외 상태를 고릅니다."),
        ("편집 영역 / 편집 모드", "개별 클립을 누르면 열리는 구간 선택 및 재생 화면입니다."),
        ("웨이브 / 웨이브 인디케이터", "영상/Live Photo 편집에서 소리 파형을 보여주는 영역입니다."),
        ("선택바", "웨이브 인디케이터의 좌우 끝에 있는 드래그 바입니다."),
        ("자동 진행", "편집에서 클립 재생이 끝나면 다음 클립으로 이어지고, 마지막 클립 뒤에는 처음 클립으로 계속 이어지는 기능입니다."),
        ("달력 썸네일 버튼", "달력에서 미디어를 고르는 화면에 있는 위/아래 이동 버튼입니다."),
        ("만들기", "전체 클립을 하나의 영상으로 생성하는 액션과 버튼입니다."),
        ("영상 생성 진행창", "영상을 만드는 동안 썸네일, 진행바, 진행률, 취소 버튼이 표시되는 창입니다."),
        ("시사회", "만들기 완료 후, 저장 또는 개봉하기 직전에 제작된 전체 영화를 확인하는 화면입니다."),
        ("개봉하기 창", "시사회에서 사진 앱 또는 파일 앱 개봉 방식을 선택하는 창입니다."),
        ("브라우저", "외부 웹페이지를 이용하는 화면입니다. 웹페이지에서 영상이 감지되면 다운, 보기, 닫기 버튼이 나타납니다. 다운은 영상을 가져오고, 보기는 감지된 영상을 전체 화면으로 재생하며, 닫기는 영상 감지 알림만 닫습니다. 즐겨찾기 패널의 파비콘을 누르면 삭제하고, 길게 누르면 첫 홈페이지로 지정합니다. 즐겨찾기 편집에서는 현재 목록을 파일로 저장할 수 있습니다. 저장한 즐겨찾기 파일을 한클립으로 공유해 불러오면 같은 주소는 가져온 값으로 덮어쓰고 새 주소만 추가합니다."),
        ("자막", "영화 화면의 미디어 추가 메뉴에서 여는 설정창입니다. 결과 영상 위에 문구를 합성할지, 문구와 색상, 서체, 그림자, 위치를 설정합니다. 자막 문구가 비어 있어도 사용을 선택할 수 있어 마지막 엔딩 카드만 넣는 방식으로도 사용할 수 있습니다."),
        ("촬영 기간 삽입", "선택한 미디어의 첫 촬영일부터 마지막 촬영일까지를 자막에 넣는 기능입니다. 기본 자막이면 기존 문구를 바꾸고, 사용자가 편집한 자막이면 현재 커서 위치에 삽입합니다."),
        ("엔딩", "클립 설정의 음악 아래에 독립된 행으로 표시되며 기본값은 안함입니다. 지도 아이콘과 현재 테마명, 표시 시간 조절, 사용·안함 상태를 한 행에서 설정합니다. 현재 위치 정보가 없어도 사용과 테마를 미리 설정할 수 있고, 이후 위치 정보가 있는 미디어를 추가하면 저장된 설정이 적용됩니다. 촬영 날짜와 위치 정보가 있는 영화의 마지막에 촬영기간과 도시 이동 경로를 여행 기록 카드로 넣습니다. 같은 도시라도 촬영 날짜가 바뀌면 새 일정으로 표시하며, 지역 이동은 차량, 국가 이동은 비행기 아이콘으로 연결합니다. 대한민국은 도시만 표시하고 해외는 국가가 처음 나오거나 바뀔 때만 국가명을 표시합니다. 도시 이름은 줄을 바꾸지 않고 한 줄로 표시합니다. 엔딩 카드 시간은 1~10초 범위에서 0.5초 단위로 조절하며 자막, 보물지도, 여행일정, 랜드마크, 오피스 테마를 선택할 수 있습니다. 퀵모드에서도 같은 행과 설정 화면을 사용합니다."),
        ("엔딩 카드 테마", "영화 마지막 여행 기록 카드의 디자인입니다. 설정 위쪽에서 테마와 표시 시간을 고르고 현재 영화 화면 비율 그대로 실제 결과를 미리 봅니다. 자막은 현재 자막 서체·글자색·그림자를 이어받습니다. 보물지도는 고전 서체와 점선 경로를 사용하며 선택된 보물지도를 다시 누르면 새 경로로 재생성합니다. 여행일정은 DAY 번호 대신 각 지역의 실제 촬영 날짜를 표시합니다. 랜드마크는 국내외 주요 도시의 대표 명소와 iPhone 기본 그림문자를 자동 조합하고 미등록 지역에는 대표 여행 아이콘을 사용합니다. 오피스는 문서번호, 촬영기간, 날짜·지역·이동수단 표가 있는 정형 보고서입니다."),
        ("컬렉션 포스터", "컬렉션은 영화 포스터를 세로로 이어지는 2열 배열로 보여주며 영화 추가 포스터는 목록의 마지막에 배치합니다. 사진은 영화 제작과 같은 사진·달력 전환 화면을 사용하되 완성 영화를 가져오는 용도이므로 영상만 표시하고 선택합니다. 파일에서도 동영상만 가져옵니다. 가져오는 동안 진행바와 완료 개수를 표시합니다. 포스터를 길게 눌러 제목 수정, 공유, 컬렉션 제거를 사용하며 제목 수정 입력창은 글의 줄 수에 맞춰 커지고 키보드 위 가용 높이를 넘으면 내부에서 스크롤합니다."),
        ("워터마크", "카피라이터에서 설정하는 기능입니다. 한클립 로고 또는 사용자가 선택한 표시를 결과 영상에 합성할지 결정합니다."),
        ("외부 호출 주소", "Ai  hanclip://aishot\n퀵모드  hanclip://quick\n파일  hanclip://files\n달력  hanclip://calendar\n사진  hanclip://photo\n검색  hanclip://search\n첫 화면  hanclip://open"),
        ("샘플 음악", """
        HanClip에 포함된 샘플 음악 \(BackgroundMusicSettings.sampleDisplayName)은 앱 기능 검증과 사용자의 일상 영상 배경음악을 위해 인공지능 생성 및 합성 방식으로 만든 샘플 음악입니다.

        이 샘플 음악은 외부 음원, 기존 곡, 상용 음악 라이브러리, 사람의 실연 녹음 파일을 가져와 사용하지 않았으며, HanClip 앱 안에서 제공되는 기본 샘플 자산입니다. 사용자는 이 샘플 음악을 HanClip으로 만든 영상 결과물의 배경음악으로 사용할 수 있습니다.

        샘플 음악 중 '지우에게 첫눈이란'은 앱 제작자의 가족이 직접 만든 개인 창작 음악을 원 저작자의 허락을 받아 HanClip 앱 안에 샘플 음악으로 포함한 곡입니다. '베이비 워킹'은 이 곡에서 느껴지는 첫눈의 감정과 경쾌한 분위기를 참고하되, 원곡 음원이나 멜로디를 직접 사용하지 않고 HanClip 샘플용으로 새롭게 생성한 음악입니다.

        영화 프리셋의 '여행의 설렘'과 '골프치러 가자'도 HanClip에 포함된 샘플 음악이며 각 프리셋에서 자동으로 선택됩니다.
        """),
        ("외부 음악", """
        음악 설정 화면의 '브라우저'는 사용자가 외부 무료 음원 사이트에서 직접 음악을 찾고 다운로드할 수 있도록 Pixabay Music과 Mixkit Music 같은 공식 웹페이지를 여는 기능입니다. HanClip은 이 외부 사이트의 음원을 앱에 내장하거나 샘플 음악으로 재배포하지 않으며, 사용자가 직접 다운로드한 파일을 사용자의 영화 배경음악으로 불러와 합성하는 방식으로 동작합니다.

        Pixabay Music과 Mixkit Music에서 다운로드한 음악은 HanClip 내장 샘플 음악이 아니며, 각 음원의 권리와 이용 조건은 해당 사이트의 라이선스와 곡별 안내를 따릅니다. 사용자는 다운로드 시점의 Pixabay Content License, Mixkit License, 곡별 안내, 다운로드 기록을 확인하고 보관한 뒤 자신이 만든 영상에 사용할 책임이 있습니다.

        HanClip은 외부 음원 파일을 독립 음원으로 판매, 배포, 재라이선스하거나 음악 라이브러리 형태로 제공하지 않습니다. 외부 음원은 사용자가 선택한 영상 결과물 안에 배경음악으로 합성될 때만 사용되며, TV/라디오 방송, 게임, CD/DVD, 음원 단독 배포 등 각 사이트가 제한하는 용도에는 사용자가 별도 라이선스 확인 또는 권리자의 허락을 받아야 합니다.
        """),
        ("내장 서체 저작권", """
        HanClip에는 사용자가 영상 위에 짧은 문구나 자막을 넣을 때 선택할 수 있도록 Kakao Big Sans, Nanum Gothic, Pretendard, MaruBuri, Puradak Gentle Gothic, Tenada, Cafe24 Ssurround, Ddulgi Mayo, Gowun Dodum, Gowun Batang, Black Han Sans, Do Hyeon, Paperlogy, NEXON Lv.1 Gothic, Poppins 서체가 포함되어 있습니다. 이 서체들은 앱 전체 UI 기본 서체가 아니라, 자막 편집 미리보기와 최종 영상 렌더링 과정에서만 선택적으로 사용됩니다.

        [[embedded_font_size_table]]

        내장 자막 서체 파일의 원본 크기 합계는 약 41.5 MB입니다. 앱 번들, 압축, App Store 처리 방식에 따라 최종 설치 크기와 다운로드 크기는 달라질 수 있습니다.

        Kakao Big Sans, Nanum Gothic, Pretendard, Tenada, Gowun Dodum, Gowun Batang, Black Han Sans, Do Hyeon, Paperlogy, Poppins는 SIL Open Font License 1.1로 제공되는 서체입니다. OFL은 서체 파일을 단독으로 판매하지 않는 조건에서 사용, 복사, 앱 또는 소프트웨어 번들, 임베딩, 재배포를 허용합니다. 또한 이 서체를 사용해 만든 영상, 이미지, 문서 같은 결과물 자체는 서체 라이선스의 적용 대상이 아니므로 HanClip으로 만든 영상 결과물의 저작권이나 이용 조건은 사용자가 정한 조건을 따릅니다.

        MaruBuri의 저작권은 NAVER 및 NAVER Cultural Foundation에 있습니다. NAVER 안내에 따라 개인과 기업을 포함한 모든 사용자가 무료로 사용할 수 있고 상업적 사용이 가능하며, 글꼴 자체를 유료로 판매하는 행위를 제외하고 저작권 안내와 라이선스 전문을 포함해 다른 소프트웨어와 번들하거나 재배포할 수 있다고 설명합니다.

        Pretendard는 Kil Hyung-jin 및 원 기반 서체 저작권자의 저작권 고지와 함께 SIL Open Font License 1.1로 제공됩니다. Pretendard, Source, Inter, M PLUS 1 등 예약된 서체명은 수정본에 임의로 사용할 수 없습니다. HanClip은 공식 배포 파일을 수정하지 않고 앱에 포함합니다.

        Gowun Dodum, Gowun Batang, Black Han Sans, Do Hyeon은 Google Fonts의 공식 google/fonts 저장소에서 제공되는 SIL Open Font License 1.1 서체입니다. Google Fonts 안내에 따라 상업적 제품, 앱, 웹사이트, 인쇄물, 영상 등에서 사용할 수 있으며, HanClip은 공식 저장소의 원본 TTF 파일과 OFL 라이선스 전문을 함께 포함합니다. 수정본을 배포하는 경우에는 OFL 조건과 예약 서체명 제한을 별도로 확인해야 합니다.

        Tenada는 공식 배포 페이지에서 SIL Open Font License 1.1로 제공됩니다. 앱에 포함된 Tenada.ttf는 공식 배포본의 원본 파일이며, HanClip에서는 골프 기록, 홀 정보, 스코어 같은 제목형 자막에 사용할 수 있도록 제공합니다.

        Paperlogy는 제작자의 공식 저장소에서 배포한 1.001 버전의 Bold 원본 파일이며, Poppins는 Google Fonts 공식 저장소의 Regular 원본 파일입니다. 두 파일 모두 SIL Open Font License 1.1 전문과 저작권 고지를 함께 포함합니다.

        NEXON Lv.1 Gothic의 저작권은 NEXON Korea에 있습니다. 넥슨의 공식 이용 조건에 따라 원본 파일을 수정하지 않고 저작권 안내와 함께 앱에 번들했으며, 글꼴 파일 자체를 단독 판매하지 않습니다.

        Cafe24 Ssurround는 Cafe24 공식 안내에 따라 개인 및 기업 사용자를 포함한 모든 사용자에게 무료로 제공되며 상업적 사용이 가능합니다. Cafe24는 영상 제작 및 자막, 소프트웨어 번들, 특정 프로그램 임베드 등 사용 범위 제한 없이 이용할 수 있다고 안내합니다. 단, 글꼴 파일 자체를 유료로 판매하는 행위는 금지됩니다.

        Puradak Gentle Gothic은 Puradak Chicken 공식 폰트 페이지에서 무료로 배포되는 서체입니다. 공개 사용 안내에 따라 상업적, 비상업적 사용과 영상 자막, 앱 사용, 소프트웨어 번들이 가능하며, HanClip은 공식 TTF 파일을 수정하지 않고 포함합니다. 서체 파일 자체를 단독 판매하거나 저작권 고지를 제거해서 재배포해서는 안 됩니다.

        Ddulgi Mayo는 제작자 공식 블로그에서 개인 및 기업의 상업적 이용이 가능하고 자유롭게 사용할 수 있다고 안내된 서체입니다. HanClip은 제작자가 공개한 원본 OTF 파일을 수정하지 않고 포함합니다. 다만 OFL처럼 세부 재배포 조건이 긴 전문 형태로 제공된 서체는 아니므로, HanClip에서는 원본 파일과 저작권 고지를 함께 보관하고 서체 파일 자체를 단독 판매하지 않습니다. 향후 라이선스 정책이 바뀌거나 앱 번들/재배포 조건이 더 엄격하게 확인될 경우에는 우선 검토 또는 제거 대상입니다.

        모든 내장 서체의 라이선스 전문, 저작권 고지, 확인한 공식 배포처 정보, 파일 크기 정리는 앱 번들에 포함된 font-licenses 파일을 기준으로 보관합니다. 서체 파일을 수정하거나 별도 재배포하는 경우에는 각 서체의 원 라이선스와 저작권 고지를 유지해야 하며, 예약된 서체명이 있는 경우 수정본에 원래 이름을 사용할 수 없습니다.
        """)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    settingsHeaderIdentity
                        .padding(.bottom, 14)

                    VStack(alignment: .leading, spacing: 14) {
                        copyrightSettings
                        sleepPreventionSettings

                        ForEach(items, id: \.title) { item in
                            if item.title == "내장 서체 저작권" {
                                embeddedFontCopyrightRow(
                                    title: item.title,
                                    body: item.body,
                                    systemImage: infoIcon(for: item.title)
                                )
                            } else {
                                infoRow(
                                    title: item.title,
                                    body: item.body,
                                    systemImage: infoIcon(for: item.title)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 0)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnDrag()
            .background(HanClipTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            loadAddress(for: selectedPlatform)
        }
        .onChange(of: purchaseManager.isPurchased) { _, isPurchased in
            if !isPurchased {
                copyrightEnabled = false
                isWatermarkSettingsExpanded = false
            }
        }
        .alert(
            "인앱 구매",
            isPresented: Binding(
                get: { purchaseManager.message != nil },
                set: { if !$0 { purchaseManager.message = nil } }
            )
        ) {
            Button("확인", role: .cancel) {
                purchaseManager.message = nil
            }
        } message: {
            Text(purchaseManager.message ?? "")
        }
    }

    private var settingsHeaderIdentity: some View {
        HanClipTopHeader(
            logoAccessibilityLabel: "설정 닫기",
            logoAction: {
                dismiss()
            }
        ) {
            HanClipHeaderActionCluster {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("닫기")

                Button {
                    resetCopyrightSettings()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("워터마크 초기화")
            }
        }
    }

    private var selectedPlatform: WatermarkPlatform {
        WatermarkPlatform(rawValue: platformRaw) ?? .hanclip
    }

    private var selectedPosition: WatermarkPosition {
        WatermarkPosition(rawValue: positionRaw)
            ?? WatermarkSettings.defaultCopyrightPosition
    }

    private var selectedIconColorMode: CopyrightIconColorMode {
        CopyrightIconColorMode(rawValue: iconColorModeRaw)
            ?? WatermarkSettings.defaultCopyrightIconColorMode
    }

    private var showsAddressInput: Bool {
        copyrightEnabled && selectedPlatform != .hanclip
    }

    private var copyrightSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HanClipTitleLine(
                "카피라이터 설정",
                systemImage: "person.text.rectangle.fill",
                leadingInset: 18,
                trailingInset: -2
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isWatermarkSettingsExpanded.toggle()
                        }
                    } label: {
                        sectionTitle("워터마크", systemImage: "seal.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(purchaseManager.isPurchasing)

                    Spacer(minLength: 8)

                    if purchaseManager.isPurchasing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("구매 진행 중")
                    }

                    if purchaseManager.isPurchased {
                        WatermarkModeSegmentedControl(
                            isEnabled: $copyrightEnabled,
                            isCompact: true
                        )
                        .frame(width: 84)
                        .accessibilityLabel("워터마크 사용 설정")
                    } else {
                        Text(
                            "구매 옵션"
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HanClipTheme.secondaryText)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isWatermarkSettingsExpanded.toggle()
                        }
                    } label: {
                        Image(
                            systemName: isWatermarkSettingsExpanded
                                ? "chevron.up"
                                : "chevron.down"
                        )
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(HanClipTheme.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(purchaseManager.isPurchasing)
                    .accessibilityLabel("워터마크 설정")
                    .accessibilityValue(
                        isWatermarkSettingsExpanded ? "펼쳐짐" : "접힘"
                    )
                }

                if isWatermarkSettingsExpanded {
                    VStack(alignment: .leading, spacing: 16) {
                        if purchaseManager.isPurchased {
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: 8),
                                    count: 5
                                ),
                                spacing: 8
                            ) {
                                ForEach(WatermarkPlatform.allCases) { platform in
                                    copyrightPlatformButton(platform)
                                }
                            }

                            if showsAddressInput {
                                TextField(
                                    selectedPlatform == .custom
                                        ? "표시할 자막"
                                        : "\(selectedPlatform.title) 한 줄 입력",
                                    text: addressBinding(for: selectedPlatform)
                                )
                                .font(.system(size: 14, weight: .medium))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background(
                                    Color.white.opacity(0.42),
                                    in: RoundedRectangle(
                                        cornerRadius: 12,
                                        style: .continuous
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius: 12,
                                        style: .continuous
                                    )
                                    .stroke(
                                        HanClipTheme.secondary.opacity(0.22),
                                        lineWidth: 1
                                    )
                                }
                            }

                            if copyrightEnabled && selectedPlatform == .custom {
                                customIconPicker
                            }

                            copyrightPositionSettings

                            VStack(alignment: .leading, spacing: 10) {
                                sectionTitle("색상", systemImage: "paintpalette.fill")

                                HStack(spacing: 10) {
                                    copyrightColorPicker(
                                        title: "글자",
                                        selection: Binding(
                                            get: {
                                                Color(hexString: textColorHex)
                                                    ?? HanClipTheme.primary
                                            },
                                            set: {
                                                textColorHex = $0.hexString
                                                    ?? WatermarkSettings.defaultCopyrightTextColor
                                                shadowColorHex = Color(
                                                    uiColor: complementaryColor(for: UIColor($0))
                                                ).hexString
                                                    ?? WatermarkSettings.defaultCopyrightShadowColor
                                            }
                                        )
                                    )

                                    copyrightColorPicker(
                                        title: "그림자 색",
                                        selection: Binding(
                                            get: {
                                                Color(hexString: shadowColorHex)
                                                    ?? HanClipTheme.secondary
                                            },
                                            set: {
                                                shadowColorHex = $0.hexString
                                                    ?? WatermarkSettings.defaultCopyrightShadowColor
                                            }
                                        )
                                    )
                                }

                                copyrightShadowOpacityControl
                            }
                        } else {
                            copyrightPurchaseOptions
                        }
                    }
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    Task {
                        await purchaseManager.restore()
                    }
                } label: {
                    Text("구매 복원")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(HanClipTheme.secondary)
                .disabled(purchaseManager.isPurchasing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        HanClipTheme.panelFill.opacity(0.96),
                        HanClipTheme.secondary.opacity(0.05),
                        Color.white.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .hanClipGlassPanel(cornerRadius: 22, shadowOpacity: 0.05)
        }
    }

    private var copyrightPurchaseOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("카피라이터 워터마크 이용권")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(HanClipTheme.text)

            Text("영구 이용권 또는 자동 갱신 구독을 선택하세요.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HanClipTheme.secondaryText)

            ForEach(CopyrightPurchasePlan.allCases) { plan in
                copyrightPurchaseButton(plan)
            }

            Text("월간 및 연간 상품은 결제 확인 후 자동 갱신되며, Apple 계정의 구독 관리에서 언제든 해지할 수 있습니다.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(HanClipTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyrightPurchaseButton(
        _ plan: CopyrightPurchasePlan
    ) -> some View {
        Button {
            Task {
                await purchaseManager.purchase(plan)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(HanClipTheme.text)

                    Text(plan.detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HanClipTheme.secondaryText)
                }

                Spacer(minLength: 8)

                Text(purchaseManager.displayPrice(for: plan))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HanClipTheme.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                HanClipTheme.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(HanClipTheme.secondary.opacity(0.20), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(purchaseManager.isPurchasing || purchaseManager.isLoading)
        .accessibilityLabel("\(plan.title), \(purchaseManager.displayPrice(for: plan))")
        .accessibilityHint(plan.detail)
    }

    private var copyrightPositionSettings: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("위치", systemImage: "scope")

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 6),
                    count: 5
                ),
                spacing: 6
            ) {
                ForEach(WatermarkPosition.allCases) { position in
                    copyrightPositionButton(position)
                }
            }
            .padding(7)
            .background(
                HanClipTheme.secondary.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }

    private var sleepPreventionMode: SleepPreventionMode {
        SleepPreventionMode(rawValue: sleepPreventionModeRaw) ?? .automatic
    }

    private var sleepPreventionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("화면 꺼짐 방지", systemImage: "sun.max.fill")

            Picker("화면 꺼짐 방지", selection: $sleepPreventionModeRaw) {
                ForEach(SleepPreventionMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text(sleepPreventionMode.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HanClipTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.panelFill.opacity(0.9),
                    HanClipTheme.secondary.opacity(0.06),
                    Color.white.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    private func sectionTitle(
        _ title: String,
        systemImage: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(HanClipTheme.secondary)
            }
            Text(title)
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(HanClipTheme.secondaryText)
    }

    private func copyrightColorPicker(
        title: String,
        selection: Binding<Color>
    ) -> some View {
        ColorPicker(title, selection: selection, supportsOpacity: false)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(HanClipTheme.secondaryText)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                Color.white.opacity(0.26),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(HanClipTheme.secondary.opacity(0.16), lineWidth: 1)
            }
    }

    private var copyrightShadowOpacityControl: some View {
        let percentage = Int((shadowOpacity * 100).rounded())

        return Button {
            let currentStep = min(100, max(0, Int(round(Double(percentage) / 10)) * 10))
            let nextStep = currentStep >= 100 ? 0 : currentStep + 10
            shadowOpacity = Double(nextStep) / 100
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(HanClipTheme.secondary)
                Text("그림자 투명도")
                Spacer(minLength: 8)
                Text("\(percentage)%")
                    .monospacedDigit()
                    .foregroundStyle(HanClipTheme.primary)
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(HanClipTheme.secondaryText)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                Color.white.opacity(0.26),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(HanClipTheme.secondary.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("워터마크 그림자 투명도")
        .accessibilityValue("\(percentage)퍼센트")
        .accessibilityHint("누를 때마다 10퍼센트씩 증가합니다")
    }

    private func copyrightPlatformButton(
        _ platform: WatermarkPlatform
    ) -> some View {
        let isSelected = copyrightEnabled && selectedPlatform == platform

        return Button {
            selectCopyrightPlatform(platform)
        } label: {
            VStack(spacing: 0) {
                CopyrightPlatformLogo(
                    platform: platform,
                    iconColorMode: selectedIconColorMode,
                    iconColorHex: iconColorHex,
                    shadowColorHex: shadowColorHex,
                    shadowOpacity: shadowOpacity
                )
                    .id(customIconRefreshID)
                    .frame(width: platform == .hanclip ? 42 : 30, height: 30)
            }
            .foregroundStyle(isSelected ? .white : HanClipTheme.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                LinearGradient(
                    colors: isSelected
                        ? [
                            HanClipTheme.primary,
                            HanClipTheme.secondary.opacity(0.82)
                        ]
                        : [
                            HanClipTheme.secondary.opacity(0.12),
                            Color.white.opacity(0.18)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color.white.opacity(0.32)
                            : HanClipTheme.secondary.opacity(0.12),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(platform.title)
    }

    private var customIconPicker: some View {
        HStack(spacing: 12) {
            customIconPreview

            PhotosPicker(
                selection: $customIconPickerItem,
                matching: .images
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                    Text("직접입력 이미지")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HanClipTheme.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    HanClipTheme.secondary.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
        .onChange(of: customIconPickerItem) { _, item in
            guard let item else { return }
            Task {
                await saveCustomIcon(from: item)
            }
        }
    }

    private var customIconPreview: some View {
        Group {
            if let image = customIconImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("CopyrightCustom")
                    .resizable()
                    .scaledToFit()
                    .padding(7)
            }
        }
        .frame(width: 44, height: 44)
        .id(customIconRefreshID)
        .background(
            Color.white.opacity(0.42),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var customIconImage: UIImage? {
        guard !customIconPath.isEmpty else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: customIconPath)) else {
            return nil
        }
        return UIImage(data: data)
    }

    @MainActor
    private func saveCustomIcon(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let pngData = resizedSquarePNGData(from: image, side: 360)
        else { return }

        do {
            let directory = try customIconDirectory()
            let url = directory.appendingPathComponent(
                "customCopyrightIcon.png"
            )
            try pngData.write(to: url, options: .atomic)
            customIconPath = url.path
            customIconRefreshID = UUID()
            customIconPickerItem = nil
        } catch {
            customIconPath = ""
            customIconRefreshID = UUID()
        }
    }

    private func customIconDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(
            "CustomCopyrightIcon",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func resizedSquarePNGData(
        from image: UIImage,
        side: CGFloat
    ) -> Data? {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side)
        )
        let resized = renderer.image { _ in
            let scale = max(side / image.size.width, side / image.size.height)
            let drawSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            let drawOrigin = CGPoint(
                x: (side - drawSize.width) / 2,
                y: (side - drawSize.height) / 2
            )
            image.draw(
                in: CGRect(origin: drawOrigin, size: drawSize)
            )
        }
        return resized.pngData()
    }

    private func copyrightPositionButton(
        _ position: WatermarkPosition
    ) -> some View {
        let isSelected = selectedPosition == position

        return Button {
            positionRaw = position.rawValue
        } label: {
            ZStack {
                Circle()
                    .stroke(
                        isSelected
                            ? HanClipTheme.primary
                            : HanClipTheme.secondary.opacity(0.52),
                        lineWidth: 2
                    )
                    .frame(width: 14, height: 14)

                if isSelected {
                    Circle()
                        .fill(HanClipTheme.primary)
                        .frame(width: 7, height: 7)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                isSelected
                    ? HanClipTheme.secondary.opacity(0.14)
                    : Color.white.opacity(0.28),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(position.title)
    }

    private func selectCopyrightPlatform(_ platform: WatermarkPlatform) {
        if platform == .hanclip,
           copyrightEnabled,
           selectedPlatform == .hanclip {
            copyrightEnabled = false
            return
        }

        platformRaw = platform.rawValue
        copyrightEnabled = true
        loadAddress(for: platform)
        applyIconDefaultCopyrightColors(for: platform)
    }

    private func loadAddress(for platform: WatermarkPlatform) {
        address = UserDefaults.standard.string(
            forKey: WatermarkSettings.addressStorageKey(for: platform)
        ) ?? ""
    }

    private func addressBinding(
        for platform: WatermarkPlatform
    ) -> Binding<String> {
        Binding(
            get: { address },
            set: { newValue in
                address = newValue
                UserDefaults.standard.set(
                    newValue,
                    forKey: WatermarkSettings.addressStorageKey(for: platform)
                )
            }
        )
    }

    private func applyIconDefaultCopyrightColors(
        for platform: WatermarkPlatform
    ) {
        guard let color = dominantCopyrightIconColor(for: platform) else {
            textColorHex = Color(
                uiColor: HanClipTheme.primaryUIColor
            ).hexString ?? WatermarkSettings.defaultCopyrightTextColor
            shadowColorHex = Color(
                uiColor: HanClipTheme.secondaryUIColor
            ).hexString ?? WatermarkSettings.defaultCopyrightShadowColor
            return
        }

        textColorHex = Color(uiColor: color).hexString
            ?? WatermarkSettings.defaultCopyrightTextColor
        shadowColorHex = Color(uiColor: complementaryColor(for: color)).hexString
            ?? WatermarkSettings.defaultCopyrightShadowColor
    }

    private func dominantCopyrightIconColor(
        for platform: WatermarkPlatform
    ) -> UIColor? {
        guard let image = copyrightIconImage(for: platform),
              let cgImage = image.cgImage
        else { return nil }

        let side = 40
        let bytesPerPixel = 4
        let bytesPerRow = side * bytesPerPixel
        var pixels = [UInt8](
            repeating: 0,
            count: side * side * bytesPerPixel
        )

        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var colorBuckets: [Int: (count: Int, red: Int, green: Int, blue: Int)] =
            [:]

        stride(from: 0, to: pixels.count, by: bytesPerPixel).forEach { index in
            let alpha = Int(pixels[index + 3])
            guard alpha > 96 else { return }

            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            let bucketRed = red / 24
            let bucketGreen = green / 24
            let bucketBlue = blue / 24
            let key = (bucketRed << 16) | (bucketGreen << 8) | bucketBlue
            let current = colorBuckets[key]
                ?? (count: 0, red: 0, green: 0, blue: 0)
            colorBuckets[key] = (
                count: current.count + 1,
                red: current.red + red,
                green: current.green + green,
                blue: current.blue + blue
            )
        }

        guard let dominant = colorBuckets.values.max(by: {
            $0.count < $1.count
        }) else { return nil }

        return UIColor(
            red: CGFloat(dominant.red / dominant.count) / 255,
            green: CGFloat(dominant.green / dominant.count) / 255,
            blue: CGFloat(dominant.blue / dominant.count) / 255,
            alpha: 1
        )
    }

    private func copyrightIconImage(
        for platform: WatermarkPlatform
    ) -> UIImage? {
        if platform == .custom,
           !customIconPath.isEmpty,
           let image = UIImage(contentsOfFile: customIconPath) {
            return image
        }

        switch platform {
        case .hanclip:
            return UIImage(named: "LogoMarkV2")
        case .instagram:
            return UIImage(named: "CopyrightInstagram")
        case .facebook:
            return UIImage(named: "CopyrightFacebook")
        case .youtube:
            return UIImage(named: "CopyrightYouTube")
        case .blog:
            return UIImage(named: "CopyrightBlog")
        case .kakaoTalk:
            return UIImage(named: "CopyrightKakaoTalk")
        case .x:
            return UIImage(named: "CopyrightX")
        case .phone:
            return UIImage(named: "CopyrightTelephone")
        case .homepage:
            return UIImage(named: "CopyrightHomepage")
        case .custom:
            return UIImage(named: "CopyrightCustom")
        }
    }

    private func complementaryColor(for color: UIColor) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        else { return HanClipTheme.secondaryUIColor }

        return UIColor(
            red: 1 - red,
            green: 1 - green,
            blue: 1 - blue,
            alpha: 1
        )
    }

    private func resetCopyrightSettings() {
        let resetPlatform = selectedPlatform
        copyrightEnabled = true
        platformRaw = resetPlatform.rawValue
        positionRaw = WatermarkSettings.defaultCopyrightPosition.rawValue
        shadowOpacity = WatermarkSettings.defaultCopyrightShadowOpacity
        iconColorModeRaw =
            WatermarkSettings.defaultCopyrightIconColorMode.rawValue
        applyIconDefaultCopyrightColors(for: resetPlatform)
        loadAddress(for: resetPlatform)
    }

    private func infoRow(
        title: String,
        body: String,
        systemImage: String
    ) -> some View {
        InfoRow(
            title: title,
            detail: body,
            systemImage: systemImage,
            imageName: infoImageName(for: title),
            isCentered: title == "Special Thanks"
        )
    }

    private func infoImageName(for title: String) -> String? {
        switch title {
        case "로고":
            return "LogoMarkV2"
        case "AiShot":
            return "AiShotIcon"
        default:
            return nil
        }
    }

    private func embeddedFontCopyrightRow(
        title: String,
        body: String,
        systemImage: String
    ) -> some View {
        EmbeddedFontCopyrightRow(
            title: title,
            detail: body,
            systemImage: systemImage
        )
    }

    private func infoIcon(for title: String) -> String {
        switch title {
        case "Special Thanks": "heart.fill"
        case "카피라이터": "info.circle.fill"
        case "첫 화면": "house.fill"
        case "영화 프리셋": "square.grid.2x2.fill"
        case "퀵모드": "bolt.fill"
        case "여행 영화": "airplane"
        case "인생 영화": "heart.fill"
        case "Ai": "sparkles"
        case "AiShot": "camera.fill"
        case "영화 목록": "rectangle.stack.fill"
        case "영화 화면": "film.fill"
        case "영화 설정": "slider.horizontal.3"
        case "클립목록": "list.bullet.rectangle.fill"
        case "묶음사진": "rectangle.stack.badge.plus"
        case "순서변경 상태": "arrow.up.arrow.down"
        case "편집 영역 / 편집 모드": "slider.horizontal.below.rectangle"
        case "시사회": "play.rectangle.fill"
        case "만들기": "wand.and.stars"
        case "영상 생성 진행창": "progress.indicator"
        case "개봉하기 창": "square.and.arrow.up.fill"
        case "테마 선택창": "paintpalette.fill"
        case "첫 화면 이동 팝업": "house.and.flag.fill"
        case "로고": "play.hexagon.fill"
        case "워터마크": "signature"
        case "세그먼트 컨트롤": "rectangle.split.2x1.fill"
        case "자동 / 수동 / 전체": "sparkles"
        case "사용 / 제외": "checkmark.circle.fill"
        case "사진 / 영상": "livephoto"
        case "한컷 / 분할": "square.stack.3d.up.fill"
        case "모클립": "rectangle.stack.fill"
        case "자클립": "rectangle.fill.on.rectangle.fill"
        case "자사진": "photo.fill"
        case "웨이브 / 웨이브 인디케이터": "waveform"
        case "선택바": "arrow.left.and.right"
        case "자동 진행": "repeat"
        case "달력 썸네일 버튼": "calendar"
        case "자막": "captions.bubble.fill"
        case "엔딩": "map.fill"
        case "브라우저": "globe"
        case "외부 호출 주소": "link"
        case "샘플 음악": "music.note.list"
        case "외부 음악": "globe"
        case "내장 서체 저작권": "textformat"
        default: "info.circle.fill"
        }
    }
}

private struct TextOverlaySettingsSheet: View {
    private struct FontPresetSpec: Identifiable {
        let id: String
        let title: String
        let preferredFontIDs: [String]
        let textColor: String
        let shadowColor: String
        let fontSize: WatermarkFontSize
        let shadowOpacity: Double

        init(
            id: String,
            title: String,
            preferredFontIDs: [String],
            textColor: String,
            shadowColor: String,
            fontSize: WatermarkFontSize,
            shadowOpacity: Double = 0.5
        ) {
            self.id = id
            self.title = title
            self.preferredFontIDs = preferredFontIDs
            self.textColor = textColor
            self.shadowColor = shadowColor
            self.fontSize = fontSize
            self.shadowOpacity =
                WatermarkSettings.normalizedShadowOpacity(shadowOpacity)
        }
    }

    private struct FontPresetAppearance: Codable, Equatable {
        var textColor: String
        var shadowColor: String
        var shadowOpacity: Double
        var fontSize: WatermarkFontSize
        var lineSpacing: WatermarkLineSpacing
        var lineSpacingScale: Double

        init(
            textColor: String,
            shadowColor: String,
            shadowOpacity: Double,
            fontSize: WatermarkFontSize,
            lineSpacing: WatermarkLineSpacing = .normal,
            lineSpacingScale: Double = WatermarkLineSpacing.defaultMultiplier
        ) {
            self.textColor = TextOverlaySettingsSheet.normalizedHex(textColor)
            self.shadowColor = TextOverlaySettingsSheet.normalizedHex(shadowColor)
            self.shadowOpacity =
                WatermarkSettings.normalizedShadowOpacity(shadowOpacity)
            self.fontSize = fontSize
            self.lineSpacing = lineSpacing
            self.lineSpacingScale =
                WatermarkSettings.normalizedLineSpacingScale(lineSpacingScale)
        }
    }

    private struct SessionState: Equatable {
        var isEnabled: Bool
        var text: String
        var position: WatermarkPosition
        var fontName: String
        var textColorHex: String
        var shadowEnabled: Bool
        var shadowOpacity: Double
        var shadowColorHex: String
        var lineSpacing: WatermarkLineSpacing
        var lineSpacingScale: Double
        var fontSize: WatermarkFontSize
        var includesEndingInfoCard: Bool
        var endingInfoCardDuration: Double
        var endingInfoCardTheme: EndingInfoCardTheme
        var endingInfoCardVariation: Int

        func matchesContent(of other: SessionState) -> Bool {
            text == other.text
                && position == other.position
                && fontName == other.fontName
                && textColorHex == other.textColorHex
                && shadowEnabled == other.shadowEnabled
                && abs(shadowOpacity - other.shadowOpacity) < 0.001
                && shadowColorHex == other.shadowColorHex
                && lineSpacing == other.lineSpacing
                && abs(lineSpacingScale - other.lineSpacingScale) < 0.001
                && fontSize == other.fontSize
                && includesEndingInfoCard == other.includesEndingInfoCard
                && abs(
                    endingInfoCardDuration - other.endingInfoCardDuration
                ) < 0.001
                && endingInfoCardTheme == other.endingInfoCardTheme
                && endingInfoCardVariation == other.endingInfoCardVariation
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var showInstalledFontPicker = false
    @State private var showFontFilePicker = false
    @State private var showAdvancedFontSettings = false
    @State private var fontImportNotice: String?
    @State private var textInputBackgroundHex =
        TextOverlaySettingsSheet.randomTextInputBackgroundHex()
    @State private var expandedTextInputHeight: CGFloat = 0
    @State private var textSelectionRange = NSRange(location: 0, length: 0)
    @State private var hasUserEditedCaptionText = false
    @State private var originalSessionState: SessionState?
    @State private var activeFontPresetID: String?
    @State private var suppressNextResetTap = false
    @State private var fontPresetResetNotice: String?
    @State private var fontPresetAppearances =
        TextOverlaySettingsSheet.loadFontPresetAppearances()
    @Binding var textEnabled: Bool
    @Binding var text: String
    @Binding var position: WatermarkPosition
    @Binding var fontName: String
    @Binding var textColorHex: String
    @Binding var shadowEnabled: Bool
    @Binding var shadowOpacity: Double
    @Binding var shadowColorHex: String
    @Binding var lineSpacing: WatermarkLineSpacing
    @Binding var lineSpacingScale: Double
    @Binding var fontSize: WatermarkFontSize
    let mediaDateRange: ClosedRange<Date>?
    let mediaCount: Int
    @Binding var includesEndingInfoCard: Bool
    @Binding var endingInfoCardDuration: Double
    @Binding var endingInfoCardTheme: EndingInfoCardTheme
    @Binding var endingInfoCardVariation: Int
    let hasEndingInfo: Bool
    let loadEndingInfoPreview: () async -> EndingInfoPreviewData?
    let renderEndingInfoPreview: (
        EndingInfoPreviewData,
        EndingInfoCardTheme
    ) -> UIImage
    @State private var endingInfoPreview: EndingInfoPreviewData?
    @State private var renderedEndingInfoPreview: UIImage?

    private var allowedTextFontNames: Set<String> {
        Set(FontRegistry.availableFonts.map(\.id))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HanClipTitleLine(
                        "자막",
                        systemImage: "textformat",
                        leadingInset: 0,
                        trailingInset: 0
                    )
                    .padding(.bottom, 2)

                    WatermarkModeSegmentedControl(isEnabled: $textEnabled)

                    if textEnabled {
                        textInputSection
                    }

                    dateCaptionSettings

                    if textEnabled {
                        fontSettings
                        appearanceSettings
                        positionSettings
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnDrag()
            .background(HanClipTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        guard !suppressNextResetTap else {
                            suppressNextResetTap = false
                            return
                        }
                        resetSettings()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.6)
                            .onEnded { _ in
                                suppressNextResetTap = true
                                resetFontPresetAppearances()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    suppressNextResetTap = false
                                }
                            }
                    )
                    .foregroundStyle(HanClipTheme.primary)
                    .accessibilityLabel("초기화")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if hasSessionChanges {
                        HStack(spacing: 2) {
                            Button {
                                discardChangesAndDismiss()
                            } label: {
                                settingsToolbarIcon("xmark")
                            }
                            .accessibilityLabel("저장 없이 나가기")

                            Button {
                                dismiss()
                            } label: {
                                settingsToolbarSaveIcon
                            }
                            .accessibilityLabel("저장 후 닫기")
                        }
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            settingsToolbarIcon("xmark")
                        }
                        .accessibilityLabel("닫기")
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if let fontPresetResetNotice {
                Text(fontPresetResetNotice)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(HanClipTheme.primary, in: Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: $showInstalledFontPicker) {
            InstalledFontPicker(fontName: $fontName)
        }
        .fullScreenCover(isPresented: $showFontFilePicker) {
            FilePicker(
                allowedContentTypes: fontContentTypes,
                allowsMultipleSelection: true
            ) { result in
                handleFontFilePicker(result)
            }
        }
        .onAppear {
            applyDefaultSettingsIfNeeded()
            normalizeSelectedFont()
            beginEditingSessionIfNeeded()
            hasUserEditedCaptionText = !isBasicDateCaptionText
            refreshTextInputBackground()
        }
        .onChange(of: textColorHex) { _, _ in
            refreshTextInputBackground()
        }
        .onChange(of: shadowColorHex) { _, _ in
            refreshTextInputBackground()
        }
        .onChange(of: shadowOpacity) { _, newValue in
            let normalized =
                WatermarkSettings.normalizedShadowOpacity(newValue)
            shadowOpacity = normalized
            shadowEnabled = normalized > 0
            rememberActiveFontPresetAppearance()
        }
        .onChange(of: textColorHex) { _, _ in
            rememberActiveFontPresetAppearance()
        }
        .onChange(of: shadowColorHex) { _, _ in
            rememberActiveFontPresetAppearance()
        }
        .onChange(of: fontSize) { _, _ in
            rememberActiveFontPresetAppearance()
        }
        .onChange(of: lineSpacing) { _, _ in
            rememberActiveFontPresetAppearance()
        }
        .onChange(of: lineSpacingScale) { _, newValue in
            lineSpacingScale =
                WatermarkSettings.normalizedLineSpacingScale(newValue)
            rememberActiveFontPresetAppearance()
        }
    }

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            textInput
        }
        .textOverlaySectionStyle()
    }

    private var dateCaptionSettings: some View {
        HStack(spacing: 6) {
            dateCaptionButton(
                title: "오늘 날짜 삽입",
                value: WatermarkSettings.dateCaptionText()
            )

            dateCaptionButton(
                title: "촬영 기간 삽입",
                value: mediaDateCaptionText
            )
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var endingInfoCardPreview: some View {
        if endingInfoPreview != nil {
            VStack(spacing: 9) {
                endingInfoThemePicker
                endingInfoDurationControl

                if let renderedEndingInfoPreview {
                    Image(uiImage: renderedEndingInfoPreview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                            .stroke(
                                endingInfoPreviewAccentColor.opacity(0.38),
                                lineWidth: 1
                            )
                        }
                        .shadow(
                            color: endingInfoPreviewAccentColor.opacity(0.12),
                            radius: 8,
                            y: 3
                        )
                        .accessibilityLabel(
                            "\(endingInfoCardTheme.title) 엔딩 카드 실제 미리보기"
                        )
                } else {
                    ProgressView()
                        .tint(endingInfoPreviewAccentColor)
                        .frame(maxWidth: .infinity, minHeight: 110)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(HanClipTheme.panelFill, in: RoundedRectangle(cornerRadius: 15))
        } else {
            ProgressView("정보를 확인하는 중…")
                .font(.system(size: 11, weight: .medium))
                .tint(HanClipTheme.primary)
                .foregroundStyle(HanClipTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    HanClipTheme.panelFill,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
        }
    }

    private func refreshRenderedEndingInfoPreview() {
        guard let endingInfoPreview else {
            renderedEndingInfoPreview = nil
            return
        }
        renderedEndingInfoPreview = renderEndingInfoPreview(
            endingInfoPreview,
            endingInfoCardTheme
        )
    }

    private var endingInfoThemePicker: some View {
        HStack(spacing: 5) {
            ForEach(EndingInfoCardTheme.allCases) { theme in
                Button {
                    if theme == .treasureMap,
                       endingInfoCardTheme == .treasureMap {
                        endingInfoCardVariation += 1
                        refreshRenderedEndingInfoPreview()
                    } else {
                        endingInfoCardTheme = theme
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: theme.systemImage)
                            .font(.system(size: 10, weight: .bold))
                        Text(theme.title)
                            .font(.system(size: 8.5, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(
                        endingInfoCardTheme == theme
                            ? endingInfoPreviewAccentColor
                            : endingInfoPreviewSecondaryColor
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 35)
                    .background(
                        endingInfoCardTheme == theme
                            ? endingInfoPreviewAccentColor.opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(
                                endingInfoCardTheme == theme
                                    ? endingInfoPreviewAccentColor.opacity(0.42)
                                    : endingInfoPreviewSecondaryColor.opacity(0.20),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var endingInfoDurationControl: some View {
        HStack(spacing: 12) {
            Text("표시 시간")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(endingInfoPreviewSecondaryColor)

            Spacer(minLength: 0)

            Button {
                endingInfoCardDuration =
                    WatermarkSettings.normalizedEndingInfoCardDuration(
                        endingInfoCardDuration - 0.5
                    )
            } label: {
                Image(systemName: "minus")
                    .frame(width: 30, height: 28)
            }
            .disabled(endingInfoCardDuration <= 1)

            Text(String(format: "%.1f초", endingInfoCardDuration))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(endingInfoPreviewTextColor)
                .frame(width: 45)

            Button {
                endingInfoCardDuration =
                    WatermarkSettings.normalizedEndingInfoCardDuration(
                        endingInfoCardDuration + 0.5
                    )
            } label: {
                Image(systemName: "plus")
                    .frame(width: 30, height: 28)
            }
            .disabled(endingInfoCardDuration >= 10)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(endingInfoPreviewAccentColor)
        .buttonStyle(.plain)
    }

    private var endingInfoPreviewAccentColor: Color {
        HanClipTheme.primary
    }

    private var endingInfoPreviewTextColor: Color {
        HanClipTheme.primaryText
    }

    private var endingInfoPreviewSecondaryColor: Color {
        HanClipTheme.secondaryText
    }

    private var endingInfoButton: some View {
        Button {
            includesEndingInfoCard.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(
                    systemName: includesEndingInfoCard
                        ? "circle.inset.filled"
                        : "circle"
                )
                .font(.system(size: 9.5, weight: .bold))
                Text("엔딩")
                    .font(.system(size: 10.5, weight: .bold))
            }
            .foregroundStyle(
                includesEndingInfoCard
                    ? HanClipTheme.primary
                    : HanClipTheme.primary.opacity(0.58)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 21)
            .background(
                includesEndingInfoCard
                    ? HanClipTheme.primary.opacity(0.13)
                    : HanClipTheme.panelFill,
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(
                    includesEndingInfoCard
                        ? HanClipTheme.primary.opacity(0.30)
                        : HanClipTheme.panelStroke.opacity(0.62),
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("마지막 엔딩 카드 삽입")
        .accessibilityValue(includesEndingInfoCard ? "선택됨" : "선택 안 됨")
    }

    private var mediaDateCaptionText: String? {
        if mediaCount <= 1 {
            return WatermarkSettings.dateRangeCaptionText(
                from: Date(),
                to: Date()
            )
        }
        guard let mediaDateRange else {
            return WatermarkSettings.dateRangeCaptionText(
                from: Date(),
                to: Date()
            )
        }
        return WatermarkSettings.dateRangeCaptionText(
            from: mediaDateRange.lowerBound,
            to: mediaDateRange.upperBound
        )
    }

    private func dateCaptionButton(
        title: String,
        value: String?
    ) -> some View {
        let isSelected = value != nil && text == value
        return Button {
            guard let value else { return }
            insertDateCaption(value)
            textEnabled = true
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(
                    isSelected
                        ? HanClipTheme.primary
                        : HanClipTheme.primary.opacity(0.58)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 21)
                .background(
                    isSelected
                        ? HanClipTheme.primary.opacity(0.13)
                        : HanClipTheme.panelFill,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            isSelected
                                ? HanClipTheme.primary.opacity(0.30)
                                : HanClipTheme.panelStroke.opacity(0.62),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(value == nil)
        .opacity(value == nil ? 0.36 : 1)
    }

    private var isBasicDateCaptionText: Bool {
        text == WatermarkSettings.dateCaptionText()
            || text == mediaDateCaptionText
            || text == WatermarkSettings.legacyDefaultText
    }

    private func insertDateCaption(_ value: String) {
        guard hasUserEditedCaptionText || !isBasicDateCaptionText else {
            text = value
            textSelectionRange = NSRange(
                location: (value as NSString).length,
                length: 0
            )
            hasUserEditedCaptionText = false
            return
        }

        let source = text as NSString
        let location = min(textSelectionRange.location, source.length)
        let length = min(textSelectionRange.length, source.length - location)
        let insertionRange = NSRange(location: location, length: length)
        text = source.replacingCharacters(in: insertionRange, with: value)
        textSelectionRange = NSRange(
            location: location + (value as NSString).length,
            length: 0
        )
        hasUserEditedCaptionText = true
    }

    private var textInput: some View {
        ShadowedCaptionTextView(
            text: $text,
            selectedRange: $textSelectionRange,
            font: textEditorUIFont(size: textEditorBaseSize),
            textColor: Self.uiColor(textColorHex)
                ?? HanClipTheme.primaryUIColor,
            shadowColor: Self.uiColor(shadowColorHex)
                ?? HanClipTheme.secondaryUIColor,
            shadowOpacity: shadowOpacity,
            textAlignment: textEditorNSTextAlignment,
            lineSpacing: textEditorLineSpacing(size: textEditorBaseSize),
            onBeginEditing: clearSampleTextIfNeeded,
            onUserTextChange: {
                hasUserEditedCaptionText = true
            },
            onRequiredHeightChange: growTextInputIfNeeded
        )
            .padding(.horizontal, 14)
            .padding(.vertical, Self.textInputOuterVerticalPadding)
            .frame(height: textInputHeight, alignment: .top)
            .background(
                textInputBackgroundColor.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HanClipTheme.secondary.opacity(0.28), lineWidth: 1)
            }
    }

    private var fontSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            fontPresetRow

            fontPanelDisclosureButton

            if showAdvancedFontSettings {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(FontRegistry.availableFonts) { font in
                            captionFontButton(font)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if let fontImportNotice {
                        Text(fontImportNotice)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(HanClipTheme.text.opacity(0.62))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .textOverlaySectionStyle()
    }

    private var fontPanelDisclosureButton: some View {
        Button {
            withAnimation(.snappy) {
                showAdvancedFontSettings.toggle()
            }
        } label: {
            Image(
                systemName: showAdvancedFontSettings
                    ? "chevron.up"
                    : "chevron.down"
            )
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(HanClipTheme.secondaryText.opacity(0.72))
            .frame(width: 42, height: 22)
            .background(HanClipTheme.secondary.opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(HanClipTheme.secondary.opacity(0.14), lineWidth: 1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            showAdvancedFontSettings ? "폰트 패널 접기" : "폰트 패널 펼치기"
        )
    }

    private var fontPresetRow: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(fontPresetSpecs) { preset in
                fontPresetButton(preset)
            }
        }
    }

    private var fontPresetSpecs: [FontPresetSpec] {
        [
            FontPresetSpec(
                id: "readable",
                title: "가독성",
                preferredFontIDs: ["pretendard"],
                textColor: "#FFFFFF",
                shadowColor: "#000000",
                fontSize: .large
            ),
            FontPresetSpec(
                id: "lovely",
                title: "러블리",
                preferredFontIDs: ["ddulgi_mayo"],
                textColor: "#FF6FAE",
                shadowColor: "#7A3FFF",
                fontSize: .large
            ),
            FontPresetSpec(
                id: "strong_hya",
                title: "강력햐",
                preferredFontIDs: ["tenada"],
                textColor: "#FFE600",
                shadowColor: "#000000",
                fontSize: .extraLarge
            ),
            FontPresetSpec(
                id: "fresh",
                title: "청량",
                preferredFontIDs: ["gowun_dodum", "pretendard"],
                textColor: "#FFFFFF",
                shadowColor: "#18A8FF",
                fontSize: .large
            ),
            FontPresetSpec(
                id: "travel",
                title: "여행",
                preferredFontIDs: WatermarkSettings.travelPreferredFontIDs,
                textColor: WatermarkSettings.travelTextColor,
                shadowColor: WatermarkSettings.travelShadowColor,
                fontSize: WatermarkSettings.travelFontSize,
                shadowOpacity: WatermarkSettings.travelShadowOpacity
            ),
            FontPresetSpec(
                id: "cinema",
                title: "시네마",
                preferredFontIDs: ["black_han_sans", "tenada"],
                textColor: "#F8F3E7",
                shadowColor: "#141414",
                fontSize: .extraLarge
            ),
            FontPresetSpec(
                id: "daily",
                title: "데일리",
                preferredFontIDs: ["do_hyeon", "cafe24_ssurround"],
                textColor: "#FFFFFF",
                shadowColor: "#FF7A3D",
                fontSize: .large
            ),
            FontPresetSpec(
                id: "sentimental",
                title: "감성",
                preferredFontIDs: ["gowun_batang", "maruburi"],
                textColor: "#FFE9F0",
                shadowColor: "#6E5BFF",
                fontSize: .normal
            ),
            FontPresetSpec(
                id: "green_golf",
                title: "그린골프",
                preferredFontIDs: WatermarkSettings.greenGolfPreferredFontIDs,
                textColor: WatermarkSettings.greenGolfTextColor,
                shadowColor: WatermarkSettings.greenGolfShadowColor,
                fontSize: WatermarkSettings.greenGolfFontSize,
                shadowOpacity: WatermarkSettings.greenGolfShadowOpacity
            ),
            FontPresetSpec(
                id: "paperlogy_magazine",
                title: "매거진",
                preferredFontIDs: ["paperlogy_bold", "black_han_sans"],
                textColor: "#FFF4D6",
                shadowColor: "#D94A32",
                fontSize: .extraLarge,
                shadowOpacity: 0.55
            ),
            FontPresetSpec(
                id: "paperlogy_sports",
                title: "스포츠",
                preferredFontIDs: ["paperlogy_bold", "tenada"],
                textColor: "#D8FF3E",
                shadowColor: "#10223A",
                fontSize: .extraLarge,
                shadowOpacity: 0.7
            ),
            FontPresetSpec(
                id: "nexon_clean",
                title: "클린",
                preferredFontIDs: ["nexon_lv1_gothic", "pretendard"],
                textColor: "#FFFFFF",
                shadowColor: "#1B4D89",
                fontSize: .large,
                shadowOpacity: 0.35
            ),
            FontPresetSpec(
                id: "nexon_neon",
                title: "네온",
                preferredFontIDs: ["nexon_lv1_gothic", "pretendard_bold"],
                textColor: "#7DF9FF",
                shadowColor: "#6C2BFF",
                fontSize: .large,
                shadowOpacity: 0.8
            ),
            FontPresetSpec(
                id: "poppins_vlog",
                title: "VLOG",
                preferredFontIDs: ["poppins", "pretendard"],
                textColor: "#FFFFFF",
                shadowColor: "#FF6B5E",
                fontSize: .large,
                shadowOpacity: 0.55
            ),
            FontPresetSpec(
                id: "poppins_pop",
                title: "POP",
                preferredFontIDs: ["poppins", "pretendard_bold"],
                textColor: "#FFE45C",
                shadowColor: "#642BFF",
                fontSize: .extraLarge,
                shadowOpacity: 0.75
            )
        ]
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(WatermarkFontSize.allCases) { size in
                        fontSizeButton(size)
                    }
                }
                .padding(3)
                .background(
                    HanClipTheme.secondary.opacity(0.14),
                    in: Capsule()
                )

                appearanceDivider
                    .padding(.vertical, 8)

                HStack(spacing: 0) {
                    ForEach(WatermarkLineSpacing.displayOrder) { spacing in
                        lineSpacingButton(spacing)
                    }
                }
                .padding(3)
                .background(
                    HanClipTheme.secondary.opacity(0.14),
                    in: Capsule()
                )

                appearanceDivider
                    .padding(.vertical, 8)

                colorAndShadowControls
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Color.white.opacity(0.22),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .textOverlaySectionStyle()
    }

    private func fontPresetButton(
        _ preset: FontPresetSpec
    ) -> some View {
        let fontID = resolvedPresetFontID(preset.preferredFontIDs)
        let appearance = appearance(for: preset)
        return fontPresetButton(
            presetID: preset.id,
            title: preset.title,
            fontID: fontID,
            textColor: appearance.textColor,
            shadowColor: appearance.shadowColor,
            shadowOpacity: appearance.shadowOpacity,
            fontSize: appearance.fontSize,
            lineSpacing: appearance.lineSpacing,
            lineSpacingScale: appearance.lineSpacingScale
        )
    }

    private func fontPresetButton(
        presetID: String,
        title: String,
        fontID: String,
        textColor: String,
        shadowColor: String,
        shadowOpacity presetShadowOpacity: Double,
        fontSize: WatermarkFontSize,
        lineSpacing presetLineSpacing: WatermarkLineSpacing,
        lineSpacingScale presetLineSpacingScale: Double
    ) -> some View {
        let isSelected = isFontPresetSelected(
            fontID: fontID,
            textColor: textColor,
            shadowColor: shadowColor,
            shadowOpacity: presetShadowOpacity,
            fontSize: fontSize,
            lineSpacing: presetLineSpacing,
            lineSpacingScale: presetLineSpacingScale
        )
        let previewColor = Color(hexString: textColor) ?? .white
        let previewShadowColor = (Color(hexString: shadowColor) ?? .black)
            .opacity(presetShadowOpacity)

        return Button {
            if isSelected {
                refreshTextInputBackground()
            } else {
                applyFontPreset(
                    presetID: presetID,
                    fontID: fontID,
                    textColor: textColor,
                    shadowColor: shadowColor,
                    shadowOpacity: presetShadowOpacity,
                    fontSize: fontSize,
                    lineSpacing: presetLineSpacing,
                    lineSpacingScale: presetLineSpacingScale
                )
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected
                                ? HanClipTheme.primary
                                : HanClipTheme.secondary.opacity(0.52),
                            lineWidth: 2
                        )
                        .frame(width: 16, height: 16)

                    if isSelected {
                        Circle()
                            .fill(HanClipTheme.primary)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(title)
                    .font(
                        FontRegistry.resolvedSwiftUIFont(
                            for: fontID,
                            size: 12,
                            weight: .bold
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 4)

                Text("Aa")
                    .font(
                        FontRegistry.resolvedSwiftUIFont(
                            for: fontID,
                            size: 12,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(previewColor)
                    .textOverlayOutline(
                        color: previewShadowColor,
                        width: presetShadowOpacity > 0 ? 0.45 : 0
                    )
                    .shadow(
                        color: previewShadowColor,
                        radius: fontPresetPreviewShadowRadius(
                            for: presetShadowOpacity
                        ),
                        x: presetShadowOpacity > 0 ? 1 : 0,
                        y: presetShadowOpacity > 0 ? 1 : 0
                    )
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? .white : HanClipTheme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 34)
            .background(
                isSelected
                    ? HanClipTheme.secondary.opacity(0.14)
                    : Color.white.opacity(0.28),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) 서체")
    }

    private func fontSizeButton(_ size: WatermarkFontSize) -> some View {
        let isSelected = fontSize == size

        return Button {
            fontSize = size
        } label: {
            Text("\(size.title) \(size.pointSize)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? .white : HanClipTheme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(HanClipTheme.primary)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(size.title) \(size.pointSize)포인트")
    }

    private var colorAndShadowControls: some View {
        HStack(spacing: 10) {
            colorPickerRow(
                title: "글자색",
                selection: textColorBinding
            )

            Rectangle()
                .fill(HanClipTheme.secondary.opacity(0.16))
                .frame(width: 1, height: 28)

            colorPickerRow(
                title: "그림자색",
                selection: shadowColorBinding
            )
            .opacity(shadowOpacity > 0 ? 1 : 0.34)
            .disabled(shadowOpacity <= 0)

            shadowOpacityControl
        }
        .frame(minHeight: 42)
        .padding(.vertical, 2)
    }

    private var shadowOpacityControl: some View {
        Slider(
            value: Binding(
                get: { shadowOpacity },
                set: { value in
                    shadowOpacity =
                        WatermarkSettings.normalizedShadowOpacity(value)
                    shadowEnabled = shadowOpacity > 0
                }
            ),
            in: 0...1,
            step: 0.05
        )
        .tint(HanClipTheme.primary)
        .frame(width: 92)
        .accessibilityLabel("그림자 투명도")
        .accessibilityValue("\(Int((shadowOpacity * 100).rounded()))퍼센트")
    }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { Color(hexString: textColorHex) ?? HanClipTheme.primary },
            set: {
                textColorHex = $0.hexString
                    ?? WatermarkSettings.defaultTextColor
                shadowColorHex = Color(
                    uiColor: complementaryTextOverlayShadowColor(
                        for: UIColor($0)
                    )
                ).hexString
                    ?? WatermarkSettings.defaultShadowColor
            }
        )
    }

    private var shadowColorBinding: Binding<Color> {
        Binding(
            get: { Color(hexString: shadowColorHex) ?? .black },
            set: {
                shadowColorHex = $0.hexString
                    ?? WatermarkSettings.defaultShadowColor
            }
        )
    }

    private var appearanceDivider: some View {
        Rectangle()
            .fill(HanClipTheme.secondary.opacity(0.10))
            .frame(height: 1)
    }

    private func appearancePickerRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HanClipTheme.text.opacity(0.72))

            content()
        }
        .padding(.vertical, 4)
    }

    private func colorPickerRow(
        title: String,
        selection: Binding<Color>
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HanClipTheme.text.opacity(0.72))

            ColorPicker(
                title,
                selection: selection,
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 34, height: 34)
        }
        .frame(minHeight: 38)
    }

    private func fontMenuButton(_ font: String) -> some View {
        Button {
            fontName = FontRegistry.normalizedID(forStoredValue: font)
        } label: {
            Text(displayFontName(font))
                .font(FontRegistry.resolvedSwiftUIFont(for: font, size: 14))
        }
    }

    private func captionFontButton(_ font: CaptionFontInfo) -> some View {
        let isSelected = fontName == font.id

        return Button {
            fontName = font.id
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected
                                ? HanClipTheme.primary
                                : HanClipTheme.secondary.opacity(0.52),
                            lineWidth: 2
                        )
                        .frame(width: 16, height: 16)

                    if isSelected {
                        Circle()
                            .fill(HanClipTheme.primary)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(font.displayName)
                    .font(
                        FontRegistry.resolvedSwiftUIFont(
                            for: font.id,
                            size: 12,
                            weight: .bold
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(
                isSelected ? HanClipTheme.primary : HanClipTheme.secondary
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 34)
            .background(
                isSelected
                    ? HanClipTheme.secondary.opacity(0.14)
                    : Color.white.opacity(0.28),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(font.displayName)
    }

    private func defaultFontButton(
        title: String,
        choiceFontName: String
    ) -> some View {
        let normalizedID = FontRegistry.normalizedID(
            forStoredValue: choiceFontName
        )
        let isSelected = fontName == normalizedID

        return Button {
            fontName = normalizedID
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected
                                ? HanClipTheme.primary
                                : HanClipTheme.secondary.opacity(0.52),
                            lineWidth: 2
                        )
                        .frame(width: 16, height: 16)

                    if isSelected {
                        Circle()
                            .fill(HanClipTheme.primary)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(title)
                    .font(defaultFontPreview(normalizedID, size: 12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(
                isSelected ? HanClipTheme.primary : HanClipTheme.secondary
            )
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                isSelected
                    ? HanClipTheme.secondary.opacity(0.14)
                    : Color.white.opacity(0.28),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func lineSpacingButton(
        _ spacing: WatermarkLineSpacing
    ) -> some View {
        let isSelected = lineSpacing == spacing

        return Button {
            updateLineSpacing(spacing)
        } label: {
            Text(spacing.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isSelected ? .white : HanClipTheme.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(HanClipTheme.primary)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spacing.title)
    }

    private func updateLineSpacing(_ spacing: WatermarkLineSpacing) {
        lineSpacing = spacing

        switch spacing {
        case .normal:
            lineSpacingScale = WatermarkLineSpacing.defaultMultiplier
        case .tight:
            lineSpacingScale = WatermarkSettings.normalizedLineSpacingScale(
                lineSpacingScale - WatermarkLineSpacing.step
            )
        case .wide:
            lineSpacingScale = WatermarkSettings.normalizedLineSpacingScale(
                lineSpacingScale + WatermarkLineSpacing.step
            )
        }
    }

    private func isFontPresetSelected(
        fontID: String,
        textColor: String,
        shadowColor: String,
        shadowOpacity presetShadowOpacity: Double,
        fontSize: WatermarkFontSize,
        lineSpacing presetLineSpacing: WatermarkLineSpacing,
        lineSpacingScale presetLineSpacingScale: Double
    ) -> Bool {
        fontName == fontID
            && Self.normalizedHex(textColorHex) == Self.normalizedHex(textColor)
            && Self.normalizedHex(shadowColorHex)
                == Self.normalizedHex(shadowColor)
            && abs(shadowOpacity - presetShadowOpacity) < 0.001
            && lineSpacing == presetLineSpacing
            && abs(
                lineSpacingScale - presetLineSpacingScale
            ) < 0.001
            && self.fontSize == fontSize
    }

    private func isFontPresetBaseSelected(_ preset: FontPresetSpec) -> Bool {
        let fontID = resolvedPresetFontID(preset.preferredFontIDs)
        let appearance = appearance(for: preset)
        return fontName == fontID
            && Self.normalizedHex(textColorHex)
                == Self.normalizedHex(appearance.textColor)
            && Self.normalizedHex(shadowColorHex)
                == Self.normalizedHex(appearance.shadowColor)
            && lineSpacing == appearance.lineSpacing
            && abs(
                lineSpacingScale - appearance.lineSpacingScale
            ) < 0.001
            && abs(shadowOpacity - appearance.shadowOpacity) < 0.001
            && fontSize == appearance.fontSize
    }

    private var readableThemeFontID: String {
        allowedTextFontNames.contains("pretendard")
            ? "pretendard"
            : FontRegistry.systemFontID
    }

    private func resolvedPresetFontID(_ preferredIDs: [String]) -> String {
        preferredIDs.first { allowedTextFontNames.contains($0) }
            ?? readableThemeFontID
    }

    private func defaultAppearance(for preset: FontPresetSpec)
        -> FontPresetAppearance
    {
        FontPresetAppearance(
            textColor: preset.textColor,
            shadowColor: preset.shadowColor,
            shadowOpacity: preset.shadowOpacity,
            fontSize: preset.fontSize
        )
    }

    private func appearance(for preset: FontPresetSpec)
        -> FontPresetAppearance
    {
        fontPresetAppearances[preset.id] ?? defaultAppearance(for: preset)
    }

    private func rememberActiveFontPresetAppearance() {
        guard let presetID = activeFontPresetID else { return }
        guard let preset = fontPresetSpecs.first(where: { $0.id == presetID })
        else { return }
        guard fontName == resolvedPresetFontID(preset.preferredFontIDs)
        else { return }

        rememberFontPresetAppearance(currentFontPresetAppearance, for: presetID)
    }

    private var currentFontPresetAppearance: FontPresetAppearance {
        FontPresetAppearance(
            textColor: textColorHex,
            shadowColor: shadowColorHex,
            shadowOpacity: shadowOpacity,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            lineSpacingScale: lineSpacingScale
        )
    }

    private func rememberFontPresetAppearance(
        _ appearance: FontPresetAppearance,
        for presetID: String
    ) {
        if fontPresetAppearances[presetID] == appearance { return }
        fontPresetAppearances[presetID] = appearance
        Self.saveFontPresetAppearances(fontPresetAppearances)
    }

    private func resetFontPresetAppearances() {
        activeFontPresetID = nil
        fontPresetAppearances = [:]
        Self.clearFontPresetAppearances()
        showFontPresetResetNotice()
    }

    private func applyFontPreset(
        presetID: String,
        fontID: String,
        textColor: String,
        shadowColor: String,
        shadowOpacity presetShadowOpacity: Double,
        fontSize: WatermarkFontSize,
        lineSpacing presetLineSpacing: WatermarkLineSpacing,
        lineSpacingScale presetLineSpacingScale: Double
    ) {
        activeFontPresetID = presetID
        fontName = fontID
        textColorHex = Self.normalizedHex(textColor)
        shadowColorHex = Self.normalizedHex(shadowColor)
        lineSpacing = presetLineSpacing
        lineSpacingScale =
            WatermarkSettings.normalizedLineSpacingScale(presetLineSpacingScale)
        self.fontSize = fontSize
        shadowOpacity =
            WatermarkSettings.normalizedShadowOpacity(presetShadowOpacity)
        shadowEnabled = shadowOpacity > 0
        rememberFontPresetAppearance(currentFontPresetAppearance, for: presetID)
        refreshTextInputBackground()
    }

    private var positionSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 5
                ),
                spacing: 8
            ) {
                ForEach(WatermarkPosition.allCases) { position in
                    positionButton(position)
                }
            }
            .padding(10)
            .background(
                HanClipTheme.secondary.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }

    private func positionButton(_ position: WatermarkPosition) -> some View {
        let isSelected = self.position == position

        return Button {
            self.position = position
        } label: {
            ZStack {
                Circle()
                    .stroke(
                        isSelected
                            ? HanClipTheme.primary
                            : HanClipTheme.secondary.opacity(0.52),
                        lineWidth: 2
                    )
                    .frame(width: 16, height: 16)

                if isSelected {
                    Circle()
                        .fill(HanClipTheme.primary)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                isSelected
                    ? HanClipTheme.secondary.opacity(0.14)
                    : Color.white.opacity(0.28),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(position.title)
    }

    private func displayFontName(_ fontName: String) -> String {
        let info = FontRegistry.font(for: fontName)
        if info.id != FontRegistry.systemFontID {
            return info.displayName
        }
        guard let font = UIFont(name: fontName, size: 14) else {
            return fontName
        }

        let familyName = font.familyName
        let displayName = font.fontDescriptor
            .object(forKey: .visibleName) as? String
        let localizedName = CTFontCopyLocalizedName(
            CTFontCreateWithName(fontName as CFString, 14, nil),
            kCTFontFullNameKey,
            nil
        ) as String?

        return [
            localizedName,
            displayName,
            familyName,
            fontName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? fontName
    }

    private func selectedFontPreview(size: CGFloat) -> Font {
        FontRegistry.resolvedSwiftUIFont(for: fontName, size: size)
    }

    private func defaultFontPreview(
        _ choiceFontName: String,
        size: CGFloat
    ) -> Font {
        FontRegistry.resolvedSwiftUIFont(
            for: choiceFontName,
            size: size,
            weight: .bold
        )
    }

    private func textEditorFont(size: CGFloat) -> Font {
        FontRegistry.resolvedSwiftUIFont(
            for: fontName,
            size: size,
            weight: .medium
        )
    }

    private func textEditorUIFont(size: CGFloat) -> UIFont {
        FontRegistry.resolvedUIFont(
            for: fontName,
            size: size,
            weight: .bold
        )
    }

    private var textEditorAlignment: TextAlignment {
        switch position.gridColumn {
        case 0, 1:
            return .leading
        case 2:
            return .center
        default:
            return .trailing
        }
    }

    private var textEditorFrameAlignment: Alignment {
        switch position.gridColumn {
        case 0, 1:
            return .topLeading
        case 2:
            return .top
        default:
            return .topTrailing
        }
    }

    private var textEditorNSTextAlignment: NSTextAlignment {
        switch position.gridColumn {
        case 0, 1:
            return .left
        case 2:
            return .center
        default:
            return .right
        }
    }

    private var textEditorBaseSize: CGFloat {
        14 * CGFloat(fontSize.multiplier)
    }

    private var textInputMinimumHeight: CGFloat {
        max(112, textEditorBaseSize * 5.8) * 0.9
    }

    private var textInputHeight: CGFloat {
        max(textInputMinimumHeight, expandedTextInputHeight)
    }

    private func growTextInputIfNeeded(_ requiredTextViewHeight: CGFloat) {
        let requiredOuterHeight = ceil(
            requiredTextViewHeight + Self.textInputOuterVerticalPadding * 2
        )
        guard requiredOuterHeight > textInputHeight + 0.5 else { return }
        expandedTextInputHeight = requiredOuterHeight
    }

    private func textEditorLineSpacing(size: CGFloat) -> CGFloat {
        size * CGFloat(lineSpacingScale - WatermarkLineSpacing.defaultMultiplier)
    }

    private func fontPresetPreviewShadowRadius(for opacity: Double) -> CGFloat {
        guard opacity > 0 else { return 0 }
        return 2.4
    }

    private func refreshTextInputBackground() {
        textInputBackgroundHex = Self.randomTextInputBackgroundHex(
            excluding: [textColorHex, shadowColorHex],
            avoiding: textInputBackgroundHex
        )
    }

    private var textInputBackgroundColor: Color {
        Color(hexString: textInputBackgroundHex) ?? Color.white
    }

    nonisolated private static func randomTextInputBackgroundHex(
        excluding excludedHexes: [String] = [],
        avoiding avoidedHex: String? = nil
    ) -> String {
        let palette = [
            "#FFF7C7",
            "#DFF4FF",
            "#E4FFD8",
            "#FFE0EA",
            "#EFE3FF",
            "#E0FFF6",
            "#FFF0D6",
            "#F2F4FF"
        ]
        let excludedColors = excludedHexes.compactMap(uiColor)
        let candidates = palette.compactMap { hex -> (hex: String, score: CGFloat)? in
            guard let color = uiColor(hex) else { return nil }
            let score = excludedColors
                .map { contrastRatio(between: color, and: $0) }
                .min() ?? 1
            return (hex, score)
        }

        let alternatives = candidates
            .filter {
                guard let avoidedHex else { return true }
                return $0.hex.caseInsensitiveCompare(avoidedHex) != .orderedSame
            }
            .sorted { $0.score > $1.score }
        guard let bestScore = alternatives.first?.score else {
            return "#FFF7C7"
        }
        let highContrastCandidates = alternatives.filter {
            $0.score >= bestScore * 0.85
        }
        return highContrastCandidates.randomElement()?.hex
            ?? alternatives[0].hex
    }

    private static let textInputOuterVerticalPadding: CGFloat = 10

    nonisolated private static func uiColor(_ hexString: String) -> UIColor? {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6,
              let value = Int(hex, radix: 16)
        else { return nil }

        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    nonisolated private static func contrastRatio(
        between first: UIColor,
        and second: UIColor
    ) -> CGFloat {
        let firstLuminance = relativeLuminance(of: first)
        let secondLuminance = relativeLuminance(of: second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    nonisolated private static func relativeLuminance(of color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        else { return 1 }

        func convert(_ component: CGFloat) -> CGFloat {
            component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * convert(red)
            + 0.7152 * convert(green)
            + 0.0722 * convert(blue)
    }

    nonisolated private static func normalizedHex(_ hex: String) -> String {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("#")
            ? trimmed.uppercased()
            : "#\(trimmed.uppercased())"
    }

    nonisolated private static let fontPresetAppearanceStorageKey =
        "hanClipTextOverlayFontPresetAppearances"

    nonisolated private static func loadFontPresetAppearances()
        -> [String: FontPresetAppearance]
    {
        guard let data = UserDefaults.standard.data(
            forKey: fontPresetAppearanceStorageKey
        ) else { return [:] }

        return (try? JSONDecoder().decode(
            [String: FontPresetAppearance].self,
            from: data
        )) ?? [:]
    }

    nonisolated private static func saveFontPresetAppearances(
        _ values: [String: FontPresetAppearance]
    ) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: fontPresetAppearanceStorageKey)
    }

    nonisolated private static func clearFontPresetAppearances() {
        UserDefaults.standard.removeObject(forKey: fontPresetAppearanceStorageKey)
    }

    private var fontContentTypes: [UTType] {
        [
            UTType(filenameExtension: "ttf"),
            UTType(filenameExtension: "otf"),
            UTType(filenameExtension: "ttc")
        ]
        .compactMap { $0 }
    }

    private func handleFontFilePicker(
        _ result: Result<[URL], Error>
    ) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            let importedNames = try FontImportStore.importFonts(from: urls)
            guard let firstFont = importedNames.first else {
                fontImportNotice = "가져올 수 있는 서체 파일이 없습니다."
                return
            }

            fontName = FontRegistry.normalizedID(forStoredValue: firstFont)
            fontImportNotice = "\(importedNames.count)개 서체를 가져왔습니다."
        } catch {
            fontImportNotice = "서체를 가져올 수 없습니다."
        }
    }

    private func resetSettings() {
        activeFontPresetID = nil
        if let originalSessionState {
            applySessionState(originalSessionState)
        } else {
            let defaults = WatermarkSettings.projectDefault()
            textEnabled = defaults.isEnabled
            text = WatermarkSettings.defaultText
            position = defaults.position
            fontName = defaults.fontName
            textColorHex = defaults.textColorHex
            shadowEnabled = defaults.shadowEnabled
            shadowOpacity = defaults.shadowOpacity
            shadowColorHex = defaults.shadowColorHex
            lineSpacing = defaults.lineSpacing
            lineSpacingScale = defaults.lineSpacingScale
            fontSize = defaults.fontSize
        }
        refreshTextInputBackground()
    }

    private func showFontPresetResetNotice() {
        let notice = "자막 프리셋을 초기화했습니다."
        withAnimation(.snappy) {
            fontPresetResetNotice = notice
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard fontPresetResetNotice == notice else { return }
            withAnimation(.snappy) {
                fontPresetResetNotice = nil
            }
        }
    }

    private func clearSampleTextIfNeeded() {
        guard text == WatermarkSettings.legacyDefaultText else { return }
        text = ""
    }

    private func applyDefaultSettingsIfNeeded() {
        guard [
            WatermarkSettings.defaultText,
            WatermarkSettings.legacyDefaultText
        ].contains(text),
              position == WatermarkSettings.defaultPosition,
              textColorHex == WatermarkSettings.defaultTextColor,
              abs(
                shadowOpacity - WatermarkSettings.defaultShadowOpacity
              ) < 0.001,
              shadowColorHex == WatermarkSettings.defaultShadowColor
        else { return }

        resetSettings()
    }

    private func beginEditingSessionIfNeeded() {
        guard originalSessionState == nil else { return }
        originalSessionState = currentSessionState()
    }

    private func discardChangesAndDismiss() {
        if let originalSessionState {
            applySessionState(originalSessionState)
        }
        dismiss()
    }

    private func applySessionState(_ state: SessionState) {
        textEnabled = state.isEnabled
        text = state.text
        position = state.position
        fontName = state.fontName
        textColorHex = state.textColorHex
        shadowEnabled = state.shadowEnabled
        shadowOpacity = state.shadowOpacity
        shadowColorHex = state.shadowColorHex
        lineSpacing = state.lineSpacing
        lineSpacingScale = state.lineSpacingScale
        fontSize = state.fontSize
        includesEndingInfoCard = state.includesEndingInfoCard
        endingInfoCardDuration = state.endingInfoCardDuration
        endingInfoCardTheme = state.endingInfoCardTheme
        endingInfoCardVariation = state.endingInfoCardVariation
    }

    private var hasSessionChanges: Bool {
        guard let originalSessionState else { return false }
        return currentSessionState() != originalSessionState
    }

    private func currentSessionState() -> SessionState {
        SessionState(
            isEnabled: textEnabled,
            text: text,
            position: position,
            fontName: fontName,
            textColorHex: Self.normalizedHex(textColorHex),
            shadowEnabled: shadowEnabled,
            shadowOpacity: WatermarkSettings.normalizedShadowOpacity(
                shadowOpacity
            ),
            shadowColorHex: Self.normalizedHex(shadowColorHex),
            lineSpacing: lineSpacing,
            lineSpacingScale: lineSpacingScale,
            fontSize: fontSize,
            includesEndingInfoCard: includesEndingInfoCard,
            endingInfoCardDuration: endingInfoCardDuration,
            endingInfoCardTheme: endingInfoCardTheme,
            endingInfoCardVariation: endingInfoCardVariation
        )
    }

    private func settingsToolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(HanClipTheme.primary)
            .frame(width: 40, height: 44)
    }

    private var settingsToolbarSaveIcon: some View {
        FloppyDiskIcon()
            .foregroundStyle(HanClipTheme.primary)
            .frame(width: 23, height: 23)
            .frame(width: 40, height: 44)
    }

    private func complementaryTextOverlayShadowColor(
        for color: UIColor
    ) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        else { return HanClipTheme.secondaryUIColor }

        return UIColor(
            red: 1 - red,
            green: 1 - green,
            blue: 1 - blue,
            alpha: 1
        )
    }

    private func normalizeSelectedFont() {
        let normalizedID = FontRegistry.normalizedID(forStoredValue: fontName)
        if allowedTextFontNames.contains(normalizedID) {
            fontName = normalizedID
        } else {
            fontName = FontRegistry.systemFontID
        }
    }
}

private struct InstalledFontPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var fontName: String

    func makeUIViewController(
        context: Context
    ) -> UIFontPickerViewController {
        let configuration = UIFontPickerViewController.Configuration()
        configuration.includeFaces = true

        let picker = UIFontPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIFontPickerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        private var parent: InstalledFontPicker

        init(parent: InstalledFontPicker) {
            self.parent = parent
        }

        func fontPickerViewControllerDidPickFont(
            _ viewController: UIFontPickerViewController
        ) {
            guard let descriptor = viewController.selectedFontDescriptor
            else {
                parent.dismiss()
                return
            }

            let pickedName = descriptor.fontAttributes[.name] as? String
                ?? UIFont(descriptor: descriptor, size: 14).fontName
            parent.fontName = FontRegistry.normalizedID(
                forStoredValue: pickedName
            )
            parent.dismiss()
        }

        func fontPickerViewControllerDidCancel(
            _ viewController: UIFontPickerViewController
        ) {
            parent.dismiss()
        }
    }
}

private struct InfoRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let imageName: String?
    let isCentered: Bool

    var body: some View {
        VStack(
            alignment: isCentered ? .center : .leading,
            spacing: 6
        ) {
            HStack(spacing: 7) {
                if let imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 17, height: 17)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HanClipTheme.primary)
                .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
                .textSelection(.enabled)

            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(HanClipTheme.text.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
                .multilineTextAlignment(isCentered ? .center : .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
        .background(
            HanClipTheme.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HanClipTheme.secondary.opacity(0.12), lineWidth: 1)
        }
    }
}

private extension View {
    @ViewBuilder
    func textOverlayOutline(color: Color, width: CGFloat) -> some View {
        if width > 0 {
            self
                .shadow(color: color, radius: 0, x: -width, y: -width)
                .shadow(color: color, radius: 0, x: 0, y: -width)
                .shadow(color: color, radius: 0, x: width, y: -width)
                .shadow(color: color, radius: 0, x: -width, y: 0)
                .shadow(color: color, radius: 0, x: width, y: 0)
                .shadow(color: color, radius: 0, x: -width, y: width)
                .shadow(color: color, radius: 0, x: 0, y: width)
                .shadow(color: color, radius: 0, x: width, y: width)
        } else {
            self
        }
    }
}

private struct GrowingCollectionTitleTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let maximumHeight: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont(
            name: "Cafe24Ssurround",
            size: 19
        ) ?? .systemFont(ofSize: 19, weight: .semibold)
        textView.textColor = HanClipTheme.primaryUIColor
        textView.textContainerInset = UIEdgeInsets(
            top: 10,
            left: 0,
            bottom: 10,
            right: 0
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .yes
        textView.returnKeyType = .default
        textView.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        DispatchQueue.main.async {
            textView.becomeFirstResponder()
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            textView.text = text
        }
        context.coordinator.reportHeight(for: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingCollectionTitleTextView

        init(parent: GrowingCollectionTitleTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            reportHeight(for: textView)
        }

        func reportHeight(for textView: UITextView) {
            guard textView.bounds.width > 0 else { return }
            let required = textView.sizeThatFits(
                CGSize(
                    width: textView.bounds.width,
                    height: .greatestFiniteMagnitude
                )
            ).height
            let clamped = min(max(56, required), parent.maximumHeight)
            textView.isScrollEnabled = required > parent.maximumHeight
            guard abs(parent.measuredHeight - clamped) > 0.5 else { return }
            DispatchQueue.main.async {
                self.parent.measuredHeight = clamped
            }
        }
    }
}

private struct ShadowedCaptionTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let font: UIFont
    let textColor: UIColor
    let shadowColor: UIColor
    let shadowOpacity: Double
    let textAlignment: NSTextAlignment
    let lineSpacing: CGFloat
    let onBeginEditing: () -> Void
    let onUserTextChange: () -> Void
    let onRequiredHeightChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.clipsToBounds = false
        textView.layer.masksToBounds = false
        textView.isScrollEnabled = false
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.textContainerInset = UIEdgeInsets(
            top: 6,
            left: 0,
            bottom: 6,
            right: 0
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        applyAttributes(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isApplyingUpdate = true
        applyAttributes(to: textView)
        context.coordinator.isApplyingUpdate = false
        DispatchQueue.main.async {
            [weak textView, weak coordinator = context.coordinator] in
            guard let textView, let coordinator else { return }
            coordinator.reportRequiredHeight(for: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func applyAttributes(to textView: UITextView) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        paragraphStyle.lineSpacing = lineSpacing

        let shadow = NSShadow()
        let opacity = WatermarkSettings.normalizedShadowOpacity(shadowOpacity)
        shadow.shadowColor = shadowColor.withAlphaComponent(opacity)
        shadow.shadowBlurRadius = opacity > 0 ? 2.4 : 0
        shadow.shadowOffset = .zero

        textView.clipsToBounds = false
        textView.layer.masksToBounds = false
        textView.layer.shadowColor = shadowColor.cgColor
        textView.layer.shadowOpacity = Float(opacity)
        textView.layer.shadowRadius = opacity > 0 ? 2.4 : 0
        textView.layer.shadowOffset = .zero

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]
        textView.typingAttributes = attributes

        if textView.text != text || textView.attributedText.length == 0 {
            textView.attributedText = NSAttributedString(
                string: text,
                attributes: attributes
            )
        } else {
            textView.textStorage.setAttributes(
                attributes,
                range: NSRange(location: 0, length: textView.textStorage.length)
            )
        }

        textView.textAlignment = textAlignment
        let textLength = (textView.text as NSString).length
        let clampedLocation = min(selectedRange.location, textLength)
        textView.selectedRange = NSRange(
            location: clampedLocation,
            length: min(selectedRange.length, textLength - clampedLocation)
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ShadowedCaptionTextView
        var isApplyingUpdate = false

        init(parent: ShadowedCaptionTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onBeginEditing()
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.selectedRange = textView.selectedRange
            parent.onUserTextChange()
            reportRequiredHeight(for: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingUpdate else { return }
            parent.selectedRange = textView.selectedRange
        }

        func reportRequiredHeight(for textView: UITextView) {
            let availableWidth = textView.bounds.width
            guard availableWidth > 0 else { return }

            let fittingSize = CGSize(
                width: availableWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
            let requiredHeight = textView.sizeThatFits(fittingSize).height
            parent.onRequiredHeightChange(requiredHeight)
        }
    }
}

private struct EmbeddedFontCopyrightRow: View {
    let title: String
    let detail: String
    let systemImage: String

    private let tableMarker = "[[embedded_font_size_table]]"

    private let rows: [EmbeddedFontSizeRow] = [
        EmbeddedFontSizeRow(
            fontName: "고운바탕",
            fileSize: "8.0 MB",
            fontFamily: "GowunBatang-Regular"
        ),
        EmbeddedFontSizeRow(
            fontName: "마루부리",
            fileSize: "7.6 MB",
            fontFamily: "MaruBuri-Regular"
        ),
        EmbeddedFontSizeRow(
            fontName: "고운돋움",
            fileSize: "6.9 MB",
            fontFamily: "GowunDodum-Regular"
        ),
        EmbeddedFontSizeRow(
            fontName: "써라운드",
            fileSize: "3.7 MB",
            fontFamily: "Cafe24Ssurround"
        ),
        EmbeddedFontSizeRow(
            fontName: "프리텐다드B",
            fileSize: "2.5 MB",
            fontFamily: "Pretendard-Bold"
        ),
        EmbeddedFontSizeRow(
            fontName: "넥슨 Lv.1 고딕",
            fileSize: "1.8 MB",
            fontFamily: "NEXONLv1GothicRegular"
        ),
        EmbeddedFontSizeRow(
            fontName: "나눔고딕",
            fileSize: "2.0 MB",
            fontFamily: "NanumGothic"
        ),
        EmbeddedFontSizeRow(
            fontName: "프리텐다드 Regular",
            fileSize: "1.5 MB",
            fontFamily: "Pretendard-Regular"
        ),
        EmbeddedFontSizeRow(
            fontName: "카카오",
            fileSize: "1.5 MB",
            fontFamily: "KakaoBigSans-Regular"
        ),
        EmbeddedFontSizeRow(
            fontName: "페이퍼로지 Bold",
            fileSize: "1.2 MB",
            fontFamily: "Paperlogy-7Bold"
        ),
        EmbeddedFontSizeRow(
            fontName: "젠틀고딕",
            fileSize: "1.1 MB",
            fontFamily: "PuradakGentleGothicR"
        ),
        EmbeddedFontSizeRow(
            fontName: "검은고딕",
            fileSize: "975 KB",
            fontFamily: "BlackHanSans-Regular"
        ),
        EmbeddedFontSizeRow(
            fontName: "태나다",
            fileSize: "973 KB",
            fontFamily: "Tenada"
        ),
        EmbeddedFontSizeRow(
            fontName: "도현",
            fileSize: "859 KB",
            fontFamily: "DoHyeon-Regular"
        ),
        EmbeddedFontSizeRow(
            fontName: "둘기마요",
            fileSize: "743 KB",
            fontFamily: "Dovemayo-Medium"
        ),
        EmbeddedFontSizeRow(
            fontName: "Poppins",
            fileSize: "157 KB",
            fontFamily: "Poppins-Regular"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HanClipTheme.primary)
                .textSelection(.enabled)

            ForEach(detailParts.indices, id: \.self) { index in
                if !detailParts[index].isEmpty {
                    detailText(detailParts[index])
                }

                if index == 0 {
                    embeddedFontSizeTable
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            HanClipTheme.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HanClipTheme.secondary.opacity(0.12), lineWidth: 1)
        }
        .onAppear {
            _ = FontRegistry.registerBundledCaptionFonts()
        }
    }

    private var detailParts: [String] {
        let parts = detail.components(separatedBy: tableMarker)
        guard parts.count == 2 else { return [detail] }
        return parts.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(HanClipTheme.text.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var embeddedFontSizeTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
            GridRow {
                tableHeader("서체명")
                tableHeader("파일크기")
                tableHeader("샘플")
            }

            ForEach(rows) { row in
                Divider()
                    .gridCellColumns(3)
                    .padding(.vertical, 4)

                GridRow {
                    tableCell(row.fontName)

                    Text(row.fileSize)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HanClipTheme.text.opacity(0.72))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text("안녕하세요")
                        .font(.custom(row.fontFamily, size: 15))
                        .foregroundStyle(HanClipTheme.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.38),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(HanClipTheme.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private func tableHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(HanClipTheme.text.opacity(0.58))
            .lineLimit(1)
    }

    private func tableCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(HanClipTheme.text.opacity(0.78))
            .lineLimit(1)
            .minimumScaleFactor(0.76)
    }
}

private struct EmbeddedFontSizeRow: Identifiable {
    let fontName: String
    let fileSize: String
    let fontFamily: String

    var id: String { fontFamily }
}

private struct ThemeOrderDropDelegate: DropDelegate {
    let targetMode: HanClipThemeMode
    @Binding var draggedMode: HanClipThemeMode?
    @Binding var customThemeOrderRaw: String
    let currentOrder: [HanClipThemeMode]

    func dropEntered(info: DropInfo) {
        guard let draggedMode,
              draggedMode != targetMode,
              HanClipThemeMode.customModes.contains(draggedMode),
              HanClipThemeMode.customModes.contains(targetMode),
              let fromIndex = currentOrder.firstIndex(of: draggedMode),
              let toIndex = currentOrder.firstIndex(of: targetMode)
        else { return }

        var updatedOrder = currentOrder
        withAnimation(.snappy) {
            updatedOrder.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
            customThemeOrderRaw = updatedOrder
                .map(\.rawValue)
                .joined(separator: ",")
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedMode = nil
        return true
    }
}

private struct EndingInfoSettingsSheet: View {
    private struct CaptionPreset: Identifiable {
        let id: String
        let title: String
        let preferredFontIDs: [String]
        let textColor: String
        let shadowColor: String
        let fontSize: WatermarkFontSize
        let shadowOpacity: Double
    }

    @Environment(\.dismiss) private var dismiss
    @Binding var isEnabled: Bool
    @Binding var duration: Double
    @Binding var theme: EndingInfoCardTheme
    @Binding var variation: Int
    @Binding var fontName: String
    @Binding var textColorHex: String
    @Binding var shadowEnabled: Bool
    @Binding var shadowOpacity: Double
    @Binding var shadowColorHex: String
    @Binding var fontSize: WatermarkFontSize
    @Binding var lineSpacing: WatermarkLineSpacing
    @Binding var lineSpacingScale: Double
    let loadPreview: () async -> EndingInfoPreviewData?
    let renderPreview: (
        EndingInfoPreviewData,
        EndingInfoCardTheme
    ) -> UIImage

    @State private var previewData: EndingInfoPreviewData?
    @State private var previewImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HanClipTitleLine(
                        "엔딩",
                        systemImage: "map.fill",
                        leadingInset: 0,
                        trailingInset: 0
                    )

                    WatermarkModeSegmentedControl(isEnabled: $isEnabled)

                    themePicker
                    durationControl

                    previewPanel

                    if theme == .caption {
                        captionPresetGrid
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(HanClipTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(HanClipTheme.primary)
                    }
                    .accessibilityLabel("닫기")
                }
            }
        }
        .task {
            previewData = await loadPreview() ?? samplePreviewData
            refreshPreviewImage()
        }
        .onChange(of: theme) { _, newTheme in
            if newTheme == .treasureMap {
                variation += 1
            }
            refreshPreviewImage()
        }
        .onChange(of: variation) { _, _ in
            refreshPreviewImage()
        }
        .onChange(of: fontName) { _, _ in refreshPreviewImage() }
        .onChange(of: textColorHex) { _, _ in refreshPreviewImage() }
        .onChange(of: shadowOpacity) { _, _ in refreshPreviewImage() }
        .onChange(of: shadowColorHex) { _, _ in refreshPreviewImage() }
        .onChange(of: fontSize) { _, _ in refreshPreviewImage() }
        .onChange(of: lineSpacing) { _, _ in refreshPreviewImage() }
        .onChange(of: lineSpacingScale) { _, _ in refreshPreviewImage() }
    }

    private var themePicker: some View {
        HStack(spacing: 5) {
            ForEach(EndingInfoCardTheme.allCases) { candidate in
                Button {
                    if candidate == .treasureMap,
                       theme == .treasureMap {
                        variation += 1
                    } else {
                        theme = candidate
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: candidate.systemImage)
                            .font(.system(size: 10, weight: .bold))
                        Text(candidate.title)
                            .font(.system(size: 8.5, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(
                        theme == candidate
                            ? HanClipTheme.primary
                            : HanClipTheme.secondaryText
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        theme == candidate
                            ? HanClipTheme.primary.opacity(0.14)
                            : HanClipTheme.panelFill,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(
                                theme == candidate
                                    ? HanClipTheme.primary.opacity(0.42)
                                    : HanClipTheme.panelStroke.opacity(0.62),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var durationControl: some View {
        HStack(spacing: 0) {
            Button {
                duration = WatermarkSettings.normalizedEndingInfoCardDuration(
                    duration - 0.5
                )
            } label: {
                Image(systemName: "minus")
                    .frame(width: 52, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(duration <= 1)

            Text(String(format: "%.1f초", duration))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)

            Button {
                duration = WatermarkSettings.normalizedEndingInfoCardDuration(
                    duration + 0.5
                )
            } label: {
                Image(systemName: "plus")
                    .frame(width: 52, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(duration >= 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(HanClipTheme.primary)
        .frame(height: 44)
        .background(HanClipTheme.secondary.opacity(0.09), in: Capsule())
        .overlay {
            Capsule().stroke(
                HanClipTheme.secondary.opacity(0.20),
                lineWidth: 1
            )
        }
    }

    @ViewBuilder
    private var previewPanel: some View {
        if let previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            HanClipTheme.primary.opacity(0.34),
                            lineWidth: 1
                        )
                }
                .accessibilityLabel("\(theme.title) 엔딩 카드 미리보기")
        } else {
            ProgressView("정보를 확인하는 중…")
                .font(.system(size: 11, weight: .medium))
                .tint(HanClipTheme.primary)
                .frame(maxWidth: .infinity, minHeight: 130)
        }
    }

    private var samplePreviewData: EndingInfoPreviewData {
        EndingInfoPreviewData(
            dateText: "2026. 8. 7. – 2026. 8. 9.",
            stops: [
                EndingInfoRouteStop(
                    countryCode: "KR",
                    label: "서울",
                    dateText: "8. 7."
                ),
                EndingInfoRouteStop(
                    countryCode: "KR",
                    label: "덕양구",
                    dateText: "8. 8."
                ),
                EndingInfoRouteStop(
                    countryCode: "PH",
                    label: "Philippines Clark",
                    dateText: "8. 9."
                )
            ]
        )
    }

    private var captionPresetGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(captionPresets) { preset in
                captionPresetButton(preset)
            }
        }
        .padding(10)
        .background(
            HanClipTheme.panelFill,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HanClipTheme.panelStroke.opacity(0.62), lineWidth: 1)
        }
    }

    private var captionPresets: [CaptionPreset] {
        [
            CaptionPreset(id: "readable", title: "가독성", preferredFontIDs: ["pretendard"], textColor: "#FFFFFF", shadowColor: "#000000", fontSize: .large, shadowOpacity: 0.5),
            CaptionPreset(id: "lovely", title: "러블리", preferredFontIDs: ["ddulgi_mayo"], textColor: "#FF6FAE", shadowColor: "#7A3FFF", fontSize: .large, shadowOpacity: 0.5),
            CaptionPreset(id: "strong_hya", title: "강력햐", preferredFontIDs: ["tenada"], textColor: "#FFE600", shadowColor: "#000000", fontSize: .extraLarge, shadowOpacity: 0.5),
            CaptionPreset(id: "fresh", title: "청량", preferredFontIDs: ["gowun_dodum", "pretendard"], textColor: "#FFFFFF", shadowColor: "#18A8FF", fontSize: .large, shadowOpacity: 0.5),
            CaptionPreset(id: "travel", title: "여행", preferredFontIDs: WatermarkSettings.travelPreferredFontIDs, textColor: WatermarkSettings.travelTextColor, shadowColor: WatermarkSettings.travelShadowColor, fontSize: WatermarkSettings.travelFontSize, shadowOpacity: WatermarkSettings.travelShadowOpacity),
            CaptionPreset(id: "cinema", title: "시네마", preferredFontIDs: ["black_han_sans", "tenada"], textColor: "#F8F3E7", shadowColor: "#141414", fontSize: .extraLarge, shadowOpacity: 0.5),
            CaptionPreset(id: "daily", title: "데일리", preferredFontIDs: ["do_hyeon", "cafe24_ssurround"], textColor: "#FFFFFF", shadowColor: "#FF7A3D", fontSize: .large, shadowOpacity: 0.5),
            CaptionPreset(id: "sentimental", title: "감성", preferredFontIDs: ["gowun_batang", "maruburi"], textColor: "#FFE9F0", shadowColor: "#6E5BFF", fontSize: .normal, shadowOpacity: 0.5),
            CaptionPreset(id: "green_golf", title: "그린골프", preferredFontIDs: WatermarkSettings.greenGolfPreferredFontIDs, textColor: WatermarkSettings.greenGolfTextColor, shadowColor: WatermarkSettings.greenGolfShadowColor, fontSize: WatermarkSettings.greenGolfFontSize, shadowOpacity: WatermarkSettings.greenGolfShadowOpacity),
            CaptionPreset(id: "paperlogy_magazine", title: "매거진", preferredFontIDs: ["paperlogy_bold", "black_han_sans"], textColor: "#FFF4D6", shadowColor: "#D94A32", fontSize: .extraLarge, shadowOpacity: 0.55),
            CaptionPreset(id: "paperlogy_sports", title: "스포츠", preferredFontIDs: ["paperlogy_bold", "tenada"], textColor: "#D8FF3E", shadowColor: "#10223A", fontSize: .extraLarge, shadowOpacity: 0.7),
            CaptionPreset(id: "nexon_clean", title: "클린", preferredFontIDs: ["nexon_lv1_gothic", "pretendard"], textColor: "#FFFFFF", shadowColor: "#1B4D89", fontSize: .large, shadowOpacity: 0.35),
            CaptionPreset(id: "nexon_neon", title: "네온", preferredFontIDs: ["nexon_lv1_gothic", "pretendard_bold"], textColor: "#7DF9FF", shadowColor: "#6C2BFF", fontSize: .large, shadowOpacity: 0.8),
            CaptionPreset(id: "poppins_vlog", title: "VLOG", preferredFontIDs: ["poppins", "pretendard"], textColor: "#FFFFFF", shadowColor: "#FF6B5E", fontSize: .large, shadowOpacity: 0.55),
            CaptionPreset(id: "poppins_pop", title: "POP", preferredFontIDs: ["poppins", "pretendard_bold"], textColor: "#FFE45C", shadowColor: "#642BFF", fontSize: .extraLarge, shadowOpacity: 0.75)
        ]
    }

    private func captionPresetButton(_ preset: CaptionPreset) -> some View {
        let resolvedFontID = preset.preferredFontIDs.first {
            availableFontIDs.contains($0)
        } ?? FontRegistry.systemFontID
        let isSelected = fontName == resolvedFontID
            && textColorHex.uppercased() == preset.textColor.uppercased()
            && shadowColorHex.uppercased() == preset.shadowColor.uppercased()
            && abs(shadowOpacity - preset.shadowOpacity) < 0.001
            && fontSize == preset.fontSize

        return Button {
            fontName = resolvedFontID
            textColorHex = preset.textColor
            shadowColorHex = preset.shadowColor
            shadowOpacity = WatermarkSettings.normalizedShadowOpacity(
                preset.shadowOpacity
            )
            shadowEnabled = shadowOpacity > 0
            fontSize = preset.fontSize
            lineSpacing = .normal
            lineSpacingScale = WatermarkLineSpacing.defaultMultiplier
            refreshPreviewImage()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 12, weight: .bold))
                Text(preset.title)
                    .font(
                        FontRegistry.resolvedSwiftUIFont(
                            for: resolvedFontID,
                            size: 11,
                            weight: .bold
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 0)
                Text("Aa")
                    .font(
                        FontRegistry.resolvedSwiftUIFont(
                            for: resolvedFontID,
                            size: 11,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(Color(hexString: preset.textColor) ?? .white)
            }
            .foregroundStyle(
                isSelected ? HanClipTheme.primary : HanClipTheme.secondaryText
            )
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                isSelected
                    ? HanClipTheme.primary.opacity(0.14)
                    : Color.white.opacity(0.22),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.title) 위치 자막 프리셋")
    }

    private var availableFontIDs: Set<String> {
        Set(FontRegistry.availableFonts.map(\.id))
    }

    private func refreshPreviewImage() {
        guard let previewData else {
            previewImage = nil
            return
        }
        previewImage = renderPreview(previewData, theme)
    }
}

private struct TextOverlaySummaryRow: View {
    let settings: WatermarkSettings
    @Binding var isEnabled: Bool
    let onSelect: () -> Void

    private var textPreview: String {
        let text = settings.displayText
        return text.isEmpty ? "자막 내용 없음" : text
    }

    private var detailText: String {
        [
            settings.fontSize.title,
            settings.position.title,
            "그림자 \(Int((settings.shadowOpacity * 100).rounded()))"
        ].joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("T")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(
                    settings.shouldRenderText
                        ? HanClipTheme.primary.opacity(0.86)
                        : HanClipTheme.text.opacity(0.38)
                )
                .frame(width: 24, alignment: .center)

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("자막")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(HanClipTheme.secondaryText.opacity(0.82))
                            .lineLimit(1)

                        Text(textPreview)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(HanClipTheme.primaryText.opacity(0.74))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Text(detailText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HanClipTheme.text.opacity(0.48))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 48, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            InlineStatusSegmentedControl(
                isOn: $isEnabled,
                isEnabled: true
            )
        }
        .frame(height: 48)
        .contentShape(Rectangle())
        .accessibilityLabel("자막")
        .accessibilityHint("자막 편집 화면을 엽니다.")
    }
}

private struct EndingInfoSummaryRow: View {
    @Binding var isEnabled: Bool
    @Binding var duration: Double
    let theme: EndingInfoCardTheme
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            HanClipTheme.secondaryText.opacity(0.78)
                        )
                        .frame(width: 24, alignment: .center)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("엔딩 :")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(
                                HanClipTheme.secondaryText.opacity(0.82)
                            )
                            .lineLimit(1)

                        Text(theme.title)
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(
                                HanClipTheme.secondaryText.opacity(0.82)
                            )
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(width: 84, alignment: .leading)
                .frame(height: 44, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            endingInfoDurationStepper

            Spacer(minLength: 4)

            InlineStatusSegmentedControl(
                isOn: $isEnabled,
                isEnabled: true
            )
        }
        .frame(height: 48)
        .contentShape(Rectangle())
        .accessibilityLabel("엔딩, \(theme.title) 테마")
        .accessibilityHint("엔딩 카드 설정 화면을 엽니다.")
        .accessibilityElement(children: .contain)
    }

    private var endingInfoDurationStepper: some View {
        HStack(spacing: 0) {
            Button {
                duration = WatermarkSettings.normalizedEndingInfoCardDuration(
                    duration - 0.5
                )
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(duration <= 1)
            .accessibilityLabel("엔딩 표시 시간 줄이기")

            Text(String(format: "%.1f초", duration))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .frame(width: 38)

            Button {
                duration = WatermarkSettings.normalizedEndingInfoCardDuration(
                    duration + 0.5
                )
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(duration >= 10)
            .accessibilityLabel("엔딩 표시 시간 늘리기")
        }
        .buttonStyle(.plain)
        .foregroundStyle(HanClipTheme.secondaryText)
        .frame(width: 118, height: 44)
        .background {
            Capsule()
                .fill(HanClipTheme.secondary.opacity(0.09))
                .frame(height: 24)
        }
        .overlay {
            Capsule()
                .stroke(
                    HanClipTheme.secondary.opacity(0.20),
                    lineWidth: 1
                )
                .frame(height: 24)
        }
    }
}

private struct BackgroundMusicSummaryRow: View {
    let settings: BackgroundMusicSettings
    @Binding var isEnabled: Bool
    let onSelect: () -> Void

    private var musicTitle: String {
        settings.hasMusicFile ? settings.displayTitle : "음악 파일 선택"
    }

    private var detailText: String {
        guard settings.hasMusicFile else {
            return "샘플 음악 또는 파일을 선택하세요"
        }

        return [
            "음악 \(Self.percentText(settings.musicVolume))",
            "원본 \(Self.percentText(settings.originalAudioVolume))",
            settings.loopsToFillVideo ? "반복" : "반복 안함",
            settings.fadeInEnabled || settings.fadeOutEnabled
                ? "페이드"
                : "페이드 안함"
        ].joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(
                    settings.shouldRender
                        ? HanClipTheme.primary.opacity(0.86)
                        : HanClipTheme.text.opacity(0.38)
                )
                .frame(width: 24, alignment: .center)

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("음악")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(HanClipTheme.secondaryText.opacity(0.82))
                            .lineLimit(1)

                        Text(musicTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(HanClipTheme.primaryText.opacity(0.74))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Text(detailText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HanClipTheme.text.opacity(0.48))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 48, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            InlineStatusSegmentedControl(
                isOn: $isEnabled,
                isEnabled: settings.hasMusicFile
            )
        }
        .frame(height: 48)
        .contentShape(Rectangle())
        .accessibilityLabel("음악")
        .accessibilityHint("음악 설정 화면을 엽니다.")
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }
}

private struct InlineStatusSegmentedControl: View {
    @Binding var isOn: Bool
    let isEnabled: Bool

    private var effectiveIsOn: Bool {
        isEnabled && isOn
    }

    var body: some View {
        HStack(spacing: 0) {
            segment(title: "사용", selected: effectiveIsOn)
            segment(title: "안함", selected: !effectiveIsOn)
        }
        .padding(2)
        .frame(width: 112, height: 28)
        .background(HanClipTheme.secondary.opacity(0.13), in: Capsule())
        .overlay {
            Button {
                guard isEnabled else { return }
                withAnimation(.snappy) {
                    isOn.toggle()
                }
            } label: {
                Color.clear
                    .frame(width: 94, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(effectiveIsOn ? "사용" : "안함")
            .accessibilityHint("어디를 눌러도 사용 상태가 전환됩니다.")
        }
        .opacity(isEnabled ? 1 : 0.48)
    }

    private func segment(title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(
                selected ? .white : HanClipTheme.secondaryText.opacity(0.78)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if selected {
                    Capsule()
                        .fill(HanClipTheme.primary.opacity(0.92))
                }
            }
            .allowsHitTesting(false)
    }
}

private struct VideoRangeSegmentedControl: View {
    @Binding var usesFullVideo: Bool
    let tint: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                segment(title: "선택구간", isFullVideo: false)
                segment(title: "전체영상", isFullVideo: true)
            }
            .padding(2)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(RoundedRectangle(cornerRadius: height / 2))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        if abs(value.translation.width) < 1 {
                            usesFullVideo.toggle()
                            return
                        }
                        usesFullVideo = value.location.x >= proxy.size.width / 2
                    }
            )
        }
        .frame(width: width, height: height)
        .background(
            tint.opacity(0.060),
            in: RoundedRectangle(cornerRadius: height / 2)
        )
        .overlay {
            RoundedRectangle(cornerRadius: height / 2)
                .stroke(tint.opacity(0.18), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
    }

    private func segment(title: String, isFullVideo: Bool) -> some View {
        let isSelected = usesFullVideo == isFullVideo

        return Text(title)
            .font(
                .system(
                    size: 10,
                    weight: isSelected ? .bold : .semibold
                )
            )
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(
                isSelected
                    ? HanClipTheme.primaryText
                    : HanClipTheme.secondaryText
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: max(4, height / 2 - 2))
                        .fill(
                            LinearGradient(
                                colors: [
                                    HanClipTheme.background.opacity(0.72),
                                    tint.opacity(0.085)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: max(4, height / 2 - 2)
                            )
                            .stroke(tint.opacity(0.24), lineWidth: 0.7)
                        }
                }
            }
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BackgroundMusicSettingsSheet: View {
    private struct SessionState: Equatable {
        var isEnabled: Bool
        var fileURL: URL?
        var displayName: String
        var musicVolume: Double
        var originalAudioVolume: Double
        var loopsToFillVideo: Bool
        var fadeInEnabled: Bool
        var fadeOutEnabled: Bool

        func matchesContent(of other: SessionState) -> Bool {
            fileURL == other.fileURL
                && displayName == other.displayName
                && abs(musicVolume - other.musicVolume) < 0.001
                && abs(
                    originalAudioVolume - other.originalAudioVolume
                ) < 0.001
                && loopsToFillVideo == other.loopsToFillVideo
                && fadeInEnabled == other.fadeInEnabled
                && fadeOutEnabled == other.fadeOutEnabled
        }
    }

    @Binding var settings: BackgroundMusicSettings
    @Binding var isEnabled: Bool
    @Binding var musicVolume: Double
    @Binding var originalAudioVolume: Double
    @Binding var loopsToFillVideo: Bool
    @Binding var fadeInEnabled: Bool
    @Binding var fadeOutEnabled: Bool
    let onUseSampleMusic: (BackgroundMusicSampleTrack) -> Void
    let onPickMusic: () -> Void
    let onImportDownloadedMusic: (URL) -> Void
    let onImportDownloadedVideo: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var previewPlayer: AVAudioPlayer?
    @State private var activePreviewID: String?
    @State private var originalSessionState: SessionState?
    @State private var isOpeningMusicPicker = false
    @State private var showOnlineMusicBrowser = false

    var body: some View {
        NavigationStack {
            ZStack {
                HanClipTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HanClipTitleLine(
                            "음악",
                            systemImage: "music.note",
                            leadingInset: 0,
                            trailingInset: 0
                        )
                        .padding(.bottom, -2)

                        musicChoiceSection

                        settingSection(spacing: 8, padding: 12) {
                            volumeSlider(
                                title: "음량",
                                value: $musicVolume
                            )
                            volumeSlider(
                                title: "원본 소리",
                                value: $originalAudioVolume
                            )
                        }

                        settingSection(spacing: 0, padding: 12) {
                            HStack(spacing: 10) {
                                toggleRow("페이드 인", isOn: $fadeInEnabled)
                                    .frame(maxWidth: .infinity)

                                Rectangle()
                                    .fill(HanClipTheme.separator.opacity(0.70))
                                    .frame(width: 1, height: 24)

                                toggleRow("페이드 아웃", isOn: $fadeOutEnabled)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        resetSettings()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(HanClipTheme.primary)
                    .accessibilityLabel("초기화")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if hasSessionChanges {
                        HStack(spacing: 2) {
                            Button {
                                discardChangesAndDismiss()
                            } label: {
                                settingsToolbarIcon("xmark")
                            }
                            .accessibilityLabel("저장 없이 나가기")

                            Button {
                                dismiss()
                            } label: {
                                settingsToolbarSaveIcon
                            }
                            .accessibilityLabel("저장 후 닫기")
                        }
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            settingsToolbarIcon("xmark")
                        }
                        .accessibilityLabel("닫기")
                    }
                }
            }
        }
        .onAppear {
            beginEditingSessionIfNeeded()
        }
        .onChange(of: musicVolume) { _, volume in
            previewPlayer?.volume = previewVolume(for: volume)
        }
        .onDisappear {
            stopPreview()
            restoreDisabledStateIfUnchanged()
        }
        .fullScreenCover(isPresented: $showOnlineMusicBrowser) {
            OnlineMusicBrowserView { url, kind in
                if kind == .video {
                    onImportDownloadedVideo(url)
                } else {
                    onImportDownloadedMusic(url)
                }
                showOnlineMusicBrowser = false
            }
        }
    }

    private var musicChoiceSection: some View {
        settingSection {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(BackgroundMusicSettings.sampleTracks) { sampleTrack in
                    sampleMusicButton(sampleTrack)
                }
            }

            Divider()
                .overlay(HanClipTheme.separator)

            onlineMusicRow

            Divider()
                .overlay(HanClipTheme.separator)

            fileMusicPickerRow

            if settings.hasMusicFile {
                InlineStatusSegmentedControl(
                    isOn: $isEnabled,
                    isEnabled: settings.hasMusicFile
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var onlineMusicRow: some View {
        actionButton(
            "브라우저",
            systemImage: "globe",
            isPrimary: false,
            action: openPixabayMusic
        )
    }

    private var fileMusicPickerRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                actionButton(
                    "음악 파일 불러오기",
                    systemImage: "folder",
                    isPrimary: false,
                    action: pickMusicFile
                )

                if settings.hasMusicFile && !isBundledSampleSelected {
                    previewButton(
                        id: "selected-music",
                        url: settings.fileURL,
                        title: "선택된 음악 미리듣기",
                        size: 38
                    )
                }
            }

            if settings.hasMusicFile && !isBundledSampleSelected {
                Text(settings.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HanClipTheme.text.opacity(0.56))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
        }
    }

    private func pickMusicFile() {
        isOpeningMusicPicker = true
        onPickMusic()
    }

    private var isBundledSampleSelected: Bool {
        BackgroundMusicSettings.sampleTracks.contains { sampleTrack in
            settings.displayName == sampleTrack.title
                || settings.fileURL?.lastPathComponent
                    == sampleTrack.url?.lastPathComponent
        }
    }

    private func settingSection<Content: View>(
        spacing: CGFloat = 14,
        padding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(padding)
        .background(
            HanClipTheme.panelFill,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(HanClipTheme.secondary.opacity(0.12), lineWidth: 1)
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .contentShape(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .background(
                    isPrimary
                        ? HanClipTheme.primary
                        : HanClipTheme.primary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .foregroundStyle(isPrimary ? .white : HanClipTheme.primary)
    }

    private func openPixabayMusic() {
        showOnlineMusicBrowser = true
    }

    private func sampleMusicButton(
        _ sampleTrack: BackgroundMusicSampleTrack
    ) -> some View {
        let isSelected = settings.displayName == sampleTrack.title

        return HStack(alignment: .top, spacing: 8) {
            Button {
                onUseSampleMusic(sampleTrack)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(
                            systemName: isSelected
                                ? "checkmark.circle.fill"
                                : "waveform"
                        )
                        .font(.system(size: 15, weight: .black))

                        Text(sampleTrack.title)
                            .font(.system(size: 12, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(
                        isSelected
                            ? HanClipTheme.primary
                            : HanClipTheme.text.opacity(0.68)
                    )

                    Text(sampleTrack.subtitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HanClipTheme.text.opacity(0.48))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.plain)

            previewButton(
                id: "sample-\(sampleTrack.id)",
                url: sampleTrack.url,
                title: "\(sampleTrack.title) 미리듣기",
                size: 30
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            isSelected
                ? HanClipTheme.primary.opacity(0.08)
                : HanClipTheme.secondary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected
                        ? HanClipTheme.primary.opacity(0.34)
                        : HanClipTheme.secondary.opacity(0.10),
                    lineWidth: 1
                )
        }
    }

    private func previewButton(
        id: String,
        url: URL?,
        title: String,
        size: CGFloat = 42
    ) -> some View {
        Button {
            togglePreview(id: id, url: url)
        } label: {
            Image(systemName: activePreviewID == id ? "stop.fill" : "play.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(
                    url == nil
                        ? HanClipTheme.text.opacity(0.28)
                        : HanClipTheme.primary
                )
                .frame(width: size, height: size)
                .background(
                    HanClipTheme.primary.opacity(url == nil ? 0.05 : 0.12),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityLabel(title)
    }

    private func togglePreview(id: String, url: URL?) {
        guard let url else { return }

        if activePreviewID == id, previewPlayer?.isPlaying == true {
            stopPreview()
            return
        }

        stopPreview()

        do {
            guard HanClipAudioSession.activatePlayback() else { return }
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = previewVolume(for: musicVolume)
            player.prepareToPlay()
            player.play()
            previewPlayer = player
            activePreviewID = id
        } catch {
            previewPlayer = nil
            activePreviewID = nil
        }
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer?.currentTime = 0
        previewPlayer = nil
        activePreviewID = nil
    }

    private func previewVolume(for value: Double) -> Float {
        Float(min(max(value, 0), 1))
    }

    private func resetSettings() {
        stopPreview()
        let defaultSettings = BackgroundMusicSettings.projectDefault
        settings = defaultSettings
        isEnabled = defaultSettings.isEnabled
        musicVolume = defaultSettings.musicVolume
        originalAudioVolume = defaultSettings.originalAudioVolume
        loopsToFillVideo = defaultSettings.loopsToFillVideo
        fadeInEnabled = defaultSettings.fadeInEnabled
        fadeOutEnabled = defaultSettings.fadeOutEnabled
    }

    private func beginEditingSessionIfNeeded() {
        guard originalSessionState == nil else { return }

        var normalizedSettings = settings
        if !normalizedSettings.hasMusicFile,
           let defaultSettings = BackgroundMusicSettings.bundledSample {
            normalizedSettings = defaultSettings
            normalizedSettings.isEnabled = settings.isEnabled
            settings = normalizedSettings
        }

        let state = currentSessionState()
        originalSessionState = state
        if !state.isEnabled {
            isEnabled = true
        }
    }

    private func restoreDisabledStateIfUnchanged() {
        guard !isOpeningMusicPicker,
              let originalSessionState,
              !originalSessionState.isEnabled,
              currentSessionState().matchesContent(of: originalSessionState)
        else { return }

        isEnabled = false
    }

    private func discardChangesAndDismiss() {
        if let originalSessionState {
            applySessionState(originalSessionState)
        }
        dismiss()
    }

    private func applySessionState(_ state: SessionState) {
        settings.isEnabled = state.isEnabled
        settings.fileURL = state.fileURL
        settings.displayName = state.displayName
        settings.musicVolume = state.musicVolume
        settings.originalAudioVolume = state.originalAudioVolume
        settings.loopsToFillVideo = state.loopsToFillVideo
        settings.fadeInEnabled = state.fadeInEnabled
        settings.fadeOutEnabled = state.fadeOutEnabled

        isEnabled = state.isEnabled
        musicVolume = state.musicVolume
        originalAudioVolume = state.originalAudioVolume
        loopsToFillVideo = state.loopsToFillVideo
        fadeInEnabled = state.fadeInEnabled
        fadeOutEnabled = state.fadeOutEnabled
    }

    private var hasSessionChanges: Bool {
        guard let originalSessionState else { return false }
        let currentState = currentSessionState()
        if !originalSessionState.isEnabled,
           currentState.isEnabled,
           currentState.matchesContent(of: originalSessionState) {
            return false
        }
        return currentState != originalSessionState
    }

    private func currentSessionState() -> SessionState {
        SessionState(
            isEnabled: isEnabled,
            fileURL: settings.fileURL,
            displayName: settings.displayName,
            musicVolume: musicVolume,
            originalAudioVolume: originalAudioVolume,
            loopsToFillVideo: loopsToFillVideo,
            fadeInEnabled: fadeInEnabled,
            fadeOutEnabled: fadeOutEnabled
        )
    }

    private func settingsToolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(HanClipTheme.primary)
            .frame(width: 40, height: 44)
    }

    private var settingsToolbarSaveIcon: some View {
        FloppyDiskIcon()
            .foregroundStyle(HanClipTheme.primary)
            .frame(width: 23, height: 23)
            .frame(width: 40, height: 44)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(HanClipTheme.text.opacity(0.68))
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(HanClipTheme.text.opacity(0.76))
            .tint(HanClipTheme.primary)
    }

    private func volumeSlider(
        title: String,
        value: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HanClipTheme.text.opacity(0.76))
                Spacer()
                Text(Self.percentText(value.wrappedValue))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(HanClipTheme.text.opacity(0.58))
            }
            Slider(value: value, in: 0...1)
                .tint(HanClipTheme.primary)
        }
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }
}

private enum BrowserDownloadKind: Equatable {
    case audio
    case video
}

private struct BrowserDetectedVideo: Equatable {
    let urlString: String

    var downloadableURL: URL? {
        guard let url = URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased())
        else { return nil }
        return url
    }
}

private struct BrowserFavoritesDocument: FileDocument {
    static let contentType = UTType(
        exportedAs: BrowserFavoritesArchive.typeIdentifier,
        conformingTo: .json
    )
    static var readableContentTypes: [UTType] { [contentType] }

    let archive: BrowserFavoritesArchive

    init(favorites: [String]) {
        archive = BrowserFavoritesArchive(favorites: favorites)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        archive = try JSONDecoder().decode(
            BrowserFavoritesArchive.self,
            from: data
        )
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(archive))
    }
}

private struct BrowserFavicon: View {
    let favorite: String

    var body: some View {
        AsyncImage(url: faviconURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .foregroundStyle(HanClipTheme.primary)
            }
        }
        .frame(width: 30, height: 30)
        .background(HanClipTheme.panelFill, in: RoundedRectangle(cornerRadius: 7))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var faviconURL: URL? {
        guard let source = URL(string: favorite),
              let scheme = source.scheme,
              let host = source.host
        else { return nil }
        return URL(string: "\(scheme)://\(host)/favicon.ico")
    }
}

private struct OnlineMusicBrowserView: View {
    let onDownloaded: (URL, BrowserDownloadKind) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hanClipOnlineMusicFavorites")
    private var favoriteMusicSitesRaw = "https://pixabay.com/music/\nhttps://mixkit.co/free-stock-music/\nhttps://intosharp.com/"
    @State private var isDownloading = false
    @State private var currentURLText = "https://pixabay.com/music/"
    @State private var addressText = "https://pixabay.com/music/"
    @State private var requestedURL: URL?
    @State private var canGoBack = false
    @State private var isPageLoading = false
    @State private var pageLoadProgress = 0.0
    @State private var isPopupOpen = false
    @State private var goBackTrigger = 0
    @State private var stopLoadingTrigger = 0
    @State private var reloadTrigger = 0
    @State private var closePopupTrigger = 0
    @State private var pauseAndRetainTrigger = 0
    @State private var cancelDownloadTrigger = 0
    @State private var downloadProgress: Double?
    @State private var downloadStatusText = "음악을 가져오는 중"
    @State private var showFavoriteEditor = false
    @State private var showFavoritePanel = false
    @State private var detectedVideo: BrowserDetectedVideo?
    @State private var detectedVideoPreviewURL: URL?
    @State private var dismissedVideoURLString: String?
    @State private var downloadDetectedVideoTrigger = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                addressBar

                ZStack(alignment: .top) {
                    OnlineMusicWebView(
                        url: firstFavoriteMusicSiteURL,
                        currentURLText: $currentURLText,
                        requestedURL: $requestedURL,
                        canGoBack: $canGoBack,
                        isPageLoading: $isPageLoading,
                        pageLoadProgress: $pageLoadProgress,
                        isPopupOpen: $isPopupOpen,
                        goBackTrigger: $goBackTrigger,
                        stopLoadingTrigger: $stopLoadingTrigger,
                        reloadTrigger: $reloadTrigger,
                        closePopupTrigger: $closePopupTrigger,
                        pauseAndRetainTrigger: $pauseAndRetainTrigger,
                        cancelDownloadTrigger: $cancelDownloadTrigger,
                        isDownloading: $isDownloading,
                        downloadProgress: $downloadProgress,
                        downloadStatusText: $downloadStatusText,
                        detectedVideo: detectedVideoBinding,
                        downloadDetectedVideoTrigger:
                            $downloadDetectedVideoTrigger,
                        onDownloaded: onDownloaded
                    )
                    .ignoresSafeArea(edges: .bottom)

                    if isDownloading {
                        downloadStatusOverlay
                    } else if detectedVideo?.downloadableURL != nil {
                        detectedVideoPanel
                    }
                }
                .overlay {
                    if showFavoritePanel {
                        GeometryReader { proxy in
                            ZStack(alignment: .topTrailing) {
                                Color.black.opacity(0.001)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        showFavoritePanel = false
                                    }

                                favoritePanel(
                                    width: favoritePanelWidth(
                                        availableWidth: proxy.size.width
                                    ),
                                    height: favoritePanelHeight(
                                        availableHeight: proxy.size.height
                                    )
                                )
                                .padding(.top, favoritePanelTopPadding)
                                .padding(.horizontal, favoritePanelSidePadding)
                                .transition(
                                    .move(edge: .top)
                                        .combined(with: .opacity)
                                )
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showFavoriteEditor) {
                OnlineMusicFavoritesEditorView(
                    favoritesRaw: $favoriteMusicSitesRaw
                )
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { detectedVideoPreviewURL != nil },
                    set: { isPresented in
                        if !isPresented {
                            detectedVideoPreviewURL = nil
                        }
                    }
                )
            ) {
                if let url = detectedVideoPreviewURL {
                    FullscreenVideoPreview(
                        url: url,
                        startTime: .zero,
                        onClose: {
                            detectedVideoPreviewURL = nil
                        }
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: currentURLText) { _, newValue in
                addressText = newValue
            }
            .onAppear {
                ensureDefaultFavorites()
                if let retainedURLText =
                    OnlineMusicBrowserSessionStore.shared.retainedURLText {
                    currentURLText = retainedURLText
                    addressText = retainedURLText
                } else {
                    let initialURL = firstFavoriteMusicSiteURL
                    currentURLText = initialURL.absoluteString
                    addressText = initialURL.absoluteString
                }
            }
            .onDisappear {
                pauseAndRetainTrigger += 1
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 7) {
            browserBackOrCloseButton

            TextField("웹 주소 입력", text: $addressText)
                .font(.system(size: 13, weight: .semibold))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(loadAddress)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    HanClipTheme.panelFill.opacity(0.72),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            HanClipTheme.secondary.opacity(0.14),
                            lineWidth: 1
                        )
                }

            browserPrimaryAddressButton

            Button {
                dismissedVideoURLString = nil
                reloadTrigger += 1
            } label: {
                browserToolbarIcon("arrow.clockwise")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("새로고침")

            Image(
                systemName: isCurrentFavorite ? "bookmark.fill" : "bookmark"
            )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    isCurrentFavorite
                        ? HanClipTheme.primary
                        : HanClipTheme.text.opacity(0.68)
                )
                .frame(width: 32, height: 32)
                .background(
                    isCurrentFavorite
                        ? HanClipTheme.primary.opacity(0.12)
                        : HanClipTheme.panelFill.opacity(0.90),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            isCurrentFavorite
                                ? HanClipTheme.primary.opacity(0.30)
                                : HanClipTheme.secondary.opacity(0.14),
                            lineWidth: 1
                        )
                }
                .contentShape(Circle())
                .gesture(favoriteButtonGesture)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(
                    showFavoritePanel
                        ? "즐겨찾기 목록 닫기"
                        : "즐겨찾기 목록 열기"
                )
                .accessibilityAction {
                    handleFavoriteButtonTap()
                }
                .accessibilityAction(
                    named: isCurrentFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가"
                ) {
                    toggleCurrentFavorite()
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(HanClipTheme.background.opacity(0.96))
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(HanClipTheme.secondary.opacity(0.18))
                    .frame(height: 1)
                pageLoadProgressBar
                    .frame(height: 2)
            }
        }
    }

    private var pageLoadProgressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HanClipTheme.panelFill.opacity(isPageLoading ? 0.80 : 0)
                HanClipTheme.primary
                    .frame(
                        width: proxy.size.width
                            * CGFloat(min(max(pageLoadProgress, 0), 1))
                    )
            }
        }
        .opacity(isPageLoading ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: pageLoadProgress)
        .animation(.easeInOut(duration: 0.16), value: isPageLoading)
        .accessibilityHidden(true)
    }

    private var browserBackOrCloseButton: some View {
        Image(systemName: isPopupOpen || !canGoBack ? "xmark" : "chevron.left")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(HanClipTheme.text.opacity(0.68))
            .frame(width: 32, height: 32)
            .background(HanClipTheme.panelFill.opacity(0.90), in: Circle())
            .overlay {
                Circle()
                    .stroke(HanClipTheme.secondary.opacity(0.14), lineWidth: 1)
            }
            .contentShape(Circle())
            .gesture(browserBackOrCloseGesture)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(
                isPopupOpen
                    ? "팝업 닫기"
                    : canGoBack
                        ? "이전 페이지"
                        : "브라우저 닫기"
            )
            .accessibilityHint(
                canGoBack && !isPopupOpen
                    ? "길게 누르면 브라우저를 닫습니다"
                    : ""
            )
            .accessibilityAction {
                handleBrowserBackOrCloseTap()
            }
            .accessibilityAction(named: "브라우저 닫기") {
                if isPopupOpen {
                    closePopupTrigger += 1
                } else {
                    pauseAndRetainTrigger += 1
                    dismiss()
                }
            }
    }

    private var browserPrimaryAddressButton: some View {
        browserToolbarIcon(
            isPageLoading ? "xmark" : "arrow.turn.down.left",
            isPrimary: true
        )
        .contentShape(Circle())
        .gesture(primaryAddressButtonGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isPageLoading ? "로딩 중지" : "주소로 이동")
        .accessibilityHint("길게 누르면 복사한 주소를 붙여넣고 바로 이동합니다")
        .accessibilityAction {
            primaryAddressAction()
        }
        .accessibilityAction(named: "복사한 주소로 이동") {
            pasteCopiedAddressAndLoad()
        }
    }

    private func browserToolbarIcon(
        _ systemName: String,
        isPrimary: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(
                isPrimary
                    ? Color.white
                    : HanClipTheme.text.opacity(isEnabled ? 0.68 : 0.26)
            )
            .frame(width: 32, height: 32)
            .background(
                isPrimary
                    ? HanClipTheme.primary
                    : HanClipTheme.panelFill.opacity(0.90),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        isPrimary
                            ? HanClipTheme.primary.opacity(0.34)
                            : HanClipTheme.secondary.opacity(0.14),
                        lineWidth: 1
                    )
            }
    }

    private var primaryAddressButtonGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .exclusively(before: TapGesture())
            .onEnded { value in
                switch value {
                case .first:
                    pasteCopiedAddressAndLoad()
                case .second:
                    primaryAddressAction()
                }
            }
    }

    private var browserBackOrCloseGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .exclusively(before: TapGesture())
            .onEnded { value in
                switch value {
                case .first:
                    if isPopupOpen {
                        closePopupTrigger += 1
                    } else {
                        pauseAndRetainTrigger += 1
                        dismiss()
                    }
                case .second:
                    handleBrowserBackOrCloseTap()
                }
            }
    }

    private func handleBrowserBackOrCloseTap() {
        if isPopupOpen {
            closePopupTrigger += 1
            return
        }
        if canGoBack {
            goBackTrigger += 1
        } else {
            pauseAndRetainTrigger += 1
            dismiss()
        }
    }

    private var favoriteButtonGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .exclusively(before: TapGesture())
            .onEnded { value in
                switch value {
                case .first:
                    toggleCurrentFavorite()
                case .second:
                    handleFavoriteButtonTap()
                }
            }
    }

    private func handleFavoriteButtonTap() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showFavoritePanel.toggle()
        }
    }

    private var favoritePanelTopPadding: CGFloat { 8 }
    private var favoritePanelSidePadding: CGFloat { 0 }
    private var favoritePanelBottomPadding: CGFloat { 0 }
    private var favoritePanelHeaderHeight: CGFloat { 53 }
    private var favoritePanelEmptyHeight: CGFloat { 112 }
    private var favoritePanelRowHeight: CGFloat { 50 }
    private var favoritePanelRowSpacing: CGFloat { 4 }
    private var favoritePanelListVerticalPadding: CGFloat { 16 }

    private func favoritePanel(
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("즐겨찾기", systemImage: "bookmark.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(HanClipTheme.primaryText)
                Spacer()
                Button {
                    showFavoritePanel = false
                    DispatchQueue.main.async {
                        showFavoriteEditor = true
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(HanClipTheme.primary)
                .accessibilityLabel("즐겨찾기 편집")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if favoriteMusicSites.isEmpty {
                Text("등록된 즐겨찾기가 없습니다.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText)
                    .padding(24)
            } else {
                ScrollView(
                    .vertical,
                    showsIndicators: shouldShowFavoriteScrollbar(
                        availableHeight: height
                    )
                ) {
                    LazyVStack(spacing: favoritePanelRowSpacing) {
                        ForEach(favoriteMusicSites, id: \.self) { favorite in
                            favoritePanelRow(favorite)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
                    .padding(
                        .trailing,
                        shouldShowFavoriteScrollbar(availableHeight: height)
                            ? 14
                            : 8
                    )
                }
                .scrollIndicators(
                    shouldShowFavoriteScrollbar(availableHeight: height)
                        ? .visible
                        : .hidden
                )
                .scrollIndicatorsFlash(trigger: showFavoritePanel)
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: width, height: height)
        .background(HanClipTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(HanClipTheme.secondary.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
    }

    private func favoritePanelWidth(availableWidth: CGFloat) -> CGFloat {
        max(260, availableWidth - favoritePanelSidePadding * 2)
    }

    private func favoritePanelHeight(availableHeight: CGFloat) -> CGFloat {
        let maximumHeight = max(
            favoritePanelEmptyHeight,
            availableHeight - favoritePanelTopPadding - favoritePanelBottomPadding
        )
        return min(favoritePanelContentHeight, maximumHeight)
    }

    private var favoritePanelContentHeight: CGFloat {
        guard !favoriteMusicSites.isEmpty else {
            return favoritePanelEmptyHeight
        }
        return favoritePanelHeaderHeight
            + favoritePanelListVerticalPadding
            + CGFloat(favoriteMusicSites.count) * favoritePanelRowHeight
            + CGFloat(max(favoriteMusicSites.count - 1, 0))
                * favoritePanelRowSpacing
    }

    private func shouldShowFavoriteScrollbar(availableHeight: CGFloat) -> Bool {
        favoritePanelContentHeight > availableHeight + 0.5
    }

    private func favoritePanelRow(_ favorite: String) -> some View {
        HStack(spacing: 10) {
            BrowserFavicon(favorite: favorite)
                .contentShape(Rectangle())
                .onTapGesture {
                    removeFavorite(favorite)
                }
                .onLongPressGesture(minimumDuration: 0.55) {
                    makeHomepage(favorite)
                }
                .accessibilityElement()
                .accessibilityLabel("\(favoriteDisplayTitle(favorite)) 삭제")
                .accessibilityAction(named: "홈페이지로 지정") {
                    makeHomepage(favorite)
                }

            Button {
                showFavoritePanel = false
                openFavorite(favorite)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(favoriteDisplayTitle(favorite))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(HanClipTheme.primaryText)
                            .lineLimit(1)
                        Text(favorite)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(HanClipTheme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if favorite == favoriteMusicSites.first {
                        Image(systemName: "house.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(HanClipTheme.primary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 50)
        .background(
            HanClipTheme.panelFill.opacity(0.84),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var detectedVideoPanel: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(HanClipTheme.primaryText)
                .accessibilityHidden(true)

            Spacer(minLength: 4)

            Button {
                downloadDetectedVideoTrigger += 1
            } label: {
                Text("다운")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("영상 다운로드")

            Button {
                detectedVideoPreviewURL = detectedVideo?.downloadableURL
            } label: {
                Text("보기")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("감지된 영상 전체 화면 보기")

            Button {
                dismissedVideoURLString = detectedVideo?.urlString
                detectedVideo = nil
            } label: {
                Text("닫기")
            }
            .buttonStyle(.bordered)
            .accessibilityHint("영상 인식 알림만 닫습니다")
        }
        .font(.system(size: 12, weight: .bold))
        .tint(HanClipTheme.primary)
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(HanClipTheme.secondary.opacity(0.22), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var detectedVideoBinding: Binding<BrowserDetectedVideo?> {
        Binding(
            get: { detectedVideo },
            set: { newValue in
                if let newValue {
                    guard newValue.downloadableURL != nil,
                          newValue.urlString != dismissedVideoURLString
                    else {
                        return
                    }
                }
                detectedVideo = newValue
            }
        )
    }

    private var downloadStatusOverlay: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(downloadStatusText)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)

                Spacer(minLength: 10)

                Button {
                    cancelDownloadTrigger += 1
                } label: {
                    Label("취소", systemImage: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .black))
                }
                .buttonStyle(.plain)
                .foregroundStyle(HanClipTheme.primary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(HanClipTheme.secondary.opacity(0.24))

                    Capsule()
                        .fill(HanClipTheme.primary)
                        .frame(
                            width: proxy.size.width
                                * CGFloat(downloadProgress ?? 0.18)
                        )
                }
            }
            .frame(height: 4)
        }
        .foregroundStyle(HanClipTheme.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            HanClipTheme.browserDownloadPanelFill,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    HanClipTheme.secondary.opacity(0.32),
                    lineWidth: 1
                )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func loadAddress() {
        guard let url = Self.normalizedURL(from: addressText) else { return }
        dismissedVideoURLString = nil
        requestedURL = url
        currentURLText = url.absoluteString
        addressText = url.absoluteString
    }

    private func primaryAddressAction() {
        if isPageLoading {
            stopLoadingTrigger += 1
        } else {
            loadAddress()
        }
    }

    private func pasteCopiedAddressAndLoad() {
        addressText = ""
        guard let pastedAddress = UIPasteboard.general.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !pastedAddress.isEmpty
        else { return }
        addressText = pastedAddress
        loadAddress()
    }

    private var favoriteMusicSites: [String] {
        favoriteMusicSitesRaw
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var firstFavoriteMusicSiteURL: URL {
        favoriteMusicSites
            .compactMap(Self.normalizedURL)
            .first
            ?? URL(string: "https://pixabay.com/music/")!
    }

    private var normalizedCurrentURLString: String? {
        Self.normalizedURL(from: currentURLText)?.absoluteString
    }

    private var isCurrentFavorite: Bool {
        guard let normalizedCurrentURLString else { return false }
        return favoriteMusicSites.contains(normalizedCurrentURLString)
    }

    private func toggleCurrentFavorite() {
        guard let normalized = normalizedCurrentURLString else { return }
        var favorites = favoriteMusicSites
        if let index = favorites.firstIndex(of: normalized) {
            favorites.remove(at: index)
        } else {
            favorites.append(normalized)
        }
        favoriteMusicSitesRaw = favorites.joined(separator: "\n")
    }

    private func removeFavorite(_ favorite: String) {
        var favorites = favoriteMusicSites
        favorites.removeAll { $0 == favorite }
        favoriteMusicSitesRaw = favorites.joined(separator: "\n")
        if favorites.isEmpty {
            showFavoritePanel = false
        }
    }

    private func makeHomepage(_ favorite: String) {
        var favorites = favoriteMusicSites
        guard let index = favorites.firstIndex(of: favorite), index != 0 else {
            return
        }
        favorites.remove(at: index)
        favorites.insert(favorite, at: 0)
        favoriteMusicSitesRaw = favorites.joined(separator: "\n")
    }

    private func ensureDefaultFavorites() {
        var favorites = favoriteMusicSites
        guard favorites.contains("https://pixabay.com/music/") else { return }

        let mixkit = "https://mixkit.co/free-stock-music/"
        let intosharp = "https://intosharp.com/"

        if let existingMixkitIndex = favorites.firstIndex(of: mixkit) {
            favorites.remove(at: existingMixkitIndex)
        }

        if let pixabayIndex = favorites.firstIndex(of: "https://pixabay.com/music/") {
            favorites.insert(mixkit, at: min(pixabayIndex + 1, favorites.endIndex))
        } else {
            favorites.append(mixkit)
        }

        if !favorites.contains(intosharp) {
            favorites.append(intosharp)
        }
        favoriteMusicSitesRaw = favorites.joined(separator: "\n")
    }

    private func openFavorite(_ favorite: String) {
        addressText = favorite
        loadAddress()
    }

    private func favoriteDisplayTitle(_ favorite: String) -> String {
        guard let url = URL(string: favorite),
              let host = url.host(percentEncoded: false)
        else { return favorite }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? host : "\(host)/\(path)"
    }

    nonisolated private static func normalizedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }
}

private struct OnlineMusicFavoritesEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var favoritesRaw: String
    @State private var favorites: [String]
    @State private var editMode = EditMode.active
    @State private var showFavoritesExporter = false
    @State private var exportErrorMessage: String?

    init(favoritesRaw: Binding<String>) {
        _favoritesRaw = favoritesRaw
        _favorites = State(
            initialValue: Self.favorites(from: favoritesRaw.wrappedValue)
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(favorites, id: \.self) { favorite in
                    favoriteRow(favorite)
                        .listRowInsets(
                            EdgeInsets(
                                top: 5,
                                leading: 16,
                                bottom: 5,
                                trailing: 16
                            )
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    favorites.move(fromOffsets: source, toOffset: destination)
                    save()
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
            .scrollContentBackground(.hidden)
            .background(HanClipTheme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if !favorites.isEmpty {
                    Text("행을 길게 잡고 움직여 순서를 바꿉니다.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HanClipTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            HanClipTheme.panelFill.opacity(0.92),
                            in: Capsule()
                        )
                        .padding(.bottom, 8)
                }
            }
            .overlay {
                if favorites.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(HanClipTheme.secondary)
                        Text("등록된 즐겨찾기가 없습니다.")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(HanClipTheme.secondaryText)
                    }
                }
            }
            .navigationTitle("즐겨찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        favorites = []
                        save()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("전체삭제")
                        }
                        .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(HanClipTheme.primary)
                    .disabled(favorites.isEmpty)
                    .accessibilityLabel("즐겨찾기 모두 삭제")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Button {
                            showFavoritesExporter = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .disabled(favorites.isEmpty)
                        .accessibilityLabel("현재 즐겨찾기 파일로 저장")

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .accessibilityLabel("닫기")
                    }
                    .foregroundStyle(HanClipTheme.primary)
                }
            }
        }
        .fileExporter(
            isPresented: $showFavoritesExporter,
            document: BrowserFavoritesDocument(favorites: favorites),
            contentType: BrowserFavoritesDocument.contentType,
            defaultFilename: "HanClip-브라우저-즐겨찾기"
        ) { result in
            if case .failure(let error) = result {
                exportErrorMessage = error.localizedDescription
            }
        }
        .alert(
            "즐겨찾기를 저장할 수 없습니다.",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    private func favoriteRow(_ favorite: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle(for: favorite))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(HanClipTheme.primaryText)
                    .lineLimit(1)

                Text(favorite)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            favoriteIconButton("trash") {
                if let index = favorites.firstIndex(of: favorite) {
                    favorites.remove(at: index)
                    save()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            HanClipTheme.panelFill.opacity(0.92),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HanClipTheme.panelStroke.opacity(0.70), lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private func favoriteIconButton(
        _ systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(HanClipTheme.primary)
                .frame(width: 28, height: 28)
                .background(
                    Color.white.opacity(0.45),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        favoritesRaw = favorites.joined(separator: "\n")
    }

    private func displayTitle(for favorite: String) -> String {
        guard let url = URL(string: favorite),
              let host = url.host(percentEncoded: false)
        else { return favorite }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? host : "\(host)/\(path)"
    }

    private static func favorites(from raw: String) -> [String] {
        raw.split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

@MainActor
private final class OnlineMusicBrowserSessionStore {
    static let shared = OnlineMusicBrowserSessionStore()

    private var retainedWebView: WKWebView?
    private var retainedAt: Date?
    private var resetTask: Task<Void, Never>?
    private(set) var retainedURLText: String?
    private let retentionInterval: TimeInterval = 10

    func retain(_ webView: WKWebView, urlText: String) {
        pausePlayback(in: webView)
        retainedWebView = webView
        retainedAt = Date()
        retainedURLText = urlText
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await MainActor.run {
                self?.clearIfExpired()
            }
        }
    }

    func takeValidWebView() -> WKWebView? {
        guard let retainedAt,
              Date().timeIntervalSince(retainedAt) <= retentionInterval,
              let retainedWebView
        else {
            clear()
            return nil
        }
        resetTask?.cancel()
        self.retainedWebView = nil
        self.retainedAt = nil
        return retainedWebView
    }

    func pausePlayback(in webView: WKWebView) {
        webView.evaluateJavaScript(
            """
            document.querySelectorAll('video,audio').forEach((media) => {
              try { media.pause(); } catch (error) {}
            });
            """
        )
    }

    private func clearIfExpired() {
        guard let retainedAt,
              Date().timeIntervalSince(retainedAt) > retentionInterval
        else { return }
        clear()
    }

    private func clear() {
        retainedWebView?.stopLoading()
        retainedWebView = nil
        retainedAt = nil
        retainedURLText = nil
        resetTask?.cancel()
        resetTask = nil
    }
}

private struct OnlineMusicWebView: UIViewRepresentable {
    let url: URL
    @Binding var currentURLText: String
    @Binding var requestedURL: URL?
    @Binding var canGoBack: Bool
    @Binding var isPageLoading: Bool
    @Binding var pageLoadProgress: Double
    @Binding var isPopupOpen: Bool
    @Binding var goBackTrigger: Int
    @Binding var stopLoadingTrigger: Int
    @Binding var reloadTrigger: Int
    @Binding var closePopupTrigger: Int
    @Binding var pauseAndRetainTrigger: Int
    @Binding var cancelDownloadTrigger: Int
    @Binding var isDownloading: Bool
    @Binding var downloadProgress: Double?
    @Binding var downloadStatusText: String
    @Binding var detectedVideo: BrowserDetectedVideo?
    @Binding var downloadDetectedVideoTrigger: Int
    let onDownloaded: (URL, BrowserDownloadKind) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentURLText: $currentURLText,
            requestedURL: $requestedURL,
            canGoBack: $canGoBack,
            isPageLoading: $isPageLoading,
            pageLoadProgress: $pageLoadProgress,
            isPopupOpen: $isPopupOpen,
            goBackTrigger: $goBackTrigger,
            stopLoadingTrigger: $stopLoadingTrigger,
            reloadTrigger: $reloadTrigger,
            closePopupTrigger: $closePopupTrigger,
            pauseAndRetainTrigger: $pauseAndRetainTrigger,
            cancelDownloadTrigger: $cancelDownloadTrigger,
            isDownloading: $isDownloading,
            downloadProgress: $downloadProgress,
            downloadStatusText: $downloadStatusText,
            detectedVideo: $detectedVideo,
            downloadDetectedVideoTrigger: $downloadDetectedVideoTrigger,
            onDownloaded: onDownloaded
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.add(
            context.coordinator,
            name: Coordinator.videoMessageName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Coordinator.videoDetectionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )
        let webView: WKWebView
        if let retainedWebView =
            OnlineMusicBrowserSessionStore.shared.takeValidWebView() {
            webView = retainedWebView
            webView.configuration.userContentController.add(
                context.coordinator,
                name: Coordinator.videoMessageName
            )
        } else {
            webView = WKWebView(frame: .zero, configuration: configuration)
        }
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.observeProgress(in: webView)
        if webView.url == nil {
            webView.load(URLRequest(url: url))
        } else {
            context.coordinator.updateCurrentURL(from: webView)
        }
        return webView
    }

    static func dismantleUIView(
        _ uiView: WKWebView,
        coordinator: Coordinator
    ) {
        OnlineMusicBrowserSessionStore.shared.retain(
            uiView,
            urlText: coordinator.currentURLSnapshot
        )
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.videoMessageName
        )
        uiView.uiDelegate = nil
        uiView.navigationDelegate = nil
        coordinator.invalidateObservers()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateBindings(
            currentURLText: $currentURLText,
            requestedURL: $requestedURL,
            canGoBack: $canGoBack,
            isPageLoading: $isPageLoading,
            pageLoadProgress: $pageLoadProgress,
            isPopupOpen: $isPopupOpen,
            goBackTrigger: $goBackTrigger,
            stopLoadingTrigger: $stopLoadingTrigger,
            reloadTrigger: $reloadTrigger,
            closePopupTrigger: $closePopupTrigger,
            pauseAndRetainTrigger: $pauseAndRetainTrigger,
            cancelDownloadTrigger: $cancelDownloadTrigger,
            isDownloading: $isDownloading,
            downloadProgress: $downloadProgress,
            downloadStatusText: $downloadStatusText,
            detectedVideo: $detectedVideo,
            downloadDetectedVideoTrigger: $downloadDetectedVideoTrigger
        )
        context.coordinator.handleBrowserControls(in: webView)
        guard let requestedURL else { return }
        if webView.url != requestedURL {
            webView.load(URLRequest(url: requestedURL))
        }
        DispatchQueue.main.async {
            self.requestedURL = nil
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate,
        WKScriptMessageHandler {
        static let videoMessageName = "hanclipVideo"
        static let videoDetectionScript = """
        (() => {
          const report = () => {
            const videos = Array.from(document.querySelectorAll('video'));
            const video = videos.find(item => item.currentSrc || item.src || item.querySelector('source'));
            if (!video) return;
            const source = video.currentSrc || video.src || video.querySelector('source')?.src || '';
            if (source) window.webkit.messageHandlers.hanclipVideo.postMessage(source);
          };
          report();
          document.addEventListener('loadedmetadata', report, true);
          new MutationObserver(report).observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['src']
          });
        })();
        """

        @Binding private var currentURLText: String
        @Binding private var requestedURL: URL?
        @Binding private var canGoBack: Bool
        @Binding private var isPageLoading: Bool
        @Binding private var pageLoadProgress: Double
        @Binding private var isPopupOpen: Bool
        @Binding private var goBackTrigger: Int
        @Binding private var stopLoadingTrigger: Int
        @Binding private var reloadTrigger: Int
        @Binding private var closePopupTrigger: Int
        @Binding private var pauseAndRetainTrigger: Int
        @Binding private var cancelDownloadTrigger: Int
        @Binding private var isDownloading: Bool
        @Binding private var downloadProgress: Double?
        @Binding private var downloadStatusText: String
        @Binding private var detectedVideo: BrowserDetectedVideo?
        @Binding private var downloadDetectedVideoTrigger: Int
        private let onDownloaded: (URL, BrowserDownloadKind) -> Void
        private var destinationURL: URL?
        private var activeDownload: WKDownload?
        private var activeDownloadKind = BrowserDownloadKind.audio
        private var handledGoBackTrigger = 0
        private var handledStopLoadingTrigger = 0
        private var handledReloadTrigger = 0
        private var handledClosePopupTrigger = 0
        private var handledPauseAndRetainTrigger = 0
        private var handledCancelDownloadTrigger = 0
        private var handledDownloadDetectedVideoTrigger = 0
        private var popupReturnURL: URL?
        private var progressObservation: NSKeyValueObservation?

        var currentURLSnapshot: String {
            currentURLText
        }

        init(
            currentURLText: Binding<String>,
            requestedURL: Binding<URL?>,
            canGoBack: Binding<Bool>,
            isPageLoading: Binding<Bool>,
            pageLoadProgress: Binding<Double>,
            isPopupOpen: Binding<Bool>,
            goBackTrigger: Binding<Int>,
            stopLoadingTrigger: Binding<Int>,
            reloadTrigger: Binding<Int>,
            closePopupTrigger: Binding<Int>,
            pauseAndRetainTrigger: Binding<Int>,
            cancelDownloadTrigger: Binding<Int>,
            isDownloading: Binding<Bool>,
            downloadProgress: Binding<Double?>,
            downloadStatusText: Binding<String>,
            detectedVideo: Binding<BrowserDetectedVideo?>,
            downloadDetectedVideoTrigger: Binding<Int>,
            onDownloaded: @escaping (URL, BrowserDownloadKind) -> Void
        ) {
            _currentURLText = currentURLText
            _requestedURL = requestedURL
            _canGoBack = canGoBack
            _isPageLoading = isPageLoading
            _pageLoadProgress = pageLoadProgress
            _isPopupOpen = isPopupOpen
            _goBackTrigger = goBackTrigger
            _stopLoadingTrigger = stopLoadingTrigger
            _reloadTrigger = reloadTrigger
            _closePopupTrigger = closePopupTrigger
            _pauseAndRetainTrigger = pauseAndRetainTrigger
            _cancelDownloadTrigger = cancelDownloadTrigger
            _isDownloading = isDownloading
            _downloadProgress = downloadProgress
            _downloadStatusText = downloadStatusText
            _detectedVideo = detectedVideo
            _downloadDetectedVideoTrigger = downloadDetectedVideoTrigger
            self.onDownloaded = onDownloaded
        }

        func updateBindings(
            currentURLText: Binding<String>,
            requestedURL: Binding<URL?>,
            canGoBack: Binding<Bool>,
            isPageLoading: Binding<Bool>,
            pageLoadProgress: Binding<Double>,
            isPopupOpen: Binding<Bool>,
            goBackTrigger: Binding<Int>,
            stopLoadingTrigger: Binding<Int>,
            reloadTrigger: Binding<Int>,
            closePopupTrigger: Binding<Int>,
            pauseAndRetainTrigger: Binding<Int>,
            cancelDownloadTrigger: Binding<Int>,
            isDownloading: Binding<Bool>,
            downloadProgress: Binding<Double?>,
            downloadStatusText: Binding<String>,
            detectedVideo: Binding<BrowserDetectedVideo?>,
            downloadDetectedVideoTrigger: Binding<Int>
        ) {
            _currentURLText = currentURLText
            _requestedURL = requestedURL
            _canGoBack = canGoBack
            _isPageLoading = isPageLoading
            _pageLoadProgress = pageLoadProgress
            _isPopupOpen = isPopupOpen
            _goBackTrigger = goBackTrigger
            _stopLoadingTrigger = stopLoadingTrigger
            _reloadTrigger = reloadTrigger
            _closePopupTrigger = closePopupTrigger
            _pauseAndRetainTrigger = pauseAndRetainTrigger
            _cancelDownloadTrigger = cancelDownloadTrigger
            _isDownloading = isDownloading
            _downloadProgress = downloadProgress
            _downloadStatusText = downloadStatusText
            _detectedVideo = detectedVideo
            _downloadDetectedVideoTrigger = downloadDetectedVideoTrigger
        }

        func observeProgress(in webView: WKWebView) {
            progressObservation = webView.observe(
                \.estimatedProgress,
                options: [.new]
            ) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.pageLoadProgress = webView.estimatedProgress
                }
            }
        }

        func invalidateObservers() {
            progressObservation?.invalidate()
            progressObservation = nil
        }

        func handleBrowserControls(in webView: WKWebView) {
            if goBackTrigger != handledGoBackTrigger {
                handledGoBackTrigger = goBackTrigger
                if webView.canGoBack {
                    webView.goBack()
                }
            }
            if stopLoadingTrigger != handledStopLoadingTrigger {
                handledStopLoadingTrigger = stopLoadingTrigger
                webView.stopLoading()
                isPageLoading = false
                pageLoadProgress = 0
            }
            if reloadTrigger != handledReloadTrigger {
                handledReloadTrigger = reloadTrigger
                webView.reload()
            }
            if closePopupTrigger != handledClosePopupTrigger {
                handledClosePopupTrigger = closePopupTrigger
                closePopup(in: webView)
            }
            if pauseAndRetainTrigger != handledPauseAndRetainTrigger {
                handledPauseAndRetainTrigger = pauseAndRetainTrigger
                OnlineMusicBrowserSessionStore.shared.retain(
                    webView,
                    urlText: currentURLText
                )
            }
            if cancelDownloadTrigger != handledCancelDownloadTrigger {
                handledCancelDownloadTrigger = cancelDownloadTrigger
                cancelActiveDownload()
            }
            if downloadDetectedVideoTrigger
                != handledDownloadDetectedVideoTrigger {
                handledDownloadDetectedVideoTrigger =
                    downloadDetectedVideoTrigger
                if let url = detectedVideo?.downloadableURL {
                    activeDownloadKind = .video
                    isDownloading = true
                    downloadProgress = nil
                    downloadStatusText = "영상을 가져오는 중"
                    Task { @MainActor [weak self, weak webView] in
                        guard let self, let webView else { return }
                        let download = await webView.startDownload(
                            using: URLRequest(url: url)
                        )
                        self.activeDownload = download
                        download.delegate = self
                    }
                }
            }
            updateCurrentURL(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil,
                  let url = navigationAction.request.url
            else { return nil }

            if !isPopupOpen {
                popupReturnURL = webView.url
            }
            isPopupOpen = true
            currentURLText = url.absoluteString
            webView.load(navigationAction.request)
            return nil
        }

        func webViewDidClose(_ webView: WKWebView) {
            closePopup(in: webView)
        }

        private func closePopup(in webView: WKWebView) {
            guard isPopupOpen else { return }
            isPopupOpen = false
            if let popupReturnURL {
                webView.load(URLRequest(url: popupReturnURL))
                self.popupReturnURL = nil
            } else if webView.canGoBack {
                webView.goBack()
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.videoMessageName,
                  let source = message.body as? String,
                  !source.isEmpty
            else { return }
            detectedVideo = BrowserDetectedVideo(urlString: source)
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            isPageLoading = true
            pageLoadProgress = max(webView.estimatedProgress, 0.08)
            detectedVideo = nil
            updateCurrentURL(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            pageLoadProgress = 1
            isPageLoading = false
            updateCurrentURL(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            pageLoadProgress = 0
            isPageLoading = false
            updateCurrentURL(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            pageLoadProgress = 0
            isPageLoading = false
            updateCurrentURL(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            downloadStatusText = "다운로드 감지됨"
            isDownloading = true
            downloadProgress = nil
            activeDownload = download
            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            downloadStatusText = "다운로드 감지됨"
            isDownloading = true
            downloadProgress = nil
            activeDownload = download
            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url {
                currentURLText = url.absoluteString
                if let kind = Self.supportedDownloadKind(for: url),
                   #available(iOS 14.5, *) {
                    if kind == .video {
                        detectedVideo = BrowserDetectedVideo(
                            urlString: url.absoluteString
                        )
                        decisionHandler(.allow)
                        return
                    }
                    activeDownloadKind = kind
                    downloadStatusText = "음악 다운로드 감지됨"
                    isDownloading = true
                    downloadProgress = nil
                    decisionHandler(.download)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            guard let response = navigationResponse.response as? HTTPURLResponse,
                  let mimeType = response.mimeType?.lowercased(),
                  let kind = Self.supportedDownloadKind(for: mimeType)
            else {
                decisionHandler(.allow)
                return
            }

            if #available(iOS 14.5, *) {
                if kind == .video {
                    if let url = response.url {
                        detectedVideo = BrowserDetectedVideo(
                            urlString: url.absoluteString
                        )
                    }
                    decisionHandler(.allow)
                    return
                }
                activeDownloadKind = kind
                downloadStatusText = "음악 다운로드 감지됨"
                isDownloading = true
                downloadProgress = nil
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            isDownloading = true
            activeDownload = download
            downloadProgress = nil
            if let mimeType = response.mimeType?.lowercased(),
               let kind = Self.supportedDownloadKind(for: mimeType) {
                activeDownloadKind = kind
            } else if let kind = Self.supportedDownloadKind(
                for: URL(fileURLWithPath: suggestedFilename)
            ) {
                activeDownloadKind = kind
            }
            downloadStatusText = activeDownloadKind == .video
                ? "영상을 가져오는 중"
                : "음악을 가져오는 중"
            let filename = Self.safeFilename(suggestedFilename, response: response)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("HanClip-OnlineMusic-")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(filename)

            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                destinationURL = destination
                completionHandler(destination)
            } catch {
                isDownloading = false
                completionHandler(nil)
            }
        }

        func downloadDidFinish(_ download: WKDownload) {
            isDownloading = false
            downloadProgress = 1
            downloadStatusText = "음악을 가져오는 중"
            guard let destinationURL else { return }
            onDownloaded(destinationURL, activeDownloadKind)
            self.destinationURL = nil
            activeDownload = nil
        }

        func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            isDownloading = false
            downloadProgress = nil
            downloadStatusText = "다운로드 실패"
            destinationURL = nil
            activeDownload = nil
        }

        func updateCurrentURL(from webView: WKWebView) {
            if let url = webView.url {
                currentURLText = url.absoluteString
            }
            canGoBack = webView.canGoBack
        }

        private func cancelActiveDownload() {
            guard let activeDownload else {
                isDownloading = false
                downloadProgress = nil
                downloadStatusText = "다운로드 취소됨"
                return
            }
            activeDownload.cancel { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isDownloading = false
                    self?.downloadProgress = nil
                    self?.downloadStatusText = "다운로드 취소됨"
                    self?.destinationURL = nil
                    self?.activeDownload = nil
                }
            }
        }

        private static func isSupportedAudioMimeType(_ mimeType: String) -> Bool {
            [
                "audio/mpeg",
                "audio/mp3",
                "audio/wav",
                "audio/x-wav",
                "audio/aac",
                "audio/mp4",
                "audio/x-m4a"
            ].contains(mimeType)
        }

        private static func isSupportedVideoMimeType(_ mimeType: String) -> Bool {
            mimeType.hasPrefix("video/")
                && !mimeType.contains("mpegurl")
        }

        private static func supportedDownloadKind(
            for mimeType: String
        ) -> BrowserDownloadKind? {
            if isSupportedAudioMimeType(mimeType) {
                return .audio
            }
            if isSupportedVideoMimeType(mimeType) {
                return .video
            }
            return nil
        }

        private static func isSupportedAudioURL(_ url: URL) -> Bool {
            [
                "mp3",
                "m4a",
                "aac",
                "wav"
            ].contains(url.pathExtension.lowercased())
        }

        private static func supportedDownloadKind(
            for url: URL
        ) -> BrowserDownloadKind? {
            if isSupportedAudioURL(url) {
                return .audio
            }
            if ["mp4", "mov", "m4v", "webm"].contains(
                url.pathExtension.lowercased()
            ) {
                return .video
            }
            return nil
        }

        private static func safeFilename(
            _ suggestedFilename: String,
            response: URLResponse
        ) -> String {
            let fallback = response.url?.lastPathComponent ?? "online-music.mp3"
            let raw = suggestedFilename.isEmpty ? fallback : suggestedFilename
            let cleaned = raw
                .components(separatedBy: CharacterSet(charactersIn: "/:"))
                .joined(separator: "-")
            return cleaned.isEmpty ? "online-music.mp3" : cleaned
        }
    }
}

private struct TextOverlayPositionThumbnail: View {
    let position: WatermarkPosition

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let inset: CGFloat = 9
            let dotSize: CGFloat = 9
            let point = dotPoint(in: size, inset: inset)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(HanClipTheme.secondary.opacity(0.16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(HanClipTheme.secondary, lineWidth: 2)
                    }

                Circle()
                    .fill(HanClipTheme.primary)
                    .frame(width: dotSize, height: dotSize)
                    .position(point)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func dotPoint(in size: CGSize, inset: CGFloat) -> CGPoint {
        let availableWidth = max(0, size.width - inset * 2)
        let availableHeight = max(0, size.height - inset * 2)
        return CGPoint(
            x: inset + availableWidth * CGFloat(position.horizontalFraction),
            y: inset + availableHeight
                * CGFloat(position.verticalFractionFromTop)
        )
    }
}

private struct WatermarkModeSegmentedControl: View {
    @Binding var isEnabled: Bool
    var isCompact = false

    var body: some View {
        HStack(spacing: 0) {
            segmentAppearance(title: "사용", value: true)
            segmentAppearance(title: "안함", value: false)
        }
        .padding(isCompact ? 2 : 3)
        .background(
            HanClipTheme.secondary.opacity(0.14),
            in: Capsule()
        )
        .overlay {
            HStack(spacing: 0) {
                segmentHitTarget(title: "사용", value: true)
                segmentHitTarget(title: "안함", value: false)
            }
            .clipShape(Capsule())
        }
    }

    private func segmentAppearance(title: String, value: Bool) -> some View {
        Text(title)
            .font(.system(size: isCompact ? 10 : 14, weight: .bold))
            .foregroundStyle(
                isEnabled == value ? .white : HanClipTheme.secondary
            )
            .frame(maxWidth: .infinity)
            .frame(height: isCompact ? 18 : 32)
            .background {
                if isEnabled == value {
                    Capsule()
                        .fill(HanClipTheme.primary)
                }
            }
            .allowsHitTesting(false)
    }

    private func segmentHitTarget(title: String, value: Bool) -> some View {
        Button {
            withAnimation(.snappy) {
                isEnabled = value
            }
        } label: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isEnabled == value ? .isSelected : [])
    }
}

private struct WatermarkPlatformSegmentedControl: View {
    @Binding var selection: WatermarkPlatform

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WatermarkPlatform.allCases) { platform in
                Button {
                    withAnimation(.snappy) {
                        selection = platform
                    }
                } label: {
                    ZStack {
                        WatermarkPlatformLogo(platform: platform)
                            .frame(
                                width: platform == .hanclip ? 54 : 26,
                                height: 26
                            )
                    }
                    .foregroundStyle(
                        selection == platform
                            ? .white
                            : HanClipTheme.secondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        selection == platform
                            ? HanClipTheme.primary
                            : HanClipTheme.secondary.opacity(0.14),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(platform.title)
            }
        }
    }
}

private struct WatermarkPlatformLogo: View {
    let platform: WatermarkPlatform

    var body: some View {
        ZStack {
            switch platform {
            case .hanclip:
                HStack(spacing: 3) {
                    Image("LogoMarkV2")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                    Text("HanClip")
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            case .instagram:
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(lineWidth: 2)
                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .bold))
            case .facebook:
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 14, weight: .bold))
            case .youtube:
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(lineWidth: 2)
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .offset(x: 0.5)
            case .blog:
                Text("B")
                    .font(.system(size: 15, weight: .heavy))
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 5,
                            style: .continuous
                        )
                        .stroke(lineWidth: 2)
                    }
            case .kakaoTalk:
                Image("CopyrightKakaoTalk")
                    .resizable()
                    .scaledToFit()
            case .x:
                Image("CopyrightX")
                    .resizable()
                    .scaledToFit()
            case .phone:
                Image("CopyrightTelephone")
                    .resizable()
                    .scaledToFit()
            case .homepage:
                Image("CopyrightHomepage")
                    .resizable()
                    .scaledToFit()
            case .custom:
                Image("CopyrightCustom")
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}

private struct CopyrightPlatformLogo: View {
    @AppStorage(WatermarkSettings.customCopyrightIconPathStorageKey)
    private var customIconPath =
        WatermarkSettings.defaultCustomCopyrightIconPath
    let platform: WatermarkPlatform
    let iconColorMode: CopyrightIconColorMode
    let iconColorHex: String
    let shadowColorHex: String
    let shadowOpacity: Double

    private var renderingMode: Image.TemplateRenderingMode {
        .original
    }

    var body: some View {
        Group {
            if platform == .custom,
               let customIconImage {
                Image(uiImage: customIconImage)
                    .resizable()
                    .renderingMode(renderingMode)
                    .scaledToFit()
            } else if let assetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(renderingMode)
                    .scaledToFit()
            } else if platform == .hanclip {
                Image("LogoMarkV2")
                    .resizable()
                    .renderingMode(renderingMode)
                    .scaledToFit()
            } else {
                WatermarkPlatformLogo(platform: platform)
            }
        }
        .foregroundStyle(
            HanClipTheme.primary
        )
        .shadow(
            color: (Color(hexString: shadowColorHex) ?? HanClipTheme.secondary)
                .opacity(0.42 * shadowOpacity),
            radius: 10,
            x: 0,
            y: 0
        )
    }

    private var customIconImage: UIImage? {
        guard !customIconPath.isEmpty else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: customIconPath)) else {
            return nil
        }
        return UIImage(data: data)
    }

    private var assetName: String? {
        switch platform {
        case .instagram:
            return "CopyrightInstagram"
        case .facebook:
            return "CopyrightFacebook"
        case .youtube:
            return "CopyrightYouTube"
        case .blog:
            return "CopyrightBlog"
        case .kakaoTalk:
            return "CopyrightKakaoTalk"
        case .x:
            return "CopyrightX"
        case .phone:
            return "CopyrightTelephone"
        case .homepage:
            return "CopyrightHomepage"
        case .custom:
            return "CopyrightCustom"
        case .hanclip:
            return nil
        }
    }
}

private struct ThumbnailScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CalendarThumbnailItem: Identifiable {
    let id: String
    let thumbnail: UIImage
    let mediaKind: ClipMediaKind
}

private struct CalendarMediaPreviewController: UIViewControllerRepresentable {
    let assetIdentifier: String
    let sourcePoint: CGPoint
    let onDelete: () -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier],
            options: nil
        )
        guard let asset = result.firstObject else {
            return UIViewController()
        }
        return PhotoPicker.MediaAssetPreviewViewController(
            asset: asset,
            imageManager: PHCachingImageManager(),
            showsCloseButton: false,
            sourcePoint: sourcePoint,
            onDelete: onDelete,
            onDismiss: onDismiss
        )
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {}
}

private struct CalendarActionButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: 88, height: 40)
            .background {
                if #available(iOS 26.0, *) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .glassEffect(
                            .regular
                                .tint(HanClipTheme.secondary.opacity(0.12))
                                .interactive(),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.52), lineWidth: 1)
                        }
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.20))
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.52), lineWidth: 1)
                        }
                }
            }
            .shadow(
                color: HanClipTheme.secondary.opacity(0.08),
                radius: 8,
                y: 4
            )
            .contentShape(Capsule())
    }
}

private struct ClipReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var clips: [ClipItem]
    @Binding var draggedClipID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedClipID,
              draggedClipID != targetID,
              let sourceIndex = index(of: draggedClipID),
              let targetIndex = index(of: targetID)
        else { return }

        let draggedClip = clips[sourceIndex]
        let targetClip = clips[targetIndex]

        if draggedClip.isVideoSegmentChild {
            reorderChild(sourceIndex: sourceIndex, targetClip: targetClip)
            return
        }

        reorderTopLevelClip(
            draggedID: draggedClip.id,
            targetID: targetClip.id
        )
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedClipID = nil
        return true
    }

    func dropExited(info: DropInfo) {}

    private func reorderChild(sourceIndex: Int, targetClip: ClipItem) {
        guard clips[sourceIndex].isVideoSegmentChild,
              targetClip.isVideoSegmentChild,
              clips[sourceIndex].videoSegmentParentID
                  == targetClip.videoSegmentParentID,
              let targetIndex = index(of: targetClip.id)
        else { return }

        moveItems(at: [sourceIndex], to: targetIndex)
    }

    private func reorderTopLevelClip(draggedID: UUID, targetID: UUID) {
        guard let sourceUnitIndex = topLevelUnits().firstIndex(where: {
            $0.contains(draggedID)
        }) else { return }

        let targetTopLevelID = clips.first(where: { $0.id == targetID })?
            .videoSegmentParentID ?? targetID
        var units = topLevelUnits()
        guard let targetUnitIndex = units.firstIndex(where: {
            $0.contains(targetTopLevelID)
        }),
              sourceUnitIndex != targetUnitIndex
        else { return }

        let movingUnit = units.remove(at: sourceUnitIndex)
        let adjustedTargetIndex = targetUnitIndex > sourceUnitIndex
            ? targetUnitIndex - 1
            : targetUnitIndex
        let insertIndex = targetUnitIndex > sourceUnitIndex
            ? adjustedTargetIndex + 1
            : adjustedTargetIndex
        units.insert(movingUnit, at: insertIndex)

        applyTopLevelUnits(units)
    }

    private func moveItems(at indices: [Int], to targetIndex: Int) {
        let movingSet = Set(indices)
        guard !movingSet.contains(targetIndex) else { return }

        let movingItems = indices.sorted().map { clips[$0] }
        var remainingClips = clips.enumerated()
            .filter { !movingSet.contains($0.offset) }
            .map(\.element)

        guard clips.indices.contains(targetIndex) else { return }

        let targetID = clips[targetIndex].id
        guard let remainingTargetIndex = remainingClips.firstIndex(where: {
                  $0.id == targetID
              })
        else { return }

        let sourceStart = indices.min() ?? targetIndex
        let insertIndex = targetIndex > sourceStart
            ? remainingTargetIndex + 1
            : remainingTargetIndex

        withAnimation(.snappy) {
            remainingClips.insert(
                contentsOf: movingItems,
                at: min(insertIndex, remainingClips.endIndex)
            )
            clips = remainingClips
        }
    }

    private func topLevelUnits() -> [[UUID]] {
        clips
            .filter { !$0.isVideoSegmentChild }
            .filter { !$0.isSimilarPhotoGroupChild }
            .map { clip in
                if clip.isVideoSegmentParent {
                    return [clip.id] + clips
                        .filter { $0.videoSegmentParentID == clip.id }
                        .map(\.id)
                }
                if clip.isSimilarPhotoGroupParent,
                   let groupID = clip.similarPhotoGroupID {
                    return [clip.id] + clips
                        .filter {
                            $0.similarPhotoGroupID == groupID
                                && $0.id != clip.id
                        }
                        .map(\.id)
                }
                return [clip.id]
            }
    }

    private func applyTopLevelUnits(_ units: [[UUID]]) {
        let clipByID = Dictionary(uniqueKeysWithValues: clips.map {
            ($0.id, $0)
        })
        let reorderedClips = units.flatMap { unit in
            unit.compactMap { clipByID[$0] }
        }

        guard reorderedClips.count == clips.count else { return }

        withAnimation(.snappy) {
            clips = reorderedClips
        }
    }

    private func index(of id: UUID) -> Int? {
        clips.firstIndex { $0.id == id }
    }
}

private struct VideoSegmentChildOrderDropDelegate: DropDelegate {
    let targetID: UUID
    let model: EditorViewModel
    @Binding var draggedClipID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedClipID,
              draggedClipID != targetID
        else { return }

        withAnimation(.snappy) {
            model.moveVideoSegmentChild(
                draggedID: draggedClipID,
                targetID: targetID
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedClipID = nil
        return true
    }
}

private struct AspectRatioIcon: View {
    let ratio: OutputAspectRatio
    let isSelected: Bool
    var usesPrimaryShapeColor = false
    let themeModeRaw: String

    private var rectangleSize: CGSize {
        let source = ratio.renderSize
        let aspect = source.width / source.height
        let maximumWidth: CGFloat = 24
        let maximumHeight: CGFloat = 24

        if aspect >= 1 {
            return CGSize(
                width: maximumWidth,
                height: maximumWidth / aspect
            )
        }
        return CGSize(
            width: maximumHeight * aspect,
            height: maximumHeight
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isSelected
                        ? HanClipTheme.primary.opacity(0.14)
                        : Color.clear
                )

            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    isSelected || usesPrimaryShapeColor
                        ? HanClipTheme.primary
                        : HanClipTheme.secondary,
                    lineWidth: 2
                )
                .frame(
                    width: rectangleSize.width,
                    height: rectangleSize.height
                )
        }
        .frame(width: 32, height: 32)
        .id("aspect-ratio-icon-\(ratio.id)-\(themeModeRaw)")
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isSelected
                        ? HanClipTheme.primary
                        : HanClipTheme.secondary.opacity(0.72),
                    lineWidth: isSelected ? 2 : 1
                )
        }
    }
}

private struct FloppyDiskIcon: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let lineWidth = max(1.2, size * 0.08)
            let frame = CGRect(
                x: (geometry.size.width - size) / 2 + size * 0.09,
                y: (geometry.size.height - size) / 2 + size * 0.08,
                width: size * 0.82,
                height: size * 0.84
            )
            let labelWidth = size * 0.46
            let labelHeight = size * 0.24

            ZStack {
                RoundedRectangle(cornerRadius: size * 0.06)
                    .stroke(lineWidth: lineWidth)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)

                Path { path in
                    path.move(to: CGPoint(x: frame.minX + size * 0.12, y: frame.minY))
                    path.addLine(to: CGPoint(x: frame.maxX - size * 0.14, y: frame.minY))
                    path.addLine(to: CGPoint(x: frame.maxX - size * 0.14, y: frame.minY + size * 0.30))
                    path.addLine(to: CGPoint(x: frame.minX + size * 0.12, y: frame.minY + size * 0.30))
                    path.closeSubpath()
                }
                .stroke(lineWidth: lineWidth)

                Rectangle()
                    .frame(width: size * 0.10, height: size * 0.22)
                    .position(
                        x: frame.maxX - size * 0.23,
                        y: frame.minY + size * 0.15
                    )

                RoundedRectangle(cornerRadius: size * 0.025)
                    .stroke(lineWidth: lineWidth)
                    .frame(width: labelWidth, height: labelHeight)
                    .position(x: frame.midX, y: frame.maxY - size * 0.23)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct ProjectMemoField: View {
    let projectID: UUID
    let focusedMemoProjectID: FocusState<UUID?>.Binding
    let onSave: (String) -> Void

    @State private var text: String
    @State private var lastSavedText: String

    init(
        projectID: UUID,
        memo: String,
        focusedMemoProjectID: FocusState<UUID?>.Binding,
        onSave: @escaping (String) -> Void
    ) {
        self.projectID = projectID
        self.focusedMemoProjectID = focusedMemoProjectID
        self.onSave = onSave
        _text = State(initialValue: memo)
        _lastSavedText = State(initialValue: memo)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HanClipTheme.secondaryText.opacity(0.62))

            TextField(
                "",
                text: $text,
                prompt: Text("메모 추가")
                    .foregroundStyle(HanClipTheme.secondaryText.opacity(0.58))
            )
                .font(.system(size: 12))
                .foregroundStyle(HanClipTheme.primaryText)
                .focused(focusedMemoProjectID, equals: projectID)
                .submitLabel(.done)
                .onSubmit {
                    saveIfNeeded()
                    focusedMemoProjectID.wrappedValue = nil
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.panelFill.opacity(0.62),
                    HanClipTheme.secondary.opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HanClipTheme.panelStroke.opacity(0.42), lineWidth: 1)
        }
        .onChange(of: focusedMemoProjectID.wrappedValue) { _, focusedID in
            if focusedID != projectID {
                saveIfNeeded()
            }
        }
        .onDisappear {
            saveIfNeeded()
        }
        .dismissKeyboardOnDrag()
        .accessibilityLabel("영화 메모")
        .id(projectID)
    }

    private func saveIfNeeded() {
        let trimmedText = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmedText != lastSavedText else { return }
        text = trimmedText
        lastSavedText = trimmedText
        onSave(trimmedText)
    }
}

private struct SwipeToDeleteRow<Content: View>: View {
    let accessibilityLabel: String
    let cornerRadius: CGFloat
    let onDelete: () -> Void
    let content: Content

    @GestureState private var dragTranslation: CGFloat = 0

    private let actionWidth: CGFloat = 72
    private let deleteThreshold: CGFloat = 82

    init(
        accessibilityLabel: String = "영화 삭제",
        cornerRadius: CGFloat = 16,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.cornerRadius = cornerRadius
        self.onDelete = onDelete
        self.content = content()
    }

    private var visibleOffset: CGFloat {
        min(
            0,
            max(-actionWidth, dragTranslation)
        )
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .background(Color.red)
            .opacity(visibleOffset < -1 ? 1 : 0)
            .accessibilityLabel(accessibilityLabel)

            content
                .offset(x: visibleOffset)
                .allowsHitTesting(!isSwiping)
                .highPriorityGesture(swipeGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var isSwiping: Bool {
        abs(visibleOffset) > 1
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .updating($dragTranslation) { value, state, _ in
                guard isHorizontalSwipe(value),
                      value.translation.width < 0
                else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard isHorizontalSwipe(value),
                      value.translation.width < 0
                else { return }

                if value.predictedEndTranslation.width < -deleteThreshold {
                    withAnimation(.snappy) {
                        onDelete()
                    }
                }
            }
    }

    private func isHorizontalSwipe(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > abs(value.translation.height) * 1.35
    }
}

private extension OutputAspectRatio {
    var accessibilityTitle: String {
        switch self {
        case .square:
            "정방형"
        case .portrait3x4:
            "짧은 세로형"
        case .landscape4x3:
            "짧은 가로형"
        case .portrait9x16:
            "긴 세로형"
        case .landscape16x9:
            "긴 가로형"
        }
    }
}

private struct QuickMovieDurationPicker: View {
    let recommendedDuration: Double
    let mediaCount: Int
    let textSettings: WatermarkSettings
    @Binding var textEnabled: Bool
    @Binding var endingInfoEnabled: Bool
    @Binding var endingInfoDuration: Double
    let musicSettings: BackgroundMusicSettings
    @Binding var musicEnabled: Bool
    @Binding var aspectRatio: OutputAspectRatio?
    let onSelectText: () -> Void
    let onSelectEndingInfo: () -> Void
    let onSelectMusic: () -> Void
    let onAddPhoto: () -> Void
    let onAddFile: () -> Void
    let onMake: (Double?) -> Void
    let onCancel: () -> Void

    @State private var selectedDuration: Double
    @State private var usesRecommendedDuration = true
    @AppStorage("hanClipThemeMode") private var themeModeRaw =
        HanClipThemeMode.automatic.rawValue

    init(
        recommendedDuration: Double,
        mediaCount: Int,
        textSettings: WatermarkSettings,
        textEnabled: Binding<Bool>,
        endingInfoEnabled: Binding<Bool>,
        endingInfoDuration: Binding<Double>,
        musicSettings: BackgroundMusicSettings,
        musicEnabled: Binding<Bool>,
        aspectRatio: Binding<OutputAspectRatio?>,
        onSelectText: @escaping () -> Void,
        onSelectEndingInfo: @escaping () -> Void,
        onSelectMusic: @escaping () -> Void,
        onAddPhoto: @escaping () -> Void,
        onAddFile: @escaping () -> Void,
        onMake: @escaping (Double?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.recommendedDuration = max(1, recommendedDuration)
        self.mediaCount = mediaCount
        self.textSettings = textSettings
        _textEnabled = textEnabled
        _endingInfoEnabled = endingInfoEnabled
        _endingInfoDuration = endingInfoDuration
        self.musicSettings = musicSettings
        _musicEnabled = musicEnabled
        _aspectRatio = aspectRatio
        self.onSelectText = onSelectText
        self.onSelectEndingInfo = onSelectEndingInfo
        self.onSelectMusic = onSelectMusic
        self.onAddPhoto = onAddPhoto
        self.onAddFile = onAddFile
        self.onMake = onMake
        self.onCancel = onCancel
        _selectedDuration = State(initialValue: max(1, recommendedDuration))
    }

    var body: some View {
        ZStack {
            HanClipTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onCancel) {
                        HanClipHeaderActionCluster {
                            Image(systemName: "xmark")
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("취소")

                    Spacer()

                    Text("퀵모드 영상 길이")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(HanClipTheme.primaryText)

                    Spacer()

                    Menu {
                        Button(action: onAddPhoto) {
                            Label("사진", systemImage: "photo.on.rectangle")
                        }

                        Button(action: onAddFile) {
                            Label("파일", systemImage: "folder")
                        }

                    } label: {
                        HanClipHeaderActionCluster {
                            Image(systemName: "photo.badge.plus")
                        }
                    }
                    .accessibilityLabel("미디어 추가")
                }

                VStack(spacing: 16) {
                    durationStepper

                    HStack(spacing: 9) {
                        Rectangle()
                            .fill(HanClipTheme.secondary.opacity(0.18))
                            .frame(height: 1)
                        Text("시간 변경")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(HanClipTheme.secondaryText)
                            .fixedSize()
                        Rectangle()
                            .fill(HanClipTheme.secondary.opacity(0.18))
                            .frame(height: 1)
                    }

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 8),
                            count: 2
                        ),
                        spacing: 12
                    ) {
                        durationChoice("30초", seconds: 30)
                        durationChoice("45초", seconds: 45)
                        durationChoice("1분", seconds: 60)
                        durationChoice("2분", seconds: 120)
                        durationChoice("3분", seconds: 180)
                        durationChoice("5분", seconds: 300)
                        specialDurationChoice(
                            title: "추천시간",
                            duration: recommendedDuration,
                            usesDefaultDuration: true
                        )
                        specialDurationChoice(
                            title: "최소시간",
                            duration: minimumSelectableDuration,
                            usesDefaultDuration: false
                        )
                    }

                }
                .padding(.top, 24)

                Spacer(minLength: 8)

                quickSettingsGroup

                Spacer(minLength: 8)

                Button {
                    onMake(usesRecommendedDuration ? nil : selectedDuration)
                } label: {
                    Text("이 시간으로 만들기")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 93)
                        .background(HanClipTheme.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .safeAreaPadding(.top, 6)
        .safeAreaPadding(.bottom, 6)
    }

    private var quickSettingsGroup: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                TextOverlaySummaryRow(
                    settings: textSettings,
                    isEnabled: $textEnabled,
                    onSelect: onSelectText
                )
                .padding(.horizontal, 12)

                Rectangle()
                    .fill(HanClipTheme.secondary.opacity(0.16))
                    .frame(height: 0.8)

                BackgroundMusicSummaryRow(
                    settings: musicSettings,
                    isEnabled: $musicEnabled,
                    onSelect: onSelectMusic
                )
                .padding(.horizontal, 12)

                Rectangle()
                    .fill(HanClipTheme.secondary.opacity(0.16))
                    .frame(height: 0.8)

                EndingInfoSummaryRow(
                    isEnabled: $endingInfoEnabled,
                    duration: $endingInfoDuration,
                    theme: textSettings.endingInfoCardTheme,
                    onSelect: onSelectEndingInfo
                )
                .padding(.horizontal, 8)
            }
            .background(
                HanClipTheme.panelFill,
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        HanClipTheme.secondary.opacity(0.18),
                        lineWidth: 1
                    )
            }

            aspectRatioPanel
        }
    }

    private var durationStepper: some View {
        HStack(spacing: 8) {
            Button {
                usesRecommendedDuration = false
                selectedDuration = max(
                    minimumSelectableDuration,
                    selectedDuration - 5
                )
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 72, height: 51)
                    .contentShape(Rectangle())
            }
            .disabled(selectedDuration <= minimumSelectableDuration)

            VStack(spacing: 2) {
                Text("선택시간")
                    .font(.system(size: 12, weight: .bold))
                Text(durationText(selectedDuration))
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 51)

            Button {
                usesRecommendedDuration = false
                selectedDuration = min(3_600, selectedDuration + 5)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 72, height: 51)
                    .contentShape(Rectangle())
            }
        }
        .foregroundStyle(HanClipTheme.primary)
        .background(
            HanClipTheme.secondary.opacity(0.08),
            in: Capsule()
        )
        .overlay {
            Capsule().stroke(
                usesRecommendedDuration
                    ? HanClipTheme.primary.opacity(0.42)
                    : HanClipTheme.secondary.opacity(0.20),
                lineWidth: 1
            )
        }
    }

    private func durationChoice(
        _ title: String,
        seconds: Double
    ) -> some View {
        let adjustedSeconds = max(seconds, minimumSelectableDuration)
        let isSelected = !usesRecommendedDuration
            && abs(selectedDuration - adjustedSeconds) < 0.01
        let maximumMediaCount = Int(seconds * 5)
        return Button {
            usesRecommendedDuration = false
            selectedDuration = adjustedSeconds
        } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Text(
                    adjustedSeconds <= seconds
                        ? "최대 \(maximumMediaCount)개"
                        : "최소 \(durationText(adjustedSeconds))로 적용"
                )
                .font(.system(size: 10, weight: .semibold))
                .opacity(0.70)
            }
                .foregroundStyle(
                    isSelected ? Color.white : HanClipTheme.primaryText
                )
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    isSelected
                        ? HanClipTheme.primary
                        : HanClipTheme.secondary.opacity(0.08),
                    in: Capsule()
                )
        }
    }

    private var minimumSelectableDuration: Double {
        max(0.2, Double(mediaCount) * 0.2)
    }

    private func specialDurationChoice(
        title: String,
        duration: Double,
        usesDefaultDuration: Bool
    ) -> some View {
        let isSelected = usesRecommendedDuration == usesDefaultDuration
            && abs(selectedDuration - duration) < 0.01
        return Button {
            usesRecommendedDuration = usesDefaultDuration
            selectedDuration = duration
        } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Text(durationText(duration))
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.70)
            }
            .foregroundStyle(
                isSelected ? Color.white : HanClipTheme.primaryText
            )
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                isSelected
                    ? HanClipTheme.primary
                    : HanClipTheme.secondary.opacity(0.08),
                in: Capsule()
            )
        }
    }

    private func durationText(_ seconds: Double) -> String {
        if seconds < 1 {
            return String(format: "%.1f초", seconds)
        }
        let rounded = max(1, Int(seconds.rounded()))
        let minutes = rounded / 60
        let remainingSeconds = rounded % 60
        if minutes == 0 { return "\(remainingSeconds)초" }
        if remainingSeconds == 0 { return "\(minutes)분" }
        return "\(minutes)분 \(remainingSeconds)초"
    }

    @ViewBuilder
    private var aspectRatioPanel: some View {
        if #available(iOS 26.0, *) {
            quickAspectRatioButtons
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(5)
                .padding(.horizontal, 9)
                .glassEffect(
                    .regular
                        .tint(HanClipTheme.secondary.opacity(0.16))
                        .interactive(),
                    in: Capsule()
                )
                .shadow(
                    color: HanClipTheme.primary.opacity(0.10),
                    radius: 6,
                    y: 2
                )
                .id("quick-aspect-ratio-picker-\(themeModeRaw)")
        } else {
            quickAspectRatioButtons
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(5)
                .padding(.horizontal, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(
                            HanClipTheme.secondary.opacity(0.32),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: HanClipTheme.primary.opacity(0.08),
                    radius: 5,
                    y: 2
                )
                .id("quick-aspect-ratio-picker-\(themeModeRaw)")
        }
    }

    private var quickAspectRatioButtons: some View {
        GeometryReader { proxy in
            HStack(spacing: 4) {
                Button {
                    aspectRatio = nil
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                aspectRatio == nil
                                    ? HanClipTheme.primary.opacity(0.14)
                                    : Color.clear
                            )

                        Text("첫\n사진")
                            .font(.system(size: 10, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineSpacing(0)
                            .foregroundStyle(
                                aspectRatio == nil
                                    ? HanClipTheme.primary
                                    : HanClipTheme.secondary
                            )
                    }
                    .frame(width: 32, height: 32)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                aspectRatio == nil
                                    ? HanClipTheme.primary
                                    : HanClipTheme.secondary.opacity(0.72),
                                lineWidth: aspectRatio == nil ? 2 : 1
                            )
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("첫 사진 비율")
                .accessibilityAddTraits(aspectRatio == nil ? .isSelected : [])

                ForEach(OutputAspectRatio.allCases) { ratio in
                    Button {
                        aspectRatio = ratio
                    } label: {
                        AspectRatioIcon(
                            ratio: ratio,
                            isSelected: aspectRatio == ratio,
                            themeModeRaw: themeModeRaw
                        )
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ratio.accessibilityTitle)
                    .accessibilityAddTraits(
                        aspectRatio == ratio ? .isSelected : []
                    )
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        selectQuickAspectRatio(
                            at: value.location.x,
                            totalWidth: proxy.size.width
                        )
                    }
                    .onEnded { value in
                        selectQuickAspectRatio(
                            at: value.location.x,
                            totalWidth: proxy.size.width
                        )
                    }
            )
        }
        .frame(height: 32)
    }

    private func selectQuickAspectRatio(
        at horizontalPosition: CGFloat,
        totalWidth: CGFloat
    ) {
        let ratios = OutputAspectRatio.allCases
        let selectionCount = ratios.count + 1
        guard totalWidth > 0, selectionCount > 0 else { return }

        let itemWidth = totalWidth / CGFloat(selectionCount)
        let clampedPosition = min(
            max(horizontalPosition, 0),
            totalWidth - 0.001
        )
        let selectedIndex = min(
            Int(clampedPosition / itemWidth),
            selectionCount - 1
        )

        if selectedIndex == 0 {
            aspectRatio = nil
        } else {
            aspectRatio = ratios[selectedIndex - 1]
        }
    }
}

private struct VideoPreviewView: View {
    let url: URL
    let onEdit: () -> Void
    let onSaveToPhotos: (String) -> Void
    let onSaveToFiles: () -> Void

    @State private var player: AVPlayer
    @State private var isSharePresented = false
    @State private var isFullscreenPreviewPresented = false
    @State private var showSaveOptions = false
    @AppStorage("hanClipPhotoAlbumName")
    private var albumName = "HanClip"

    init(
        url: URL,
        onEdit: @escaping () -> Void,
        onSaveToPhotos: @escaping (String) -> Void,
        onSaveToFiles: @escaping () -> Void
    ) {
        self.url = url
        self.onEdit = onEdit
        self.onSaveToPhotos = onSaveToPhotos
        self.onSaveToFiles = onSaveToFiles
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HanClipTopHeader(
                    logoAccessibilityLabel: "다시 편집",
                    logoAction: {
                        onEdit()
                    }
                ) {
                    HanClipHeaderActionCluster {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("다시 편집")
                    }
                }

                HanClipTitleLine(
                    "시사회",
                    systemImage: "play.rectangle.fill",
                    leadingInset: 18,
                    trailingInset: 20
                )
                .padding(.top, 2)
                .padding(.bottom, -4)

                Spacer(minLength: 0)

                previewContent

                Spacer(minLength: 0)
            }
            .safeAreaPadding(.top, 6)
            .safeAreaPadding(.bottom, 8)
            .background(HanClipTheme.backgroundGradient.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(
                HanClipTheme.background.opacity(0.18),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .blur(radius: 0)
        .animation(
            .easeInOut(duration: 0.10),
            value: showSaveOptions
        )
        .overlay {
            if showSaveOptions {
                saveOptionsOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .background(HanClipTheme.backgroundGradient.ignoresSafeArea())
        .onAppear {
            HanClipAudioSession.activatePlayback()
            player.seek(to: .zero)
            player.play()
        }
        .onDisappear {
            hideSaveOptionsImmediately()
            player.pause()
        }
        .fullScreenCover(
            isPresented: $isSharePresented,
            onDismiss: {
                HanClipAudioSession.activatePlayback()
                player.play()
            }
        ) {
            VideoShareSheet(items: [url])
        }
        .fullScreenCover(
            isPresented: $isFullscreenPreviewPresented,
            onDismiss: {
                HanClipAudioSession.activatePlayback()
                player.play()
            }
        ) {
            FullscreenVideoPreview(
                url: url,
                startTime: player.currentTime(),
                onClose: {
                    isFullscreenPreviewPresented = false
                }
            )
        }
    }

    private var previewContent: some View {
        VStack(spacing: 12) {
            ZStack {
                PreviewPlayerSurface(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        HanClipTheme.secondary.opacity(0.02)
                    )

                Button {
                    togglePreviewPlayback()
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("시사회 재생 또는 일시정지")

                VStack {
                    HStack {
                        Spacer()

                        Button {
                            player.pause()
                            isFullscreenPreviewPresented = true
                        } label: {
                            Image(
                                systemName:
                                    "arrow.up.left.and.arrow.down.right"
                            )
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(HanClipTheme.primaryText)
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                            .background(
                                HanClipTheme.background.opacity(0.30),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white.opacity(0.38),
                                        lineWidth: 1
                                    )
                            }
                            .shadow(
                                color: HanClipTheme.secondary.opacity(0.12),
                                radius: 10,
                                y: 5
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("시사회 전체 화면")
                    }

                    Spacer()
                }
                .padding(12)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.38), lineWidth: 1)
            }
            .shadow(
                color: HanClipTheme.secondary.opacity(0.10),
                radius: 16,
                y: 8
            )
            .padding(.horizontal, 18)

            PersistentVideoProgressBar(player: player)

            HStack(spacing: 12) {
                Button {
                    onEdit()
                } label: {
                    Label("다시 편집", systemImage: "chevron.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HanClipTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            HanClipTheme.secondary.opacity(0.10),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)

                Button {
                    player.pause()
                    isSharePresented = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(HanClipTheme.primaryText)
                        .frame(width: 54, height: 48)
                        .background(
                            HanClipTheme.secondary.opacity(0.10),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("공유하기")
                .accessibilityHint(
                    "완성된 영상 파일을 다른 앱으로 공유합니다."
                )

                Button {
                    player.pause()
                    withAnimation(.snappy) {
                        showSaveOptions = true
                    }
                } label: {
                    Label("개봉하기", systemImage: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            LinearGradient(
                                colors: [
                                    HanClipTheme.primary,
                                    HanClipTheme.secondary.opacity(0.82)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
        }
    }

    private var saveOptionsOverlay: some View {
        ZStack {
            HanClipTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HanClipTopHeader(
                    logoAccessibilityLabel: "개봉 위치 설정 취소",
                    logoAction: {
                        returnToPreviewFromSaveOptions()
                    }
                ) {
                    HanClipHeaderActionCluster {
                        Button {
                            returnToPreviewFromSaveOptions()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("취소")
                    }
                }

                HanClipTitleLine(
                    "개봉",
                    systemImage: "square.and.arrow.down.fill",
                    leadingInset: 18,
                    trailingInset: 18
                )
                .padding(.top, 8)

                Spacer(minLength: 42)

                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        Button {
                            hideSaveOptionsImmediately()
                            onSaveToPhotos(albumName)
                        } label: {
                            Label(
                                "사진 앱으로 개봉",
                                systemImage: "photo.on.rectangle"
                            )
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: [
                                        HanClipTheme.primary,
                                        HanClipTheme.secondary.opacity(0.82)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Capsule()
                            )
                            .shadow(
                                color: HanClipTheme.primary.opacity(0.22),
                                radius: 14,
                                y: 7
                            )
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 10) {
                            Text("앨범")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(HanClipTheme.secondaryText)

                            TextField("앨범명", text: $albumName)
                                .font(.system(size: 15, weight: .medium))
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(
                                    HanClipTheme.background.opacity(0.28),
                                    in: RoundedRectangle(
                                        cornerRadius: 16,
                                        style: .continuous
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius: 16,
                                        style: .continuous
                                    )
                                    .stroke(
                                        HanClipTheme.primary.opacity(0.14),
                                        lineWidth: 1
                                    )
                                }
                        }
                    }
                    .padding(14)
                    .background(
                        LinearGradient(
                            colors: [
                                HanClipTheme.primary.opacity(0.075),
                                HanClipTheme.background.opacity(0.34),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                HanClipTheme.primary.opacity(0.16),
                                lineWidth: 1
                            )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            hideSaveOptionsImmediately()
                            onSaveToFiles()
                        } label: {
                            Label(
                                "파일 앱으로 개봉",
                                systemImage: "folder"
                            )
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(HanClipTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                LinearGradient(
                                    colors: [
                                        HanClipTheme.background.opacity(0.38),
                                        HanClipTheme.secondary.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        HanClipTheme.secondary.opacity(0.20),
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)

                    }
                    .frame(minHeight: 84, alignment: .center)
                    .padding(14)
                    .background(
                        LinearGradient(
                            colors: [
                                HanClipTheme.secondary.opacity(0.07),
                                HanClipTheme.background.opacity(0.26),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                HanClipTheme.secondary.opacity(0.12),
                                lineWidth: 1
                            )
                    }
                }
                .padding(22)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                )
                .background(
                    LinearGradient(
                        colors: [
                            HanClipTheme.panelFill.opacity(0.90),
                            HanClipTheme.background.opacity(0.30),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(
                            Color.white.opacity(0.52),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: HanClipTheme.primary.opacity(0.12),
                    radius: 26,
                    y: 14
                )

                Spacer(minLength: 24)

                Button(role: .cancel) {
                    returnToPreviewFromSaveOptions()
                } label: {
                    Label("취소", systemImage: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(HanClipTheme.secondaryText)
                        .frame(width: 146, height: 48)
                        .background(
                            .ultraThinMaterial,
                            in: Capsule()
                        )
                        .background(
                            HanClipTheme.secondary.opacity(0.10),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    HanClipTheme.secondary.opacity(0.18),
                                    lineWidth: 1
                                )
                        }
                        .shadow(
                            color: HanClipTheme.secondary.opacity(0.08),
                            radius: 10,
                            y: 5
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 18)
            }
            .padding(.horizontal, 22)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.height > 60 {
                        returnToPreviewFromSaveOptions()
                    }
                }
        )
        .dismissKeyboardOnDrag()
    }

    private func togglePreviewPlayback() {
        if player.timeControlStatus == .playing {
            player.pause()
            return
        }

        if let duration = player.currentItem?.duration.seconds,
           duration.isFinite,
           player.currentTime().seconds >= duration - 0.05 {
            player.seek(to: .zero)
        }
        HanClipAudioSession.activatePlayback()
        player.play()
    }

    private func hideSaveOptionsImmediately() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showSaveOptions = false
        }
    }

    private func returnToPreviewFromSaveOptions() {
        withAnimation(.snappy) {
            showSaveOptions = false
        }
        HanClipAudioSession.activatePlayback()
        player.play()
    }
}

private struct FullscreenVideoPreview: View {
    let url: URL
    let startTime: CMTime
    let onClose: () -> Void

    @State private var player: AVPlayer
    @State private var loopObserver: NSObjectProtocol?
    @State private var orientationObserver: NSObjectProtocol?
    @State private var deviceOrientation = UIDeviceOrientation.portrait
    @State private var isPlaybackControlVisible = false
    @State private var isAspectFill = true
    @State private var isPlaying = true
    @State private var isLooping = true
    @State private var playbackControlHideTask: Task<Void, Never>?

    init(
        url: URL,
        startTime: CMTime,
        onClose: @escaping () -> Void
    ) {
        self.url = url
        self.startTime = startTime
        self.onClose = onClose
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                let displaySize = fullscreenDisplaySize(for: proxy.size)

                fullscreenPlayer(in: displaySize)
                    .frame(
                        width: displaySize.width,
                        height: displaySize.height
                    )
                    .rotationEffect(.degrees(displayRotationDegrees))
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height / 2
                    )
            }
            .ignoresSafeArea()

            Button {
                toggleFullscreenPlayback()
            } label: {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ignoresSafeArea()
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        revealPlaybackControls()
                    }
            )
            .accessibilityLabel(
                isPlaybackControlVisible ? "전체 화면 재생" : "전체 화면 일시정지"
            )

            if isPlaybackControlVisible {
                if usesLandscapeLayout {
                    GeometryReader { proxy in
                        playbackControls
                            .frame(width: max(proxy.size.height - 108, 260))
                            .rotationEffect(.degrees(displayRotationDegrees))
                            .position(
                                x: displayRotationDegrees > 0
                                    ? 30
                                    : proxy.size.width - 30,
                                y: proxy.size.height / 2
                            )
                    }
                    .ignoresSafeArea()
                } else {
                    VStack {
                        Spacer()

                        playbackControls
                            .padding(.horizontal, 18)
                            .padding(.bottom, 24)
                    }
                }
            }

            GeometryReader { proxy in
                let displaySize = fullscreenDisplaySize(for: proxy.size)

                fullscreenMiniProgressLine(in: displaySize)
                    .frame(
                        width: displaySize.width,
                        height: displaySize.height
                    )
                    .rotationEffect(.degrees(displayRotationDegrees))
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height / 2
                    )
            }
            .ignoresSafeArea()

            Button {
                player.pause()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.trailing, 18)
            .accessibilityLabel("전체 화면 닫기")
        }
        .onAppear {
            HanClipAudioSession.activatePlayback()
            installOrientationObserverIfNeeded()
            updateVideoOrientation()
            installLoopObserverIfNeeded()
            isPlaybackControlVisible = true
            player.seek(
                to: startTime,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            player.play()
            isPlaying = true
            schedulePlaybackControlHide()
        }
        .onDisappear {
            playbackControlHideTask?.cancel()
            removeOrientationObserver()
            removeLoopObserver()
            player.pause()
        }
    }

    private func fullscreenDisplaySize(for viewportSize: CGSize) -> CGSize {
        guard usesLandscapeLayout else { return viewportSize }
        return CGSize(
            width: viewportSize.height,
            height: viewportSize.width
        )
    }

    private func fullscreenPlayer(in size: CGSize) -> some View {
        PreviewPlayerSurface(
            player: player,
            videoGravity: usesLandscapeLayout && isAspectFill
                ? .resizeAspectFill
                : .resizeAspect
        )
            .frame(width: size.width, height: size.height)
    }

    private func fullscreenMiniProgressLine(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            FullscreenVideoMiniProgressLine(player: player)
                .frame(width: size.width, height: 2)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
    }

    private var playbackControls: some View {
        HStack(spacing: 10) {
            FullscreenVideoProgressBar(player: player)

            Button(action: toggleFullscreenPlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "일시정지" : "재생")

            Button {
                isLooping.toggle()
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isLooping ? .white : .white.opacity(0.46))
                    .frame(width: 44, height: 44)
                    .background(
                        isLooping
                            ? Color.white.opacity(0.18)
                            : Color.clear,
                        in: Circle()
                    )
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(
                                Color.white.opacity(isLooping ? 0.5 : 0.2),
                                lineWidth: 1
                            )
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLooping ? "반복 재생 끄기" : "반복 재생 켜기")

            if usesLandscapeLayout {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isAspectFill.toggle()
                    }
                } label: {
                    Image(
                        systemName: isAspectFill
                            ? "rectangle.arrowtriangle.2.inward"
                            : "rectangle.arrowtriangle.2.outward"
                    )
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isAspectFill ? "화면에 맞추기" : "화면 채우기"
                )
            }
        }
        .transition(.opacity)
    }

    private func toggleFullscreenPlayback() {
        if player.timeControlStatus == .playing {
            playbackControlHideTask?.cancel()
            player.pause()
            isPlaying = false
            withAnimation(.easeInOut(duration: 0.24)) {
                isPlaybackControlVisible = true
            }
        } else {
            if let duration = player.currentItem?.duration,
               player.currentTime() >= duration {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            HanClipAudioSession.activatePlayback()
            player.play()
            isPlaying = true
            isPlaybackControlVisible = true
            schedulePlaybackControlHide()
        }
    }

    private func schedulePlaybackControlHide() {
        playbackControlHideTask?.cancel()
        playbackControlHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled,
                  player.timeControlStatus == .playing
            else { return }
            withAnimation(.easeOut(duration: 0.7)) {
                isPlaybackControlVisible = false
            }
        }
    }

    private func revealPlaybackControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPlaybackControlVisible = true
        }
        if player.timeControlStatus == .playing {
            schedulePlaybackControlHide()
        }
    }

    private func installLoopObserverIfNeeded() {
        guard loopObserver == nil else { return }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if isLooping {
                    player.seek(
                        to: .zero,
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )
                    player.play()
                    isPlaying = true
                } else {
                    playbackControlHideTask?.cancel()
                    isPlaying = false
                    withAnimation(.easeInOut(duration: 0.24)) {
                        isPlaybackControlVisible = true
                    }
                }
            }
        }
    }

    private func removeLoopObserver() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
    }

    private var usesLandscapeLayout: Bool {
        UIDevice.current.userInterfaceIdiom != .pad
            && deviceOrientation.isLandscape
    }

    private var displayRotationDegrees: Double {
        guard usesLandscapeLayout else { return 0 }
        if deviceOrientation == .landscapeRight {
            return -90
        }
        return 90
    }

    private func installOrientationObserverIfNeeded() {
        guard orientationObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        updateDeviceOrientation(UIDevice.current.orientation)
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            updateDeviceOrientation(UIDevice.current.orientation)
        }
    }

    private func removeOrientationObserver() {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
            self.orientationObserver = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func updateDeviceOrientation(_ orientation: UIDeviceOrientation) {
        guard orientation == .portrait
                || orientation == .portraitUpsideDown
                || orientation.isLandscape
        else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            deviceOrientation = orientation
        }
    }

    private func updateVideoOrientation() {
        Task {
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(
                withMediaType: .video
            ).first,
                  let naturalSize = try? await track.load(.naturalSize),
                  let preferredTransform = try? await track.load(
                    .preferredTransform
                  )
            else { return }

            let orientedRect = CGRect(
                origin: .zero,
                size: naturalSize
            )
            .applying(preferredTransform)
            let orientedSize = CGSize(
                width: abs(orientedRect.width),
                height: abs(orientedRect.height)
            )

            await MainActor.run {
                isAspectFill = orientedSize.width > orientedSize.height
            }
        }
    }
}

private struct FullscreenVideoProgressBar: View {
    let player: AVPlayer

    @State private var currentSeconds = 0.0
    @State private var durationSeconds = 0.0
    @State private var timeObserver: Any?

    var body: some View {
        HStack(spacing: 10) {
            Text(formattedTime(currentSeconds))
                .frame(width: 42, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { min(currentSeconds, sliderMaximum) },
                    set: { seek(to: $0) }
                ),
                in: 0...sliderMaximum
            )
            .tint(.white)

            Text(formattedTime(durationSeconds))
                .frame(width: 42, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        }
        .onAppear(perform: startObserving)
        .onDisappear(perform: stopObserving)
        .accessibilityElement(children: .contain)
    }

    private var sliderMaximum: Double {
        max(durationSeconds, 0.1)
    }

    private func seek(to seconds: Double) {
        currentSeconds = min(max(seconds, 0), sliderMaximum)
        player.seek(
            to: CMTime(seconds: currentSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func startObserving() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { time in
            let seconds = time.seconds
            if seconds.isFinite {
                currentSeconds = max(0, seconds)
            }
            if let duration = player.currentItem?.duration.seconds,
               duration.isFinite,
               duration > 0 {
                durationSeconds = duration
            }
        }
    }

    private func stopObserving() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        return String(
            format: "%d:%02d",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }
}

private struct FullscreenVideoMiniProgressLine: View {
    let player: AVPlayer

    @State private var currentSeconds = 0.0
    @State private var durationSeconds = 0.0
    @State private var timeObserver: Any?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.22))

                Rectangle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .onAppear(perform: startObserving)
        .onDisappear(perform: stopObserving)
        .accessibilityHidden(true)
    }

    private var progress: CGFloat {
        guard durationSeconds > 0 else { return 0 }
        return CGFloat(min(1, max(0, currentSeconds / durationSeconds)))
    }

    private func startObserving() {
        guard timeObserver == nil else { return }
        if let duration = player.currentItem?.duration.seconds,
           duration.isFinite,
           duration > 0 {
            durationSeconds = duration
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { time in
            let seconds = time.seconds
            if seconds.isFinite {
                currentSeconds = max(0, seconds)
            }
            if let duration = player.currentItem?.duration.seconds,
               duration.isFinite,
               duration > 0 {
                durationSeconds = duration
            }
        }
    }

    private func stopObserving() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}

private struct PreviewPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PreviewPlayerSurfaceView {
        let view = PreviewPlayerSurfaceView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        view.setBackgroundColor(
            HanClipTheme.secondaryUIColor.withAlphaComponent(0.02)
        )
        return view
    }

    func updateUIView(
        _ uiView: PreviewPlayerSurfaceView,
        context: Context
    ) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = videoGravity
        uiView.setBackgroundColor(
            HanClipTheme.secondaryUIColor.withAlphaComponent(0.02)
        )
    }
}

private final class PreviewPlayerSurfaceView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspect
    }

    func setBackgroundColor(_ color: UIColor) {
        backgroundColor = color
        playerLayer.backgroundColor = color.cgColor
    }
}

private struct VideoShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

private struct PersistentVideoProgressBar: View {
    let player: AVPlayer

    @State private var currentSeconds = 0.0
    @State private var durationSeconds = 0.0
    @State private var isScrubbing = false
    @State private var isPlaying = false
    @State private var reachedEnd = false
    @State private var isLooping = false
    @State private var loopIconRotation = 0.0
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        HStack(spacing: 10) {
            Button(action: togglePlayback) {
                Image(systemName: playbackButtonImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(HanClipTheme.primary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playbackButtonLabel)

            Text(formattedTime(currentSeconds))
                .frame(width: 46, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { min(currentSeconds, sliderMaximum) },
                    set: { seekFromSlider(to: $0) }
                ),
                in: 0...sliderMaximum,
                onEditingChanged: scrubberChanged
            )
            .tint(HanClipTheme.primary)
            .frame(minHeight: 32)

            Text(formattedTime(durationSeconds))
                .frame(width: 46, alignment: .leading)

            loopPlaybackButton
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(HanClipTheme.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .background(
            HanClipTheme.secondary.opacity(0.055),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
        }
        .shadow(
            color: HanClipTheme.secondary.opacity(0.07),
            radius: 8,
            y: 4
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .onAppear(perform: startObserving)
        .onDisappear(perform: stopObserving)
        .onChange(of: isLooping) { _, newValue in
            updateLoopIconAnimation(newValue)
        }
        .accessibilityElement(children: .contain)
    }

    private var sliderMaximum: Double {
        max(durationSeconds, 0.1)
    }

    private var playbackButtonImage: String {
        if reachedEnd {
            return "arrow.counterclockwise"
        }
        return isPlaying ? "pause.fill" : "play.fill"
    }

    private var playbackButtonLabel: String {
        if reachedEnd {
            return "처음부터 다시 재생"
        }
        return isPlaying ? "일시정지" : "재생"
    }

    private var loopPlaybackButton: some View {
        Button(action: toggleLooping) {
            Image(systemName: isLooping ? "arrow.triangle.2.circlepath" : "repeat")
                .font(.system(size: 14, weight: .semibold))
                .rotationEffect(.degrees(isLooping ? loopIconRotation : 0))
                .foregroundStyle(
                    isLooping
                        ? Color.white
                        : HanClipTheme.primary.opacity(0.72)
                )
                .frame(width: 32, height: 32)
                .background(
                    isLooping
                        ? HanClipTheme.primary.opacity(0.92)
                        : HanClipTheme.secondary.opacity(0.11),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            isLooping
                                ? Color.white.opacity(0.30)
                                : HanClipTheme.primary.opacity(0.18),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLooping ? "반복 재생 끄기" : "반복 재생 켜기")
    }

    private func togglePlayback() {
        if reachedEnd
            || (
                durationSeconds > 0
                && currentSeconds >= durationSeconds - 0.05
            ) {
            currentSeconds = 0
            reachedEnd = false
            player.seek(to: .zero)
            player.play()
            isPlaying = true
        } else if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func toggleLooping() {
        isLooping.toggle()
        reachedEnd = false
        if isLooping {
            if durationSeconds > 0,
               currentSeconds >= durationSeconds - 0.05 {
                currentSeconds = 0
                player.seek(to: .zero)
            }
            player.play()
            isPlaying = true
        }
    }

    private func updateLoopIconAnimation(_ looping: Bool) {
        if looping {
            loopIconRotation = 0
            withAnimation(
                .linear(duration: 1.0)
                    .repeatForever(autoreverses: false)
            ) {
                loopIconRotation = 360
            }
        } else {
            withAnimation(.linear(duration: 0.12)) {
                loopIconRotation = 0
            }
        }
    }

    private func scrubberChanged(_ editing: Bool) {
        isScrubbing = editing
        guard !editing else { return }

        seek(to: currentSeconds)
    }

    private func seekFromSlider(to seconds: Double) {
        currentSeconds = min(max(seconds, 0), sliderMaximum)
        reachedEnd = false
        seek(to: currentSeconds)
    }

    private func seek(to seconds: Double) {
        reachedEnd = durationSeconds > 0
            && seconds >= durationSeconds - 0.05
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func startObserving() {
        guard timeObserver == nil else { return }

        isPlaying = player.timeControlStatus == .playing
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { time in
            if !isScrubbing {
                let seconds = time.seconds
                if seconds.isFinite {
                    currentSeconds = max(seconds, 0)
                }
            }

            if let itemDuration = player.currentItem?.duration.seconds,
               itemDuration.isFinite,
               itemDuration > 0 {
                durationSeconds = itemDuration
            }

            isPlaying = player.timeControlStatus == .playing
            if durationSeconds > 0,
               currentSeconds >= durationSeconds - 0.05 {
                if isLooping {
                    reachedEnd = false
                } else {
                    reachedEnd = true
                    isPlaying = false
                }
            } else if currentSeconds < durationSeconds - 0.05 {
                reachedEnd = false
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            if isLooping {
                currentSeconds = 0
                reachedEnd = false
                player.seek(to: .zero)
                player.play()
                isPlaying = true
            } else {
                currentSeconds = durationSeconds
                reachedEnd = true
                isPlaying = false
            }
        }
    }

    private func stopObserving() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        isLooping = false
        loopIconRotation = 0
    }

    private func formattedTime(_ seconds: Double) -> String {
        let tenths = max(Int((seconds * 10).rounded()), 0)
        let minutes = tenths / 600
        let remainingSeconds = Double(tenths % 600) / 10
        return String(
            format: "%d:%04.1f",
            minutes,
            remainingSeconds
        )
    }
}

private enum CollectionPlayerDragAxis {
    case horizontal
    case vertical
}

private struct CollectionMoviePlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let movie: CollectedMovie
    let url: URL
    @State private var player: AVPlayer
    @State private var deviceOrientation = UIDeviceOrientation.portrait
    @State private var orientationObserver: NSObjectProtocol?
    @State private var timeObserver: Any?
    @State private var isPlaying = true
    @State private var playerDragAxis: CollectionPlayerDragAxis?
    @State private var dragStartSeconds = 0.0
    @State private var dragPreviewSeconds: Double?
    @State private var downwardDragOffset = 0.0
    @State private var arePlayerControlsVisible = true
    @State private var playerControlsHideTask: Task<Void, Never>?
    @State private var playerZoomScale = 1.0
    @State private var playerZoomStartScale = 1.0
    @State private var playerZoomOffset = CGSize.zero
    @State private var playerZoomStartOffset = CGSize.zero
    @State private var isPlayerMagnifying = false

    init(movie: CollectedMovie, url: URL) {
        self.movie = movie
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        GeometryReader { proxy in
            let displaySize = collectionDisplaySize(for: proxy.size)
            let topPadding = collectionPlayerTopPadding(
                geometrySafeArea: proxy.safeAreaInsets
            )

            collectionPlayerContent(topPadding: topPadding)
                .frame(width: displaySize.width, height: displaySize.height)
                .rotationEffect(.degrees(displayRotationDegrees))
                .contentShape(Rectangle())
                .simultaneousGesture(
                    collectionMagnificationGesture(viewportSize: displaySize)
                )
                .simultaneousGesture(
                    collectionZoomPanGesture(viewportSize: displaySize)
                )
                .simultaneousGesture(collectionZoomResetGesture)
                .position(
                    x: proxy.size.width / 2,
                    y: proxy.size.height / 2
                )
                .offset(y: downwardDragOffset)
                .opacity(dismissDragOpacity(for: proxy.size.height))
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            HanClipAudioSession.activatePlayback()
            installOrientationObserver()
            installPlaybackObserver()
            player.play()
            isPlaying = true
            showPlayerControlsTemporarily()
        }
        .onDisappear {
            playerControlsHideTask?.cancel()
            player.pause()
            removePlaybackObserver()
            removeOrientationObserver()
        }
    }

    private func collectionPlayerContent(topPadding: CGFloat) -> some View {
        ZStack {
            Color.black

            GeometryReader { proxy in
                PreviewPlayerSurface(player: player, videoGravity: .resizeAspect)
                    .scaleEffect(playerZoomScale)
                    .offset(playerZoomOffset)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        togglePlayerControlsVisibility()
                    }
                    .simultaneousGesture(
                        collectionPlaybackGesture(viewportSize: proxy.size)
                    )
            }
            .clipped()

            if let dragPreviewSeconds {
                Text(collectionPlaybackTime(dragPreviewSeconds))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    playerCircleButton(
                        systemImage: "xmark",
                        accessibilityLabel: "컬렉션 닫기"
                    ) {
                        dismiss()
                    }

                    Text(movie.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    ShareLink(item: url) {
                        playerCircleLabel(systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("컬렉션 영화 공유")
                }
                .padding(.horizontal, 18)
                .padding(.top, topPadding)

                Spacer(minLength: 16)

                HStack(spacing: 10) {
                    FullscreenVideoProgressBar(player: player)

                    playerCircleButton(
                        systemImage: isPlaying ? "pause.fill" : "play.fill",
                        accessibilityLabel: isPlaying ? "일시정지" : "재생"
                    ) {
                        togglePlayback()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .opacity(arePlayerControlsVisible ? 1 : 0)
            .allowsHitTesting(arePlayerControlsVisible)
            .animation(
                .easeInOut(duration: 0.20),
                value: arePlayerControlsVisible
            )
        }
    }

    private func collectionPlayerTopPadding(
        geometrySafeArea: EdgeInsets
    ) -> CGFloat {
        guard !usesManualLandscapeRotation else { return 18 }
        let windowTopInset = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
        return max(18, max(geometrySafeArea.top, windowTopInset) + 8)
    }

    private func playerCircleButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            playerCircleLabel(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func playerCircleLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle().stroke(Color.white.opacity(0.28), lineWidth: 1)
            }
    }

    private func collectionDisplaySize(for viewportSize: CGSize) -> CGSize {
        guard usesManualLandscapeRotation else { return viewportSize }
        return CGSize(width: viewportSize.height, height: viewportSize.width)
    }

    private var displayRotationDegrees: Double {
        guard usesManualLandscapeRotation else { return 0 }
        return deviceOrientation == .landscapeRight ? -90 : 90
    }

    private var usesManualLandscapeRotation: Bool {
        UIDevice.current.userInterfaceIdiom != .pad
            && deviceOrientation.isLandscape
    }

    private func togglePlayback() {
        showPlayerControlsTemporarily()
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            if let duration = player.currentItem?.duration,
               player.currentTime() >= duration {
                player.seek(to: .zero)
            }
            HanClipAudioSession.activatePlayback()
            player.play()
            isPlaying = true
        }
    }

    private func collectionPlaybackGesture(
        viewportSize: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard !isPlayerMagnifying,
                      playerZoomScale <= 1.01
                else { return }
                let translation = collectionScreenTranslation(
                    value.translation
                )
                if playerDragAxis == nil {
                    playerControlsHideTask?.cancel()
                    let horizontalDistance = abs(translation.width)
                    let verticalDistance = abs(translation.height)
                    playerDragAxis = horizontalDistance >= verticalDistance
                        ? .horizontal
                        : .vertical
                    dragStartSeconds = player.currentTime().seconds.isFinite
                        ? max(player.currentTime().seconds, 0)
                        : 0
                }

                switch playerDragAxis {
                case .horizontal:
                    guard let duration = player.currentItem?.duration.seconds,
                          duration.isFinite,
                          duration > 0
                    else { return }
                    let width = max(viewportSize.width, 1)
                    let delta = Double(translation.width / width) * duration
                    let target = min(max(dragStartSeconds + delta, 0), duration)
                    dragPreviewSeconds = target
                    player.seek(
                        to: CMTime(seconds: target, preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )

                case .vertical:
                    downwardDragOffset = max(translation.height, 0)

                case nil:
                    break
                }
            }
            .onEnded { value in
                guard !isPlayerMagnifying,
                      playerZoomScale <= 1.01
                else {
                    playerDragAxis = nil
                    dragPreviewSeconds = nil
                    downwardDragOffset = 0
                    return
                }
                let translation = collectionScreenTranslation(
                    value.translation
                )
                let shouldDismiss = playerDragAxis == .vertical
                    && translation.height
                        > max(55, viewportSize.height * 0.08)

                playerDragAxis = nil
                dragPreviewSeconds = nil

                if shouldDismiss {
                    player.pause()
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        downwardDragOffset = 0
                    }
                    showPlayerControlsTemporarily()
                }
            }
    }

    private func collectionMagnificationGesture(
        viewportSize: CGSize
    ) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.001)
            .onChanged { value in
                isPlayerMagnifying = true
                playerControlsHideTask?.cancel()
                playerDragAxis = nil
                dragPreviewSeconds = nil
                downwardDragOffset = 0
                playerZoomScale = min(
                    max(playerZoomStartScale * value.magnification, 1),
                    4
                )
                playerZoomOffset = clampedPlayerZoomOffset(
                    playerZoomOffset,
                    scale: playerZoomScale,
                    viewportSize: viewportSize
                )
            }
            .onEnded { value in
                let finalScale = min(
                    max(playerZoomStartScale * value.magnification, 1),
                    4
                )
                if finalScale < 1.04 {
                    resetPlayerZoom(animated: true)
                } else {
                    playerZoomScale = finalScale
                    playerZoomStartScale = finalScale
                    playerZoomOffset = clampedPlayerZoomOffset(
                        playerZoomOffset,
                        scale: finalScale,
                        viewportSize: viewportSize
                    )
                    playerZoomStartOffset = playerZoomOffset
                }
                isPlayerMagnifying = false
                showPlayerControlsTemporarily()
            }
    }

    private func collectionZoomPanGesture(
        viewportSize: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                guard playerZoomScale > 1.01
                else { return }
                let translation = collectionScreenTranslation(
                    value.translation
                )
                let proposedOffset = CGSize(
                    width: playerZoomStartOffset.width + translation.width,
                    height: playerZoomStartOffset.height + translation.height
                )
                playerZoomOffset = clampedPlayerZoomOffset(
                    proposedOffset,
                    scale: playerZoomScale,
                    viewportSize: viewportSize
                )
            }
            .onEnded { _ in
                guard playerZoomScale > 1.01 else { return }
                playerZoomStartOffset = playerZoomOffset
            }
    }

    private var collectionZoomResetGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                guard playerZoomScale > 1.01 else { return }
                resetPlayerZoom(animated: true)
                showPlayerControlsTemporarily()
            }
    }

    private func clampedPlayerZoomOffset(
        _ offset: CGSize,
        scale: Double,
        viewportSize: CGSize
    ) -> CGSize {
        let extraScale = max(scale - 1, 0)
        let maximumX = viewportSize.width * extraScale / 2
        let maximumY = viewportSize.height * extraScale / 2
        return CGSize(
            width: min(max(offset.width, -maximumX), maximumX),
            height: min(max(offset.height, -maximumY), maximumY)
        )
    }

    private func resetPlayerZoom(animated: Bool) {
        let changes = {
            playerZoomScale = 1
            playerZoomStartScale = 1
            playerZoomOffset = .zero
            playerZoomStartOffset = .zero
            isPlayerMagnifying = false
        }
        if animated {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                changes()
            }
        } else {
            changes()
        }
    }

    private func togglePlayerControlsVisibility() {
        if arePlayerControlsVisible {
            playerControlsHideTask?.cancel()
            withAnimation(.easeInOut(duration: 0.20)) {
                arePlayerControlsVisible = false
            }
        } else {
            showPlayerControlsTemporarily()
        }
    }

    private func showPlayerControlsTemporarily() {
        playerControlsHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.20)) {
            arePlayerControlsVisible = true
        }
        playerControlsHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled,
                  playerDragAxis == nil
            else { return }
            withAnimation(.easeInOut(duration: 0.20)) {
                arePlayerControlsVisible = false
            }
        }
    }

    private func collectionScreenTranslation(_ translation: CGSize) -> CGSize {
        // The player is rotated manually while DragGesture reports in the
        // unrotated global coordinate space. Convert with the inverse of the
        // display rotation so visible left/right and up/down keep their
        // expected directions in landscape.
        guard usesManualLandscapeRotation else { return translation }
        switch deviceOrientation {
        case .landscapeLeft:
            return CGSize(
                width: translation.height,
                height: -translation.width
            )
        case .landscapeRight:
            return CGSize(
                width: -translation.height,
                height: translation.width
            )
        default:
            return translation
        }
    }

    private func dismissDragOpacity(for height: CGFloat) -> Double {
        guard height > 0 else { return 1 }
        return max(0.55, 1 - Double(downwardDragOffset / height) * 0.9)
    }

    private func collectionPlaybackTime(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func installOrientationObserver() {
        guard orientationObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        updateDeviceOrientation(UIDevice.current.orientation)
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                updateDeviceOrientation(UIDevice.current.orientation)
            }
        }
    }

    private func removeOrientationObserver() {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
            self.orientationObserver = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func updateDeviceOrientation(_ orientation: UIDeviceOrientation) {
        guard orientation == .portrait
                || orientation == .portraitUpsideDown
                || orientation.isLandscape
        else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            deviceOrientation = orientation
            resetPlayerZoom(animated: false)
        }
    }

    private func installPlaybackObserver() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { _ in
            Task { @MainActor in
                isPlaying = player.timeControlStatus == .playing
            }
        }
    }

    private func removePlaybackObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}

private struct CalendarMediaPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var visibleMonth: Date
    @State private var mediaDates: Set<Date> = []
    @State private var mediaCountsByDate: [Date: Int] = [:]
    @State private var holidayDates: Set<Date> = []
    @State private var holidayNamesByDate: [Date: String] = [:]
    @State private var loadedMediaMonth: Date?
    @State private var loadedHolidayYear: Int?
    @State private var selectedDates: Set<Date> = []
    @State private var isLoadingMonth = false
    @State private var monthLoadProgress = 0.0
    @State private var showMonthYearPicker = false
    @State private var draftYear: Int
    @State private var draftMonth: Int
    @State private var selectedThumbnails: [CalendarThumbnailItem] = []
    @State private var previewedThumbnailItem: CalendarThumbnailItem?
    @State private var previewSourcePoint: CGPoint = .zero
    @State private var excludedAssetIdentifiers: Set<String> = []
    @State private var thumbnailLoadTask: Task<Void, Never>?
    @State private var thumbnailColumnCount = 6
    @State private var thumbnailMagnificationCheckpoint: CGFloat = 1
    @State private var thumbnailScrollOffset: CGFloat = 0
    @State private var areThumbnailScrollButtonsVisible = false
    @State private var thumbnailScrollButtonsHideTask: Task<Void, Never>?
    @State private var didApplyInitialSharedSelection = false

    let onConfirm: (Set<Date>, Set<String>) -> Void
    let onCancel: () -> Void
    let onShowPhotos: ([String]) -> Void
    private let videoOnly: Bool
    private let initialSelectionIdentifiers: Set<String>

    private let calendar = Calendar.current
    private let calendarBaseRowHeight: CGFloat = 46
    private let compactCalendarRowHeight: CGFloat = 32.2
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 0),
        count: 7
    )
    private let thumbnailColumnSteps = [8, 6, 4, 2, 1]
    private let thumbnailTopID = "calendarThumbnailTop"
    private let thumbnailBottomID = "calendarThumbnailBottom"
    private let thumbnailScrollCoordinateSpace = "calendarThumbnailScroll"
    private let weekdays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    init(
        initialMonth: Date,
        initialMediaDates: Set<Date>,
        initialMediaCounts: [Date: Int],
        initialSelectionIdentifiers: [String],
        videoOnly: Bool = false,
        onCancel: @escaping () -> Void,
        onShowPhotos: @escaping ([String]) -> Void,
        onConfirm: @escaping (Set<Date>, Set<String>) -> Void
    ) {
        let calendar = Calendar.current
        let month = calendar.date(
            from: calendar.dateComponents([.year, .month], from: initialMonth)
        ) ?? initialMonth
        _visibleMonth = State(initialValue: month)
        _mediaDates = State(initialValue: initialMediaDates)
        _mediaCountsByDate = State(initialValue: initialMediaCounts)
        _loadedMediaMonth = State(
            initialValue: initialMediaCounts.isEmpty ? nil : month
        )
        let initialAssets = PHAsset.fetchAssets(
            withLocalIdentifiers: initialSelectionIdentifiers,
            options: nil
        )
        var initialDates: Set<Date> = []
        initialAssets.enumerateObjects { asset, _, _ in
            if let date = asset.creationDate {
                initialDates.insert(calendar.startOfDay(for: date))
            }
        }
        _selectedDates = State(initialValue: initialDates)
        _draftYear = State(
            initialValue: calendar.component(.year, from: month)
        )
        _draftMonth = State(
            initialValue: calendar.component(.month, from: month)
        )
        self.onShowPhotos = onShowPhotos
        self.onCancel = onCancel
        self.videoOnly = videoOnly
        self.initialSelectionIdentifiers = Set(initialSelectionIdentifiers)
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                calendarActionBar

                monthControls
                    .padding(.top, 14)

                calendarTable
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                selectionSummary
            }
            .overlay(alignment: .bottom) {
                calendarQuickSelectionButtons
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(HanClipTheme.backgroundGradient.ignoresSafeArea())
            .interactiveDismissDisabled(true)
            .task(id: visibleMonth) {
                await loadHolidayDates()
                await loadMediaDates()
                applyInitialSharedSelectionIfNeeded()
            }
            .onChange(of: selectedDates) { _, _ in
                reloadSelectedThumbnails()
            }
            .onDisappear {
                thumbnailLoadTask?.cancel()
                thumbnailScrollButtonsHideTask?.cancel()
            }
            .fullScreenCover(isPresented: $showMonthYearPicker) {
                monthYearPicker
            }
            .overlay {
                if let item = previewedThumbnailItem {
                    CalendarMediaPreviewController(
                        assetIdentifier: item.id,
                        sourcePoint: previewSourcePoint,
                        onDelete: {
                            excludedAssetIdentifiers.insert(item.id)
                            selectedThumbnails.removeAll { $0.id == item.id }
                            previewedThumbnailItem = nil
                        },
                        onDismiss: {
                            previewedThumbnailItem = nil
                        }
                    )
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
        }
    }

    private var calendarTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background {
                            Rectangle()
                                .fill(weekdayColor(weekday))
                        }
                        .overlay {
                            Rectangle()
                                .stroke(
                                    Color.gray.opacity(0.10),
                                    lineWidth: 1
                                )
                        }
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(HanClipTheme.secondary.opacity(0.14))
                    .frame(height: 2)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(HanClipTheme.secondary.opacity(0.14))
                    .frame(height: 2)
            }

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) {
                    _,
                    date in
                    if let date {
                        dayButton(for: date)
                    } else {
                        Color.clear
                            .frame(height: calendarRowHeight)
                            .overlay {
                                Rectangle()
                                    .stroke(
                                        HanClipTheme.secondary.opacity(0.07),
                                        lineWidth: 1
                                    )
                            }
                    }
                }
            }
            .frame(height: calendarGridHeight, alignment: .top)
        }
        .background(
            HanClipTheme.panelFill.opacity(0.46),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HanClipTheme.secondary.opacity(0.14), lineWidth: 1)
        }
        .shadow(
            color: HanClipTheme.secondary.opacity(0.06),
            radius: 10,
            y: 5
        )
    }

    private var monthControls: some View {
        HStack(spacing: 12) {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(monthArrowIconColor)
                    .shadow(color: monthArrowIconShadowColor, radius: 1.5)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .background(monthArrowBackground)
            .clipShape(Circle())
            .accessibilityLabel("이전 달")

            Spacer()

            Button {
                draftYear = calendar.component(.year, from: visibleMonth)
                draftMonth = calendar.component(.month, from: visibleMonth)
                showMonthYearPicker = true
            } label: {
                VStack(spacing: 6) {
                    Text(monthTitle)
                        .font(.system(size: 20, weight: .semibold))

                    if isLoadingMonth {
                        HStack(spacing: 8) {
                            Text(
                                "\(Int((monthLoadProgress * 100).rounded()))%"
                            )
                            .font(
                                .system(
                                    size: 12,
                                    weight: .semibold,
                                    design: .monospaced
                                )
                            )
                            .frame(width: 34, alignment: .trailing)

                            ProgressView(value: monthLoadProgress, total: 1)
                                .progressViewStyle(.linear)
                                .tint(HanClipTheme.primary)
                        }
                        .frame(width: 130)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(HanClipTheme.text)
            .accessibilityHint("연도와 월을 선택해 이동합니다.")

            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(monthArrowIconColor)
                    .shadow(color: monthArrowIconShadowColor, radius: 1.5)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .background(monthArrowBackground)
            .clipShape(Circle())
            .accessibilityLabel("다음 달")
        }
        .foregroundStyle(HanClipTheme.secondary)
        .padding(.horizontal, 14)
    }

    private var monthArrowIconColor: Color {
        colorScheme == .dark ? .white : HanClipTheme.secondary
    }

    private var monthArrowIconShadowColor: Color {
        colorScheme == .dark ? .clear : .white.opacity(0.75)
    }

    @ViewBuilder
    private var monthArrowBackground: some View {
        if #available(iOS 26.0, *) {
            Circle()
                .fill(Color.white.opacity(0.12))
                .glassEffect(
                    .regular
                        .tint(Color.white.opacity(0.18))
                        .interactive(),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                }
        } else {
            Circle()
                .fill(Color.white.opacity(0.18))
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                }
        }
    }

    private var calendarActionBar: some View {
        HStack(spacing: 10) {
            Button("취소") {
                onCancel()
            }
            .foregroundStyle(HanClipTheme.text.opacity(0.72))
            .calendarActionButtonStyle()

            Spacer()

            Button("달력") {
                thumbnailLoadTask?.cancel()
                onShowPhotos(resolvedSelectedAssetIdentifiers())
            }
            .foregroundStyle(HanClipTheme.text)
            .calendarActionButtonStyle()

            Spacer()

            Button("추가") {
                confirmCalendarSelection()
            }
            .foregroundStyle(HanClipTheme.text.opacity(0.72))
            .disabled(selectedDates.isEmpty)
            .calendarActionButtonStyle()
        }
        .font(.system(size: 16, weight: .semibold))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var monthYearPicker: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("연도", selection: $draftYear) {
                    ForEach(yearRange, id: \.self) { year in
                        Text("\(year)년").tag(year)
                    }
                }
                .pickerStyle(.wheel)

                Picker("월", selection: $draftMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text("\(month)월").tag(month)
                    }
                }
                .pickerStyle(.wheel)
            }
            .padding(.horizontal, 18)
            .navigationTitle("년 월 이동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        showMonthYearPicker = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("이동") {
                        applyDraftMonth()
                    }
                }
            }
        }
    }

    private var selectionSummary: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let leftWidth = geometry.size.width * 2 / 3
                let rightWidth = geometry.size.width - leftWidth

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Text("선택 \(selectedDates.count)일 · 미디어 \(selectedMediaCount)개")
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                            .padding(.leading, 16)
                            .frame(
                                width: leftWidth,
                                height: 44,
                                alignment: .leading
                            )

                        Label("해제", systemImage: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(
                                width: rightWidth,
                                height: 44,
                                alignment: .center
                            )
                    }

                    Rectangle()
                        .fill(Color.black.opacity(0.001))
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { event in
                                    if event.location.x < leftWidth {
                                        withAnimation(.snappy) {
                                            handleTodayDoubleTap()
                                        }
                                    } else if !selectedDates.isEmpty {
                                        clearSelectedCalendarMedia()
                                    }
                                }
                        )

                    Rectangle()
                        .fill(HanClipTheme.secondary.opacity(0.30))
                        .frame(width: 1, height: 24)
                        .offset(x: leftWidth - 0.5)
                        .allowsHitTesting(false)
                }
            }
            .foregroundStyle(
                selectedDates.isEmpty
                    ? HanClipTheme.text.opacity(0.45)
                    : HanClipTheme.secondary
            )
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(selectionSummaryButtonBackground)
            .shadow(
                color: HanClipTheme.secondary.opacity(
                    selectedDates.isEmpty ? 0.03 : 0.16
                ),
                radius: 9,
                x: 0,
                y: 4
            )
            .contentShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "선택 \(selectedDates.count)일, 미디어 \(selectedMediaCount)개"
            )
            .accessibilityAction(named: "날짜 선택") {
                withAnimation(.snappy) {
                    handleTodayDoubleTap()
                }
            }
            .accessibilityAction(named: "해제") {
                guard !selectedDates.isEmpty else { return }
                clearSelectedCalendarMedia()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)

            selectedThumbnailGrid
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var selectionSummaryButtonBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(Color.white.opacity(0.10))
                .glassEffect(
                    .regular
                        .tint(HanClipTheme.secondary.opacity(0.12))
                        .interactive(),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            HanClipTheme.secondary.opacity(0.18),
                            lineWidth: 1
                        )
                }
        } else {
            Capsule()
                .fill(Color.white.opacity(0.16))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(
                            HanClipTheme.secondary.opacity(0.18),
                            lineWidth: 1
                        )
                }
        }
    }

    private func clearSelectedCalendarMedia() {
        selectedDates.removeAll()
        selectedThumbnails.removeAll()
        excludedAssetIdentifiers.removeAll()
    }

    private func applyInitialSharedSelectionIfNeeded() {
        guard !didApplyInitialSharedSelection else { return }
        didApplyInitialSharedSelection = true
        guard !initialSelectionIdentifiers.isEmpty,
              !selectedDates.isEmpty else { return }

        let allIdentifiers = Set(
            assetsForSelectedDates().map(\.localIdentifier)
        )
        excludedAssetIdentifiers = allIdentifiers
            .subtracting(initialSelectionIdentifiers)
        reloadSelectedThumbnails()
    }

    private func resolvedSelectedAssetIdentifiers() -> [String] {
        assetsForSelectedDates()
            .map(\.localIdentifier)
            .filter { !excludedAssetIdentifiers.contains($0) }
    }

    private func assetsForSelectedDates() -> [PHAsset] {
        guard let firstDate = selectedDates.min(),
              let lastDate = selectedDates.max(),
              let endDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: lastDate
              ) else { return [] }

        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: true)
        ]
        if videoOnly {
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@ AND mediaType == %d",
                firstDate as NSDate,
                endDate as NSDate,
                PHAssetMediaType.video.rawValue
            )
        } else {
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@ AND (mediaType == %d OR mediaType == %d)",
                firstDate as NSDate,
                endDate as NSDate,
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue
            )
        }
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate,
                  selectedDates.contains(calendar.startOfDay(for: date))
            else { return }
            assets.append(asset)
        }
        return assets
    }

    private var calendarQuickSelectionButtons: some View {
        HStack {
            calendarQuickSelectionButton(title: "전날") {
                handleTodayDoubleTap()
            }

            Spacer()

            calendarQuickSelectionButton(title: "오늘") {
                handleTodayButtonTap()
            }

            Spacer()

            calendarQuickSelectionButton(
                title: "해제",
                isEnabled: !selectedDates.isEmpty
            ) {
                clearSelectedCalendarMedia()
            }

            Spacer()

            calendarQuickSelectionButton(
                title: "추가",
                isEnabled: !selectedDates.isEmpty
            ) {
                confirmCalendarSelection()
            }
        }
        .padding(.horizontal, 18)
    }

    private func confirmCalendarSelection() {
        let confirmedDates = selectedDates
        let excludedIdentifiers = excludedAssetIdentifiers
        thumbnailLoadTask?.cancel()
        thumbnailLoadTask = nil
        previewedThumbnailItem = nil
        selectedThumbnails.removeAll(keepingCapacity: false)
        onConfirm(confirmedDates, excludedIdentifiers)
    }

    private func calendarQuickSelectionButton(
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(HanClipTheme.primary)
                .frame(width: 58, height: 58)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(
                            HanClipTheme.secondary.opacity(0.34),
                            lineWidth: 1.25
                        )
                }
                .shadow(
                    color: HanClipTheme.secondary.opacity(0.18),
                    radius: 10,
                    y: 5
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.34)
        .accessibilityLabel(title == "해제" ? "선택 해제" : title)
    }

    private var selectedThumbnailGrid: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 4
            let horizontalPadding: CGFloat = 14
            let cornerRadius: CGFloat = 16
            let fadeHeight: CGFloat = 50
            let bottomThumbnailPadding: CGFloat = 96
            let availableWidth = max(
                geometry.size.width - (horizontalPadding * 2),
                0
            )
            let fadeStart = max(
                (geometry.size.height - fadeHeight)
                / max(geometry.size.height, 1),
                0
            )
            let fadeMiddle = min(fadeStart + (1 - fadeStart) * 0.58, 1)
            let itemSize = (
                availableWidth
                - spacing * CGFloat(thumbnailColumnCount - 1)
            ) / CGFloat(thumbnailColumnCount)
            let sixColumnThumbnailSize = (
                availableWidth
                - spacing * CGFloat(6 - 1)
            ) / CGFloat(6)
            let mediaIconSize = sixColumnThumbnailSize / 3
            let mediaIconOpacity = thumbnailMediaIconOpacity(
                for: thumbnailColumnCount
            )
            let rowCount = Int(
                ceil(
                    Double(selectedThumbnails.count)
                    / Double(max(thumbnailColumnCount, 1))
                )
            )
            let contentHeight =
                CGFloat(rowCount) * itemSize
                + CGFloat(max(rowCount - 1, 0)) * spacing
                + bottomThumbnailPadding
            let canScroll = contentHeight > geometry.size.height + 1
            let scrollButtonOpacity =
                canScroll && areThumbnailScrollButtonsVisible ? 1.0 : 0.0
            let thumbnailColumns = Array(
                repeating: GridItem(.fixed(itemSize), spacing: spacing),
                count: thumbnailColumnCount
            )

            ScrollViewReader { proxy in
                ZStack {
                    ScrollView {
                        Color.clear
                            .frame(height: 0)
                            .id(thumbnailTopID)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: ThumbnailScrollOffsetPreferenceKey.self,
                                        value: proxy.frame(
                                            in: .named(thumbnailScrollCoordinateSpace)
                                        ).minY
                                    )
                                }
                            }

                        LazyVGrid(columns: thumbnailColumns, spacing: spacing) {
                            ForEach(
                                Array(selectedThumbnails.enumerated()),
                                id: \.offset
                            ) { _, item in
                                GeometryReader { itemGeometry in
                                    Image(uiImage: item.thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: itemSize, height: itemSize)
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius: max(
                                                    2,
                                                    itemSize * 0.035
                                                ),
                                                style: .continuous
                                            )
                                        )
                                        .overlay(alignment: .bottomLeading) {
                                            calendarThumbnailMediaIcon(
                                                for: item.mediaKind,
                                                size: mediaIconSize,
                                                opacity: mediaIconOpacity
                                            )
                                            .padding(
                                                sixColumnThumbnailSize * 0.06
                                            )
                                        }
                                        .onLongPressGesture(
                                            minimumDuration: 0.45,
                                            maximumDistance: 16
                                        ) {
                                            let frame = itemGeometry.frame(
                                                in: .global
                                            )
                                            previewSourcePoint = CGPoint(
                                                x: frame.midX,
                                                y: frame.midY
                                            )
                                            previewedThumbnailItem = item
                                        }
                                }
                                .frame(width: itemSize, height: itemSize)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, bottomThumbnailPadding)

                        Color.clear
                            .frame(height: 0)
                            .id(thumbnailBottomID)
                    }
                    .coordinateSpace(name: thumbnailScrollCoordinateSpace)
                    .scrollIndicators(.hidden)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                showThumbnailScrollButtons(canScroll: canScroll)
                            }
                            .onEnded { _ in
                                scheduleThumbnailScrollButtonsHide()
                            }
                    )
                    .onPreferenceChange(ThumbnailScrollOffsetPreferenceKey.self) {
                        handleThumbnailScrollOffsetChange($0, canScroll: canScroll)
                    }

                    if canScroll {
                        thumbnailScrollButton(systemImage: "chevron.down") {
                            withAnimation(.snappy) {
                                proxy.scrollTo(thumbnailBottomID, anchor: .bottom)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 0)
                        .opacity(scrollButtonOpacity)
                        .allowsHitTesting(areThumbnailScrollButtonsVisible)
                        .animation(
                            .easeInOut(duration: 1.0),
                            value: areThumbnailScrollButtonsVisible
                        )

                        thumbnailScrollButton(systemImage: "chevron.up") {
                            withAnimation(.snappy) {
                                proxy.scrollTo(thumbnailTopID, anchor: .top)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 52)
                        .opacity(scrollButtonOpacity)
                        .allowsHitTesting(areThumbnailScrollButtonsVisible)
                        .animation(
                            .easeInOut(duration: 1.0),
                            value: areThumbnailScrollButtonsVisible
                        )
                    }
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        HanClipTheme.panelFill.opacity(0.72),
                        HanClipTheme.secondary.opacity(0.035),
                        Color.white.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(HanClipTheme.secondary.opacity(0.10), lineWidth: 1)
            }
            .mask {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: fadeStart),
                            .init(color: .black.opacity(0.82), location: fadeMiddle),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        updateThumbnailColumns(for: value)
                    }
                    .onEnded { _ in
                        thumbnailMagnificationCheckpoint = 1
                    }
            )
        }
        .frame(maxHeight: selectedThumbnails.isEmpty ? 0 : .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func thumbnailScrollButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(HanClipTheme.secondary)
                .shadow(
                    color: HanClipTheme.secondary.opacity(0.70),
                    radius: 3,
                    x: 0,
                    y: 1.5
                )
                .frame(width: 92, height: 68)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func calendarThumbnailMediaIcon(
        for mediaKind: ClipMediaKind,
        size: CGFloat,
        opacity: Double
    ) -> some View {
        Group {
            switch mediaKind {
            case .video:
                FilmCameraIcon()
                    .frame(width: size, height: size * 17 / 21)
            case .livePhoto:
                Image(systemName: "livephoto")
                    .font(.system(size: size, weight: .semibold))
            case .photo:
                Image(systemName: "photo.fill")
                    .font(.system(size: size * 0.82, weight: .semibold))
            }
        }
        .foregroundStyle(HanClipTheme.secondary.opacity(opacity * 0.62))
        .shadow(
            color: Color.black.opacity(0.34),
            radius: 1.6,
            x: 0,
            y: 0.8
        )
    }

    private func thumbnailMediaIconOpacity(for columnCount: Int) -> Double {
        let clampedColumnCount = min(max(columnCount, 1), 8)
        return 1.0 - (Double(clampedColumnCount - 1) / 7.0 * 0.5)
    }

    private func showThumbnailScrollButtons(canScroll: Bool) {
        guard canScroll else {
            thumbnailScrollButtonsHideTask?.cancel()
            areThumbnailScrollButtonsVisible = false
            return
        }

        areThumbnailScrollButtonsVisible = true
        thumbnailScrollButtonsHideTask?.cancel()
    }

    private func scheduleThumbnailScrollButtonsHide() {
        thumbnailScrollButtonsHideTask?.cancel()
        thumbnailScrollButtonsHideTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                areThumbnailScrollButtonsVisible = false
            }
        }
    }

    private func handleThumbnailScrollOffsetChange(
        _ offset: CGFloat,
        canScroll: Bool
    ) {
        let didScroll = abs(offset - thumbnailScrollOffset) > 0.5
        thumbnailScrollOffset = offset

        guard canScroll else {
            showThumbnailScrollButtons(canScroll: false)
            return
        }

        guard didScroll else { return }

        showThumbnailScrollButtons(canScroll: true)
        scheduleThumbnailScrollButtonsHide()
    }

    private func dayButton(for date: Date) -> some View {
        let normalizedDate = calendar.startOfDay(for: date)
        let isSelected = selectedDates.contains(normalizedDate)
        let hasMedia = (mediaCountsByDate[normalizedDate] ?? 0) > 0
        let isToday = calendar.isDateInToday(date)
        let holidayName = holidayName(for: normalizedDate)

        return Button {
            guard hasMedia else { return }

            withAnimation(.snappy) {
                if isSelected {
                    selectedDates.remove(normalizedDate)
                } else {
                    selectedDates.insert(normalizedDate)
                }
            }
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    if hasMedia || isToday {
                        Circle()
                            .fill(
                                dayCircleFill(
                                    isSelected: isSelected,
                                    isToday: isToday,
                                    hasMedia: hasMedia
                                )
                            )
                            .frame(
                                width: isToday ? 28 : 24,
                                height: isToday ? 28 : 24
                            )
                    }

                    Text("\(calendar.component(.day, from: date))")
                        .font(
                            .system(
                                size: 16,
                                weight: hasMedia ? .semibold : .regular
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(dateTextColor(for: date))
                }
                .frame(height: 25)

                if let holidayName {
                    Text(String(holidayName.prefix(7)))
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(restDayColor)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: calendarRowHeight)
            .background {
                if isSelected {
                    Rectangle()
                        .fill(HanClipTheme.secondary.opacity(0.16))
                }
            }
            .overlay {
                Rectangle()
                    .stroke(HanClipTheme.secondary.opacity(0.07), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(calendar.component(.day, from: date))일"
        )
    }

    private var monthCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: visibleMonth),
              let firstDay = calendar.date(
                from: calendar.dateComponents(
                    [.year, .month],
                    from: visibleMonth
                )
              )
        else { return [] }

        let leadingEmptyCount =
            calendar.component(.weekday, from: firstDay) - 1
        let dates = range.compactMap { day -> Date? in
            calendar.date(
                byAdding: .day,
                value: day - 1,
                to: firstDay
            )
        }
        let fixedCellCount = neededCalendarRowCount * 7
        let cells = Array(repeating: nil, count: leadingEmptyCount) + dates
        return cells + Array(
            repeating: nil,
            count: fixedCellCount - cells.count
        )
    }

    private var neededCalendarRowCount: Int {
        guard let range = calendar.range(of: .day, in: .month, for: visibleMonth),
              let firstDay = calendar.date(
                from: calendar.dateComponents(
                    [.year, .month],
                    from: visibleMonth
                )
              )
        else { return 5 }

        let leadingEmptyCount =
            calendar.component(.weekday, from: firstDay) - 1
        let rawRowCount = Int(
            ceil(Double(leadingEmptyCount + range.count) / 7.0)
        )
        return min(max(rawRowCount, 4), 6)
    }

    private var calendarRowHeight: CGFloat {
        calendarGridHeight / CGFloat(neededCalendarRowCount)
    }

    private var calendarGridHeight: CGFloat {
        calendarBaseRowHeight * 4
    }

    private var yearRange: ClosedRange<Int> {
        let currentYear = calendar.component(.year, from: Date())
        return (currentYear - 30)...(currentYear + 10)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: visibleMonth)
    }

    private var selectedMediaCount: Int {
        let total = selectedDates.reduce(0) { partialResult, date in
            partialResult + (mediaCountsByDate[date] ?? 0)
        }
        return max(0, total - excludedAssetIdentifiers.count)
    }

    private func dateTextColor(for date: Date) -> Color {
        if calendar.isDateInToday(date) {
            return HanClipTheme.onSecondary
        }
        if isSunday(date) || isKoreanHoliday(date) {
            return restDayColor
        }
        if isSaturday(date) {
            return saturdayColor
        }
        return HanClipTheme.text
    }

    private func dayCircleFill(
        isSelected: Bool,
        isToday: Bool,
        hasMedia: Bool
    ) -> Color {
        if isSelected {
            return HanClipTheme.secondary.opacity(0.34)
        }
        if isToday {
            return HanClipTheme.primary.opacity(0.78)
        }
        if hasMedia {
            return HanClipTheme.secondary.opacity(0.18)
        }
        return Color.clear
    }

    private func weekdayColor(_ weekday: String) -> Color {
        if weekday == "SUN" {
            return restDayColor
        }
        if weekday == "SAT" {
            return saturdayColor
        }
        return HanClipTheme.text.opacity(0.55)
    }

    private var restDayColor: Color {
        HanClipTheme.primary
    }

    private var saturdayColor: Color {
        HanClipTheme.lightSecondary
    }

    private func isSunday(_ date: Date) -> Bool {
        calendar.component(.weekday, from: date) == 1
    }

    private func isKoreanHoliday(_ date: Date) -> Bool {
        holidayDates.contains(calendar.startOfDay(for: date))
    }

    private func holidayName(for date: Date) -> String? {
        holidayNamesByDate[calendar.startOfDay(for: date)]
    }

    private func isSaturday(_ date: Date) -> Bool {
        calendar.component(.weekday, from: date) == 7
    }

    private func moveMonth(by value: Int) {
        guard let month = calendar.date(
            byAdding: .month,
            value: value,
            to: visibleMonth
        ) else { return }
        visibleMonth = month
    }

    private func moveToToday() {
        let todayMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: Date())
        ) ?? Date()
        visibleMonth = todayMonth
    }

    private func handleTodayButtonTap() {
        let today = calendar.startOfDay(for: Date())
        let todayMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: today)
        ) ?? today

        guard calendar.isDate(
            visibleMonth,
            equalTo: todayMonth,
            toGranularity: .month
        ) else {
            visibleMonth = todayMonth
            return
        }

        guard (mediaCountsByDate[today] ?? 0) > 0 else { return }
        selectedDates.insert(today)
    }

    private func handleTodayDoubleTap() {
        if selectedDates.isEmpty {
            selectClosestMediaDateFromYesterday()
        } else {
            selectPreviousDay()
        }
    }

    private func selectClosestMediaDateFromYesterday() {
        let yesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()

        Task {
            let closestDate = await Task.detached {
                PhotoLibraryService.closestMediaDate(
                    to: yesterday,
                    calendar: Calendar.current,
                    mediaType: videoOnly ? .video : nil
                )
            }.value
            guard let date = closestDate else { return }

            await MainActor.run {
                selectDateAndShowMonth(date)
            }
        }
    }

    private func selectPreviousDay() {
        let earliestSelectedDate = selectedDates.min()
        let baseDate = earliestSelectedDate ?? calendar.startOfDay(for: Date())
        Task {
            let previousDate = await Task.detached {
                PhotoLibraryService.previousMediaDate(
                    before: baseDate,
                    calendar: Calendar.current,
                    mediaType: videoOnly ? .video : nil
                )
            }.value
            guard let date = previousDate else { return }

            await MainActor.run {
                selectDateAndShowMonth(date)
            }
        }
    }

    private func selectDateAndShowMonth(_ date: Date) {
        let normalizedDate = calendar.startOfDay(for: date)
        if mediaDates.contains(normalizedDate) == false,
           mediaCountsByDate[normalizedDate] == nil,
           calendar.isDate(normalizedDate, equalTo: visibleMonth, toGranularity: .month) {
            return
        }

        withAnimation(.snappy) {
            selectedDates.insert(normalizedDate)
            visibleMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: date)
            ) ?? visibleMonth
        }
    }

    private func updateThumbnailColumns(for magnification: CGFloat) {
        guard let currentIndex = thumbnailColumnSteps.firstIndex(
            of: thumbnailColumnCount
        ) else { return }

        let relativeMagnification =
            magnification / thumbnailMagnificationCheckpoint

        if relativeMagnification > 1.35 {
            thumbnailColumnCount = thumbnailColumnSteps[
                min(currentIndex + 1, thumbnailColumnSteps.count - 1)
            ]
            thumbnailMagnificationCheckpoint = magnification
        } else if relativeMagnification < 0.65 {
            thumbnailColumnCount = thumbnailColumnSteps[
                max(currentIndex - 1, 0)
            ]
            thumbnailMagnificationCheckpoint = magnification
        }
    }

    private func applyDraftMonth() {
        guard let month = calendar.date(
            from: DateComponents(year: draftYear, month: draftMonth)
        ) else { return }
        visibleMonth = month
        showMonthYearPicker = false
    }

    private func reloadSelectedThumbnails() {
        thumbnailLoadTask?.cancel()
        guard !selectedDates.isEmpty else {
            selectedThumbnails = []
            return
        }

        let dates = selectedDates
        let excludedIdentifiers = excludedAssetIdentifiers
        thumbnailLoadTask = Task {
            let assets = await Task.detached {
                PhotoLibraryService.mediaAssets(
                    on: dates,
                    calendar: Calendar.current,
                    mediaType: videoOnly ? .video : nil
                )
            }.value

            var thumbnails: [CalendarThumbnailItem] = []
            for asset in assets {
                guard !Task.isCancelled,
                      !excludedIdentifiers.contains(asset.localIdentifier),
                      let thumbnail = try? await PhotoLibraryService
                        .thumbnail(
                            for: asset,
                            size: CGSize(width: 120, height: 120)
                        )
                else { continue }
                thumbnails.append(
                    CalendarThumbnailItem(
                        id: asset.localIdentifier,
                        thumbnail: thumbnail,
                        mediaKind: calendarThumbnailMediaKind(for: asset)
                    )
                )
            }

            guard !Task.isCancelled else { return }
            selectedThumbnails = thumbnails
        }
    }

    private func calendarThumbnailMediaKind(for asset: PHAsset) -> ClipMediaKind {
        if asset.mediaType == .video {
            return .video
        }
        if asset.mediaSubtypes.contains(.photoLive) {
            return .livePhoto
        }
        return .photo
    }

    @MainActor
    private func loadHolidayDates() async {
        let year = calendar.component(.year, from: visibleMonth)
        guard loadedHolidayYear != year else { return }

        loadedHolidayYear = year
        holidayNamesByDate = KoreanHolidayService.cachedHolidayNames(
            for: year,
            calendar: calendar
        )
        holidayDates = Set(holidayNamesByDate.keys)

        let refreshedNames = await KoreanHolidayService.refreshedHolidayNames(
            for: year,
            calendar: calendar
        )
        holidayNamesByDate = refreshedNames
        holidayDates = Set(refreshedNames.keys)
    }

    @MainActor
    private func loadMediaDates() async {
        if let loadedMediaMonth,
           calendar.isDate(
            loadedMediaMonth,
            equalTo: visibleMonth,
            toGranularity: .month
           ) {
            return
        }

        isLoadingMonth = true
        monthLoadProgress = 0
        let month = visibleMonth
        let counts = await Task.detached {
            PhotoLibraryService.mediaCounts(
                in: month,
                calendar: Calendar.current,
                mediaType: videoOnly ? .video : nil
            ) { progress in
                Task { @MainActor in
                    monthLoadProgress = progress
                }
            }
        }.value
        guard calendar.isDate(
            month,
            equalTo: visibleMonth,
            toGranularity: .month
        ) else { return }
        mediaDates = Set(counts.keys)
        mediaCountsByDate.merge(counts) { _, new in new }
        loadedMediaMonth = month
        monthLoadProgress = 1
        isLoadingMonth = false
    }
}
