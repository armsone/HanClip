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
    @Binding var autoAdvanceEnabled: Bool
    @Binding var autoAdvanceLoops: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onFirst: () -> Void
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
    @State private var stillAutoAdvanceTask: Task<Void, Never>?
    @State private var didAutoAdvanceCurrentClip = false
    @State private var isPlaybackLooping = false
    @State private var stillPlaybackStartDate: Date?
    @State private var stillPlaybackStartProgress = 0.0
    @GestureState private var dismissDragOffset: CGFloat = 0

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
        VStack(alignment: .leading, spacing: 10) {
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    .ultraThinMaterial,
                    in: Capsule()
                )
                .background(
                    LinearGradient(
                        colors: [
                            HanClipTheme.secondary.opacity(0.08),
                            HanClipTheme.background.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.30), lineWidth: 1)
                }
                .shadow(
                    color: Color.black.opacity(0.06),
                    radius: 8,
                    y: 3
                )
                .padding(.horizontal, 22)

            previewWithNavigation

            if hasPlayableMedia {
                waveform
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .padding(.horizontal, 22)

                playbackControls
                    .padding(.horizontal, 22)
            } else {
                waveform
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .padding(.horizontal, 22)
                    .allowsHitTesting(false)

                playbackControls
                    .padding(.horizontal, 22)
            }

            footerActions
                .padding(.horizontal, 22)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                HanClipTheme.backgroundGradient
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        HanClipTheme.secondary.opacity(0.09),
                        HanClipTheme.background.opacity(0.0),
                        HanClipTheme.secondary.opacity(0.055),
                        Color.white.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            HanClipTheme.secondary.opacity(0.16),
                            HanClipTheme.background.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150)

                    Spacer()

                    LinearGradient(
                        colors: [
                            HanClipTheme.background.opacity(0.0),
                            HanClipTheme.secondary.opacity(0.07)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 170)
                }
                .ignoresSafeArea()
            }
        }
        .offset(y: dismissDragOffset)
        .opacity(dismissDragOffset > 0 ? max(0.86, 1 - dismissDragOffset / 900) : 1)
        .background {
            HanClipTheme.backgroundGradient
                .ignoresSafeArea()
        }
        .simultaneousGesture(confirmOnDownwardDrag)
        .onAppear {
            preparePlayer()
            updateLoopIconAnimation(autoAdvanceLoops && autoAdvanceEnabled)
        }
        .onChange(of: clip.id) { _, _ in
            releasePlayer()
            playbackProgress = 0
            restartPlaybackAtSelectionStart = true
            didAutoAdvanceCurrentClip = false
            preparePlayer()
            updateLoopIconAnimation(autoAdvanceLoops && autoAdvanceEnabled)
        }
        .onChange(of: autoAdvanceEnabled) { _, isEnabled in
            if isEnabled {
                startAutoAdvanceForCurrentClip()
            } else {
                autoAdvanceLoops = false
                updateLoopIconAnimation(false)
                stillAutoAdvanceTask?.cancel()
                stillAutoAdvanceTask = nil
            }
        }
        .onChange(of: autoAdvanceLoops) { _, isLooping in
            updateLoopIconAnimation(isLooping || isPlaybackLooping)
        }
        .onChange(of: isPlaybackLooping) { _, isLooping in
            updateLoopIconAnimation(autoAdvanceLoops || isLooping)
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
            Text("삭제한 미디어는 현재 영화의 클립 목록에서 제거됩니다.")
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
                .background(HanClipTheme.secondary.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                }
                .shadow(
                    color: HanClipTheme.primary.opacity(0.11),
                    radius: 14,
                    y: 7
                )
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
                            .frame(width: proxy.size.width * 0.60)
                            .accessibilityLabel(
                                isPlaying
                                    ? "시사회 일시 정지"
                                    : "시사회 재생"
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
        .padding(.horizontal, 20)
    }

    private func previewCornerButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(HanClipTheme.primary)
                .frame(width: 38, height: 38)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.48), lineWidth: 1)
                }
                .shadow(
                    color: Color.black.opacity(0.14),
                    radius: 8,
                    y: 4
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(label)
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
                        .withAlphaComponent(0.24)
                        )

                if isLoadingPlayableMedia {
                    ProgressView()
                        .tint(.white)
                        .padding(14)
                        .background(.black.opacity(0.44), in: Circle())
                }
            }
            .background(HanClipTheme.secondary.opacity(0.24))
        } else {
            Image(uiImage: clip.thumbnail)
                .resizable()
                .scaledToFill()
                .background(HanClipTheme.secondary.opacity(0.24))
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
                .foregroundStyle(HanClipTheme.secondaryText)
        }
        .frame(height: 60)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.panelFill,
                    HanClipTheme.secondary.opacity(0.035)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            if clip.isLivePhoto {
                previewPositionText

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
                .frame(maxWidth: .infinity, alignment: .center)

                deletePreviewButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                previewPositionText

                currentMediaIcon
                    .frame(maxWidth: .infinity, alignment: .center)

                deletePreviewButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 40)
    }

    private var previewPositionText: some View {
        Text("\(currentPosition) / \(totalClipCount)")
            .font(
                .system(
                    size: 15,
                    weight: .semibold,
                    design: .rounded
                )
            )
            .monospacedDigit()
            .foregroundStyle(HanClipTheme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
            .frame(height: 28)
            .accessibilityLabel(
                "\(currentPosition) / \(totalClipCount)번째 시사회"
            )
    }

    private var currentMediaIcon: some View {
        Group {
            if clip.isVideoSegmentChild {
                Image(systemName: "movieclapper")
                    .font(.system(size: 18, weight: .semibold))
            } else if clip.isVideoClip {
                FilmCameraIcon()
                    .frame(width: 22, height: 18)
            } else {
                Image(systemName: "photo.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .foregroundStyle(HanClipTheme.primary)
        .opacity(0.88)
        .frame(height: 28)
        .accessibilityHidden(true)
    }

    private var deletePreviewButton: some View {
        Button {
            pausePlayback()
            showDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.red.opacity(0.76))
                .frame(width: 32, height: 32)
                .background(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.10),
                            HanClipTheme.background.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(Color.red.opacity(0.24), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("미디어 삭제")
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
        HStack(spacing: 10) {
            Button {
                pausePlayback()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HanClipTheme.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        HanClipTheme.background.opacity(0.36),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(HanClipTheme.primary.opacity(0.28), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .frame(width: 50)
            .accessibilityLabel("닫기")

            Button(action: resetSelection) {
                Label("리셋", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        HanClipTheme.background.opacity(0.36),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(HanClipTheme.primary.opacity(0.28), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .frame(width: 88)

            Button(action: openFullPreview) {
                HStack(spacing: 5) {
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
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(HanClipTheme.primaryText.opacity(0.82))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: [
                            HanClipTheme.primary.opacity(0.10),
                            HanClipTheme.secondary.opacity(0.065),
                            HanClipTheme.background.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(HanClipTheme.primary.opacity(0.22), lineWidth: 2)
                }
                .shadow(
                    color: HanClipTheme.primary.opacity(0.035),
                    radius: 4,
                    y: 1
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
                movableSelection(
                    startX: startX,
                    endX: endX,
                    height: proxy.size.height,
                    waveformWidth: width
                )

                waveformBars(waveformWidth: width)

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

                if let markerTime =
                    selectionCenterMarkerTime ?? clip.audioPeakTime {
                    Rectangle()
                        .fill(Color.white.opacity(0.88))
                        .frame(width: 1.25, height: proxy.size.height - 12)
                        .position(
                            x: width * markerTime / sourceDuration,
                            y: proxy.size.height / 2
                        )
                        .allowsHitTesting(false)
                        .zIndex(7)
                }

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
            .padding(.vertical, 4)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(
                HanClipTheme.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(HanClipTheme.primary.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
        }
        .accessibilityLabel("사운드 인디케이터와 영상 선택 구간")
    }

    private func playbackPositionBar(
        x: CGFloat,
        height: CGFloat
    ) -> some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 1.5, height: height - 12)
            .position(x: x, y: height / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func waveformBars(waveformWidth: CGFloat) -> some View {
        let values = waveformValues
        let spacing: CGFloat = 1.5
        let availableWidth = max(1, waveformWidth)
        let totalSpacing = spacing * CGFloat(max(0, values.count - 1))
        let barWidth = max(
            1.2,
            (availableWidth - totalSpacing) / CGFloat(max(1, values.count))
        )

        return HStack(alignment: .center, spacing: spacing) {
            ForEach(
                Array(values.enumerated()),
                id: \.offset
            ) { _, value in
                Capsule()
                    .fill(HanClipTheme.primary.opacity(0.62))
                    .frame(
                        width: barWidth,
                        height: max(1.4, 42 * pow(value, 1.35))
                    )
            }
        }
        .frame(width: availableWidth)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func unselectedArea(
        width: CGFloat,
        alignment: Alignment,
        edge: TrimEdge,
        waveformWidth: CGFloat
    ) -> some View {
        let interactiveArea = HanClipTheme.background.opacity(0.42)
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
        let selectionHeight = max(1, height - 8)

        return Color.clear
            .frame(width: moveTouchWidth, height: height)
            .contentShape(Rectangle())
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(HanClipTheme.secondary.opacity(0.13))
                }
                .frame(width: selectionWidth, height: selectionHeight)
                .allowsHitTesting(false)
            }
            .position(
                x: (startX + endX) / 2,
                y: height / 2 - 4
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
            Capsule()
                .fill(HanClipTheme.primary.opacity(0.88))
                .frame(width: 14, height: geometry.size.height - 10)
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(
                    color: HanClipTheme.primary.opacity(0.22),
                    radius: 4,
                    y: 1
                )

            Image(
                systemName: edge == .leading
                    ? "chevron.right"
                    : "chevron.left"
            )
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
        }
        .frame(width: 44, height: geometry.size.height)
        .contentShape(Rectangle())
            .position(
                x: min(
                    max(26, x),
                    max(26, geometry.size.width - 26)
            ),
            y: geometry.size.height / 2 - 4
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
            Button(action: handlePlaybackButtonTap) {
                playbackButtonIcon
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: [
                            HanClipTheme.primary,
                            HanClipTheme.secondary.opacity(0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .shadow(
                    color: HanClipTheme.primary.opacity(0.16),
                    radius: 8,
                    y: 4
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playbackButtonAccessibilityLabel)

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
                        if hasPlayableMedia {
                            seek(
                                to: clip.trimStart
                                    + newValue * clip.duration
                            )
                        } else if isPlaying {
                            startStillPreviewPlayback(
                                from: newValue,
                                shouldRestartTimer: true
                            )
                        }
                    }
                ),
                in: 0...1,
                onEditingChanged: handleScrubbing
            )
            .tint(HanClipTheme.primary)
            .accessibilityLabel("선택 구간 진행바")

            Text(playbackTimeText(clip.duration))
                .frame(width: 46, alignment: .leading)

            loopPlaybackButton
        }
        .font(
            .system(
                size: 12,
                weight: .medium,
                design: .monospaced
            )
        )
        .frame(height: 40)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .background(
            HanClipTheme.secondary.opacity(0.07),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }

    @ViewBuilder
    private var playbackButtonIcon: some View {
        Image(systemName: playbackButtonSystemImage)
            .font(.system(size: 16, weight: .bold))
            .id(playbackButtonSystemImage)
    }

    private var playbackButtonSystemImage: String {
        if isPlaying {
            return "pause.fill"
        }

        return playbackProgress >= 0.999
            ? "arrow.counterclockwise"
            : "play.fill"
    }

    private var playbackButtonAccessibilityLabel: String {
        if isPlaying {
            return "일시 정지"
        }

        return playbackProgress >= 0.999 ? "다시 재생" : "재생"
    }

    private var loopPlaybackButton: some View {
        Button(action: togglePlaybackLoop) {
            ZStack {
                Circle()
                    .fill(
                        autoAdvanceLoops
                            ? HanClipTheme.primary.opacity(0.92)
                            : HanClipTheme.secondary.opacity(0.11)
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                autoAdvanceLoops
                                    ? Color.white.opacity(0.30)
                                    : HanClipTheme.primary.opacity(0.18),
                                lineWidth: 1
                            )
                    }

                if autoAdvanceLoops {
                    RotatingLoopIcon(size: 15)
                        .foregroundStyle(.white)
                        .id("loop-on")
                } else {
                    Image(systemName: "repeat")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HanClipTheme.primary.opacity(0.72))
                        .id("loop-off")
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            autoAdvanceLoops ? "무한 루프 끄기" : "무한 루프 켜기"
        )
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
        let sampledValues: [Double]

        if source.count <= displaySampleCount {
            sampledValues = source
        } else {
            sampledValues = (0..<displaySampleCount).map { index in
            let lower = index * source.count / displaySampleCount
            let upper = max(
                lower + 1,
                (index + 1) * source.count / displaySampleCount
            )
            let values = source[lower..<min(source.count, upper)]
            return values.reduce(0, +) / Double(values.count)
            }
        }

        let rawMaximum = sampledValues.max() ?? 0
        guard rawMaximum > 0.12 else {
            return sampledValues.map { value in
                min(0.16, max(0.02, value))
            }
        }

        let maximum = max(rawMaximum, 0.001)
        return sampledValues.map { value in
            let normalized = min(1, max(0, value / maximum))
            return pow(normalized, 0.72)
        }
    }

    private func preparePlayer() {
        initialTrimStart = clip.trimStart
        initialDuration = clip.duration
        selectionCenterMarkerTime = clip.audioPeakTime
        guard hasPlayableMedia else {
            startAutoAdvanceForCurrentClip()
            return
        }
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
        startAutoAdvanceForCurrentClip()
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
        stillAutoAdvanceTask?.cancel()
        stillAutoAdvanceTask = nil
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
            didAutoAdvanceCurrentClip = false
            startAutoAdvanceForCurrentClip()
            return
        }

        clip.livePhotoMode = .motion
        applyLivePhotoPlaybackWindow()
        playbackProgress = 0
        releasePlayer()
        didAutoAdvanceCurrentClip = false

        if let sourceURL {
            configurePlayer(with: sourceURL)
        } else {
            loadLivePhotoMotionIfNeeded()
        }
    }

    private func togglePlayback() {
        if !hasPlayableMedia {
            if isPlaying {
                pausePlayback()
            } else {
                startStillPreviewPlayback(
                    from: playbackProgress >= 0.999 ? 0 : playbackProgress,
                    shouldRestartTimer: true
                )
            }
            return
        }

        guard player.currentItem != nil else { return }
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

    private func handlePlaybackButtonTap() {
        togglePlayback()
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

    private var confirmOnDownwardDrag: some Gesture {
        DragGesture(minimumDistance: 28)
            .updating($dismissDragOffset) { value, state, _ in
                guard isConfirmDrag(value) else { return }
                state = min(value.translation.height * 0.45, 80)
            }
            .onEnded { value in
                guard isConfirmDrag(value),
                      value.predictedEndTranslation.height > 120
                else { return }
                confirmAndDismiss()
            }
    }

    private func isConfirmDrag(_ value: DragGesture.Value) -> Bool {
        value.translation.height > 0
            && abs(value.translation.height) > abs(value.translation.width) * 1.45
    }

    private func confirmAndDismiss() {
        pausePlayback()
        dismiss()
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
        stillAutoAdvanceTask?.cancel()
        stillAutoAdvanceTask = nil
        onPrevious()
    }

    private func navigateToNext() {
        guard canGoNext else { return }
        shouldAutoplayAfterNavigation = true
        pausePlayback()
        stillAutoAdvanceTask?.cancel()
        stillAutoAdvanceTask = nil
        onNext()
    }

    private func pausePlayback() {
        player.pause()
        isPlaying = false
        stillPlaybackStartDate = nil
        stillAutoAdvanceTask?.cancel()
        stillAutoAdvanceTask = nil
    }

    private func synchronizePlaybackProgress() {
        if !hasPlayableMedia {
            synchronizeStillPreviewProgress()
            return
        }

        let seconds = player.currentTime().seconds
        guard seconds.isFinite, clip.duration > 0 else { return }

        if seconds >= clip.trimEnd - 0.02 {
            if isPlaying {
                player.pause()
                isPlaying = false
            }
            playbackProgress = 1
            restartPlaybackAtSelectionStart = true
            advanceAfterCurrentClipIfNeeded()
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
        if !hasPlayableMedia {
            if isEditing {
                wasPlayingBeforeScrub = isPlaying
                pausePlayback()
            } else if wasPlayingBeforeScrub, playbackProgress < 0.999 {
                startStillPreviewPlayback(
                    from: playbackProgress,
                    shouldRestartTimer: true
                )
                wasPlayingBeforeScrub = false
            }
            return
        }

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

    private func toggleAutoAdvanceLoop() {
        autoAdvanceLoops.toggle()
        didAutoAdvanceCurrentClip = false

        if autoAdvanceLoops {
            autoAdvanceEnabled = true
            updateLoopIconAnimation(true)
            startAutoAdvanceForCurrentClip()
        } else {
            autoAdvanceEnabled = false
            updateLoopIconAnimation(false)
            stillAutoAdvanceTask?.cancel()
            stillAutoAdvanceTask = nil
        }
    }

    private var shouldAnimateLoopIcon: Bool {
        autoAdvanceLoops || isPlaybackLooping
    }

    private func togglePlaybackLoop() {
        autoAdvanceLoops.toggle()
        isPlaybackLooping = false
        didAutoAdvanceCurrentClip = false

        if autoAdvanceLoops {
            autoAdvanceEnabled = true
            updateLoopIconAnimation(true)
            startAutoAdvanceForCurrentClip()
        } else {
            autoAdvanceEnabled = false
            updateLoopIconAnimation(false)
            stillAutoAdvanceTask?.cancel()
            stillAutoAdvanceTask = nil
        }
    }

    private func updateLoopIconAnimation(_ isLooping: Bool) {
        _ = isLooping
    }

    private func startAutoAdvanceForCurrentClip() {
        stillAutoAdvanceTask?.cancel()
        stillAutoAdvanceTask = nil
        guard autoAdvanceEnabled else { return }

        if hasPlayableMedia {
            playFromSelectionStart()
            return
        }

        startStillPreviewPlayback(
            from: playbackProgress >= 0.999 ? 0 : playbackProgress,
            shouldRestartTimer: false
        )
    }

    private func startStillPreviewPlayback(
        from progress: Double,
        shouldRestartTimer: Bool
    ) {
        if shouldRestartTimer {
            stillAutoAdvanceTask?.cancel()
            stillAutoAdvanceTask = nil
        }

        autoAdvanceEnabled = true
        didAutoAdvanceCurrentClip = false
        playbackProgress = min(1, max(0, progress))
        stillPlaybackStartProgress = playbackProgress
        stillPlaybackStartDate = Date()
        isPlaying = true

        stillAutoAdvanceTask = Task {
            let waitTime = max(
                0.1,
                clip.duration * (1 - playbackProgress)
            )
            try? await Task.sleep(
                for: .milliseconds(Int((waitTime * 1000).rounded()))
            )
            await MainActor.run {
                guard autoAdvanceEnabled, !hasPlayableMedia else { return }
                advanceAfterCurrentClipIfNeeded()
            }
        }
    }

    private func synchronizeStillPreviewProgress() {
        guard isPlaying,
              let playbackStartDate = stillPlaybackStartDate,
              clip.duration > 0
        else { return }

        let elapsed = Date().timeIntervalSince(playbackStartDate)
        playbackProgress = min(
            1,
            stillPlaybackStartProgress + elapsed / clip.duration
        )

        if playbackProgress >= 0.999 {
            isPlaying = false
            stillPlaybackStartDate = nil
        }
    }

    private func advanceAfterCurrentClipIfNeeded() {
        guard autoAdvanceEnabled, !didAutoAdvanceCurrentClip else { return }
        didAutoAdvanceCurrentClip = true

        if canGoNext {
            navigateToNext()
        } else if autoAdvanceLoops {
            guard totalClipCount > 1 else {
                didAutoAdvanceCurrentClip = false
                shouldAutoplayAfterNavigation = false
                if hasPlayableMedia {
                    playFromSelectionStart()
                } else {
                    startAutoAdvanceForCurrentClip()
                }
                return
            }

            shouldAutoplayAfterNavigation = true
            pausePlayback()
            stillAutoAdvanceTask?.cancel()
            stillAutoAdvanceTask = nil
            onFirst()
        } else {
            autoAdvanceEnabled = false
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

private struct RotatingLoopIcon: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let angle = seconds.truncatingRemainder(dividingBy: 1.0) * 360

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: size, weight: .bold))
                .rotationEffect(.degrees(angle))
        }
    }
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
