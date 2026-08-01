import AVFoundation
import SwiftUI
import UIKit

struct VideoTrimEditor: View {
    @Binding var clip: ClipItem
    let previewAspectRatio: CGFloat
    let currentPosition: Int
    let totalClipCount: Int
    let defaultDuration: Double
    let totalDurationText: String
    let autoplayOnLoad: Bool
    let onAutoplayConsumed: () -> Void
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onDelete: () -> Void
    let onPreview: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var temporaryLivePhotoURL: URL?
    @State private var mediaLoadTask: Task<Void, Never>?
    @State private var audioAnalysisTask: Task<Void, Never>?
    @State private var isLoadingPlayableMedia = false
    @State private var initialTrimStart: Double?
    @State private var initialDuration: Double?
    @State private var selectionMoveOrigin: Double?
    @State private var selectionMoveDuration: Double?
    @State private var trimDragEdge: TrimEdge?
    @State private var trimDragBoundaryOrigin: Double?
    @State private var isPlaying = false
    @State private var playbackProgress = 0.0
    @State private var wasPlayingBeforeScrub = false
    @State private var restartPlaybackAtSelectionStart = true
    @State private var shouldAutoplayAfterNavigation = false
    @State private var selectionCenterMarkerTime: Double?
    @State private var showDeleteConfirmation = false

    private var sourceURL: URL? {
        switch clip.source {
        case .videoFile(let url):
            return url
        case .livePhotoFiles(_, let videoURL)
            where clip.livePhotoMode == .motion:
            return videoURL
        default:
            return temporaryLivePhotoURL
        }
    }

    private var hasPlayableMedia: Bool {
        clip.isVideoClip
            || (clip.isLivePhoto && clip.livePhotoMode == .motion)
    }

    private var sourceDuration: Double {
        max(0.5, clip.sourceDuration ?? clip.duration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal, 20)

            previewWithNavigation

            if hasPlayableMedia {
                waveform
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .padding(.horizontal, 20)

                playbackControls
                    .padding(.horizontal, 20)
            } else {
                nonVideoInformation
                    .padding(.horizontal, 20)

                Color.clear
                    .frame(height: 44)
            }

            footerActions
                .padding(.horizontal, 20)
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .presentationDetents([.height(710)])
        .presentationDragIndicator(.visible)
        .onAppear(perform: preparePlayer)
        .onChange(of: clip.id) { _, _ in
            releasePlayer()
            playbackProgress = 0
            restartPlaybackAtSelectionStart = true
            preparePlayer()
        }
        .onDisappear(perform: releasePlayer)
        .onReceive(
            Timer.publish(
                every: 0.05,
                on: .main,
                in: .common
            ).autoconnect()
        ) { _ in
            synchronizePlaybackProgress()
        }
        .alert(
            "현재 미디어를 삭제할까요?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("삭제", role: .destructive) {
                pausePlayback()
                onDelete()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제한 미디어는 현재 프로젝트의 클립 목록에서 제거됩니다.")
        }
    }

