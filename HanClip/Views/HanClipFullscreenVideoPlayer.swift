import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

enum HanClipPlayerAspectMode {
    case automatic
    case fit
    case fill
}

struct HanClipFullscreenPlayerConfiguration {
    var title: String?
    var shareURL: URL?
    var startTime: CMTime
    var autoplay: Bool
    var loop: Bool
    var showsLoopControl: Bool
    var aspectMode: HanClipPlayerAspectMode
    var allowsAspectModeToggle: Bool
    var showsMiniProgress: Bool

    init(
        title: String? = nil,
        shareURL: URL? = nil,
        startTime: CMTime = .zero,
        autoplay: Bool = true,
        loop: Bool = false,
        showsLoopControl: Bool = false,
        aspectMode: HanClipPlayerAspectMode = .fit,
        allowsAspectModeToggle: Bool = false,
        showsMiniProgress: Bool = false
    ) {
        self.title = title
        self.shareURL = shareURL
        self.startTime = startTime
        self.autoplay = autoplay
        self.loop = loop
        self.showsLoopControl = showsLoopControl
        self.aspectMode = aspectMode
        self.allowsAspectModeToggle = allowsAspectModeToggle
        self.showsMiniProgress = showsMiniProgress
    }
}

@MainActor
enum HanClipFullscreenVideoOrientationPolicy {
    static func prepareForPresentation() {
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }

        HanClipAppDelegate.supportedOrientationMask = .allButUpsideDown
        invalidateOrientationPreferences()
    }

    static func request(_ preferred: UIInterfaceOrientationMask) {
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }
        prepareForPresentation()
        guard let windowScene = activeWindowScene else { return }
        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: preferred)
        ) { error in
            #if DEBUG
            print("HanClip player orientation request failed: \(error)")
            #endif
        }
    }

    static func restorePortrait() {
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }

        HanClipAppDelegate.supportedOrientationMask = .portrait
        invalidateOrientationPreferences()
        guard let windowScene = activeWindowScene else { return }
        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: .portrait)
        ) { error in
            #if DEBUG
            print("HanClip portrait restore failed: \(error)")
            #endif
        }
    }

    private static func invalidateOrientationPreferences() {
        activeWindowScene?.windows.forEach { window in
            invalidateOrientationPreferences(from: window.rootViewController)
        }
    }

    private static func invalidateOrientationPreferences(
        from viewController: UIViewController?
    ) {
        guard let viewController else { return }
        viewController.setNeedsUpdateOfSupportedInterfaceOrientations()
        viewController.children.forEach {
            invalidateOrientationPreferences(from: $0)
        }
        invalidateOrientationPreferences(
            from: viewController.presentedViewController
        )
    }

    private static var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }

    static func requestCurrentDeviceOrientation() {
        let preferred: UIInterfaceOrientationMask
        switch UIDevice.current.orientation {
        case .portrait, .portraitUpsideDown:
            preferred = .portrait
        case .landscapeLeft:
            preferred = .landscapeRight
        case .landscapeRight:
            preferred = .landscapeLeft
        default:
            return
        }
        request(preferred)
    }
}

extension View {
    func hanClipFullscreenPlayerCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background {
            HanClipFullscreenPlayerPresenter(
                isPresented: isPresented,
                onDismiss: onDismiss,
                content: content
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
    }
}

private final class HanClipPlayerHostingController<Content: View>:
    UIHostingController<Content> {
    var onFirstAppearance: (() -> Void)?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad
            ? .all
            : .allButUpsideDown
    }

    override var shouldAutorotate: Bool {
        true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfSupportedInterfaceOrientations()
        onFirstAppearance?()
        onFirstAppearance = nil
    }
}

