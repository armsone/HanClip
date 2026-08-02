import AVKit
import CoreText
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct EditorView: View {
    @StateObject private var model = EditorViewModel()
    @State private var isReordering = false
    @State private var showResetConfirmation = false
    @State private var showThemeSelection = false
    @State private var showImportantInfo = false
    @State private var showTextOverlaySettings = false
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
    @State private var isDeleteDropTargeted = false
    @State private var isSharedInboxBannerDismissed = false
    @State private var bulkLivePhotoMode = LivePhotoMode.motion
    @AppStorage("hanClipThemeMode") private var themeModeRaw =
        HanClipThemeMode.automatic.rawValue
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

    private var themeMode: HanClipThemeMode {
        HanClipThemeMode(rawValue: themeModeRaw) ?? .automatic
    }

    private var isSharedInboxBannerVisible: Bool {
        !model.isProjectOpen
            && model.pendingSharedItemCount > 0
            && !isSharedInboxBannerDismissed
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Image("LogoMarkV2")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 35.2, height: 35.2)

                        Text("HanClip")
                            .font(.system(size: 26, weight: .semibold))
                    }
                        .frame(width: 154, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(HanClipTheme.primary)
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
                                    case .second(_):
                                        handleLogoTap()
                                    default:
                                        break
                                    }
                                }
                        )
                        .accessibilityLabel("HanClip")
                        .accessibilityHint(
                            model.isProjectOpen
                                ? "한 번 누르면 첫 화면 이동 여부를 묻고, 길게 누르면 테마 선택창을 엽니다."
                                : "한 번 누르면 다음 테마로 변경하고, 길게 누르면 테마 선택창을 엽니다."
                        )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    mediaImportMenu {
                        Label("미디어 추가", systemImage: "photo.badge.plus")
                    }
                    .tint(HanClipTheme.secondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !model.clips.isEmpty {
                    makeButton
                } else if !model.isProjectOpen {
                    importantInfoButton
                }
            }
            .blur(
                radius: isBusyOverlayVisible || isSharedInboxBannerVisible
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
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if let importSelectionNotice {
                    Text(importSelectionNotice)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(HanClipTheme.secondary, in: Capsule())
                        .padding(.top, themeNotice == nil ? 8 : 52)
                        .transition(.move(edge: .top).combined(with: .opacity))
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
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.snappy) {
                                    pendingSegmentResetClipID = nil
                                }
                            }

                        VStack(spacing: 18) {
                            ZStack {
                                Circle()
                                    .fill(HanClipTheme.primary.opacity(0.12))
                                    .frame(width: 46, height: 46)

                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(HanClipTheme.primary)
                            }

                            VStack(spacing: 6) {
                                Text("Reset?")
                                    .font(.system(size: 22, weight: .heavy))
                                    .foregroundStyle(HanClipTheme.text)

                                Text("자영상 편집 내역을 처음 상태로 돌릴까요?")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(
                                        HanClipTheme.text.opacity(0.58)
                                    )
                                    .multilineTextAlignment(.center)
                            }

                            HStack(spacing: 10) {
                                Button {
                                    withAnimation(.snappy) {
                                        pendingSegmentResetClipID = nil
                                    }
                                } label: {
                                    Text("No")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(HanClipTheme.secondary)
                                        .frame(width: 94, height: 40)
                                        .background(
                                            HanClipTheme.secondary.opacity(0.10),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    confirmSegmentReset()
                                } label: {
                                    Text("Yes")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 94, height: 40)
                                        .background(
                                            HanClipTheme.primary,
                                            in: Capsule()
                                        )
                                        .shadow(
                                            color: HanClipTheme.primary
                                                .opacity(0.24),
                                            radius: 8,
                                            y: 4
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                        .frame(maxWidth: 300)
                        .background(.ultraThinMaterial)
                        .background(
                            HanClipTheme.background.opacity(0.88),
                            in: RoundedRectangle(
                                cornerRadius: 26,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 26,
                                style: .continuous
                            )
                            .stroke(
                                HanClipTheme.primary.opacity(0.30),
                                lineWidth: 1
                            )
                        }
                        .shadow(
                            color: Color.black.opacity(0.20),
                            radius: 22,
                            y: 10
                        )
                    }
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if isSharedInboxBannerVisible {
                    sharedInboxBanner
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .transition(
                            .move(edge: .top).combined(with: .opacity)
                        )
                }
            }
        }
        .blur(
            radius: showResetConfirmation
                || showThemeSelection
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
            value: showThemeSelection
        )
        .animation(
            .easeInOut(duration: 0.20),
            value: selectedClipID != nil
        )
        .preferredColorScheme(themeMode.colorScheme)
        .overlay {
            GeometryReader { proxy in
                if showResetConfirmation || showThemeSelection {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.20)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.snappy) {
                                    showResetConfirmation = false
                                    showThemeSelection = false
                                }
                            }

                        if showResetConfirmation {
                            resetConfirmationPopup
                                .frame(width: proxy.size.width)
                                .transition(
                                    .move(edge: .top)
                                        .combined(with: .opacity)
                                )
                        } else {
                            themeSelectionPopup
                                .frame(width: proxy.size.width * 0.92)
                                .transition(
                                    .move(edge: .top)
                                        .combined(with: .opacity)
                                )
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $model.isPickerPresented) {
            PhotoPicker(onComplete: model.addPickedItems)
                .ignoresSafeArea()
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
                    if videoSegmentPreviewParentID != nil {
                        videoSegmentParentPreviewHeader
                        videoSegmentChildOrderStrip
                    }

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
                        }
                    )
                }
                .id(id)
                .ignoresSafeArea(edges: videoSegmentPreviewParentID != nil ? [] : [])
            }
        }
        .sheet(
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
            ImportantInfoSheet(
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
        .fileExporter(
            isPresented: $model.showFileExporter,
            document: model.fileDocument,
            contentType: .mpeg4Movie,
            defaultFilename: "HanClip-\(formattedDate).mp4"
        ) { result in
            switch result {
            case .success:
                model.alertMessage = "선택한 위치에 저장했습니다."
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
            model.reloadProjects()
            model.handlePendingSharedItemsOnActivation()
            isSharedInboxBannerDismissed = false
            handlePendingQuickAction()
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
            }
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

    private func handlePendingQuickAction() {
        guard let action = quickActionRouter.pendingAction else { return }

        handleQuickAction(action)
        quickActionRouter.clear(action)
    }

    private func handleQuickAction(_ action: HanClipQuickAction) {
        showResetConfirmation = false
        showThemeSelection = false
        closeClipPreview()
        isSharedInboxBannerDismissed = true

        switch action {
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

    private var videoSegmentChildOrderStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(currentPreviewClips.enumerated()), id: \.element.id) {
                    index,
                    clip in
                    Image(uiImage: clip.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                                    HanClipTheme.primary.opacity(0.70),
                                    in: Circle()
                                )
                                .padding(3)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    selectedClipID == clip.id
                                        ? HanClipTheme.primary
                                        : HanClipTheme.secondary.opacity(0.30),
                                    lineWidth: selectedClipID == clip.id ? 2 : 1
                                )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedClipID = clip.id
                        }
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
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(HanClipTheme.secondary.opacity(0.08))
    }

    private var videoSegmentParentPreviewHeader: some View {
        VStack(spacing: 4) {
            Text("📥")
                .font(.system(size: 44))

            Text("모영상")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(HanClipTheme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(HanClipTheme.background)
    }

    private var sharedInboxBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 36, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text("공유 파일 \(model.pendingSharedItemCount)개")
                        .font(.system(size: 16, weight: .semibold))
                    Text("사진 및 영상 선택 또는 프로젝트를 열면 추가됩니다.")
                        .font(.system(size: 12))
                        .opacity(0.82)
                    sharedInboxThumbnailStrip
                        .padding(.top, 3)
                }

                Spacer(minLength: 4)

                Button {
                    withAnimation(.snappy) {
                        model.deletePendingSharedItems()
                        isSharedInboxBannerDismissed = true
                    }
                } label: {
                    Text("지우기")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HanClipTheme.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("공유 공간의 대기 파일을 삭제합니다.")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                HanClipTheme.primary,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                dismissSharedInboxBanner()
            }

            Button {
                dismissSharedInboxBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HanClipTheme.secondary)
                    .frame(width: 38, height: 38)
                    .background(.white, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(
                                HanClipTheme.secondary.opacity(0.24),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(0.14),
                        radius: 6,
                        y: 3
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("알림 닫기")
            .accessibilityHint("공유 파일은 보관하고 알림만 닫습니다.")
        }
    }

    private var sharedInboxThumbnailStrip: some View {
        HStack(spacing: 3) {
            ForEach(
                Array(model.pendingSharedThumbnails.enumerated()),
                id: \.offset
            ) { _, thumbnail in
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 35, height: 35)
                    .clipped()
            }

            if model.pendingSharedItemCount > 5 {
                Text("....")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
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

            Button {
                selectMediaImportSource("텍스트") {
                    showTextOverlaySettings = true
                }
            } label: {
                Label("텍스트", systemImage: "textformat")
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

        let notice = "\(title) 선택"

        withAnimation(.snappy) {
            importSelectionNotice = notice
        }

        action()

        Task {
            try? await Task.sleep(for: .milliseconds(900))
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

    private var resetConfirmationPopup: some View {
        VStack(spacing: 12) {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.snappy) {
                            showResetConfirmation = false
                            videoSegmentPreviewParentID = nil
                            isReordering = false
                            model.saveProjectAndReturnHome()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            FloppyDiskIcon()
                                .frame(width: 20, height: 20)
                            Text("홈 + 저장")
                        }
                            .frame(maxWidth: .infinity)
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .buttonStyle(.borderedProminent)
                    .tint(HanClipTheme.primary)

                    Button {
                        withAnimation(.snappy) {
                            showResetConfirmation = false
                            videoSegmentPreviewParentID = nil
                            selectedClipID = nil
                            draggedClipID = nil
                            isReordering = false
                            model.returnHomeWithoutSaving()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 20, height: 20)
                            Text("홈으로")
                        }
                            .frame(maxWidth: .infinity)
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondary)
                    .buttonStyle(.bordered)
                    .tint(HanClipTheme.secondary)
                }
                .controlSize(.large)

                VStack(spacing: 6) {
                    Text("홈으로 이동할까요?")
                        .font(.system(size: 16, weight: .semibold))

                    Text("저장하고 이동하거나, 저장 없이 홈으로 이동할 수 있습니다.")
                        .font(.system(size: 14))
                        .foregroundStyle(HanClipTheme.text.opacity(0.62))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
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
            .contentShape(Rectangle())
            .onTapGesture {
                dismissResetConfirmation()
            }

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
        }
    }

    private var themeSelectionPopup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SELECT THEME")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HanClipTheme.text)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            VStack(spacing: -2) {
                ForEach(HanClipThemeMode.allCases, id: \.rawValue) { mode in
                    Button {
                        selectTheme(mode)
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

                            Spacer()

                            if let colors = HanClipTheme.previewColors(
                                for: mode
                            ) {
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
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                        .padding(.horizontal, 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        themeMode == mode ? "선택됨" : "선택되지 않음"
                    )

                    if mode != HanClipThemeMode.allCases.last {
                        Divider()
                            .padding(.leading, 50)
                    }
                }
            }
            .padding(.bottom, 8)
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

    private func selectTheme(_ mode: HanClipThemeMode) {
        themeModeRaw = mode.rawValue
        let notice = "\(mode.displayName)로 변경했습니다."

        withAnimation(.snappy) {
            showThemeSelection = false
        }

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
            withAnimation(.snappy) {
                showResetConfirmation = true
            }
        } else {
            selectNextTheme()
        }
    }

    private func selectNextTheme() {
        let modes = HanClipThemeMode.allCases
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
                VStack(spacing: 0) {
                    Button {
                        model.openPicker()
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("NEW PROJECT")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(
                                    HanClipTheme.text.opacity(0.30)
                                )
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .trailing
                                )
                                .padding(.horizontal, 18)

                            VStack(spacing: 16) {
                                HStack(spacing: 10) {
                                    Image(systemName: "photo.stack")
                                    Text("Han 개의 Clip으로")
                                    Image(systemName: "film")
                                }
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(HanClipTheme.secondary)

                                Text(
                                    "영상이나 사진이나 Live Photo를 선택하시면\n하나의 영상으로 이어 붙여 드립니다."
                                )
                                .font(.system(size: 16))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(
                                    HanClipTheme.secondary.opacity(0.70)
                                )

                                Label(
                                    "사진 및 영상 선택",
                                    systemImage: "photo.on.rectangle.angled"
                                )
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                                .background(
                                    HanClipTheme.primary,
                                    in: Capsule()
                                )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .background(
                                HanClipTheme.secondary.opacity(0.10),
                                in: RoundedRectangle(
                                    cornerRadius: 24,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 24,
                                    style: .continuous
                                )
                                .stroke(
                                    HanClipTheme.primary.opacity(0.30),
                                    lineWidth: 1
                                )
                            }
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
        .accessibilityHint("중요 정보 창을 엽니다.")
    }

    private var savedProjectList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(model.savedProjects.count)/10")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HanClipTheme.secondary)
                Spacer()
                Text("PROJECT LIST")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.gray.opacity(0.70))
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
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                Group {
                    if let thumbnail = ProjectStore.thumbnailImage(for: project) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(HanClipTheme.secondary)
                    }
                }
                .frame(width: 62, height: 62)
                .background(HanClipTheme.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(project.updatedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        ))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(HanClipTheme.text.opacity(0.6))
                        .lineLimit(1)
                        .offset(y: 2)

                        if model.newlySavedProjectID == project.id {
                            Text("NEW")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(HanClipTheme.primary)
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
                    .foregroundStyle(HanClipTheme.text.opacity(0.62))
                    .offset(y: -2)

                    projectThumbnailStrip(project)
                        .offset(y: -4)
                }

                Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    model.loadProjectAndImportPending(id: project.id)
                }
                .onLongPressGesture(minimumDuration: 0.6) {
                    withAnimation {
                        model.toggleProjectPin(id: project.id)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint(
                    "한 번 누르면 프로젝트를 열고, 길게 누르면 상단 고정을 전환합니다."
                )

                if project.isPinned {
                    Button {
                        withAnimation {
                            model.toggleProjectPin(id: project.id)
                        }
                    } label: {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(HanClipTheme.primary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("핀 해제")
                    .accessibilityHint(
                        "이 프로젝트의 상단 고정을 해제합니다."
                    )
                }
            }

            ProjectMemoField(
                projectID: project.id,
                memo: project.memo
            ) { memo in
                model.updateProjectMemo(id: project.id, memo: memo)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            HanClipTheme.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    HanClipTheme.primary.opacity(0.30),
                    lineWidth: 1
                )
        }
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
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if project.clipCount > 9 {
                Text("....")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(HanClipTheme.text.opacity(0.62))
            }
        }
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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .scrollIndicators(.hidden)
                .background(
                    HanClipTheme.secondary.opacity(0.06)
                )
            } else {
                clipList
            }
        }
    }

    private var clipList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                clipEditorSettings

                clipModeHeader

                if model.textOverlaySettings.shouldRenderText {
                    TextOverlaySummaryRow(
                        settings: model.textOverlaySettings,
                        onSelect: {
                            showTextOverlaySettings = true
                        }
                    )
                    .padding(
                        EdgeInsets(
                            top: 5,
                            leading: 4,
                            bottom: model.clips.isEmpty ? 18 : 5,
                            trailing: 16
                        )
                    )
                    .background(HanClipTheme.secondary.opacity(0.10))
                }

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
                                    videoSegmentPreviewParentID = clip.id
                                    selectedClipID = firstChildClip.id
                                },
                                onSelect: {
                                    guard !clip.isVideoSegmentParent else { return }
                                    videoSegmentPreviewParentID = nil
                                    selectedClipID = clip.id
                                }
                            )
                            .padding(clipRowInsets(for: clip.id))
                            .background(
                                clip.isVideoSegmentParent
                                    ? HanClipTheme.secondary.opacity(0.30)
                                    : clip.isVideoSegmentChild
                                        ? HanClipTheme.secondary.opacity(0.04)
                                        : HanClipTheme.secondary.opacity(0.06)
                            )
                            .accessibilityHint(
                                "눌러서 에디터를 열고, 순서 변경 버튼에서 위치를 바꿉니다."
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

    private var clipEditorSettings: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                Text("PROJECT EDIT")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.gray.opacity(0.70))
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 2)

            defaultDurationPanel
                .padding(.horizontal, 4)
                .padding(.top, 0)
                .padding(.bottom, 8)
        }
    }

    private var clipListFooterControls: some View {
        HStack(spacing: 12) {
            mediaImportMenu {
                circularMediaAddControl(systemImage: "plus")
            }
            .accessibilityLabel("미디어 추가")
            .accessibilityHint(
                "현재 프로젝트의 마지막에 사진이나 영상을 추가합니다."
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
                .accessibilityHint("현재 빈 프로젝트를 닫고 첫 화면으로 돌아갑니다.")
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
                : model.clips.first?.id == id ? 18 : 5,
            leading: 4,
            bottom: clipRowBottomInset(
                id: id,
                isVideoSegmentChild: isVideoSegmentChild,
                isFollowedByVideoSegmentChild: isFollowedByVideoSegmentChild
            ),
            trailing: 16
        )
    }

    private func clipRowBottomInset(
        id: UUID,
        isVideoSegmentChild: Bool,
        isFollowedByVideoSegmentChild: Bool
    ) -> CGFloat {
        if isVideoSegmentChild {
            return isFollowedByVideoSegmentChild ? 0 : 5
        }
        if isFollowedByVideoSegmentChild {
            return 0
        }
        return model.clips.last?.id == id ? 18 : 5
    }

    private var clipModeHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(HanClipTheme.secondary)
                .accessibilityHidden(true)

            Text("클립 \(model.renderableClips.count)개")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HanClipTheme.secondary)

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
                .padding(.horizontal, isReordering ? 11 : 0)
                .padding(.vertical, isReordering ? 2 : 0)
                .background {
                    if isReordering {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(HanClipTheme.primary)
                    }
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(
                isReordering ? Color.white : HanClipTheme.secondary
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var defaultDurationPanel: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "stopwatch")
                        .accessibilityHidden(true)

                    Text("기본재생시간")

                    Text(
                        "\(model.defaultDuration, specifier: "%.1f")초"
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                }
                .font(.system(size: 16))
                .foregroundStyle(HanClipTheme.secondary)

                Spacer()

                CompactDurationStepper(
                    value: $model.defaultDuration,
                    range: 0.5...30,
                    step: 0.5,
                    controlWidth: 88,
                    controlHeight: 24.2,
                    iconSize: 19.8
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .overlay(
                    HanClipTheme.secondary.opacity(0.18)
                )

            HStack(spacing: 0) {
                Button {
                    model.selectFullRangeForAllVideoClips()
                } label: {
                    Text("select all")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(HanClipTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 24)
                    .overlay(
                        HanClipTheme.primary.opacity(0.30)
                    )

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
                    height: 30
                )
                .padding(.horizontal, 12)
                .accessibilityLabel("모든 Live Photo 사용 방식")
                .accessibilityValue(bulkLivePhotoMode.rawValue)
                .accessibilityHint("모든 Live Photo 클립을 포토 또는 Live 모드로 전환합니다.")

                Divider()
                    .frame(height: 24)
                    .overlay(
                        HanClipTheme.primary.opacity(0.30)
                    )

                Button {
                    model.applyDefaultDurationToAll()
                } label: {
                    Text("Apply to all")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(HanClipTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 14)
        }
        .background(
            HanClipTheme.secondary.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    HanClipTheme.primary.opacity(0.30),
                    lineWidth: 1
                )
        }
    }

    private var reorderGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 6),
                count: 4
            ),
            spacing: 8
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
                            HanClipTheme.primary.opacity(0.50)
                        }
                    }
                }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                            .frame(width: 22, height: 22)
                            .background(
                                HanClipTheme.primary.opacity(0.30),
                                in: Circle()
                            )
                            .padding(4)
                    }
                    .overlay(alignment: .topTrailing) {
                        Text(reorderMediaTitle(for: clip))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .opacity(0.70)
                            .shadow(
                                color: .black,
                                radius: 2,
                                x: 0,
                                y: 1
                            )
                            .multilineTextAlignment(.trailing)
                            .padding(4)
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
                            .opacity(0.70)
                            .shadow(
                                color: .black,
                                radius: 2,
                                x: 0,
                                y: 1
                            )
                            .padding(.bottom, 4)
                    }
                    .overlay {
                        if clip.isVideoSegmentParent {
                            Text("📥")
                                .font(.system(size: 36, weight: .heavy))
                                .foregroundStyle(Color.white.opacity(0.70))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                HanClipTheme.secondary.opacity(0.30),
                                lineWidth: 1
                            )
                    }
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
                            videoSegmentPreviewParentID = clip.id
                            selectedClipID = firstChildClip.id
                        } else {
                            videoSegmentPreviewParentID = nil
                            selectedClipID = clip.id
                        }
                    }
                    .accessibilityLabel(
                        "\(index + 1)번째 \(reorderMediaTitle(for: clip))"
                    )
                    .accessibilityHint(
                        "한 번 누르면 에디터를 열고, 누른 뒤 끌면 순서를 변경합니다."
                    )
            }

            mediaImportMenu {
                reorderMediaAddTile
            }
            .accessibilityLabel("미디어 추가")
            .accessibilityHint(
                "현재 프로젝트의 마지막에 사진이나 영상을 추가합니다."
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
                        .tint(HanClipTheme.secondary.opacity(0.16))
                        .interactive(),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            Color.white.opacity(0.68),
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
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            HanClipTheme.secondary.opacity(0.34),
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
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.34))

            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(HanClipTheme.secondary)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 8))
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
                                : HanClipTheme.secondary.opacity(0.16)
                        )
                        .interactive(),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isDeleteDropTargeted
                                ? Color.red.opacity(0.80)
                                : Color.white.opacity(0.68),
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
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isDeleteDropTargeted
                                ? Color.red.opacity(0.80)
                                : HanClipTheme.secondary.opacity(0.34),
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
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isDeleteDropTargeted
                        ? Color.red.opacity(0.18)
                        : Color.white.opacity(0.34)
                )

            Image(systemName: "minus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(
                    isDeleteDropTargeted
                        ? Color.red
                        : HanClipTheme.secondary
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(isDeleteDropTargeted ? 1.04 : 1)
        .animation(.easeInOut(duration: 0.16), value: isDeleteDropTargeted)
    }

    private func reorderMediaTitle(for clip: ClipItem) -> String {
        if clip.isVideoClip {
            return "clip"
        }
        if clip.isLivePhoto {
            return "Live"
        }
        return "photo"
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
                    color: HanClipTheme.primary.opacity(0.16),
                    radius: 8,
                    y: 3
                )
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
                            HanClipTheme.secondary.opacity(0.42),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: HanClipTheme.primary.opacity(0.12),
                    radius: 7,
                    y: 3
                )
        }
    }

    private var aspectRatioButtons: some View {
        GeometryReader { proxy in
            HStack(spacing: 4) {
                Button {
                    model.selectOutputAspectRatio(nil)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                            model.outputAspectRatio == nil
                                    ? HanClipTheme.primary
                                    : Color.clear
                            )

                        Text("첫\n사진")
                            .font(.system(size: 10, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineSpacing(0)
                            .foregroundStyle(
                                model.outputAspectRatio == nil
                                    ? Color.white
                                    : HanClipTheme.secondary
                            )
                    }
                    .frame(width: 32, height: 32)
                    .overlay {
                        if model.outputAspectRatio != nil {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(HanClipTheme.secondary, lineWidth: 1)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ForEach(OutputAspectRatio.allCases) { ratio in
                    Button {
                        model.selectOutputAspectRatio(ratio)
                    } label: {
                        AspectRatioIcon(
                            ratio: ratio,
                            isSelected: model.outputAspectRatio == ratio
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
                            totalWidth: proxy.size.width
                        )
                    }
            )
        }
        .frame(height: 32)
    }

    private func selectAspectRatio(
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
            model.selectOutputAspectRatio(nil)
        } else {
            model.selectOutputAspectRatio(ratios[selectedIndex - 1])
        }
    }

    private var makeButton: some View {
        VStack(spacing: 8) {
            aspectRatioPicker
                .frame(maxWidth: .infinity, alignment: .center)

            Button {
                model.saveProjectAndOpenPreview()
            } label: {
                HStack(spacing: 8) {
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
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(HanClipTheme.primary)
            .controlSize(.large)
            .disabled(model.isExporting)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.clear)
    }

    private var progressOverlay: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: 16) {
                if model.isPreviewRendering {
                    if let thumbnail = model.previewThumbnail {
                        generationProgressThumbnail(thumbnail)
                    }

                    HStack(spacing: 8) {
                        Text(
                            progressTimeText(
                                model.previewProgress
                                    * model.totalDuration
                            )
                        )
                        .frame(width: 46, alignment: .trailing)

                        ProgressView(
                            value: model.previewProgress,
                            total: 1
                        )
                        .progressViewStyle(.linear)
                        .tint(HanClipTheme.primary)

                        Text(progressTimeText(model.totalDuration))
                            .frame(width: 46, alignment: .leading)
                    }
                    .font(
                        .system(
                            size: 12,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .frame(width: 300)

                    Text(
                        "\(Int((model.previewProgress * 100).rounded()))%"
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(HanClipTheme.primary)
                } else if model.isImportingSharedItems {
                    ProgressView(value: model.sharedImportProgress, total: 1)
                        .progressViewStyle(.linear)
                        .tint(HanClipTheme.primary)
                        .frame(width: 300)

                    Text(
                        "\(Int((model.sharedImportProgress * 100).rounded()))%"
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(HanClipTheme.primary)
                } else if model.isLoadingCalendarPicker {
                    HStack(spacing: 10) {
                        Text(
                            "\(Int((model.calendarPickerLoadProgress * 100).rounded()))%"
                        )
                        .font(
                            .system(
                                size: 14,
                                weight: .semibold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(HanClipTheme.primary)
                        .frame(width: 44, alignment: .trailing)

                        ProgressView(
                            value: model.calendarPickerLoadProgress,
                            total: 1
                        )
                        .progressViewStyle(.linear)
                        .tint(HanClipTheme.primary)
                    }
                    .frame(width: 300)
                } else if model.isImportingCalendarMedia {
                    ProgressView(value: model.calendarImportProgress, total: 1)
                        .progressViewStyle(.linear)
                        .tint(HanClipTheme.primary)
                        .frame(width: 300)

                    Text(
                        "\(Int((model.calendarImportProgress * 100).rounded()))%"
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(HanClipTheme.primary)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(HanClipTheme.primary)
                }

                Text(model.progressMessage)
                    .font(.system(size: 16, weight: .semibold))

                if model.isPreviewRendering {
                    Button("취소", role: .cancel) {
                        model.cancelPreviewGeneration()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .buttonStyle(.bordered)
                    .tint(HanClipTheme.secondary)
                }
            }
            .padding(28)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(HanClipTheme.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                HanClipTheme.secondary.opacity(0.02)
                            )
                    }
            }
            .offset(y: -30)
        }
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
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        HanClipTheme.secondary.opacity(0.30),
                        lineWidth: 1
                    )
            }
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
        let maximumDimension: CGFloat = 240

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
    @Binding var copyrightEnabled: Bool
    @Binding var platformRaw: String
    @Binding var address: String
    @Binding var positionRaw: String
    @Binding var textColorHex: String
    @Binding var shadowColorHex: String
    @Binding var iconColorModeRaw: String
    @Binding var iconColorHex: String

    private let items: [(title: String, body: String)] = [
        ("제작자", "송기원, 한병기"),
        ("카피라이터", "첫 화면 하단의 i 원형 유리 버튼입니다. 카피라이터 입력과 중요 정보를 보여주는 창입니다."),
        ("첫 화면", "앱 실행 후 NEW PROJECT와 저장된 프로젝트 목록이 보이는 홈 화면입니다."),
        ("프로젝트 새로 만들기 영역", "첫 화면 상단의 사진 및 영상 선택 카드입니다. 새 프로젝트를 시작하기 위해 미디어를 고르는 영역입니다."),
        ("프로젝트 리스트", "첫 화면에 저장된 프로젝트들이 표시되는 영역입니다."),
        ("프로젝트 화면", "미디어를 선택한 후 기본 재생 시간, 화면 비율, 클립 리스트 등을 편집하는 화면입니다."),
        ("프로젝트 에디트", "프로젝트 화면의 로고 아래, 기본 재생시간 설정 위쪽에 들어간 PROJECT EDIT 텍스트입니다."),
        ("클립 리스트", "선택한 Photo, Live, Clip이 순서대로 표시되는 목록입니다. 썸네일, 시간, 아이콘, 세그먼트 컨트롤, +/- 버튼이 있는 영역입니다."),
        ("순서변경 상태", "썸네일을 한 줄에 여러 개 표시하고 드래그해서 클립 순서를 변경하는 상태입니다."),
        ("에디터 영역 / 에디터 모드", "개별 클립을 누르면 열리는 구간 선택 및 재생 화면입니다."),
        ("미리보기", "에디터 안에서는 개별 클립을 확인하는 재생 영역이고, 만들기 완료 후에는 제작된 전체 영상을 재생하고 확인하는 화면입니다."),
        ("만들기", "전체 클립을 하나의 영상으로 생성하는 액션과 버튼입니다."),
        ("영상 생성 진행창", "영상을 만드는 동안 썸네일, 진행바, 진행률, 취소 버튼이 표시되는 창입니다."),
        ("저장하기 창", "미리보기에서 사진 앱 또는 파일 앱 저장 방식을 선택하는 창입니다."),
        ("테마 선택창", "로고를 길게 눌렀을 때 5개 테마를 선택하는 창입니다."),
        ("첫 화면 이동 팝업", "편집 중 로고를 눌렀을 때 홈 + 저장, 홈으로를 선택하는 창입니다."),
        ("로고", "상단의 앱 심볼과 HanClip 글자 부분입니다."),
        ("카피라이터 입력", "카피라이터에서 설정하는 기능입니다. 한클립 로고 또는 SNS/기타 표시를 결과 영상에 합성할지 결정합니다."),
        ("세그먼트 컨트롤", "포토 / Live, 단일 / 다중처럼 두 옵션 중 하나를 고르는 스위치형 컨트롤입니다."),
        ("단일 / 다중", "영상 클립을 하나의 구간으로 쓸지, 사운드 피크 기준으로 여러 자영상으로 나눌지 정하는 영상 세그먼트 모드입니다."),
        ("모영상", "다중 세그먼트를 만들 때 원본 역할로 남는 부모 영상입니다."),
        ("자영상", "모영상에서 사운드 피크 기준으로 만들어진 하위 영상 클립입니다."),
        ("웨이브 / 웨이브 인디케이터", "영상/Live Photo 에디터에서 소리 파형을 보여주는 영역입니다."),
        ("선택바", "웨이브 인디케이터의 좌우 끝에 있는 드래그 바입니다."),
        ("자동 진행", "에디터 영역 왼쪽 상단 카운트 영역을 눌러 켜는 기능입니다."),
        ("무한 루프", "자동 진행 버튼을 롱터치해서 켜는 기능입니다."),
        ("달력 썸네일 버튼", "달력에서 미디어를 고르는 화면에 있는 위/아래 이동 버튼입니다."),
        ("텍스트 넣기", "프로젝트 화면의 미디어 추가 메뉴에서 여는 설정창입니다. 결과 영상 위에 문구를 합성할지, 문구와 색상, 서체, 그림자, 위치를 설정합니다."),
        ("외부 호출 주소", "hanclip://photo\nhanclip://calendar\nhanclip://files\nhanclip://open"),
        ("내장 서체 저작권", "HanClip에는 Pretendard, Kakao Big Sans, Nanum Gothic, Noto Sans KR 서체가 포함되어 있습니다. 각 서체는 SIL Open Font License 1.1에 따라 제공되며, 서체 파일 자체를 단독으로 판매할 수 없고 저작권 및 라이선스 고지를 유지해야 합니다. 라이선스 전문은 앱 번들에 포함된 각 OFL/라이선스 텍스트 파일을 따릅니다.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    infoHeader
                    copyrightSettings

                    ForEach(items, id: \.title) { item in
                        infoRow(title: item.title, body: item.body)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnDrag()
            .background(HanClipTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("중요 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        resetCopyrightSettings()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(HanClipTheme.primary)
                    .accessibilityLabel("카피라이터 초기화")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("확인") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(HanClipTheme.primary)
                }
            }
        }
        .onAppear {
            loadAddress(for: selectedPlatform)
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
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 3
                ),
                spacing: 8
            ) {
                ForEach(WatermarkPlatform.allCases) { platform in
                    copyrightPlatformButton(platform)
                }
            }

            if showsAddressInput {
                TextEditor(text: addressBinding(for: selectedPlatform))
                    .font(.system(size: 14, weight: .medium))
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 74)
                    .scrollContentBackground(.hidden)
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

            copyrightPositionSettings

            Picker("아이콘", selection: $iconColorModeRaw) {
                ForEach(CopyrightIconColorMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .font(.system(size: 14, weight: .bold))

            if selectedIconColorMode == .overlay {
                ColorPicker(
                    "아이콘색",
                    selection: Binding(
                        get: {
                            Color(hexString: iconColorHex)
                                ?? HanClipTheme.primary
                        },
                        set: {
                            iconColorHex = $0.hexString
                                ?? WatermarkSettings.defaultCopyrightIconColor
                        }
                    ),
                    supportsOpacity: false
                )
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HanClipTheme.text.opacity(0.72))
            }

            ColorPicker(
                "글자색",
                selection: Binding(
                    get: {
                        Color(hexString: textColorHex)
                            ?? HanClipTheme.primary
                    },
                    set: {
                        textColorHex = $0.hexString
                            ?? WatermarkSettings.defaultCopyrightTextColor
                    }
                ),
                supportsOpacity: false
            )
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(HanClipTheme.text.opacity(0.72))

            ColorPicker(
                "그림자색",
                selection: Binding(
                    get: {
                        Color(hexString: shadowColorHex)
                            ?? HanClipTheme.secondary
                    },
                    set: {
                        shadowColorHex = $0.hexString
                            ?? WatermarkSettings.defaultCopyrightShadowColor
                    }
                ),
                supportsOpacity: false
            )
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(HanClipTheme.text.opacity(0.72))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            HanClipTheme.primary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HanClipTheme.primary.opacity(0.20), lineWidth: 1)
        }
    }

    private var copyrightPositionSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("위치")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HanClipTheme.text.opacity(0.72))

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 3
                ),
                spacing: 8
            ) {
                ForEach(WatermarkPosition.allCases) { position in
                    copyrightPositionButton(position)
                }
            }
            .padding(10)
            .background(
                HanClipTheme.secondary.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
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
                    iconColorHex: iconColorHex
                )
                    .frame(width: 30, height: 30)
                if platform == .other {
                    Text("etc")
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, -2)
                }
            }
            .foregroundStyle(isSelected ? .white : HanClipTheme.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                isSelected
                    ? HanClipTheme.primary
                    : HanClipTheme.secondary.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(platform.title)
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

    private func resetCopyrightSettings() {
        copyrightEnabled = true
        platformRaw = WatermarkPlatform.hanclip.rawValue
        positionRaw = WatermarkSettings.defaultCopyrightPosition.rawValue
        iconColorModeRaw =
            WatermarkSettings.defaultCopyrightIconColorMode.rawValue
        iconColorHex = WatermarkSettings.defaultCopyrightIconColor
        textColorHex = Color(
            uiColor: HanClipTheme.primaryUIColor
        ).hexString ?? WatermarkSettings.defaultCopyrightTextColor
        shadowColorHex = Color(
            uiColor: HanClipTheme.secondaryUIColor
        ).hexString ?? WatermarkSettings.defaultCopyrightShadowColor
        loadAddress(for: .hanclip)
    }

    private var infoHeader: some View {
        HStack(spacing: 10) {
            Image("LogoMarkV2")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("HanClip")
                    .font(.system(size: 22, weight: .semibold))
            }
            .textSelection(.enabled)
        }
        .foregroundStyle(HanClipTheme.primary)
        .padding(.bottom, 8)
    }

    private func infoRow(title: String, body: String) -> some View {
        InfoRow(title: title, detail: body)
    }
}