    private var previewWithNavigation: some View {
        GeometryReader { outerProxy in
            let previewSize = fittedPreviewSize(in: outerProxy.size)

            previewSurface
                .frame(
                    width: previewSize.width,
                    height: previewSize.height
                )
                .background(HanClipTheme.secondary.opacity(0.30))
                .clipped()
                .overlay {
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            previewNavigationButton(
                                systemImage: "chevron.left",
                                label: "이전 클립",
                                isEnabled: canGoPrevious,
                                action: navigateToPrevious
                            )
                            .frame(width: proxy.size.width * 0.20)

                            Button(action: togglePlaybackFromPreview) {
                                Color.clear
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasPlayableMedia)
                            .frame(width: proxy.size.width * 0.60)
                            .accessibilityLabel(
                                isPlaying
                                    ? "미리보기 일시 정지"
                                    : "미리보기 재생"
                            )

                            previewNavigationButton(
                                systemImage: "chevron.right",
                                label: "다음 클립",
                                isEnabled: canGoNext,
                                action: navigateToNext
                            )
                            .frame(width: proxy.size.width * 0.20)
                        }
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .center
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func fittedPreviewSize(in availableSize: CGSize) -> CGSize {
        let maximumDimension = min(
            availableSize.width,
            availableSize.height
        )
        let ratio = max(0.01, previewAspectRatio)

        if ratio >= 1 {
            return CGSize(
                width: maximumDimension,
                height: maximumDimension / ratio
            )
        }

        return CGSize(
            width: maximumDimension * ratio,
            height: maximumDimension
        )
    }

    @ViewBuilder
    private var previewSurface: some View {
        if hasPlayableMedia {
            ZStack {
                PlayerSurface(
                    player: player,
                    backgroundColor: HanClipTheme.secondaryUIColor
                        .withAlphaComponent(0.30)
                )

                if isLoadingPlayableMedia {
                    ProgressView()
                        .tint(.white)
                        .padding(14)
                        .background(.black.opacity(0.44), in: Circle())
                }
            }
            .background(HanClipTheme.secondary.opacity(0.30))
        } else {
            Image(uiImage: clip.thumbnail)
                .resizable()
                .scaledToFill()
                .background(HanClipTheme.secondary.opacity(0.30))
        }
    }

    private func previewNavigationButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Color.clear
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.24), in: Circle())
                    .opacity(isEnabled ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private var nonVideoInformation: some View {
        HStack {
            Text(
                clip.isLivePhoto
                    ? clip.livePhotoMode.rawValue
                    : "Photo"
            )
            .font(.system(size: 16, weight: .semibold))

            Spacer()

            Text(nonVideoDurationText)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(HanClipTheme.text.opacity(0.66))
        }
        .frame(height: 60)
        .padding(.horizontal, 16)
        .background(
            HanClipTheme.secondary.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 10) {
                Text("\(currentPosition) / \(totalClipCount)")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                Button(action: deleteCurrentMedia) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 28)
                        .background(
                            HanClipTheme.primary,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("현재 미디어 삭제")
            }

            if clip.isLivePhoto {
                LivePhotoModeSegmentedControl(
                    mode: Binding(
                        get: { clip.livePhotoMode },
                        set: { mode in
                            setLivePhotoMode(mode)
                        }
                    ),
                    tint: HanClipTheme.primary,
                    width: 124,
                    height: 28
                )
                .accessibilityLabel("Live Photo 사용 방식")
                .accessibilityValue(clip.livePhotoMode.rawValue)
                .accessibilityHint("포토와 라이브 모드를 전환합니다.")
            }
        }
    }

    private var nonVideoDurationText: String {
        if clip.isLivePhoto, clip.livePhotoMode == .motion {
            return String(
                format: "%.1f / 전체 %@",
                clip.duration,
                totalSourceDurationText
            )
        }
        return String(format: "%.1f초", clip.duration)
    }

