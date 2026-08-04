import AVFoundation
import AVKit
import CoreText
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    }

    @StateObject private var model = EditorViewModel()
    @State private var isReordering = false
    @State private var showResetConfirmation = false
    @State private var showHeaderExitConfirmation = false
    @State private var showThemeSelection = false
    @State private var showImportantInfo = false
    @State private var showTextOverlaySettings = false
    @State private var showBackgroundMusicSettings = false
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
    @State private var selectAllSnapshot: [UUID: SelectAllClipSnapshot] = [:]
    @State private var selectAllAppliedSignature: [SelectAllClipSnapshot] = []
    @State private var isSelectAllChecked = false
    @FocusState private var focusedMemoProjectID: UUID?

    private let aspectRatioPickerAnimation = Animation.snappy
    @AppStorage("hanClipThemeMode") private var themeModeRaw =
        HanClipThemeMode.automatic.rawValue
    @AppStorage("hanClipCustomThemeOrder") private var customThemeOrderRaw =
        "rosyBrown,electricCobalt,blossomGlow,grayscalePlay"
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
    @AppStorage(WatermarkSettings.shadowColorStorageKey)
    private var watermarkShadowColorHex =
        WatermarkSettings.defaultShadowColor
    @AppStorage(WatermarkSettings.copyrightShadowColorStorageKey)
    private var copyrightShadowColorHex =
        WatermarkSettings.defaultCopyrightShadowColor
    @AppStorage(WatermarkSettings.copyrightIconColorModeStorageKey)
    private var copyrightIconColorModeRaw =
        WatermarkSettings.defaultCopyrightIconColorMode.rawValue
    @AppStorage(WatermarkSettings.copyrightIconColorStorageKey)
    private var copyrightIconColorHex =
        WatermarkSettings.defaultCopyrightIconColor
    @EnvironmentObject private var quickActionRouter:
        HanClipQuickActionRouter
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hanClipSleepPreventionMode") private var sleepPreventionModeRaw =
        SleepPreventionMode.defaultValue.rawValue

    private var themeMode: HanClipThemeMode {
        if themeModeRaw == "readableComfort" {
            return .light
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
        switch sleepPreventionMode {
        case .alwaysOn:
            true
        case .alwaysOff:
            false
        case .automatic:
            shouldKeepScreenOnForBackgroundWork
        }
    }

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled =
            scenePhase == .active && shouldDisableIdleTimer
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HanClipTheme.backgroundGradient
                    .ignoresSafeArea()

                Group {
                    if model.isProjectOpen {
                        clipEditor
                    } else {
                        emptyState
                    }
                }
            }
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
                if isBusyOverlayVisible {
                    progressOverlay
                }
            }
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
                            .frame(maxWidth: .infinity)
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
        }
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
                                .frame(width: proxy.size.width)
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
                                .frame(width: proxy.size.width)
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
                                .frame(width: proxy.size.width * 0.92)
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
                        Color.black.opacity(0.12)
                            .ignoresSafeArea()
                            .transition(.opacity)
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
                                .frame(width: proxy.size.width - 28)
                        }
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottom
                        )
                        .offset(y: 16)
                        .padding(.bottom, 22)
                    }
                    .transition(
                        .move(edge: .bottom).combined(with: .opacity)
                    )
                    .allowsHitTesting(true)
                }
            }
        }
        .fullScreenCover(isPresented: $model.isPickerPresented) {
            photoPicker
        }
        .fullScreenCover(isPresented: $model.isCalendarPickerPresented) {
            CalendarMediaPickerView(
                initialMonth: model.initialCalendarMonth,
                initialMediaDates: model.initialCalendarMediaDates,
                initialMediaCounts: model.initialCalendarMediaCounts,
                onConfirm: model.importMediaFromCalendarDates
            )
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
                    model.alertMessage = error.localizedDescription
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
                        autoplayOnLoad: true,
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
                            shouldAutoplaySelectedClip = true
                            selectedClipID = currentPreviewClips[
                                currentPreviewClips.index(before: index)
                            ].id
                        },
                        onNext: {
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
        .fullScreenCover(isPresented: $showTextOverlaySettings) {
            TextOverlaySettingsSheet(
                textEnabled: textOverlayBinding(\.isEnabled),
                text: textOverlayBinding(\.text),
                position: textOverlayBinding(\.position),
                fontName: textOverlayBinding(\.fontName),
                textColorHex: textOverlayBinding(\.textColorHex),
                shadowEnabled: textOverlayBinding(\.shadowEnabled),
                shadowColorHex: textOverlayBinding(\.shadowColorHex),
                lineSpacing: textOverlayBinding(\.lineSpacing),
                lineSpacingScale: textOverlayBinding(\.lineSpacingScale),
                fontSize: textOverlayBinding(\.fontSize)
            )
        }
        .fullScreenCover(isPresented: $showBackgroundMusicSettings) {
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
                }
            )
        }
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
            model.reloadProjects()
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
            } else {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .onChange(of: sleepPreventionModeRaw) { _, _ in
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
            onComplete: handlePhotoPickerComplete,
            onStart: model.startPhotoLibraryImport
        )
        .ignoresSafeArea()
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
        .accessibilityHint(
            "첫 화면에서 누르면 테마가 바뀌고, 길게 누르면 테마 선택창을 엽니다."
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
                VStack(spacing: 3) {
                    mediaImportMenu {
                        HanClipHeaderActionCluster {
                            Image(systemName: "photo.badge.plus")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(HanClipTheme.primary)
                        }
                    }

                    Text("영화 만들기")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(HanClipTheme.secondaryText.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
    }

    private var importantInfoSheet: some View {
        ImportantInfoSheet(
            sleepPreventionModeRaw: $sleepPreventionModeRaw,
            copyrightEnabled: $logoWatermarkEnabled,
            platformRaw: $watermarkPlatformRaw,
            address: $watermarkAddress,
            positionRaw: $copyrightPositionRaw,
            textColorHex: $copyrightTextColorHex,
            shadowColorHex: $copyrightShadowColorHex,
            iconColorModeRaw: $copyrightIconColorModeRaw,
            iconColorHex: $copyrightIconColorHex
        )
    }

    private func handlePhotoPickerComplete(_ items: [ClipItem]) {
        model.addPickedItems(items)
        model.finishPhotoLibraryImport()
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
        case .photo:
            model.openPicker()
        case .calendar:
            model.openCalendarPicker()
        case .files:
            model.openFilePicker()
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
                    withAnimation(.snappy) {
                        isSharedInboxBannerDismissed = true
                    }
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
            if !model.hasUnsavedProjectChanges {
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

        if !model.hasUnsavedProjectChanges {
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

    private var emptyState: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 6) {
                    Button {
                        model.openPicker()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HanClipTitleLine(
                                "영화 만들기",
                                systemImage: "photo.badge.plus"
                            )

                            ZStack {
                                LinearGradient(
                                    colors: [
                                        HanClipTheme.primary.opacity(0.10),
                                        HanClipTheme.secondary.opacity(0.08),
                                        Color.white.opacity(0.16)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )

                                Circle()
                                    .fill(HanClipTheme.secondary.opacity(0.16))
                                    .frame(width: 120, height: 120)
                                    .blur(radius: 28)
                                    .offset(x: 110, y: -58)

                                Circle()
                                    .fill(HanClipTheme.primary.opacity(0.10))
                                    .frame(width: 96, height: 96)
                                    .blur(radius: 24)
                                    .offset(x: -118, y: 64)

                                VStack(spacing: 14) {
                                    HStack(spacing: 9) {
                                        Image(systemName: "photo.stack.fill")
                                        Text("사진과 영상을 한 편으로")
                                        Image(systemName: "sparkles")
                                    }
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(HanClipTheme.primaryText)

                                    Text("고르고, 다듬고, 바로 만드세요.")
                                        .font(.system(size: 15, weight: .medium))
                                        .lineSpacing(2)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(
                                            HanClipTheme.secondaryText
                                        )

                                    Label(
                                        "영화 제작",
                                        systemImage: "plus.circle.fill"
                                    )
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
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
                                        color: HanClipTheme.primary.opacity(0.16),
                                        radius: 10,
                                        y: 5
                                    )
                                }
                            }
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 26,
                                    style: .continuous
                                )
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .shadow(
                                color: HanClipTheme.primary.opacity(0.10),
                                radius: 18,
                                y: 8
                            )
                            .hanClipGlassPanel(cornerRadius: 26)
                            .padding(.horizontal, 16)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .padding(.vertical, 20)
                    .buttonStyle(.plain)
                    .accessibilityLabel("사진 및 영상 선택")
                    .accessibilityHint(
                        "미디어 선택 화면을 엽니다."
                    )

                    if !model.savedProjects.isEmpty {
                        savedProjectList
                    }
                }
                .frame(
                    minHeight: proxy.size.height,
                    alignment: .top
                )
                .padding(.bottom, 24)
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
    }

    private var importantInfoButton: some View {
        Button {
            showImportantInfo = true
        } label: {
            Text("i")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(HanClipTheme.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            if #available(iOS 26.0, *) {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .glassEffect(
                        .regular
                            .tint(HanClipTheme.secondary.opacity(0.16))
                            .interactive(),
                        in: Circle()
                    )
            } else {
                Circle()
                    .fill(Color.white.opacity(0.24))
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        }
        .shadow(
            color: HanClipTheme.secondary.opacity(0.18),
            radius: 10,
            y: 4
        )
        .padding(.bottom, 8)
        .accessibilityLabel("카피라이터")
        .accessibilityHint("설정 창을 엽니다.")
    }

    private var savedProjectList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text("\(model.savedProjects.count)/10")
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

            LazyVStack(spacing: 8) {
                ForEach(model.savedProjects) { project in
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
    }

    private func savedProjectRow(
        _ project: SavedProjectSummary
    ) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                Group {
                    if let thumbnail = ProjectStore.thumbnailImage(for: project) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(HanClipTheme.secondary)
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
                    HStack(spacing: 6) {
                        Text(homeProjectDateText(project.updatedAt))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HanClipTheme.primaryText)
                        .lineLimit(1)

                        if model.newlySavedProjectID == project.id {
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(red: 0.78, green: 0.13, blue: 0.18))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
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
                        }
                    }

                    Text(
                        "클립 \(project.clipCount)개 · "
                            + projectDurationText(project.totalDuration)
                            + projectFileSizeSuffix(
                                project.storedByteCount
                            )
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(HanClipTheme.secondaryText)
                    .lineLimit(1)

                    projectThumbnailStrip(project)
                }
                .frame(maxHeight: 56, alignment: .center)

                Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    model.loadProjectAndImportPending(id: project.id)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint(
                    "한 번 누르면 영화를 엽니다."
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
            .frame(height: 56)

            ProjectMemoField(
                projectID: project.id,
                memo: project.memo,
                focusedMemoProjectID: $focusedMemoProjectID
            ) { memo in
                model.updateProjectMemo(id: project.id, memo: memo)
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 107)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.panelFill.opacity(0.96),
                    HanClipTheme.secondary.opacity(0.045),
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
                            model.removeClip(id: clip.id)
                        } content: {
                            ClipRow(
                                position: clipPosition(for: clip.id),
                                clip: $clip,
                                defaultDuration: model.defaultDuration,
                                childSegmentCount: model.childSegmentCount(
                                    for: clip.id
                                ),
                                childSegmentDuration: model.childSegmentDuration(
                                    for: clip.id
                                ),
                                canShowVideoSegmentSwitch: model
                                    .canUseMultipleVideoSegments(for: clip.id),
                                onSelectVideoSegmentMode: { mode in
                                    withAnimation(.snappy) {
                                        model.setVideoSegmentMode(
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
                                onSelect: {
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
        HanClipTheme.secondary.opacity(themeMode == .dark ? 0.08 : 0.055)
    }

    private func clipRowFill(for clip: ClipItem) -> Color {
        if clip.isVideoSegmentParent {
            return HanClipTheme.secondary.opacity(
                themeMode == .dark ? 0.13 : 0.18
            )
        }
        if clip.isVideoSegmentChild {
            return HanClipTheme.secondary.opacity(
                themeMode == .dark ? 0.070 : 0.090
            )
        }
        return HanClipTheme.secondary.opacity(
            themeMode == .dark ? 0.038 : 0.034
        )
    }

    @ViewBuilder
    private func clipRowRoleAccent(for clip: ClipItem) -> some View {
        if clip.isVideoSegmentParent {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            HanClipTheme.primary.opacity(0.20),
                            HanClipTheme.secondary.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 118)
        } else if clip.isVideoSegmentChild {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            HanClipTheme.primary.opacity(0.10),
                            HanClipTheme.secondary.opacity(0.04),
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
                    ? HanClipTheme.primary.opacity(0.15)
                    : HanClipTheme.secondary.opacity(0.15)
            )
            .frame(height: clip.isVideoSegmentChild ? 0.6 : 0.8)
            .padding(.leading, clip.isVideoSegmentChild ? 70 : 14)
            .padding(.trailing, 14)
    }

    private func clipRowBottomDivider(for clip: ClipItem) -> some View {
        Rectangle()
            .fill(
                clip.isVideoSegmentParent
                    ? HanClipTheme.primary.opacity(0.28)
                    : HanClipTheme.secondary.opacity(0.16)
            )
            .frame(height: clip.isVideoSegmentParent ? 1.2 : 0.8)
            .padding(.leading, clip.isVideoSegmentChild ? 70 : 14)
            .padding(.trailing, 14)
    }

    private var clipEditorSettings: some View {
        VStack(spacing: 0) {
            clipSettingsHeader

            clipSettingsSectionTitle
            .padding(.top, 2)
            .padding(.bottom, 4)

            defaultDurationPanel
                .padding(.horizontal, 14)
                .padding(.top, 0)
                .padding(.bottom, 10)
        }
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
                .foregroundStyle(HanClipTheme.primaryText)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
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
        let isVideoSegmentChild = clipIndex.map {
            model.clips[$0].isVideoSegmentChild
        } ?? false
        let isFollowedByVideoSegmentChild = clipIndex.map { index in
            let nextIndex = model.clips.index(after: index)
            return nextIndex < model.clips.endIndex
                && model.clips[nextIndex].isVideoSegmentChild
        } ?? false
        return EdgeInsets(
            top: isVideoSegmentChild
                ? 0
                : model.clips.first?.id == id ? 12 : 3,
            leading: 14,
            bottom: clipRowBottomInset(
                id: id,
                isVideoSegmentChild: isVideoSegmentChild,
                isFollowedByVideoSegmentChild: isFollowedByVideoSegmentChild
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
                .foregroundStyle(HanClipTheme.primaryText)

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
                .frame(height: 34)
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
                Image(systemName: "stopwatch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText.opacity(0.78))
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)

                HStack(spacing: 6) {
                    Text("기본시간")

                    Text("\(model.defaultDuration, specifier: "%.1f")초")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                }
                .font(.system(size: 14))
                .foregroundStyle(HanClipTheme.secondaryText)

                Spacer()

                HStack(spacing: 7) {
                    CompactDurationStepper(
                        value: $model.defaultDuration,
                        range: 0.5...30,
                        step: 0.5,
                        controlWidth: 82,
                        controlHeight: 22,
                        iconSize: 18
                    )

                    Button {
                        model.applyDefaultDurationToAll()
                        UIImpactFeedbackGenerator(style: .light)
                            .impactOccurred()
                        showTopActionNotice("전체 클립에 적용했습니다")
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 26)
                            .background(
                                LinearGradient(
                                    colors: [
                                        HanClipTheme.primary.opacity(0.94),
                                        HanClipTheme.secondary.opacity(0.82)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(
                                    cornerRadius: 8,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 8,
                                    style: .continuous
                                )
                                .stroke(
                                    Color.white.opacity(0.42),
                                    lineWidth: 1
                                )
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
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: 42)

            settingsPanelDivider

            HStack(spacing: 0) {
                Image(
                    systemName: isSelectAllChecked
                        ? "checkmark.square.fill"
                        : "square"
                )
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(HanClipTheme.secondaryText.opacity(0.78))
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)

                Button {
                    toggleSelectAllFullRange()
                } label: {
                    Text("Select all")
                        .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(
                        HanClipTheme.secondary.opacity(0.09),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                HanClipTheme.secondary.opacity(0.20),
                                lineWidth: 1
                            )
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)

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
                    width: 123,
                    height: 26
                )
                .accessibilityLabel("모든 Live Photo 사용 방식")
                .accessibilityValue(bulkLivePhotoMode.rawValue)
                .accessibilityHint("모든 Live Photo 클립을 포토 또는 Live 모드로 전환합니다.")
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: 42)

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
        }
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
            isVideoSegmentParent: clip.isVideoSegmentParent
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
        }
    }

    private func clearSelectAllSnapshotIfNeeded(
        currentSignature: [SelectAllClipSnapshot]
    ) {
        guard !selectAllSnapshot.isEmpty
        else { return }

        isSelectAllChecked = currentSignature == selectAllAppliedSignature
    }

    private var reorderGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 7),
                count: 4
            ),
            spacing: 9
        ) {
            ForEach(
                Array(
                    model.clips
                        .filter { !$0.isVideoSegmentChild }
                        .enumerated()
                ),
                id: \.element.id
            ) {
                index,
                clip in
                GeometryReader { proxy in
                    ZStack {
                        Image(uiImage: clip.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: proxy.size.width,
                                height: proxy.size.height
                            )
                            .clipped()

                        if clip.isVideoSegmentParent {
                            LinearGradient(
                                colors: [
                                    HanClipTheme.secondary.opacity(0.30),
                                    HanClipTheme.primary.opacity(0.28),
                                    Color.black.opacity(0.14)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .blendMode(.multiply)

                            HanClipTheme.secondary.opacity(0.18)
                        }

                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.34),
                                Color.clear,
                                Color.black.opacity(0.40)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        Text("\(index + 1)")
                            .font(
                                .system(
                                    size: 12,
                                    weight: .bold,
                                    design: .monospaced
                                )
                            )
                            .foregroundStyle(.white)
                            .frame(width: 23, height: 23)
                            .background(
                                HanClipTheme.primary.opacity(0.88),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white.opacity(0.34),
                                        lineWidth: 0.8
                                    )
                            }
                            .shadow(
                                color: Color.black.opacity(0.22),
                                radius: 3,
                                y: 1
                            )
                            .padding(5)
                    }
                    .overlay(alignment: .topTrailing) {
                        Text(reorderMediaTitle(for: clip))
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 6)
                            .frame(height: 22)
                            .background(
                                HanClipTheme.primary.opacity(0.84),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        Color.white.opacity(0.28),
                                        lineWidth: 0.8
                                    )
                            }
                            .shadow(
                                color: Color.black.opacity(0.22),
                                radius: 3,
                                y: 1
                            )
                            .multilineTextAlignment(.trailing)
                            .padding(5)
                    }
                    .overlay(alignment: .bottom) {
                        Text(projectDurationText(clip.duration))
                            .font(
                                .system(
                                    size: 12,
                                    weight: .semibold,
                                    design: .monospaced
                                )
                            )
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.46),
                                        Color.black.opacity(0.20)
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .shadow(
                                color: Color.black.opacity(0.26),
                                radius: 2,
                                y: 1
                            )
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if clip.isVideoSegmentParent {
                            Text("\(model.childSegmentCount(for: clip.id))")
                                .font(
                                    .system(
                                        size: 15,
                                        weight: .black,
                                        design: .rounded
                                    )
                                )
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .frame(height: 24)
                                .background(
                                    HanClipTheme.primary.opacity(0.82),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            Color.white.opacity(0.30),
                                            lineWidth: 0.8
                                        )
                                }
                                .shadow(
                                    color: Color.black.opacity(0.22),
                                    radius: 3,
                                    y: 1
                                )
                                .padding(5)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                Color.white.opacity(0.40),
                                lineWidth: 0.8
                            )
                    }
                    .shadow(
                        color: HanClipTheme.secondary.opacity(0.12),
                        radius: 5,
                        y: 2
                    )
                    .opacity(1)
                    .contentShape(Rectangle())
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
                        delegate: ClipReorderDropDelegate(
                            targetID: clip.id,
                            clips: $model.clips,
                            draggedClipID: $draggedClipID
                        )
                    )
                    .onTapGesture {
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
                        } else {
                            isAutoAdvancingPreview = false
                            isLoopingPreviewAutoAdvance = false
                            videoSegmentPreviewParentID = nil
                            selectedClipID = clip.id
                        }
                    }
                    .accessibilityLabel(
                        "\(index + 1)번째 \(reorderMediaTitle(for: clip))"
                    )
                    .accessibilityHint(
                        "한 번 누르면 편집을 열고, 누른 뒤 끌면 순서를 변경합니다."
                    )
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
        if clip.isVideoClip {
            return model.canUseMultipleVideoSegments(for: clip.id)
                ? "클립+"
                : "클립"
        }
        if clip.isLivePhoto {
            return "Live"
        }
        return "포토"
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.clear)
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
                    themeModeRaw: themeModeRaw
                )
                .frame(width: 34, height: 34)
            } else {
                Text("첫\n사진")
                    .font(.system(size: 10, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(0)
                    .foregroundStyle(HanClipTheme.secondary)
                    .frame(width: 34, height: 34)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(HanClipTheme.secondary.opacity(0.72), lineWidth: 1)
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
                        Text(model.isPreviewRendering ? "개봉 준비 중" : "준비하고 있습니다")
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
                    .ultraThinMaterial,
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

                if model.isPreviewRendering {
                    Button(role: .cancel) {
                        model.cancelPreviewGeneration()
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
        if model.isImportingSharedItems {
            return model.sharedImportProgress
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
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .background(
                Color.white.opacity(0.30),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
            }
            .shadow(
                color: HanClipTheme.secondary.opacity(0.08),
                radius: 12,
                y: 5
            )
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
            Color.white.opacity(0.30),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
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

private struct ImportantInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WatermarkSettings.customCopyrightIconPathStorageKey)
    private var customIconPath =
        WatermarkSettings.defaultCustomCopyrightIconPath
    @Binding var sleepPreventionModeRaw: String
    @Binding var copyrightEnabled: Bool
    @Binding var platformRaw: String
    @Binding var address: String
    @Binding var positionRaw: String
    @Binding var textColorHex: String
    @Binding var shadowColorHex: String
    @Binding var iconColorModeRaw: String
    @Binding var iconColorHex: String
    @State private var customIconPickerItem: PhotosPickerItem?
    @State private var customIconRefreshID = UUID()

    private let items: [(title: String, body: String)] = [
        (SpecialThanksInfo.title, SpecialThanksInfo.body),
        ("카피라이터", "첫 화면 하단의 i 원형 유리 버튼입니다. 카피라이터 설정과 설정 정보를 보여주는 창입니다."),
        ("첫 화면", "앱 실행 후 영화 만들기와 저장된 영화 목록이 보이는 홈 화면입니다."),
        ("영화 만들기 영역", "첫 화면 상단의 영화 제작 카드입니다. 영화를 시작하기 위해 미디어를 고르는 영역입니다."),
        ("영화 목록", "첫 화면에 저장된 영화들이 표시되는 영역입니다."),
        ("영화 화면", "미디어를 선택한 후 기본 재생 시간, 화면 비율, 클립 리스트 등을 편집하는 화면입니다."),
        ("영화 설정", "영화 화면의 로고 아래, 기본 시간과 자막, 음악을 설정하는 패널입니다."),
        ("클립 리스트", "선택한 Photo, Live, Clip이 순서대로 표시되는 목록입니다. 썸네일, 시간, 아이콘, 세그먼트 컨트롤, +/- 버튼이 있는 영역입니다."),
        ("순서변경 상태", "썸네일을 한 줄에 여러 개 표시하고 드래그해서 클립 순서를 변경하는 상태입니다."),
        ("편집 영역 / 편집 모드", "개별 클립을 누르면 열리는 구간 선택 및 재생 화면입니다."),
        ("시사회", "만들기 완료 후, 저장 또는 개봉하기 직전에 제작된 전체 영화를 확인하는 화면입니다."),
        ("만들기", "전체 클립을 하나의 영상으로 생성하는 액션과 버튼입니다."),
        ("영상 생성 진행창", "영상을 만드는 동안 썸네일, 진행바, 진행률, 취소 버튼이 표시되는 창입니다."),
        ("개봉하기 창", "시사회에서 사진 앱 또는 파일 앱 개봉 방식을 선택하는 창입니다."),
        ("테마 선택창", "로고를 길게 눌렀을 때 6개 테마를 선택하는 창입니다."),
        ("첫 화면 이동 팝업", "편집 중 로고를 눌렀을 때 홈 + 저장, 홈으로를 선택하는 창입니다."),
        ("로고", "상단의 앱 심볼과 HanClip 글자 부분입니다."),
        ("카피라이터 입력", "카피라이터에서 설정하는 기능입니다. 한클립 로고 또는 SNS/기타 표시를 결과 영상에 합성할지 결정합니다."),
        ("세그먼트 컨트롤", "포토 / Live, 단일 / 다중처럼 두 옵션 중 하나를 고르는 스위치형 컨트롤입니다."),
        ("단일 / 다중", "클립을 하나의 구간으로 쓸지, 사운드 피크 기준으로 여러 자클립으로 나눌지 정하는 클립 분할 모드입니다."),
        ("모클립", "다중 분할을 만들 때 원본 역할로 남는 부모 클립입니다."),
        ("자클립", "모클립에서 사운드 피크 기준으로 만들어진 하위 클립입니다."),
        ("웨이브 / 웨이브 인디케이터", "영상/Live Photo 편집에서 소리 파형을 보여주는 영역입니다."),
        ("선택바", "웨이브 인디케이터의 좌우 끝에 있는 드래그 바입니다."),
        ("자동 진행", "편집에서 클립 재생이 끝나면 다음 클립으로 이어지는 기능입니다."),
        ("무한 루프", "편집 상태바의 루프 버튼으로 현재 클립을 반복 재생하는 기능입니다."),
        ("달력 썸네일 버튼", "달력에서 미디어를 고르는 화면에 있는 위/아래 이동 버튼입니다."),
        ("자막", "영화 화면의 미디어 추가 메뉴에서 여는 설정창입니다. 결과 영상 위에 문구를 합성할지, 문구와 색상, 서체, 그림자, 위치를 설정합니다."),
        ("샘플 음악 저작권", """
        HanClip에 포함된 샘플 음악 \(BackgroundMusicSettings.sampleDisplayName)은 앱 기능 검증과 사용자의 일상 영상 배경음악을 위해 인공지능 생성 및 합성 방식으로 만든 샘플 음악입니다.

        이 샘플 음악은 외부 음원, 기존 곡, 상용 음악 라이브러리, 사람의 실연 녹음 파일을 가져와 사용하지 않았으며, HanClip 앱 안에서 제공되는 기본 샘플 자산입니다. 사용자는 이 샘플 음악을 HanClip으로 만든 영상 결과물의 배경음악으로 사용할 수 있습니다.
        """),
        ("외부 호출 주소", "hanclip://photo\nhanclip://calendar\nhanclip://files\nhanclip://open"),
        ("내장 서체 저작권", """
        HanClip에는 사용자가 영상 위에 짧은 문구나 자막을 넣을 때 선택할 수 있도록 Kakao Big Sans, Nanum Gothic, Pretendard, MaruBuri, Puradak Gentle Gothic, Tenada, Cafe24 Ssurround, Dovemayo 서체가 포함되어 있습니다. 이 서체들은 앱 전체 UI 기본 서체가 아니라, 자막과 영상 렌더링 과정에서만 선택적으로 사용됩니다.

        Kakao Big Sans, Nanum Gothic, Pretendard, MaruBuri, Tenada는 SIL Open Font License 1.1 또는 그에 준하는 공식 오픈 라이선스 조건으로 제공됩니다. 해당 라이선스는 서체 파일을 단독으로 판매하지 않는 한 사용, 복사, 앱 또는 소프트웨어 번들, 임베딩, 재배포를 허용합니다. 또한 이 서체를 사용해 만든 영상, 이미지, 문서 같은 결과물 자체는 서체 라이선스의 적용 대상이 아니므로 HanClip으로 만든 영상 결과물의 저작권이나 이용 조건은 사용자가 정한 조건을 따릅니다.

        Nanum Gothic과 MaruBuri의 저작권은 NAVER 및 NAVER Cultural Foundation에 있으며, NAVER 안내에 따라 개인과 기업을 포함한 모든 사용자가 무료로 사용할 수 있고 상업적 사용이 가능합니다. NAVER 안내는 글꼴 자체를 유료로 판매하는 행위를 제외하고, 저작권 안내와 라이선스 전문을 포함해 다른 소프트웨어와 번들하거나 재배포할 수 있다고 설명합니다.

        Pretendard는 Kil Hyung-jin 및 원 기반 서체 저작권자의 저작권 고지와 함께 SIL Open Font License 1.1로 제공됩니다. Pretendard, Source, Inter, M PLUS 1 등 예약된 서체명은 수정본에 임의로 사용할 수 없습니다. HanClip은 공식 배포 파일을 수정하지 않고 앱에 포함합니다.

        Tenada는 공식 배포 페이지에서 SIL Open Font License 1.1로 제공됩니다. 앱에 포함된 Tenada.ttf는 공식 배포본의 원본 파일이며, HanClip에서는 골프 기록, 홀 정보, 스코어 같은 제목형 자막에 사용할 수 있도록 제공합니다.

        Cafe24 Ssurround는 Cafe24 공식 안내에 따라 개인 및 기업 사용자를 포함한 모든 사용자에게 무료로 제공되며 상업적 사용이 가능합니다. Cafe24는 영상 제작 및 자막, 소프트웨어 번들, 특정 프로그램 임베드 등 사용 범위 제한 없이 이용할 수 있다고 안내합니다. 단, 글꼴 자체를 유료로 판매하는 행위는 금지됩니다.

        Puradak Gentle Gothic은 Puradak Chicken 공식 폰트 페이지에서 무료로 배포되는 서체입니다. 공개 사용 안내에 따라 상업적, 비상업적 사용과 영상 자막, 앱 사용, 소프트웨어 번들이 가능하며, HanClip은 공식 TTF 파일을 수정하지 않고 포함합니다. 서체 파일 자체를 단독 판매하거나 저작권 고지를 제거해서 재배포해서는 안 됩니다.

        Dovemayo는 제작자 공식 블로그에서 개인 및 기업의 상업적 이용이 가능하고 자유롭게 사용할 수 있다고 안내된 서체입니다. HanClip은 제작자가 공개한 원본 OTF 파일을 수정하지 않고 포함합니다. 다만 OFL처럼 세부 재배포 조건이 긴 전문 형태로 제공된 서체는 아니므로, HanClip에서는 원본 파일과 저작권 고지를 함께 보관하고 서체 파일 자체를 단독 판매하지 않습니다.

        모든 내장 서체의 라이선스 전문, 저작권 고지, 확인한 공식 배포처 정보는 앱 번들에 포함된 font-licenses 파일을 기준으로 보관합니다. 서체 파일을 수정하거나 별도 재배포하는 경우에는 각 서체의 원 라이선스와 저작권 고지를 유지해야 하며, 예약된 서체명이 있는 경우 수정본에 원래 이름을 사용할 수 없습니다.
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
                            infoRow(title: item.title, body: item.body)
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
                .accessibilityLabel("카피라이터 초기화")
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
                leadingInset: 18,
                trailingInset: -2
            )

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("SNS / 로고")

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
                    sectionTitle("색상")

                    HStack(spacing: 10) {
                        copyrightColorPicker(
                            title: "글자색",
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
                            title: "그림자색",
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
                }
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

    private var copyrightPositionSettings: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("위치")

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
            sectionTitle("화면 꺼짐 방지")

            Picker("화면 꺼짐 방지", selection: $sleepPreventionModeRaw) {
                ForEach(SleepPreventionMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text(sleepPreventionMode.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HanClipTheme.secondaryText)
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
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
                    shadowColorHex: shadowColorHex
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
        iconColorModeRaw =
            WatermarkSettings.defaultCopyrightIconColorMode.rawValue
        applyIconDefaultCopyrightColors(for: resetPlatform)
        loadAddress(for: resetPlatform)
    }

    private func infoRow(title: String, body: String) -> some View {
        InfoRow(
            title: title,
            detail: body,
            isCentered: title == "Special Thanks"
        )
    }
}

private struct TextOverlaySettingsSheet: View {
    private struct SessionState: Equatable {
        var isEnabled: Bool
        var text: String
        var position: WatermarkPosition
        var fontName: String
        var textColorHex: String
        var shadowEnabled: Bool
        var shadowColorHex: String
        var lineSpacing: WatermarkLineSpacing
        var lineSpacingScale: Double
        var fontSize: WatermarkFontSize

        func matchesContent(of other: SessionState) -> Bool {
            text == other.text
                && position == other.position
                && fontName == other.fontName
                && textColorHex == other.textColorHex
                && shadowEnabled == other.shadowEnabled
                && shadowColorHex == other.shadowColorHex
                && lineSpacing == other.lineSpacing
                && abs(lineSpacingScale - other.lineSpacingScale) < 0.001
                && fontSize == other.fontSize
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var showInstalledFontPicker = false
    @State private var showFontFilePicker = false
    @State private var showAdvancedFontSettings = false
    @State private var fontImportNotice: String?
    @State private var textInputBackgroundHex =
        TextOverlaySettingsSheet.randomTextInputBackgroundHex()
    @State private var originalSessionState: SessionState?
    @Binding var textEnabled: Bool
    @Binding var text: String
    @Binding var position: WatermarkPosition
    @Binding var fontName: String
    @Binding var textColorHex: String
    @Binding var shadowEnabled: Bool
    @Binding var shadowColorHex: String
    @Binding var lineSpacing: WatermarkLineSpacing
    @Binding var lineSpacingScale: Double
    @Binding var fontSize: WatermarkFontSize

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
                        resetSettings()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(HanClipTheme.primary)
                    .accessibilityLabel("초기화")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        if hasSessionChanges {
                            FloppyDiskIcon()
                                .frame(width: 17, height: 17)
                        } else {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundStyle(HanClipTheme.primary)
                    .accessibilityLabel(hasSessionChanges ? "저장 후 닫기" : "닫기")
                }
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
            refreshTextInputBackground()
        }
        .onDisappear {
            restoreDisabledStateIfUnchanged()
        }
        .onChange(of: textColorHex) { _, _ in
            refreshTextInputBackground()
        }
        .onChange(of: shadowColorHex) { _, _ in
            refreshTextInputBackground()
        }
    }

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            textInput
        }
        .textOverlaySectionStyle()
    }

    private var textInput: some View {
        let textColor = Color(hexString: textColorHex) ?? HanClipTheme.primary
        let shadowColor = Color(hexString: shadowColorHex)
            ?? HanClipTheme.secondary

        return TextEditor(text: $text)
            .font(textEditorFont(size: textEditorBaseSize))
            .foregroundStyle(textColor)
            .lineSpacing(textEditorLineSpacing(size: textEditorBaseSize))
            .multilineTextAlignment(textEditorAlignment)
            .autocorrectionDisabled()
            .shadow(
                color: shadowColor,
                radius: shadowEnabled ? 9.0 : 0,
                x: 0,
                y: 0
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: textInputMinimumHeight)
            .scrollContentBackground(.hidden)
            .background(
                textInputBackgroundColor.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HanClipTheme.secondary.opacity(0.28), lineWidth: 1)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    clearSampleTextIfNeeded()
                }
            )
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
        HStack(spacing: 8) {
            fontPresetButton(
                title: "가독성",
                fontID: readableThemeFontID,
                textColor: "#FFFFFF",
                shadowColor: "#000000",
                fontSize: .large
            )

            fontPresetButton(
                title: "러블리",
                fontID: lovelyThemeFontID,
                textColor: "#FF6FAE",
                shadowColor: "#7A3FFF",
                fontSize: .large
            )

            fontPresetButton(
                title: "강력",
                fontID: powerfulThemeFontID,
                textColor: "#FFE600",
                shadowColor: "#000000",
                fontSize: .extraLarge
            )
        }
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
        title: String,
        fontID: String,
        textColor: String,
        shadowColor: String,
        fontSize: WatermarkFontSize
    ) -> some View {
        let isSelected = isFontPresetSelected(
            fontID: fontID,
            textColor: textColor,
            shadowColor: shadowColor,
            fontSize: fontSize
        )
        let previewColor = Color(hexString: textColor) ?? .white
        let previewShadowColor = Color(hexString: shadowColor) ?? .black

        return Button {
            applyFontPreset(
                fontID: fontID,
                textColor: textColor,
                shadowColor: shadowColor,
                fontSize: fontSize
            )
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
                    .shadow(color: previewShadowColor, radius: 4, x: 0, y: 0)
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

            Toggle("그림자", isOn: $shadowEnabled)
                .labelsHidden()
                .tint(HanClipTheme.primary)
                .frame(width: 52)
                .accessibilityLabel("그림자")

            colorPickerRow(
                title: "그림자색",
                selection: shadowColorBinding
            )
            .opacity(shadowEnabled ? 1 : 0.34)
            .disabled(!shadowEnabled)
        }
        .frame(minHeight: 42)
        .padding(.vertical, 2)
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
        fontSize: WatermarkFontSize
    ) -> Bool {
        fontName == fontID
            && Self.normalizedHex(textColorHex) == Self.normalizedHex(textColor)
            && shadowEnabled
            && Self.normalizedHex(shadowColorHex)
                == Self.normalizedHex(shadowColor)
            && lineSpacing == .normal
            && abs(
                lineSpacingScale - WatermarkLineSpacing.defaultMultiplier
            ) < 0.001
            && self.fontSize == fontSize
    }

    private var readableThemeFontID: String {
        allowedTextFontNames.contains("pretendard")
            ? "pretendard"
            : FontRegistry.systemFontID
    }

    private var lovelyThemeFontID: String {
        allowedTextFontNames.contains("ddulgi_mayo")
            ? "ddulgi_mayo"
            : readableThemeFontID
    }

    private var powerfulThemeFontID: String {
        allowedTextFontNames.contains("tenada")
            ? "tenada"
            : readableThemeFontID
    }

    private func applyFontPreset(
        fontID: String,
        textColor: String,
        shadowColor: String,
        fontSize: WatermarkFontSize
    ) {
        fontName = fontID
        textColorHex = Self.normalizedHex(textColor)
        shadowEnabled = true
        shadowColorHex = Self.normalizedHex(shadowColor)
        lineSpacing = .normal
        lineSpacingScale = WatermarkLineSpacing.defaultMultiplier
        self.fontSize = fontSize
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

    private var textEditorBaseSize: CGFloat {
        14 * CGFloat(fontSize.multiplier)
    }

    private var textInputMinimumHeight: CGFloat {
        max(112, textEditorBaseSize * 5.8)
    }

    private func textEditorLineSpacing(size: CGFloat) -> CGFloat {
        size * CGFloat(lineSpacingScale - WatermarkLineSpacing.defaultMultiplier)
    }

    private func refreshTextInputBackground() {
        textInputBackgroundHex = Self.randomTextInputBackgroundHex(
            excluding: [textColorHex, shadowColorHex]
        )
    }

    private var textInputBackgroundColor: Color {
        Color(hexString: textInputBackgroundHex) ?? Color.white
    }

    private static func randomTextInputBackgroundHex(
        excluding excludedHexes: [String] = []
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

        return candidates.max { $0.score < $1.score }?.hex ?? "#FFF7C7"
    }

    private static func uiColor(_ hexString: String) -> UIColor? {
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

    private static func contrastRatio(
        between first: UIColor,
        and second: UIColor
    ) -> CGFloat {
        let firstLuminance = relativeLuminance(of: first)
        let secondLuminance = relativeLuminance(of: second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(of color: UIColor) -> CGFloat {
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

    private static func normalizedHex(_ hex: String) -> String {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("#")
            ? trimmed.uppercased()
            : "#\(trimmed.uppercased())"
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
        let defaults = WatermarkSettings.projectDefault()
        textEnabled = defaults.isEnabled
        text = WatermarkSettings.defaultText
        position = defaults.position
        fontName = defaults.fontName
        textColorHex = defaults.textColorHex
        shadowEnabled = defaults.shadowEnabled
        shadowColorHex = defaults.shadowColorHex
        lineSpacing = defaults.lineSpacing
        lineSpacingScale = defaults.lineSpacingScale
        fontSize = defaults.fontSize
        refreshTextInputBackground()
    }

    private func clearSampleTextIfNeeded() {
        let sampleTexts = [
            WatermarkSettings.defaultText,
            WatermarkSettings.legacyDefaultText
        ]
        guard sampleTexts.contains(text) else { return }
        text = ""
    }

    private func applyDefaultSettingsIfNeeded() {
        guard [
            WatermarkSettings.defaultText,
            WatermarkSettings.legacyDefaultText
        ].contains(text),
              position == WatermarkSettings.defaultPosition,
              textColorHex == WatermarkSettings.defaultTextColor,
              shadowColorHex == WatermarkSettings.defaultShadowColor
        else { return }

        resetSettings()
    }

    private func beginEditingSessionIfNeeded() {
        guard originalSessionState == nil else { return }
        let state = currentSessionState()
        originalSessionState = state
        if !state.isEnabled {
            textEnabled = true
        }
    }

    private func restoreDisabledStateIfUnchanged() {
        guard let originalSessionState,
              !originalSessionState.isEnabled,
              currentSessionState().matchesContent(of: originalSessionState)
        else { return }

        textEnabled = false
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
            isEnabled: textEnabled,
            text: text,
            position: position,
            fontName: fontName,
            textColorHex: Self.normalizedHex(textColorHex),
            shadowEnabled: shadowEnabled,
            shadowColorHex: Self.normalizedHex(shadowColorHex),
            lineSpacing: lineSpacing,
            lineSpacingScale: lineSpacingScale,
            fontSize: fontSize
        )
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
    let isCentered: Bool

    var body: some View {
        VStack(
            alignment: isCentered ? .center : .leading,
            spacing: 6
        ) {
            Text(title)
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

private struct TextOverlaySummaryRow: View {
    let settings: WatermarkSettings
    @Binding var isEnabled: Bool
    let onSelect: () -> Void

    private var statusText: String {
        isEnabled && !settings.displayText.isEmpty ? "사용" : "안함"
    }

    private var textPreview: String {
        let text = settings.displayText
        return text.isEmpty ? "자막 내용 없음" : text
    }

    private var detailText: String {
        [
            settings.fontSize.title,
            settings.position.title,
            settings.shadowEnabled ? "그림자 사용" : "그림자 안함"
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
                .frame(height: 42, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            InlineStatusToggle(
                title: "상태",
                value: statusText,
                isOn: $isEnabled,
                isEnabled: !settings.displayText.isEmpty
            )
        }
        .frame(height: 42)
        .contentShape(Rectangle())
        .accessibilityLabel("자막")
        .accessibilityHint("자막 편집 화면을 엽니다.")
    }
}

private struct BackgroundMusicSummaryRow: View {
    let settings: BackgroundMusicSettings
    @Binding var isEnabled: Bool
    let onSelect: () -> Void

    private var statusText: String {
        settings.hasMusicFile && isEnabled ? "사용" : "안함"
    }

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
                .frame(height: 42, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            InlineStatusToggle(
                title: "상태",
                value: statusText,
                isOn: $isEnabled,
                isEnabled: settings.hasMusicFile
            )
        }
        .frame(height: 42)
        .contentShape(Rectangle())
        .accessibilityLabel("음악")
        .accessibilityHint("음악 설정 화면을 엽니다.")
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }
}

private struct InlineStatusToggle: View {
    let title: String
    let value: String
    @Binding var isOn: Bool
    let isEnabled: Bool

    var body: some View {
        Button {
            guard isEnabled else { return }
            isOn.toggle()
        } label: {
            HStack(spacing: 3) {
                Text("\(title) :")
                    .font(.system(size: 10, weight: .semibold))

                Text(value)
                    .font(.system(size: 10, weight: .black))
            }
            .foregroundStyle(
                isOn && isEnabled
                    ? .white
                    : HanClipTheme.secondaryText.opacity(isEnabled ? 0.82 : 0.45)
            )
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule()
                    .fill(
                        isOn && isEnabled
                            ? HanClipTheme.secondary.opacity(0.92)
                            : HanClipTheme.secondary.opacity(0.13)
                    )
            )
            .overlay {
                Capsule()
                    .stroke(
                        Color.white.opacity(isOn && isEnabled ? 0.26 : 0.0),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("\(title) \(value)")
        .accessibilityHint("눌러서 사용과 안함을 바꿉니다.")
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
    @Environment(\.dismiss) private var dismiss
    @State private var previewPlayer: AVAudioPlayer?
    @State private var activePreviewID: String?
    @State private var originalSessionState: SessionState?
    @State private var isOpeningMusicPicker = false

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
                            HStack(spacing: 12) {
                                toggleRow("페이드 인", isOn: $fadeInEnabled)
                                toggleRow("페이드 아웃", isOn: $fadeOutEnabled)
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
                    Button {
                        dismiss()
                    } label: {
                        if hasSessionChanges {
                            FloppyDiskIcon()
                                .frame(width: 17, height: 17)
                        } else {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundStyle(HanClipTheme.primary)
                    .accessibilityLabel(hasSessionChanges ? "저장 후 닫기" : "닫기")
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

            fileMusicPickerRow

            if settings.hasMusicFile {
                InlineStatusToggle(
                    title: "상태",
                    value: isEnabled ? "사용" : "안함",
                    isOn: $isEnabled,
                    isEnabled: settings.hasMusicFile
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var fileMusicPickerRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                actionButton(
                    "음악 파일 불러오기",
                    systemImage: "folder",
                    isPrimary: false,
                    action: {
                        isOpeningMusicPicker = true
                        onPickMusic()
                    }
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
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPrimary ? .white : HanClipTheme.primary)
        .background(
            isPrimary
                ? HanClipTheme.primary
                : HanClipTheme.primary.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
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

        if activePreviewID == id {
            stopPreview()
            return
        }

        stopPreview()

        do {
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

    var body: some View {
        HStack(spacing: 0) {
            segment(title: "사용", value: true)
            segment(title: "안함", value: false)
        }
        .padding(3)
        .background(
            HanClipTheme.secondary.opacity(0.14),
            in: Capsule()
        )
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.snappy) {
                isEnabled.toggle()
            }
        }
    }

    private func segment(title: String, value: Bool) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(isEnabled == value ? .white : HanClipTheme.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background {
                if isEnabled == value {
                    Capsule()
                        .fill(HanClipTheme.primary)
                }
            }
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
                .opacity(0.42),
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

private struct CalendarThumbnailItem {
    let thumbnail: UIImage
    let mediaKind: ClipMediaKind
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
            .map { clip in
                if clip.isVideoSegmentParent {
                    return [clip.id] + clips
                        .filter { $0.videoSegmentParentID == clip.id }
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
                    isSelected ? HanClipTheme.primary : HanClipTheme.secondary,
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
                .foregroundStyle(HanClipTheme.secondary.opacity(0.72))

            TextField("메모 추가", text: $text)
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
                    HanClipTheme.secondary.opacity(0.055),
                    Color.white.opacity(0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
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
                player.play()
            }
        ) {
            VideoShareSheet(items: [url])
        }
        .fullScreenCover(
            isPresented: $isFullscreenPreviewPresented,
            onDismiss: {
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
        player.play()
    }
}

private struct FullscreenVideoPreview: View {
    let url: URL
    let startTime: CMTime
    let onClose: () -> Void

    @State private var player: AVPlayer
    @State private var loopObserver: NSObjectProtocol?
    @State private var isLandscapeVideo = false

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
                fullscreenPlayer(in: proxy.size)
                    .frame(
                        width: isLandscapeVideo
                            ? proxy.size.height
                            : proxy.size.width,
                        height: isLandscapeVideo
                            ? proxy.size.width
                            : proxy.size.height
                    )
                    .rotationEffect(isLandscapeVideo ? .degrees(90) : .zero)
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
            updateVideoOrientation()
            installLoopObserverIfNeeded()
            player.seek(
                to: startTime,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            player.play()
        }
        .onDisappear {
            removeLoopObserver()
            player.pause()
        }
    }

    private func fullscreenPlayer(in size: CGSize) -> some View {
        PreviewPlayerSurface(player: player)
            .frame(width: size.width, height: size.height)
    }

    private func installLoopObserverIfNeeded() {
        guard loopObserver == nil else { return }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
        }
    }

    private func removeLoopObserver() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
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
                isLandscapeVideo = orientedSize.width > orientedSize.height
            }
        }
    }
}

private struct PreviewPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PreviewPlayerSurfaceView {
        let view = PreviewPlayerSurfaceView()
        view.playerLayer.player = player
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
                    set: { currentSeconds = $0 }
                ),
                in: 0...sliderMaximum,
                onEditingChanged: scrubberChanged
            )
            .tint(HanClipTheme.primary)

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
        .accessibilityLabel(isLooping ? "무한 루프 끄기" : "무한 루프 켜기")
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

        reachedEnd = durationSeconds > 0
            && currentSeconds >= durationSeconds - 0.05
        player.seek(
            to: CMTime(seconds: currentSeconds, preferredTimescale: 600),
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
    @State private var thumbnailLoadTask: Task<Void, Never>?
    @State private var thumbnailColumnCount = 6
    @State private var thumbnailMagnificationCheckpoint: CGFloat = 1
    @State private var thumbnailScrollOffset: CGFloat = 0
    @State private var areThumbnailScrollButtonsVisible = false
    @State private var thumbnailScrollButtonsHideTask: Task<Void, Never>?

    let onConfirm: (Set<Date>) -> Void

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
        onConfirm: @escaping (Set<Date>) -> Void
    ) {
        let calendar = Calendar.current
        let month = calendar.date(
            from: calendar.dateComponents([.year, .month], from: initialMonth)
        ) ?? initialMonth
        _visibleMonth = State(initialValue: month)
        _mediaDates = State(initialValue: initialMediaDates)
        _mediaCountsByDate = State(initialValue: initialMediaCounts)
        _loadedMediaMonth = State(initialValue: month)
        _draftYear = State(
            initialValue: calendar.component(.year, from: month)
        )
        _draftMonth = State(
            initialValue: calendar.component(.month, from: month)
        )
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(HanClipTheme.backgroundGradient.ignoresSafeArea())
            .interactiveDismissDisabled(true)
            .task(id: visibleMonth) {
                await loadHolidayDates()
                await loadMediaDates()
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
                thumbnailPreviewOverlay
            }
            }
    }

    private var thumbnailPreviewOverlay: some View {
        GeometryReader { geometry in
            if let previewedThumbnailItem {
                let previewWidth = geometry.size.width * 0.7
                let iconBaseWidth = max(
                    geometry.size.width - 28 - 4 * CGFloat(6 - 1),
                    0
                ) / 6
                let iconSize = iconBaseWidth / 3

                Image(uiImage: previewedThumbnailItem.thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .frame(width: previewWidth, height: previewWidth)
                    .background(HanClipTheme.secondary.opacity(0.82))
                    .clipShape(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.38), lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        calendarThumbnailMediaIcon(
                            for: previewedThumbnailItem.mediaKind,
                            size: iconSize,
                            opacity: thumbnailMediaIconOpacity(
                                for: thumbnailColumnCount
                            )
                        )
                        .padding(.top, 14)
                    }
                    .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .animation(.snappy(duration: 0.16), value: previewedThumbnailItem != nil)
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
                dismiss()
            }
            .foregroundStyle(HanClipTheme.text.opacity(0.72))
            .calendarActionButtonStyle()

            Spacer()

            Button("오늘") {
                withAnimation(.snappy) {
                    moveToToday()
                }
            }
            .foregroundStyle(HanClipTheme.primary)
            .calendarActionButtonStyle()

            Spacer()

            Button("확인") {
                onConfirm(selectedDates)
            }
            .foregroundStyle(
                selectedDates.isEmpty
                    ? HanClipTheme.text.opacity(0.35)
                    : HanClipTheme.secondary
            )
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
                let dividerWidth: CGFloat = 1
                let spacing: CGFloat = 12
                let usableWidth = max(0, geometry.size.width - spacing - dividerWidth)
                let leftWidth = usableWidth * 2 / 3
                let rightWidth = usableWidth - leftWidth

                HStack(spacing: spacing) {
                    Button {
                        withAnimation(.snappy) {
                            handleTodayDoubleTap()
                        }
                    } label: {
                        Text("선택 \(selectedDates.count)일 · 미디어 \(selectedMediaCount)개")
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: leftWidth, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(width: dividerWidth)
                        .overlay(HanClipTheme.secondary.opacity(0.22))
                        .padding(.vertical, 10)

                    Button {
                        clearSelectedCalendarMedia()
                    } label: {
                        Label("지우기", systemImage: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: rightWidth, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedDates.isEmpty)
                }
            }
            .foregroundStyle(
                selectedDates.isEmpty
                    ? HanClipTheme.text.opacity(0.45)
                    : HanClipTheme.secondary
            )
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.horizontal, 16)
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
            .accessibilityElement(children: .combine)
            .accessibilityHint("왼쪽은 사진 선택, 오른쪽은 지우기입니다.")
            .accessibilityAddTraits(.isButton)
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
    }

    private var selectedThumbnailGrid: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 4
            let horizontalPadding: CGFloat = 14
            let cornerRadius: CGFloat = 16
            let fadeHeight: CGFloat = 50
            let bottomThumbnailPadding = fadeHeight + spacing
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
                                Image(uiImage: item.thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: itemSize, height: itemSize)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: max(2, itemSize * 0.035),
                                            style: .continuous
                                        )
                                    )
                                    .overlay(alignment: .bottomLeading) {
                                        calendarThumbnailMediaIcon(
                                            for: item.mediaKind,
                                            size: mediaIconSize,
                                            opacity: mediaIconOpacity
                                        )
                                        .padding(sixColumnThumbnailSize * 0.06)
                                    }
                                    .onLongPressGesture(
                                        minimumDuration: 0.22,
                                        maximumDistance: 14,
                                        pressing: { isPressing in
                                            if !isPressing {
                                                previewedThumbnailItem = nil
                                            }
                                        }
                                    ) {
                                        previewedThumbnailItem = item
                                    }
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
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: hasMedia ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(dateTextColor(for: date))

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
        selectedDates.reduce(0) { partialResult, date in
            partialResult + (mediaCountsByDate[date] ?? 0)
        }
    }

    private func dateTextColor(for date: Date) -> Color {
        if isSunday(date) || isKoreanHoliday(date) {
            return restDayColor
        }
        if calendar.isDateInToday(date) {
            return HanClipTheme.primary
        }
        if isSaturday(date) {
            return saturdayColor
        }
        return HanClipTheme.text
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
        HanClipTheme.rosyBrownPrimary
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
                    calendar: Calendar.current
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
                    calendar: Calendar.current
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
        thumbnailLoadTask = Task {
            let assets = await Task.detached {
                PhotoLibraryService.mediaAssets(
                    on: dates,
                    calendar: Calendar.current
                )
            }.value

            var thumbnails: [CalendarThumbnailItem] = []
            for asset in assets {
                guard !Task.isCancelled,
                      let thumbnail = try? await PhotoLibraryService
                        .thumbnail(
                            for: asset,
                            size: CGSize(width: 240, height: 240)
                        )
                else { continue }
                thumbnails.append(
                    CalendarThumbnailItem(
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
                calendar: Calendar.current
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