private struct TextOverlaySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showInstalledFontPicker = false
    @State private var showFontFilePicker = false
    @State private var fontImportNotice: String?
    @State private var textInputBackgroundHex =
        TextOverlaySettingsSheet.randomTextInputBackgroundHex()
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

    private let defaultFontChoices: [(title: String, fontName: String)] = [
        ("시스템", WatermarkSettings.defaultFontName),
        ("나눔고딕", "NanumGothic"),
        ("카카오", "KakaoBigSans-Regular")
    ]

    private var allAvailableFonts: [String] {
        let uiKitFonts = UIFont.familyNames
            .flatMap { UIFont.fontNames(forFamilyName: $0) }
        let coreTextFonts =
            CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []

        return Array(Set(uiKitFonts + coreTextFonts + bundledFonts + myFonts))
            .filter { UIFont(name: $0, size: 14) != nil }
            .sorted {
                displayFontName($0).localizedStandardCompare(
                    displayFontName($1)
                ) == .orderedAscending
            }
    }

    private var bundledFonts: [String] {
        FontImportStore.bundledFontNames.sorted {
            displayFontName($0).localizedStandardCompare(
                displayFontName($1)
            ) == .orderedAscending
        }
    }

    private var myFonts: [String] {
        FontImportStore.userFontNames.sorted {
            displayFontName($0).localizedStandardCompare(
                displayFontName($1)
            ) == .orderedAscending
        }
    }

    private var otherFonts: [String] {
        let excludedFonts = Set(bundledFonts + myFonts)
        return allAvailableFonts.filter { !excludedFonts.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    WatermarkModeSegmentedControl(isEnabled: $textEnabled)

                    if textEnabled {
                        textInput
                        styleSettings
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
            .navigationTitle("텍스트 넣기")
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
                    Button("확인") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(HanClipTheme.primary)
                }
            }
        }
        .sheet(isPresented: $showInstalledFontPicker) {
            InstalledFontPicker(fontName: $fontName)
        }
        .sheet(isPresented: $showFontFilePicker) {
            FilePicker(
                allowedContentTypes: fontContentTypes,
                allowsMultipleSelection: true
            ) { result in
                handleFontFilePicker(result)
            }
        }
        .onAppear {
            refreshTextInputBackground()
        }
        .onChange(of: textColorHex) { _, _ in
            refreshTextInputBackground()
        }
        .onChange(of: shadowColorHex) { _, _ in
            refreshTextInputBackground()
        }
    }

    private var textInput: some View {
        TextEditor(text: $text)
            .font(textEditorFont(size: textEditorBaseSize))
            .foregroundStyle(
                Color(hexString: textColorHex) ?? HanClipTheme.primary
            )
            .lineSpacing(textEditorLineSpacing(size: textEditorBaseSize))
            .multilineTextAlignment(textEditorAlignment)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 104)
            .scrollContentBackground(.hidden)
            .background(
                (Color(hexString: textInputBackgroundHex) ?? .white)
                    .opacity(0.34),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HanClipTheme.secondary.opacity(0.22), lineWidth: 1)
            }
    }

    private var styleSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                Text("서체")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HanClipTheme.text.opacity(0.72))

                HStack(spacing: 8) {
                    ForEach(defaultFontChoices, id: \.fontName) { choice in
                        defaultFontButton(
                            title: choice.title,
                            choiceFontName: choice.fontName
                        )
                    }
                }

                Menu {
                    Button {
                        showFontFilePicker = true
                    } label: {
                        Label("서체 파일 가져오기", systemImage: "square.and.arrow.down")
                    }

                    Divider()

                    if !myFonts.isEmpty {
                        Section("나의 서체") {
                            ForEach(myFonts, id: \.self) { font in
                                fontMenuButton(font)
                            }
                        }

                        Divider()
                    }

                    Button {
                        showInstalledFontPicker = true
                    } label: {
                        Label("아이폰 서체", systemImage: "textformat")
                    }

                    Divider()

                    Section("기타 서체") {
                        ForEach(otherFonts, id: \.self) { font in
                            fontMenuButton(font)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(
                            fontName.isEmpty
                                ? "서체 더 선택"
                                : displayFontName(fontName)
                        )
                            .font(selectedFontPreview(size: 12))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(HanClipTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let fontImportNotice {
                Text(fontImportNotice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HanClipTheme.text.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Picker("서체크기", selection: $fontSize) {
                ForEach(WatermarkFontSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .font(.system(size: 14, weight: .bold))

            ColorPicker(
                "글자색",
                selection: Binding(
                    get: { Color(hexString: textColorHex) ?? .white },
                    set: {
                        textColorHex = $0.hexString
                            ?? WatermarkSettings.defaultTextColor
                    }
                ),
                supportsOpacity: false
            )
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(HanClipTheme.text.opacity(0.72))

            Toggle("그림자", isOn: $shadowEnabled)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HanClipTheme.text.opacity(0.72))
                .tint(HanClipTheme.primary)

            if shadowEnabled {
                ColorPicker(
                    "그림자색",
                    selection: Binding(
                        get: { Color(hexString: shadowColorHex) ?? .black },
                        set: {
                            shadowColorHex = $0.hexString
                                ?? WatermarkSettings.defaultShadowColor
                        }
                    ),
                    supportsOpacity: false
                )
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HanClipTheme.text.opacity(0.72))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("줄간격")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HanClipTheme.text.opacity(0.72))

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
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            HanClipTheme.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func fontMenuButton(_ font: String) -> some View {
        Button {
            fontName = font
        } label: {
            Text(displayFontName(font))
                .font(.custom(font, size: 14))
        }
    }

    private func defaultFontButton(
        title: String,
        choiceFontName: String
    ) -> some View {
        let isSelected = fontName == choiceFontName

        return Button {
            fontName = choiceFontName
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
                    .font(defaultFontPreview(choiceFontName, size: 12))
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

    private var positionSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("위치")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HanClipTheme.text.opacity(0.72))

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 3
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
        fontName.isEmpty
            ? .system(size: size, weight: .semibold)
            : .custom(fontName, size: size)
    }

    private func defaultFontPreview(
        _ choiceFontName: String,
        size: CGFloat
    ) -> Font {
        choiceFontName.isEmpty
            ? .system(size: size, weight: .bold)
            : .custom(choiceFontName, size: size)
    }

    private func textEditorFont(size: CGFloat) -> Font {
        fontName.isEmpty
            ? .system(size: size, weight: .medium)
            : .custom(fontName, size: size)
    }

    private var textEditorAlignment: TextAlignment {
        switch position {
        case .topLeading, .middleLeading, .bottomLeading:
            return .leading
        case .topCenter, .center, .bottomCenter:
            return .center
        case .topTrailing, .middleTrailing, .bottomTrailing:
            return .trailing
        }
    }

    private var textEditorBaseSize: CGFloat {
        14 * CGFloat(fontSize.multiplier)
    }

    private func textEditorLineSpacing(size: CGFloat) -> CGFloat {
        size * CGFloat(lineSpacingScale - WatermarkLineSpacing.defaultMultiplier)
    }

    private func refreshTextInputBackground() {
        textInputBackgroundHex = Self.randomTextInputBackgroundHex(
            excluding: [textColorHex, shadowColorHex]
        )
    }

    private static func randomTextInputBackgroundHex(
        excluding excludedHexes: [String] = []
    ) -> String {
        let palette = [
            "#F6E8EA",
            "#E7F0FF",
            "#EAF7EA",
            "#FFF2D8",
            "#EFE8FF",
            "#E8F7F4",
            "#F2F0E8",
            "#F7EAF2"
        ]
        let excluded = Set(excludedHexes.map(normalizedHex))
        let choices = palette.filter {
            !excluded.contains(normalizedHex($0))
        }

        return choices.randomElement() ?? "#F2F0E8"
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

            fontName = firstFont
            fontImportNotice = "\(importedNames.count)개 서체를 가져왔습니다."
        } catch {
            fontImportNotice = "서체를 가져올 수 없습니다."
        }
    }

    private func resetSettings() {
        let defaults = WatermarkSettings.projectDefault()
        textEnabled = defaults.isEnabled
        text = defaults.text
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

            parent.fontName =
                descriptor.fontAttributes[.name] as? String
                ?? UIFont(descriptor: descriptor, size: 14).fontName
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HanClipTheme.primary)
                .textSelection(.enabled)

            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(HanClipTheme.text.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
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
                .stroke(HanClipTheme.secondary.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct TextOverlaySummaryRow: View {
    let settings: WatermarkSettings
    let onSelect: () -> Void

    private var fontText: String {
        settings.fontName.isEmpty
            ? "시스템"
            : displayFontName(settings.fontName)
    }

    private var shadowText: String {
        settings.shadowEnabled ? "사용" : "안함"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Text("T")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(HanClipTheme.primary)
                    .frame(width: 18, height: 62, alignment: .center)

                HStack(spacing: 14) {
                    TextOverlayPositionThumbnail(position: settings.position)
                        .frame(width: 62, height: 62)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            summaryLabel("서체", value: nil)
                            colorSwatch(settings.textColorHex)
                            Text(fontText)
                                .font(summaryFontPreview(size: 12))
                                .foregroundStyle(HanClipTheme.text.opacity(0.68))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }

                        HStack(spacing: 8) {
                            summaryLabel("그림자", value: shadowText)
                            if settings.shadowEnabled {
                                colorSwatch(settings.shadowColorHex)
                            }
                        }

                        HStack(spacing: 10) {
                            summaryLabel("크기", value: settings.fontSize.title)
                            summaryLabel("줄간격", value: settings.lineSpacing.title)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minHeight: 62)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("텍스트")
        .accessibilityHint("텍스트 넣기 편집 화면을 엽니다.")
    }

    private func summaryLabel(_ title: String, value: String?) -> some View {
        HStack(spacing: 4) {
            Text("\(title) :")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(HanClipTheme.text.opacity(0.72))

            if let value {
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HanClipTheme.text.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func colorSwatch(_ hex: String) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(hexString: hex) ?? HanClipTheme.text)
            .frame(width: 22, height: 14)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(HanClipTheme.text.opacity(0.18), lineWidth: 1)
            }
    }

    private func displayFontName(_ fontName: String) -> String {
        guard let font = UIFont(name: fontName, size: 14) else {
            return fontName
        }

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
            font.familyName,
            fontName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? fontName
    }

    private func summaryFontPreview(size: CGFloat) -> Font {
        settings.fontName.isEmpty
            ? .system(size: size, weight: .medium)
            : .custom(settings.fontName, size: size)
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
        let leading = inset
        let centerX = size.width / 2
        let trailing = size.width - inset
        let top = inset
        let centerY = size.height / 2
        let bottom = size.height - inset

        switch position {
        case .topLeading:
            return CGPoint(x: leading, y: top)
        case .topCenter:
            return CGPoint(x: centerX, y: top)
        case .topTrailing:
            return CGPoint(x: trailing, y: top)
        case .middleLeading:
            return CGPoint(x: leading, y: centerY)
        case .center:
            return CGPoint(x: centerX, y: centerY)
        case .middleTrailing:
            return CGPoint(x: trailing, y: centerY)
        case .bottomLeading:
            return CGPoint(x: leading, y: bottom)
        case .bottomCenter:
            return CGPoint(x: centerX, y: bottom)
        case .bottomTrailing:
            return CGPoint(x: trailing, y: bottom)
        }
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
            case .other:
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12, weight: .bold))
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 5,
                            style: .continuous
                        )
                        .stroke(lineWidth: 2)
                    }
            }
        }
    }
}

private struct CopyrightPlatformLogo: View {
    let platform: WatermarkPlatform
    let iconColorMode: CopyrightIconColorMode
    let iconColorHex: String

    var body: some View {
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(
                        iconColorMode == .overlay ? .template : .original
                    )
                    .scaledToFit()
            } else if platform == .hanclip {
                Image("LogoMarkV2")
                    .resizable()
                    .renderingMode(
                        iconColorMode == .overlay ? .template : .original
                    )
                    .scaledToFit()
            } else {
                WatermarkPlatformLogo(platform: platform)
            }
        }
        .foregroundStyle(
            Color(hexString: iconColorHex) ?? HanClipTheme.primary
        )
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
        case .hanclip, .other:
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
            .frame(width: 86, height: 38)
            .background {
                if #available(iOS 26.0, *) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .glassEffect(
                            .regular
                                .tint(Color.white.opacity(0.18))
                                .interactive(),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.48), lineWidth: 1)
                        }
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.48), lineWidth: 1)
                        }
                }
            }
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
                        ? HanClipTheme.primary
                        : Color.clear
                )

            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    isSelected ? Color.white : HanClipTheme.secondary,
                    lineWidth: 2
                )
                .frame(
                    width: rectangleSize.width,
                    height: rectangleSize.height
                )
        }
        .frame(width: 32, height: 32)
        .overlay {
            if !isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(HanClipTheme.secondary, lineWidth: 1)
            }
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
    let onSave: (String) -> Void

    @State private var text: String
    @State private var lastSavedText: String
    @FocusState private var isFocused: Bool

    init(
        projectID: UUID,
        memo: String,
        onSave: @escaping (String) -> Void
    ) {
        self.projectID = projectID
        self.onSave = onSave
        _text = State(initialValue: memo)
        _lastSavedText = State(initialValue: memo)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HanClipTheme.secondary)

            TextField("메모 추가", text: $text)
                .font(.system(size: 12))
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(saveIfNeeded)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            HanClipTheme.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .onChange(of: isFocused) { _, focused in
            if !focused {
                saveIfNeeded()
            }
        }
        .onDisappear {
            saveIfNeeded()
        }
        .dismissKeyboardOnDrag()
        .accessibilityLabel("프로젝트 메모")
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
        accessibilityLabel: String = "프로젝트 삭제",
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
                    .accessibilityLabel("미리보기 재생 또는 일시정지")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                PersistentVideoProgressBar(player: player)

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            onEdit()
                        } label: {
                            Label("다시 편집", systemImage: "chevron.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(HanClipTheme.secondary)

                        Button {
                            player.pause()
                            isSharePresented = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 30)
                        }
                        .buttonStyle(.bordered)
                        .tint(HanClipTheme.secondary)
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
                            Label("저장하기", systemImage: "square.and.arrow.down")
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HanClipTheme.primary)
                    }
                    .controlSize(.large)
                }
                .padding()
                .background(HanClipTheme.secondary.opacity(0.02))
            }
            .background(HanClipTheme.secondary.opacity(0.02))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        onEdit()
                    } label: {
                        HStack(spacing: 8) {
                            Image("LogoMarkV2")
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                                .frame(width: 24, height: 24)

                            Text("HanClip")
                                .font(.system(size: 20, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HanClipTheme.primary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("다시 편집")
                }
            }
            .toolbarBackground(
                HanClipTheme.secondary.opacity(0.02),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .blur(radius: showSaveOptions ? 2 : 0)
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
        .background(
            HanClipTheme.secondary.opacity(0.02).ignoresSafeArea()
        )
        .onAppear {
            player.seek(to: .zero)
            player.play()
        }
        .onDisappear {
            hideSaveOptionsImmediately()
            player.pause()
        }
        .sheet(
            isPresented: $isSharePresented,
            onDismiss: {
                player.play()
            }
        ) {
            VideoShareSheet(items: [url])
        }
    }

    private var saveOptionsOverlay: some View {
        ZStack {
            Color.black.opacity(0.20)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("저장하기")
                    .font(.system(size: 18, weight: .semibold))

                Button {
                    hideSaveOptionsImmediately()
                    onSaveToPhotos(albumName)
                } label: {
                    Label(
                        "사진 앱에 저장",
                        systemImage: "photo.on.rectangle"
                    )
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(HanClipTheme.primary)
                .controlSize(.large)

                HStack(spacing: 8) {
                    Text("앨범 :")
                        .font(.system(size: 16, weight: .medium))

                    TextField("앨범명", text: $albumName)
                        .font(.system(size: 16))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            HanClipTheme.background,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    HanClipTheme.secondary.opacity(0.30),
                                    lineWidth: 1
                                )
                        }
                }
                .padding(.bottom, 20)

                Button {
                    hideSaveOptionsImmediately()
                    onSaveToFiles()
                } label: {
                    Label(
                        "파일 앱에 저장",
                        systemImage: "folder"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(HanClipTheme.secondary)
                .controlSize(.large)

                Button("취소", role: .cancel) {
                    withAnimation(.snappy) {
                        showSaveOptions = false
                    }
                    player.play()
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .tint(HanClipTheme.secondary)
            }
            .padding(20)
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
            .padding(.horizontal, 24)
        }
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
    @State private var didTriggerLongPress = false
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if didTriggerLongPress {
                    didTriggerLongPress = false
                } else if isLooping {
                    toggleLooping()
                } else {
                    togglePlayback()
                }
            } label: {
                Image(systemName: playbackButtonImage)
                    .font(.system(size: 16, weight: .bold))
                    .rotationEffect(.degrees(loopIconRotation))
                    .foregroundStyle(HanClipTheme.primary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        didTriggerLongPress = true
                        toggleLooping()
                    }
            )
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
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(HanClipTheme.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(HanClipTheme.secondary.opacity(0.02))
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
        if isLooping {
            return "arrow.triangle.2.circlepath"
        }
        if reachedEnd {
            return "arrow.counterclockwise"
        }
        return isPlaying ? "pause.fill" : "play.fill"
    }

    private var playbackButtonLabel: String {
        if isLooping {
            return "무한 루프 재생"
        }
        if reachedEnd {
            return "처음부터 다시 재생"
        }
        return isPlaying ? "일시정지" : "재생"
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
            .sheet(isPresented: $showMonthYearPicker) {
                monthYearPicker
                    .presentationDetents([.height(320)])
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
                    .fill(Color.gray.opacity(0.18))
                    .frame(height: 2)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.gray.opacity(0.18))
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
                                        Color.gray.opacity(0.10),
                                        lineWidth: 1
                                    )
                            }
                    }
                }
            }
            .frame(height: calendarGridHeight, alignment: .top)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.gray.opacity(0.14), lineWidth: 1)
        }
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

            Text("오늘")
                .contentShape(Rectangle())
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.55)
                        .onEnded { _ in
                            clearSelectedCalendarMedia()
                        }
                )
                .gesture(
                    TapGesture(count: 2)
                        .exclusively(before: TapGesture())
                        .onEnded { result in
                            switch result {
                            case .first:
                                handleTodayDoubleTap()
                            case .second:
                                moveToToday()
                            }
                        }
                )
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
            HStack(spacing: 12) {
                Text("날짜 \(selectedDates.count)일, 미디어 \(selectedMediaCount)개")
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()

                Spacer()

                Text("지우기")
                    .font(.system(size: 14, weight: .semibold))
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
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.55)
                    .onEnded { _ in
                        clearSelectedCalendarMedia()
                    }
            )
            .gesture(
                TapGesture(count: 2)
                    .exclusively(before: TapGesture())
                    .onEnded { result in
                        switch result {
                        case .first:
                            handleTodayDoubleTap()
                        case .second:
                            withAnimation(.snappy) {
                                clearSelectedCalendarMedia()
                            }
                        }
                    }
            )
            .accessibilityHint("선택한 날짜와 미리보기를 모두 지웁니다.")
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 20)

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
                                    .clipped()
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
                Color.black.opacity(0.035),
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
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
        .foregroundStyle(HanClipTheme.secondary.opacity(opacity))
        .shadow(
            color: Color.black.opacity(0.70),
            radius: 3,
            x: 0,
            y: 1.5
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
                        .fill(HanClipTheme.secondary.opacity(0.24))
                }
            }
            .overlay {
                Rectangle()
                    .stroke(Color.gray.opacity(0.10), lineWidth: 1)
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