private struct HanClipFullscreenPlayerPresenter<Content: View>:
    UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear
        context.coordinator.presentationAnchor = viewController
        return viewController
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.onDismiss = onDismiss

        if isPresented {
            context.coordinator.presentIfNeeded(content: content)
        } else {
            context.coordinator.dismissIfNeeded()
        }
    }

    static func dismantleUIViewController(
        _ uiViewController: UIViewController,
        coordinator: Coordinator
    ) {
        coordinator.dismissImmediately()
    }

    @MainActor
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        weak var presentationAnchor: UIViewController?
        var isPresented: Binding<Bool>
        var onDismiss: () -> Void

        private weak var presentedController: UIViewController?
        private var isPresentationScheduled = false
        private var isDismissing = false

        init(
            isPresented: Binding<Bool>,
            onDismiss: @escaping () -> Void
        ) {
            self.isPresented = isPresented
            self.onDismiss = onDismiss
        }

        func presentIfNeeded(content: @escaping () -> Content) {
            guard presentedController == nil,
                  !isPresentationScheduled,
                  !isDismissing
            else { return }

            isPresentationScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isPresentationScheduled = false
                guard self.isPresented.wrappedValue,
                      self.presentedController == nil,
                      let anchor = self.presentationAnchor,
                      anchor.viewIfLoaded?.window != nil
                else { return }

                HanClipFullscreenVideoOrientationPolicy
                    .prepareForPresentation()
                let hostingController = HanClipPlayerHostingController(
                    rootView: content()
                )
                hostingController.onFirstAppearance = {
                    HanClipFullscreenVideoOrientationPolicy
                        .requestCurrentDeviceOrientation()
                }
                hostingController.modalPresentationStyle = .fullScreen
                hostingController.presentationController?.delegate = self
                self.presentedController = hostingController
                anchor.present(hostingController, animated: true)
            }
        }

        func dismissIfNeeded() {
            guard let presentedController, !isDismissing else { return }
            isDismissing = true
            presentedController.dismiss(animated: true) { [weak self] in
                self?.finishDismissal()
            }
        }

        func dismissImmediately() {
            isPresentationScheduled = false
            guard let presentedController else { return }
            presentedController.dismiss(animated: false)
            self.presentedController = nil
            HanClipFullscreenVideoOrientationPolicy.restorePortrait()
        }

        func presentationControllerDidDismiss(
            _ presentationController: UIPresentationController
        ) {
            finishDismissal()
        }

        private func finishDismissal() {
            guard presentedController != nil || isDismissing else { return }
            presentedController = nil
            isDismissing = false
            if isPresented.wrappedValue {
                isPresented.wrappedValue = false
            }
            HanClipFullscreenVideoOrientationPolicy.restorePortrait()
            onDismiss()
        }
    }
}

private enum HanClipPlayerDragMode {
    case horizontalScrub
    case downwardDismiss
    case volume
    case zoomPan
}

