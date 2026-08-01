import AVKit
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct EditorView: View {
    @StateObject private var model = EditorViewModel()
    @State private var isReordering = false
    @State private var showResetConfirmation = false
    @State private var showThemeSelection = false
    @State private var themeNotice: String?
    @State private var importSelectionNotice: String?
    @State private var selectedClipID: UUID?
    @State private var shouldAutoplaySelectedClip = false
    @State private var draggedClipID: UUID?
    @State private var isDeleteDropTargeted = false
    @State private var isSharedInboxBannerDismissed = false
    @State private var bulkLivePhotoMode = LivePhotoMode.motion
    @AppStorage("hanClipThemeMode") private var themeModeRaw =
        HanClipThemeMode.automatic.rawValue
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
        .sheet(
            isPresented: Binding(
                get: { selectedClipID != nil },
                set: { if !$0 { selectedClipID = nil } }
            )
        ) {
            if let id = selectedClipID,
               let index = model.renderableClips.firstIndex(where: {
                   $0.id == id
               }) {
                let presentedClip = model.renderableClips[index]
                VideoTrimEditor(
                    clip: bindingForClip(id: id, fallback: presentedClip),
                    previewAspectRatio: model.outputRenderSize.width
                        / max(1, model.outputRenderSize.height),
                    currentPosition: index + 1,
                    totalClipCount: model.renderableClips.count,
                    defaultDuration: model.defaultDuration,
                    totalDurationText: model.totalDurationText,
                    autoplayOnLoad: true,
                    onAutoplayConsumed: {
                        shouldAutoplaySelectedClip = false
                    },
                    canGoPrevious: index > model.renderableClips.startIndex,
                    canGoNext: index < model.renderableClips.index(
                        before: model.renderableClips.endIndex
                    ),
                    onPrevious: {
                        guard index > model.renderableClips.startIndex
                        else { return }
                        shouldAutoplaySelectedClip = true
                        selectedClipID = model.renderableClips[
                            model.renderableClips.index(before: index)
                        ].id
                    },
                    onNext: {
                        guard index < model.renderableClips.index(
                            before: model.renderableClips.endIndex
                        ) else { return }
                        shouldAutoplaySelectedClip = true
                        selectedClipID = model.renderableClips[
                            model.renderableClips.index(after: index)
                        ].id
                    },
                    onDelete: {
                        deleteClipFromEditor(id: id)
                    },
                    onPreview: {
                        selectedClipID = nil
                        Task { @MainActor in
                            try? await Task.sleep(
                                for: .milliseconds(300)
                            )
                            model.saveProjectAndOpenPreview()
                        }
                    }
                )
                .id(id)
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
        selectedClipID = nil
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

    private var resetConfirmationPopup: some View {
        VStack(spacing: 12) {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.snappy) {
                            showResetConfirmation = false
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
        let editableClips = model.renderableClips
        guard let index = editableClips.firstIndex(where: { $0.id == id })
        else {
            selectedClipID = nil
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
            selectedClipID = nextClipID
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
        List {
            Section {
                clipEditorSettings
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: 0,
                            bottom: 0,
                            trailing: 0
                        )
                    )

                clipModeHeader
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: 0,
                            bottom: 0,
                            trailing: 0
                        )
                    )

                ForEach($model.clips) { $clip in
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
                        onSelect: {
                            guard !clip.isVideoSegmentParent else { return }
                            selectedClipID = clip.id
                        }
                    )
                        .listRowBackground(
                            clip.isVideoSegmentParent
                                ? HanClipTheme.secondary.opacity(0.16)
                                : HanClipTheme.secondary.opacity(0.06)
                        )
                        .listRowInsets(
                            clipRowInsets(for: clip.id)
                        )
                        .opacity(
                            draggedClipID == clip.id ? 0.62 : 1
                        )
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
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 10)
                                )
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: ClipReorderDropDelegate(
                                targetID: clip.id,
                                clips: $model.clips,
                                draggedClipID: $draggedClipID
                            )
                        )
                        .accessibilityHint(
                            "길게 누른 뒤 끌어서 순서를 변경하거나, 눌러서 에디터를 엽니다."
                        )
                }
                .onDelete(perform: model.removeClips)
                .onMove(perform: model.moveClips)

                clipListFooterControls
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(
                        EdgeInsets(
                            top: 10,
                            leading: 0,
                            bottom: 18,
                            trailing: 0
                        )
                    )
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
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
                .padding(.horizontal, 16)
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
            bottom: isVideoSegmentChild || isFollowedByVideoSegmentChild
                ? 0
                : model.clips.last?.id == id ? 18 : 5,
            trailing: 16
        )
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
                        HanClipTheme.secondary.opacity(0.30)
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
                        HanClipTheme.secondary.opacity(0.30)
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
    }

    private var reorderGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 6),
                count: 4
            ),
            spacing: 8
        ) {
            ForEach(Array(model.clips.enumerated()), id: \.element.id) {
                index,
                clip in
                GeometryReader { proxy in
                    Image(uiImage: clip.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                        .clipped()
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
                                HanClipTheme.primary.opacity(0.50),
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
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                draggedClipID == clip.id
                                    ? HanClipTheme.primary
                                    : HanClipTheme.secondary.opacity(0.30),
                                lineWidth: draggedClipID == clip.id ? 3 : 1
                            )
                    }
                    .opacity(draggedClipID == clip.id ? 0.62 : 1)
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
                        selectedClipID = clip.id
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
}

private extension View {
    func calendarActionButtonStyle() -> some View {
        modifier(CalendarActionButtonStyle())
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
              let sourceIndex = clips.firstIndex(where: {
                  $0.id == draggedClipID
              }),
              let targetIndex = clips.firstIndex(where: {
                  $0.id == targetID
              })
        else { return }

        withAnimation(.snappy) {
            clips.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex
                    ? targetIndex + 1
                    : targetIndex
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

    func dropExited(info: DropInfo) {}
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
    let onDelete: () -> Void
    let content: Content

    @State private var restingOffset: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0

    private let actionWidth: CGFloat = 72

    init(
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onDelete = onDelete
        self.content = content()
    }

    private var visibleOffset: CGFloat {
        min(
            0,
            max(-actionWidth, restingOffset + dragTranslation)
        )
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                restingOffset = 0
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
            .accessibilityLabel("프로젝트 삭제")

            content
                .offset(x: visibleOffset)
                .simultaneousGesture(swipeGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .updating($dragTranslation) { value, state, _ in
                guard isHorizontalSwipe(value)
                else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard isHorizontalSwipe(value)
                else { return }

                let projectedOffset = restingOffset
                    + value.predictedEndTranslation.width
                withAnimation(.snappy) {
                    restingOffset = projectedOffset < -actionWidth / 2
                        ? -actionWidth
                        : 0
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
            .easeInOut(duration: 0.20),
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
                    showSaveOptions = false
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
                    showSaveOptions = false
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
                reachedEnd = true
                isPlaying = false
            } else if currentSeconds < durationSeconds - 0.05 {
                reachedEnd = false
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            currentSeconds = durationSeconds
            reachedEnd = true
            isPlaying = false
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