    private var totalSourceDurationText: String {
        let totalSeconds = max(
            0,
            Int((clip.sourceDuration ?? clip.livePhotoDuration ?? clip.duration).rounded())
        )
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            Button(action: resetSelection) {
                Label("리셋", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        HanClipTheme.primary,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 84)

            Button {
                pausePlayback()
                dismiss()
            } label: {
                Label("확인", systemImage: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        HanClipTheme.primary,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 76)

            Button(action: openFullPreview) {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")

                    Text(totalDurationText)
                        .font(
                            .system(
                                size: 12,
                                weight: .semibold,
                                design: .monospaced
                            )
                        )

                    Text("만들기")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    HanClipTheme.primary,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var waveform: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let startX = width * clip.trimStart / sourceDuration
            let endX = width * clip.trimEnd / sourceDuration

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(HanClipTheme.secondary.opacity(0.10))

                waveformBars

                if let markerTime =
                    selectionCenterMarkerTime ?? clip.audioPeakTime {
                    Rectangle()
                        .fill(HanClipTheme.primary)
                        .frame(width: 2)
                        .position(
                            x: width * markerTime / sourceDuration,
                            y: proxy.size.height / 2
                        )
                        .allowsHitTesting(false)
                }

                unselectedArea(
                    width: startX,
                    alignment: .leading,
                    edge: .leading,
                    waveformWidth: width
                )
                unselectedArea(
                    width: width - endX,
                    alignment: .trailing,
                    edge: .trailing,
                    waveformWidth: width
                )

                movableSelection(
                    startX: startX,
                    endX: endX,
                    height: proxy.size.height,
                    waveformWidth: width
                )

                if isPlaying {
                    playbackPositionBar(
                        x: width
                            * (
                                clip.trimStart
                                    + playbackProgress * clip.duration
                            )
                            / sourceDuration,
                        height: proxy.size.height
                    )
                    .zIndex(8)
                }

                trimHandle(
                    edge: .leading,
                    x: startX,
                    geometry: proxy
                )
                .zIndex(12)

                trimHandle(
                    edge: .trailing,
                    x: endX,
                    geometry: proxy
                )
                .zIndex(11)
            }
            .coordinateSpace(name: "waveform")
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel("사운드 인디케이터와 영상 선택 구간")
    }

    private func playbackPositionBar(
        x: CGFloat,
        height: CGFloat
    ) -> some View {
        Capsule()
            .fill(HanClipTheme.primary)
            .frame(width: 4, height: height - 8)
            .overlay {
                Capsule()
                    .stroke(Color.black.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.24), radius: 2)
            .position(x: x, y: height / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var waveformBars: some View {
        HStack(alignment: .center, spacing: 1) {
            ForEach(
                Array(waveformValues.enumerated()),
                id: \.offset
            ) { _, value in
                Capsule()
                    .fill(HanClipTheme.secondary.opacity(0.68))
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: max(4, 52 * value)
                    )
            }
        }
        .padding(.horizontal, 8)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func unselectedArea(
        width: CGFloat,
        alignment: Alignment,
        edge: TrimEdge,
        waveformWidth: CGFloat
    ) -> some View {
        let interactiveArea = Color.black.opacity(0.42)
            .frame(width: max(0, width))
            .contentShape(Rectangle())
            .highPriorityGesture(
                trimGesture(
                    edge: edge,
                    waveformWidth: waveformWidth
                ),
                including: .all
            )

        if alignment == .leading {
            HStack(spacing: 0) {
                interactiveArea
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
        } else {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                interactiveArea
            }
        }
    }

    private func movableSelection(
        startX: CGFloat,
        endX: CGFloat,
        height: CGFloat,
        waveformWidth: CGFloat
    ) -> some View {
        let selectionWidth = max(1, endX - startX)
        let moveTouchWidth = max(1, selectionWidth - 44)

        return Color.clear
            .frame(width: moveTouchWidth, height: height)
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(HanClipTheme.primary, lineWidth: 3)
                    .frame(width: selectionWidth)
                    .allowsHitTesting(false)
            }
            .position(
                x: (startX + endX) / 2,
                y: height / 2
            )
            .gesture(moveSelectionGesture(width: waveformWidth))
            .zIndex(2)
    }

    private func trimHandle(
        edge: TrimEdge,
        x: CGFloat,
        geometry: GeometryProxy
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(HanClipTheme.primary)
                .frame(width: 8, height: geometry.size.height)
                .offset(x: edge == .leading ? 4 : -4)

            Image(
                systemName: edge == .leading
                    ? "chevron.right"
                    : "chevron.left"
            )
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
        }
        .frame(width: 44, height: geometry.size.height)
        .contentShape(Rectangle())
        .position(
            x: min(
                max(22, x),
                max(22, geometry.size.width - 22)
            ),
            y: geometry.size.height / 2
        )
        .highPriorityGesture(
            moveSelectionGesture(width: geometry.size.width),
            including: .all
        )
        .accessibilityLabel(
            edge == .leading ? "선택 구간 왼쪽 이동" : "선택 구간 오른쪽 이동"
        )
    }

    private func trimGesture(
        edge: TrimEdge,
        waveformWidth: CGFloat
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named("waveform")
        )
        .onChanged { value in
            pausePlayback()
            if shouldMoveSelectionWhenDraggingHandle(
                waveformWidth: waveformWidth
            ) {
                moveSelection(
                    translationWidth: value.translation.width,
                    waveformWidth: waveformWidth
                )
                return
            }

            let currentBoundary = edge == .leading
                ? clip.trimStart
                : clip.trimEnd
            if trimDragEdge != edge || trimDragBoundaryOrigin == nil {
                trimDragEdge = edge
                trimDragBoundaryOrigin = currentBoundary
            }
            let boundaryOrigin = trimDragBoundaryOrigin ?? currentBoundary
            let time = min(
                sourceDuration,
                max(
                    0,
                    boundaryOrigin
                        + Double(
                            value.translation.width
                                / max(1, waveformWidth)
                        ) * sourceDuration
                )
            )

            switch edge {
            case .leading:
                let fixedEnd = clip.trimEnd
                clip.trimStart = max(
                    0,
                    min(fixedEnd - 0.5, time)
                )
                clip.duration = fixedEnd - clip.trimStart
                clip.photoDuration = clip.duration
                updatePlaybackBoundary()
                showTrimEdge(.leading)

            case .trailing:
                let newEnd = min(
                    sourceDuration,
                    max(clip.trimStart + 0.5, time)
                )
                clip.duration = newEnd - clip.trimStart
                clip.photoDuration = clip.duration
                updatePlaybackBoundary()
                showTrimEdge(.trailing)
            }
        }
        .onEnded { _ in
            trimDragEdge = nil
            trimDragBoundaryOrigin = nil
            selectionMoveOrigin = nil
            selectionMoveDuration = nil
        }
    }

    private func shouldMoveSelectionWhenDraggingHandle(
        waveformWidth: CGFloat
    ) -> Bool {
        let selectionWidth = CGFloat(clip.duration / sourceDuration)
            * waveformWidth
        let visibleGap = selectionWidth - 8
        return visibleGap <= 4
    }

    private func moveSelectionGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                pausePlayback()
                moveSelection(
                    translationWidth: value.translation.width,
                    waveformWidth: width
                )
            }
            .onEnded { _ in
                selectionMoveOrigin = nil
                selectionMoveDuration = nil
            }
    }

    private func moveSelection(
        translationWidth: CGFloat,
        waveformWidth: CGFloat
    ) {
        if selectionMoveOrigin == nil {
            selectionMoveOrigin = clip.trimStart
            selectionMoveDuration = clip.duration
        }
        let origin = selectionMoveOrigin ?? clip.trimStart
        let fixedDuration = selectionMoveDuration ?? clip.duration
        let delta = Double(
            translationWidth / max(1, waveformWidth)
        ) * sourceDuration
        clip.duration = fixedDuration
        clip.photoDuration = fixedDuration
        clip.trimStart = max(
            0,
            min(sourceDuration - fixedDuration, origin + delta)
        )
        selectionCenterMarkerTime = clip.trimStart + fixedDuration / 2
        updatePlaybackBoundary()
        showSelectionMidpoint()
    }

    private var playbackControls: some View {
        HStack(spacing: 8) {
            Button(action: togglePlayback) {
                Image(
                    systemName: isPlaying
                        ? "pause.fill"
                        : playbackProgress >= 0.999
                            ? "arrow.counterclockwise"
                            : "play.fill"
                )
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(HanClipTheme.primary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isPlaying
                    ? "일시 정지"
                    : playbackProgress >= 0.999
                        ? "다시 재생"
                        : "재생"
            )

            Text(
                playbackTimeText(
                    playbackProgress * clip.duration
                )
            )
            .frame(width: 46, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { playbackProgress },
                    set: { newValue in
                        playbackProgress = newValue
                        seek(
                            to: clip.trimStart
                                + newValue * clip.duration
                        )
                    }
                ),
                in: 0...1,
                onEditingChanged: handleScrubbing
            )
            .tint(HanClipTheme.primary)
            .accessibilityLabel("선택 구간 진행바")

            Text(playbackTimeText(clip.duration))
                .frame(width: 46, alignment: .leading)
        }
        .font(
            .system(
                size: 12,
                weight: .medium,
                design: .monospaced
            )
        )
        .frame(height: 44)
    }

    private func playbackTimeText(_ seconds: Double) -> String {
        let tenths = max(Int((seconds * 10).rounded()), 0)
        let minutes = tenths / 600
        let remainingSeconds = Double(tenths % 600) / 10
        return String(
            format: "%d:%04.1f",
            minutes,
            remainingSeconds
        )
    }

    private var waveformValues: [Double] {
        let displaySampleCount = 80
        let source = clip.audioWaveform.isEmpty
            ? Array(repeating: 0.08, count: displaySampleCount)
            : clip.audioWaveform
        guard source.count > displaySampleCount else { return source }

        return (0..<displaySampleCount).map { index in
            let lower = index * source.count / displaySampleCount
            let upper = max(
                lower + 1,
                (index + 1) * source.count / displaySampleCount
            )
            let values = source[lower..<min(source.count, upper)]
            return values.reduce(0, +) / Double(values.count)
        }
    }

    private func preparePlayer() {
        initialTrimStart = clip.trimStart
        initialDuration = clip.duration
        selectionCenterMarkerTime = clip.audioPeakTime
        guard hasPlayableMedia else { return }
        if let sourceURL {
            configurePlayer(with: sourceURL)
            return
        }
        loadLivePhotoMotionIfNeeded()
    }

    private func configurePlayer(with sourceURL: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: sourceURL))
        analyzePlayableAudioIfNeeded(from: sourceURL)
        updatePlaybackBoundary()
        showSelectionMidpoint()
        if shouldAutoplayAfterNavigation || autoplayOnLoad {
            shouldAutoplayAfterNavigation = false
            onAutoplayConsumed()
            playFromSelectionStart()
        }
    }

    private func playFromSelectionStart() {
        guard hasPlayableMedia, player.currentItem != nil else { return }
        restartPlaybackAtSelectionStart = false
        updatePlaybackBoundary()
        player.seek(
            to: CMTime(seconds: clip.trimStart, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { finished in
            Task { @MainActor in
                guard finished else { return }
                playbackProgress = 0
                player.play()
                isPlaying = true
            }
        }
    }

    private func releasePlayer() {
        mediaLoadTask?.cancel()
        mediaLoadTask = nil
        audioAnalysisTask?.cancel()
        audioAnalysisTask = nil
        pausePlayback()
        player.replaceCurrentItem(with: nil)
        if let temporaryLivePhotoURL {
            try? FileManager.default.removeItem(at: temporaryLivePhotoURL)
            self.temporaryLivePhotoURL = nil
        }
        isLoadingPlayableMedia = false
    }

    private func analyzePlayableAudioIfNeeded(from url: URL) {
        guard clip.isLivePhoto,
              clip.livePhotoMode == .motion,
              clip.audioWaveform.isEmpty
        else { return }

        let clipID = clip.id
        audioAnalysisTask?.cancel()
        audioAnalysisTask = Task {
            guard let analysis = try? await AudioAnalysisService.analyze(url: url)
            else { return }
            await MainActor.run {
                guard clip.id == clipID else { return }
                clip.audioWaveform = analysis.waveform
                clip.audioPeakTime = analysis.peakTime
                clip.audioPeakTimes = analysis.peakTimes
                selectionCenterMarkerTime = analysis.peakTime
            }
        }
    }

    private func loadLivePhotoMotionIfNeeded() {
        guard clip.isLivePhoto,
              clip.livePhotoMode == .motion,
              case .photoAsset(let identifier) = clip.source,
              let asset = PhotoLibraryService.asset(
                localIdentifier: identifier
              )
        else { return }

        isLoadingPlayableMedia = true
        mediaLoadTask = Task {
            do {
                let url = try await PhotoLibraryService.exportPairedVideo(
                    for: asset
                )
                try Task.checkCancellation()
                temporaryLivePhotoURL = url
                isLoadingPlayableMedia = false
                configurePlayer(with: url)
            } catch is CancellationError {
                isLoadingPlayableMedia = false
            } catch {
                isLoadingPlayableMedia = false
            }
            mediaLoadTask = nil
        }
    }

    private func setLivePhotoMode(_ mode: LivePhotoMode) {
        guard clip.isLivePhoto, clip.livePhotoMode != mode else { return }

        if mode == .still {
            clip.livePhotoMode = .still
            clip.photoDuration = defaultDuration
            clip.duration = defaultDuration
            releasePlayer()
            return
        }

        clip.livePhotoMode = .motion
        applyLivePhotoPlaybackWindow()
        playbackProgress = 0
        releasePlayer()

        if let sourceURL {
            configurePlayer(with: sourceURL)
        } else {
            loadLivePhotoMotionIfNeeded()
        }
    }

    private func togglePlayback() {
        guard hasPlayableMedia, player.currentItem != nil else { return }
        if isPlaying {
            pausePlayback()
            return
        }

        let current = player.currentTime().seconds
        if restartPlaybackAtSelectionStart
            || playbackProgress >= 0.999
            || !current.isFinite
            || current < clip.trimStart
            || current >= clip.trimEnd {
            seek(to: clip.trimStart)
            playbackProgress = 0
        }
        restartPlaybackAtSelectionStart = false
        updatePlaybackBoundary()
        player.play()
        isPlaying = true
    }

    private func applyLivePhotoPlaybackWindow() {
        let sourceDuration = clip.sourceDuration
            ?? clip.livePhotoDuration
            ?? clip.duration
        let selectedDuration = min(defaultDuration, sourceDuration)
        clip.sourceDuration = sourceDuration
        clip.livePhotoDuration = sourceDuration
        clip.duration = selectedDuration
        clip.trimStart = max(0, (sourceDuration - selectedDuration) / 2)
    }

    private func togglePlaybackFromPreview() {
        togglePlayback()
    }

    private func openFullPreview() {
        pausePlayback()
        dismiss()
        onPreview()
    }

    private func deleteCurrentMedia() {
        pausePlayback()
        if clip.isVideoSegmentChild {
            onDelete()
            return
        }
        showDeleteConfirmation = true
    }

    private func navigateToPrevious() {
        guard canGoPrevious else { return }
        shouldAutoplayAfterNavigation = true
        pausePlayback()
        onPrevious()
    }

    private func navigateToNext() {
        guard canGoNext else { return }
        shouldAutoplayAfterNavigation = true
        pausePlayback()
        onNext()
    }

    private func pausePlayback() {
        player.pause()
        isPlaying = false
    }

    private func synchronizePlaybackProgress() {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, clip.duration > 0 else { return }

        if seconds >= clip.trimEnd - 0.02 {
            if isPlaying {
                player.pause()
                isPlaying = false
            }
            playbackProgress = 1
            restartPlaybackAtSelectionStart = true
            return
        }

        playbackProgress = min(
            1,
            max(0, (seconds - clip.trimStart) / clip.duration)
        )
        if player.rate == 0, isPlaying {
            isPlaying = false
        }
    }

    private func handleScrubbing(_ isEditing: Bool) {
        if isEditing {
            wasPlayingBeforeScrub = isPlaying
            pausePlayback()
            restartPlaybackAtSelectionStart = false
        } else if wasPlayingBeforeScrub, playbackProgress < 0.999 {
            player.play()
            isPlaying = true
            wasPlayingBeforeScrub = false
        }
    }

    private func updatePlaybackBoundary() {
        player.currentItem?.forwardPlaybackEndTime = CMTime(
            seconds: clip.trimEnd,
            preferredTimescale: 600
        )
    }

    private func showSelectionMidpoint() {
        restartPlaybackAtSelectionStart = true
        seek(to: clip.trimStart + clip.duration / 2)
    }

    private func showTrimEdge(_ edge: TrimEdge) {
        restartPlaybackAtSelectionStart = true
        switch edge {
        case .leading:
            seek(to: clip.trimStart)
        case .trailing:
            let frameInsideSelection = max(
                clip.trimStart,
                clip.trimEnd - 1.0 / 600.0
            )
            seek(to: frameInsideSelection)
        }
    }

    private func seek(to seconds: Double) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        if clip.duration > 0 {
            playbackProgress = min(
                1,
                max(0, (seconds - clip.trimStart) / clip.duration)
            )
        }
    }

    private func resetSelection() {
        guard let initialTrimStart, let initialDuration else { return }
        pausePlayback()
        clip.trimStart = initialTrimStart
        clip.duration = initialDuration
        clip.photoDuration = initialDuration
        selectionMoveOrigin = nil
        selectionMoveDuration = nil
        selectionCenterMarkerTime = clip.audioPeakTime
        updatePlaybackBoundary()
        showSelectionMidpoint()
    }
}

private enum TrimEdge {
    case leading
    case trailing
}

private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let backgroundColor: UIColor

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.player = player
        view.backgroundColor = backgroundColor
        return view
    }

    func updateUIView(
        _ uiView: PlayerSurfaceView,
        context: Context
    ) {
        uiView.playerLayer.player = player
        uiView.backgroundColor = backgroundColor
    }
}

private final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspectFill
    }
}