struct HanClipFullscreenVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL
    let configuration: HanClipFullscreenPlayerConfiguration
    let onClose: () -> Void

    @State private var player: AVPlayer
    @State private var isPlaying: Bool
    @State private var isLooping: Bool
    @State private var isAspectFill: Bool
    @State private var areControlsVisible = true
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var aspectDetectionTask: Task<Void, Never>?
    @State private var timeControlStatusObserver: NSKeyValueObservation?
    @State private var endObserver: NSObjectProtocol?
    @State private var orientationObserver: NSObjectProtocol?
    @State private var orientationRefreshTask: Task<Void, Never>?
    @State private var didRequestClose = false
    @State private var didManuallySelectAspectMode = false

    @State private var playerDragMode: HanClipPlayerDragMode?
    @State private var dragStartSeconds = 0.0
    @State private var dragPreviewSeconds: Double?
    @State private var dragPreviewVolume: Float?
    @State private var volumeDragPreviousTranslationY: CGFloat = 0
    @State private var downwardDragOffset: CGFloat = 0
    @State private var systemVolumeSlider: UISlider?

    @State private var zoomScale: CGFloat = 1
    @State private var previousMagnification: CGFloat = 1
    @State private var zoomOffset = CGSize.zero
    @State private var zoomDragStartOffset = CGSize.zero
    @State private var isMagnifying = false
    @State private var playerSurfaceIdentity = UUID()
    @State private var lastRequestedInterfaceOrientationMask:
        UIInterfaceOrientationMask?
    @GestureState private var isPlayerInteractionActive = false

    private let minimumZoomScale: CGFloat = 0.5
    private let maximumZoomScale: CGFloat = 4

    init(
        url: URL,
        configuration: HanClipFullscreenPlayerConfiguration = .init(),
        onClose: @escaping () -> Void = {}
    ) {
        self.url = url
        self.configuration = configuration
        self.onClose = onClose
        _player = State(initialValue: AVPlayer(url: url))
        _isPlaying = State(initialValue: configuration.autoplay)
        _isLooping = State(initialValue: configuration.loop)
        _isAspectFill = State(
            initialValue: configuration.aspectMode == .fill
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let safeAreaPadding = playerSafeAreaPadding(
                geometrySafeArea: proxy.safeAreaInsets
            )

            playerContent(
                viewportSize: proxy.size,
                safeAreaPadding: safeAreaPadding
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
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
        .onAppear(perform: startPlayer)
        .onDisappear(perform: stopPlayer)
    }

    private func playerContent(
        viewportSize: CGSize,
        safeAreaPadding: EdgeInsets
    ) -> some View {
        ZStack {
            Color.black

            HanClipSystemVolumeView { slider in
                systemVolumeSlider = slider
            }
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            HanClipPlayerSurface(
                player: player,
                videoGravity: videoGravity(for: viewportSize)
            )
            .id(playerSurfaceIdentity)
            .scaleEffect(zoomScale)
            .offset(zoomOffset)
            .contentShape(Rectangle())
            .simultaneousGesture(
                playerInteractionGesture(viewportSize: viewportSize)
            )
            .simultaneousGesture(playerTapGesture)
            .accessibilityLabel("한클립 동영상 플레이어")
            .accessibilityHint(
                "한 번 탭하면 재생하거나 일시정지합니다."
            )
            .accessibilityAction(.magicTap) {
                togglePlayback()
            }
            .accessibilityAction(named: Text("10초 앞으로")) {
                seekBy(seconds: 10)
            }
            .accessibilityAction(named: Text("10초 뒤로")) {
                seekBy(seconds: -10)
            }
            .accessibilityAction(named: Text("화면 크기 초기화")) {
                resetZoom(animated: true)
            }

            gesturePreview

            controls(
                viewportSize: viewportSize,
                safeAreaPadding: safeAreaPadding
            )

            if configuration.showsMiniProgress, !areControlsVisible {
                HanClipVideoMiniProgressLine(player: player)
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .clipped()
        .onChange(of: isPlayerInteractionActive) { wasActive, isActive in
            guard wasActive, !isActive else { return }
            cleanUpCancelledInteractionIfNeeded()
        }
    }

    @ViewBuilder
    private var gesturePreview: some View {
        if let dragPreviewSeconds {
            Text(playbackTime(dragPreviewSeconds))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if let dragPreviewVolume {
            HStack(spacing: 9) {
                Image(systemName: volumeSystemImage(for: dragPreviewVolume))
                Text("\(Int((dragPreviewVolume * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if abs(zoomScale - 1) > 0.01, isMagnifying {
            Text(String(format: "%.1f×", zoomScale))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func controls(
        viewportSize: CGSize,
        safeAreaPadding: EdgeInsets
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                circleButton(
                    systemImage: "xmark",
                    accessibilityLabel: closeAccessibilityLabel
                ) {
                    closePlayer()
                }

                if let title = configuration.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if let shareURL = configuration.shareURL {
                    ShareLink(item: shareURL) {
                        circleLabel(systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("동영상 공유")
                }
            }
            .padding(.leading, safeAreaPadding.leading)
            .padding(.trailing, safeAreaPadding.trailing)
            .padding(.top, safeAreaPadding.top)

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                HanClipVideoProgressBar(player: player)

                circleButton(
                    systemImage: isPlaying ? "pause.fill" : "play.fill",
                    accessibilityLabel: isPlaying ? "일시정지" : "재생"
                ) {
                    togglePlayback()
                }

                if configuration.showsLoopControl {
                    circleButton(
                        systemImage: "repeat",
                        accessibilityLabel:
                            isLooping ? "반복 재생 끄기" : "반복 재생 켜기",
                        isActive: isLooping
                    ) {
                        isLooping.toggle()
                        revealControls()
                    }
                    .accessibilityValue(isLooping ? "켬" : "끔")
                }

                if configuration.allowsAspectModeToggle,
                   viewportSize.width > viewportSize.height {
                    circleButton(
                        systemImage: isAspectFill
                            ? "rectangle.arrowtriangle.2.inward"
                            : "rectangle.arrowtriangle.2.outward",
                        accessibilityLabel:
                            isAspectFill ? "화면에 맞추기" : "화면 채우기"
                    ) {
                        didManuallySelectAspectMode = true
                        aspectDetectionTask?.cancel()
                        aspectDetectionTask = nil
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isAspectFill.toggle()
                        }
                        revealControls()
                    }
                    .accessibilityValue(
                        isAspectFill ? "화면 채우기" : "화면 맞추기"
                    )
                }
            }
            .padding(.leading, safeAreaPadding.leading)
            .padding(.trailing, safeAreaPadding.trailing)
            .padding(.bottom, safeAreaPadding.bottom)
        }
        .opacity(areControlsVisible ? 1 : 0)
        .allowsHitTesting(areControlsVisible)
        .animation(.easeInOut(duration: 0.20), value: areControlsVisible)
    }

    private var closeAccessibilityLabel: String {
        guard let title = configuration.title, !title.isEmpty
        else { return "동영상 닫기" }
        return "\(title) 닫기"
    }

    private func circleButton(
        systemImage: String,
        accessibilityLabel: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            circleLabel(systemImage: systemImage, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func circleLabel(
        systemImage: String,
        isActive: Bool = false
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(isActive ? .white : .white.opacity(0.94))
            .frame(width: 44, height: 44)
            .background(
                isActive ? Color.white.opacity(0.18) : Color.clear,
                in: Circle()
            )
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle().stroke(
                    Color.white.opacity(isActive ? 0.48 : 0.28),
                    lineWidth: 1
                )
            }
    }

    private func startPlayer() {
        HanClipAudioSession.activatePlayback()
        installOrientationObserver()
        installPlaybackObservers()
        configureInitialAspectMode()

        player.seek(
            to: normalizedStartTime,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        if configuration.autoplay {
            player.play()
            isPlaying = true
        } else {
            isPlaying = false
        }
        revealControls()
    }

    private func stopPlayer() {
        controlsHideTask?.cancel()
        aspectDetectionTask?.cancel()
        aspectDetectionTask = nil
        removePlaybackObservers()
        player.pause()
        removeOrientationObserver()
        resetInteractionState()
    }

    private var normalizedStartTime: CMTime {
        let seconds = configuration.startTime.seconds
        guard seconds.isFinite, seconds >= 0 else { return .zero }
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func closePlayer() {
        guard !didRequestClose else { return }
        didRequestClose = true
        player.pause()
        onClose()
        dismiss()
    }

    private func togglePlayback() {
        if player.timeControlStatus == .playing {
            controlsHideTask?.cancel()
            player.pause()
            isPlaying = false
            withAnimation(.easeInOut(duration: 0.20)) {
                areControlsVisible = true
            }
            return
        }

        if let duration = player.currentItem?.duration,
           duration.isNumeric,
           player.currentTime() >= duration {
            player.seek(to: .zero)
        }
        HanClipAudioSession.activatePlayback()
        player.play()
        isPlaying = true
        revealControls()
    }

    private func seekBy(seconds: Double) {
        let current = player.currentTime().seconds
        guard current.isFinite else { return }
        let duration = player.currentItem?.duration.seconds
        let upperBound = duration?.isFinite == true ? max(duration ?? 0, 0) : nil
        var target = max(current + seconds, 0)
        if let upperBound {
            target = min(target, upperBound)
        }
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        revealControls()
    }

    private func revealControls() {
        controlsHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.20)) {
            areControlsVisible = true
        }
        scheduleControlsHideIfPlaying()
    }

    private func scheduleControlsHideIfPlaying() {
        controlsHideTask?.cancel()
        guard player.timeControlStatus == .playing else {
            controlsHideTask = nil
            return
        }
        controlsHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled,
                  player.timeControlStatus == .playing,
                  playerDragMode == nil,
                  !isMagnifying
            else { return }
            withAnimation(.easeInOut(duration: 0.20)) {
                areControlsVisible = false
            }
        }
    }

    private func installPlaybackObservers() {
        guard timeControlStatusObserver == nil, endObserver == nil
        else { return }
        timeControlStatusObserver = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { observedPlayer, _ in
            Task { @MainActor in
                updatePlaybackStatus(observedPlayer.timeControlStatus)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if isLooping {
                    player.seek(to: .zero)
                    player.play()
                    isPlaying = true
                } else {
                    controlsHideTask?.cancel()
                    isPlaying = false
                    withAnimation(.easeInOut(duration: 0.20)) {
                        areControlsVisible = true
                    }
                }
            }
        }
    }

    private func removePlaybackObservers() {
        timeControlStatusObserver?.invalidate()
        timeControlStatusObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func updatePlaybackStatus(
        _ status: AVPlayer.TimeControlStatus
    ) {
        let wasPlaying = isPlaying
        isPlaying = status == .playing

        switch status {
        case .playing:
            if !wasPlaying, areControlsVisible {
                scheduleControlsHideIfPlaying()
            }
        case .waitingToPlayAtSpecifiedRate:
            controlsHideTask?.cancel()
            controlsHideTask = nil
            if !areControlsVisible {
                withAnimation(.easeInOut(duration: 0.20)) {
                    areControlsVisible = true
                }
            }
        case .paused:
            controlsHideTask?.cancel()
            controlsHideTask = nil
        @unknown default:
            controlsHideTask?.cancel()
            controlsHideTask = nil
        }
    }

    private func configureInitialAspectMode() {
        aspectDetectionTask?.cancel()
        aspectDetectionTask = nil
        didManuallySelectAspectMode = false
        switch configuration.aspectMode {
        case .fit:
            isAspectFill = false
        case .fill:
            isAspectFill = true
        case .automatic:
            aspectDetectionTask = Task {
                let asset = AVURLAsset(url: url)
                guard let track = try? await asset.loadTracks(
                    withMediaType: .video
                ).first,
                      let naturalSize = try? await track.load(.naturalSize),
                      let preferredTransform = try? await track.load(
                        .preferredTransform
                      ),
                      !Task.isCancelled
                else { return }

                let orientedRect = CGRect(
                    origin: .zero,
                    size: naturalSize
                ).applying(preferredTransform)
                await MainActor.run {
                    guard !Task.isCancelled,
                          !didManuallySelectAspectMode
                    else { return }
                    isAspectFill =
                        abs(orientedRect.width) > abs(orientedRect.height)
                    aspectDetectionTask = nil
                }
            }
        }
    }

    private func videoGravity(for viewportSize: CGSize) -> AVLayerVideoGravity {
        guard viewportSize.width > viewportSize.height, isAspectFill
        else { return .resizeAspect }
        return .resizeAspectFill
    }

    private func playerInteractionGesture(
        viewportSize: CGSize
    ) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.001)
            .simultaneously(
                with: DragGesture(
                    minimumDistance: 12,
                    coordinateSpace: .global
                )
            )
            .updating($isPlayerInteractionActive) { _, isActive, _ in
                isActive = true
            }
            .onChanged { value in
                if let magnification = value.first {
                    updateMagnification(
                        magnification,
                        viewportSize: viewportSize
                    )
                } else if let drag = value.second, !isMagnifying {
                    updatePlayerDrag(drag, viewportSize: viewportSize)
                }
            }
            .onEnded { value in
                if let magnification = value.first {
                    finishMagnification(
                        magnification,
                        viewportSize: viewportSize
                    )
                } else if let drag = value.second {
                    finishPlayerDrag(drag, viewportSize: viewportSize)
                }
            }
    }

    private var playerTapGesture: some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { value in
                switch value {
                case .first:
                    guard abs(zoomScale - 1) > 0.01
                            || zoomOffset != .zero
                    else { return }
                    resetZoom(animated: true)
                    revealControls()
                case .second:
                    togglePlayback()
                }
            }
    }

    private func updateMagnification(
        _ value: MagnifyGesture.Value,
        viewportSize: CGSize
    ) {
        if !isMagnifying {
            isMagnifying = true
            previousMagnification = 1
            controlsHideTask?.cancel()
            cancelActiveDrag()
        }

        let magnification = max(
            value.magnification,
            CGFloat.leastNonzeroMagnitude
        )
        let previous = max(
            previousMagnification,
            CGFloat.leastNonzeroMagnitude
        )
        let delta = magnification / previous
        previousMagnification = magnification
        zoomScale = min(
            max(zoomScale * delta, minimumZoomScale),
            maximumZoomScale
        )
        zoomOffset = clampedZoomOffset(
            zoomOffset,
            scale: zoomScale,
            viewportSize: viewportSize
        )
        if zoomScale <= 1 {
            zoomOffset = .zero
            zoomDragStartOffset = .zero
        }
    }

    private func finishMagnification(
        _ value: MagnifyGesture.Value,
        viewportSize: CGSize
    ) {
        if !isMagnifying
            || abs(value.magnification - previousMagnification) > 0.0001 {
            updateMagnification(value, viewportSize: viewportSize)
        }
        previousMagnification = 1
        isMagnifying = false

        if abs(zoomScale - 1) < 0.015 {
            resetZoom(animated: true)
        } else {
            zoomOffset = clampedZoomOffset(
                zoomOffset,
                scale: zoomScale,
                viewportSize: viewportSize
            )
            zoomDragStartOffset = zoomOffset
        }
        revealControls()
    }

    private func updatePlayerDrag(
        _ value: DragGesture.Value,
        viewportSize: CGSize
    ) {
        let translation = value.translation
        if playerDragMode == nil {
            controlsHideTask?.cancel()
            if zoomScale > 1.01 {
                playerDragMode = .zoomPan
                zoomDragStartOffset = zoomOffset
            } else {
                let horizontalDistance = abs(translation.width)
                let verticalDistance = abs(translation.height)
                if horizontalDistance >= verticalDistance {
                    playerDragMode = .horizontalScrub
                    dragStartSeconds = player.currentTime().seconds.isFinite
                        ? max(player.currentTime().seconds, 0)
                        : 0
                } else if translation.height < 0 {
                    playerDragMode = .volume
                    dragPreviewVolume = AVAudioSession.sharedInstance()
                        .outputVolume
                    volumeDragPreviousTranslationY = 0
                } else {
                    playerDragMode = .downwardDismiss
                }
            }
        }

        switch playerDragMode {
        case .horizontalScrub:
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

        case .downwardDismiss:
            downwardDragOffset = max(translation.height, 0)

        case .volume:
            let adjustmentHeight = max(viewportSize.height * 0.72, 160)
            let translationDelta = translation.height
                - volumeDragPreviousTranslationY
            volumeDragPreviousTranslationY = translation.height
            let currentVolume = dragPreviewVolume
                ?? AVAudioSession.sharedInstance().outputVolume
            let targetVolume = min(
                max(
                    currentVolume
                        - Float(translationDelta / adjustmentHeight),
                    0
                ),
                1
            )
            dragPreviewVolume = targetVolume
            setSystemVolume(targetVolume)

        case .zoomPan:
            let proposedOffset = CGSize(
                width: zoomDragStartOffset.width + translation.width,
                height: zoomDragStartOffset.height + translation.height
            )
            zoomOffset = clampedZoomOffset(
                proposedOffset,
                scale: zoomScale,
                viewportSize: viewportSize
            )

        case nil:
            break
        }
    }

    private func finishPlayerDrag(
        _ value: DragGesture.Value,
        viewportSize: CGSize
    ) {
        let completedMode = playerDragMode
        let shouldDismiss = completedMode == .downwardDismiss
            && value.translation.height
                > max(55, viewportSize.height * 0.08)

        if completedMode == .zoomPan {
            zoomDragStartOffset = zoomOffset
        }
        cancelActiveDrag()

        if shouldDismiss {
            closePlayer()
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                downwardDragOffset = 0
            }
            revealControls()
        }
    }

    private func cancelActiveDrag() {
        playerDragMode = nil
        dragPreviewSeconds = nil
        dragPreviewVolume = nil
        volumeDragPreviousTranslationY = 0
        downwardDragOffset = 0
    }

    private func cleanUpCancelledInteractionIfNeeded() {
        guard isMagnifying || playerDragMode != nil else { return }
        previousMagnification = 1
        isMagnifying = false
        if playerDragMode == .zoomPan {
            zoomDragStartOffset = zoomOffset
        }
        cancelActiveDrag()
        revealControls()
    }

    private func clampedZoomOffset(
        _ offset: CGSize,
        scale: CGFloat,
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

    private func resetZoom(animated: Bool) {
        let changes = {
            zoomScale = 1
            previousMagnification = 1
            zoomOffset = .zero
            zoomDragStartOffset = .zero
            isMagnifying = false
        }
        if animated {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                changes()
            }
        } else {
            changes()
        }
    }

    private func resetInteractionState() {
        cancelActiveDrag()
        resetZoom(animated: false)
    }

    private func setSystemVolume(_ volume: Float) {
        guard let systemVolumeSlider else { return }
        systemVolumeSlider.setValue(volume, animated: false)
        systemVolumeSlider.sendActions(for: .valueChanged)
    }

    private func volumeSystemImage(for volume: Float) -> String {
        if volume <= 0.001 {
            return "speaker.slash.fill"
        }
        if volume < 0.34 {
            return "speaker.wave.1.fill"
        }
        if volume < 0.67 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    private func dismissDragOpacity(for height: CGFloat) -> Double {
        guard height > 0 else { return 1 }
        return max(0.55, 1 - Double(downwardDragOffset / height) * 0.9)
    }

    private func playbackTime(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        return String(
            format: "%d:%02d",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }

    private func playerSafeAreaPadding(
        geometrySafeArea: EdgeInsets
    ) -> EdgeInsets {
        let windowInsets = activeWindowScene?
            .windows
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
        return EdgeInsets(
            top: max(18, max(geometrySafeArea.top, windowInsets.top) + 8),
            leading: max(
                18,
                max(geometrySafeArea.leading, windowInsets.left) + 8
            ),
            bottom: max(
                24,
                max(geometrySafeArea.bottom, windowInsets.bottom) + 8
            ),
            trailing: max(
                18,
                max(geometrySafeArea.trailing, windowInsets.right) + 8
            )
        )
    }

    private func installOrientationObserver() {
        guard orientationObserver == nil else { return }
        HanClipFullscreenVideoOrientationPolicy.prepareForPresentation()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                updateDeviceOrientation(UIDevice.current.orientation)
            }
        }
        updateDeviceOrientation(UIDevice.current.orientation)
        orientationRefreshTask?.cancel()
        orientationRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            updateDeviceOrientation(UIDevice.current.orientation)
        }
    }

    private func removeOrientationObserver() {
        orientationRefreshTask?.cancel()
        orientationRefreshTask = nil
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
            self.orientationObserver = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func updateDeviceOrientation(_ orientation: UIDeviceOrientation) {
        let preferredOrientation: UIInterfaceOrientationMask
        switch orientation {
        case .portrait, .portraitUpsideDown:
            preferredOrientation = .portrait
        case .landscapeLeft:
            preferredOrientation = .landscapeRight
        case .landscapeRight:
            preferredOrientation = .landscapeLeft
        default:
            return
        }
        if lastRequestedInterfaceOrientationMask != preferredOrientation {
            lastRequestedInterfaceOrientationMask = preferredOrientation
            resetInteractionState()
            playerSurfaceIdentity = UUID()
        }
        HanClipFullscreenVideoOrientationPolicy.request(preferredOrientation)
    }

    private var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }

}

private struct HanClipSystemVolumeView: UIViewRepresentable {
    let onSliderReady: (UISlider) -> Void

    final class Coordinator {
        weak var slider: UISlider?

        func resolveSlider(
            in volumeView: MPVolumeView,
            onSliderReady: @escaping (UISlider) -> Void,
            retriesRemaining: Int = 3
        ) {
            guard slider == nil else { return }
            volumeView.layoutIfNeeded()
            if let resolvedSlider = volumeView.subviews
                .compactMap({ $0 as? UISlider })
                .first {
                slider = resolvedSlider
                DispatchQueue.main.async {
                    onSliderReady(resolvedSlider)
                }
                return
            }

            guard retriesRemaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                [weak self, weak volumeView] in
                guard let self, let volumeView else { return }
                self.resolveSlider(
                    in: volumeView,
                    onSliderReady: onSliderReady,
                    retriesRemaining: retriesRemaining - 1
                )
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        context.coordinator.resolveSlider(
            in: volumeView,
            onSliderReady: onSliderReady
        )
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        context.coordinator.resolveSlider(
            in: uiView,
            onSliderReady: onSliderReady
        )
    }
}

private struct HanClipPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> HanClipPlayerSurfaceView {
        let view = HanClipPlayerSurfaceView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(
        _ uiView: HanClipPlayerSurfaceView,
        context: Context
    ) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = videoGravity
    }
}

private final class HanClipPlayerSurfaceView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.backgroundColor = UIColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        playerLayer.backgroundColor = UIColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
    }
}

private struct HanClipVideoProgressBar: View {
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
            .accessibilityLabel("재생 위치")
            .accessibilityValue(
                "\(formattedTime(currentSeconds)) / "
                    + formattedTime(durationSeconds)
            )

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

private struct HanClipVideoMiniProgressLine: View {
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
