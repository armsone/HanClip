import AVFoundation
import Combine
import SwiftUI
import UIKit

private enum AutoCaptureSensitivity: String, CaseIterable, Identifiable {
    case noisy
    case normal
    case quiet
    case automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noisy:
            "시끄러움"
        case .normal:
            "일반"
        case .quiet:
            "조용함"
        case .automatic:
            "자동"
        }
    }

    var iconName: String {
        switch self {
        case .noisy:
            "speaker.wave.3.fill"
        case .normal:
            "speaker.wave.2.fill"
        case .quiet:
            "speaker.wave.1.fill"
        case .automatic:
            "wand.and.stars"
        }
    }

}

enum AutoCapturePhase {
    case detecting
    case detected
    case saving

    var title: String {
        switch self {
        case .detecting:
            "감지 중"
        case .detected:
            "감지 됨"
        case .saving:
            "저장 중"
        }
    }
}

struct AutoCaptureCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = AutoCaptureCameraController()
    @AppStorage("hanClipAutoCaptureSensitivity")
    private var sensitivityRaw = AutoCaptureSensitivity.automatic.rawValue

    let onComplete: (URL, Double) -> Void

    var body: some View {
        ZStack {
            AutoCapturePreviewView(session: camera.session)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                cameraControls
                    .padding(.top, 10)
                Spacer()
                manualCaptureButton
                    .padding(.bottom, 18)
                statusPanel
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .background(Color.black)
        .task {
            camera.setSensitivity(selectedSensitivity)
            await camera.start()
        }
        .onChange(of: sensitivityRaw) { _, _ in
            camera.setSensitivity(selectedSensitivity)
        }
        .onDisappear {
            camera.cancel()
        }
        .onChange(of: camera.completedCapture) { _, capture in
            guard let capture else { return }
            onComplete(capture.url, capture.triggerTime)
            camera.markCompletedCaptureHandled(capture)
        }
    }

    private var header: some View {
        HStack {
            Label("자동촬영", systemImage: "figure.golf")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.42), in: Capsule())

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.42), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("자동촬영 닫기")
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 13) {
            if !camera.statusText.isEmpty {
                HStack(spacing: 10) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)

                    Text(camera.statusText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()
                }
            }

            HStack(spacing: 12) {
                soundMeter

                Text(statusBadgeText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.18), in: Capsule())
            }

            VStack(spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("소리 감도")
                    Spacer()
                    Text(selectedSensitivity.title)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)

                HStack(spacing: 5) {
                    ForEach(AutoCaptureSensitivity.allCases) { sensitivity in
                        sensitivityButton(sensitivity)
                    }
                }

            }
            .padding(10)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .accessibilityHint("주변 소음에 맞는 타구음 감도를 선택합니다")
        }
        .padding(16)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 18))
    }

    private var cameraControls: some View {
        HStack(spacing: 11) {
            Button {
                camera.switchCamera()
            } label: {
                Label(
                    camera.cameraPosition == .front ? "전면" : "후면",
                    systemImage: "arrow.triangle.2.circlepath.camera"
                )
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(minWidth: 67)
            }
            .buttonStyle(.plain)
            .accessibilityHint("전면과 후면 카메라를 전환합니다")

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1, height: 24)

            Image(systemName: "minus.magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            Slider(
                value: Binding(
                    get: { Double(camera.zoomFactor) },
                    set: { camera.setZoom($0) }
                ),
                in: Double(camera.minimumZoomFactor)...Double(
                    camera.maximumZoomFactor
                )
            )
            .tint(.white)
            .disabled(camera.maximumZoomFactor <= camera.minimumZoomFactor)

            Text(String(format: "%.1fx", Double(camera.zoomFactor)))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 39, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 13)
        .frame(height: 48)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .disabled(camera.isTriggered || camera.isSwitchingCamera)
        .opacity(camera.isTriggered ? 0.55 : 1)
    }

    private func sensitivityButton(
        _ sensitivity: AutoCaptureSensitivity
    ) -> some View {
        let isSelected = sensitivity == selectedSensitivity

        return Button {
            sensitivityRaw = sensitivity.rawValue
        } label: {
            VStack(spacing: 5) {
                Image(systemName: sensitivity.iconName)
                    .font(.system(size: 15, weight: .semibold))
                Text(sensitivity.title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                isSelected ? Color.white : Color.white.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(sensitivity.title) 환경 감도")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var statusColor: Color {
        switch camera.capturePhase {
        case .detecting:
            return camera.isReadyForTrigger ? .green : .yellow
        case .detected:
            return .red
        case .saving:
            return .orange
        }
    }

    private var statusBadgeText: String {
        camera.capturePhase.title
    }

    private var selectedSensitivity: AutoCaptureSensitivity {
        AutoCaptureSensitivity(rawValue: sensitivityRaw) ?? .automatic
    }

    private var manualCaptureButton: some View {
        Button {
            camera.triggerManualCapture()
        } label: {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.28))
                    .frame(width: 86, height: 86)

                Circle()
                    .stroke(
                        camera.isTriggered
                            ? Color.red.opacity(0.28)
                            : Color.white,
                        lineWidth: 4
                    )
                    .frame(width: 74, height: 74)

                if camera.isTriggered {
                    Circle()
                        .trim(from: 0, to: camera.saveProgress)
                        .stroke(
                            Color.red,
                            style: StrokeStyle(
                                lineWidth: 5,
                                lineCap: .round
                            )
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 74, height: 74)

                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(y: -37)
                        .rotationEffect(
                            .degrees(360 * camera.saveProgress)
                        )
                }

                Circle()
                    .fill(
                        camera.isReadyForTrigger && !camera.isTriggered
                            ? Color.white
                            : Color.white.opacity(0.42)
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: "video.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.78))
            }
            .contentShape(Circle())
        }
        .buttonStyle(ManualCaptureButtonStyle())
        .disabled(!camera.isReadyForTrigger || camera.isTriggered)
        .accessibilityLabel("수동 촬영")
        .accessibilityHint("현재 순간을 직접 촬영해 클립으로 저장합니다")
        .accessibilityValue(statusBadgeText)
    }

    private var soundMeter: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                Capsule()
                    .fill(camera.isTriggered ? Color.green : Color.white)
                    .frame(width: proxy.size.width * camera.soundLevel)
            }
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }
}

private struct ManualCaptureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct AutoCapturePreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

private final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct AutoCaptureResult: Equatable {
    let url: URL
    let triggerTime: Double
}

final class AutoCaptureCameraController: NSObject, ObservableObject,
    @unchecked Sendable
{
    private static let clipSideDuration: CFTimeInterval = 5

    private struct SoundMetrics {
        let rms: Double
        let peak: Double
        let crossingRate: Double

        var impactScore: Double {
            let highFrequencyWeight = min(1, crossingRate * 10)
            return min(
                1,
                rms * 0.55
                    + peak * 0.45
                    + highFrequencyWeight * rms * 0.35
            )
        }
    }

    private struct ImpactThresholds {
        let strongScoreFloor: Double
        let strongBaselineMultiplier: Double
        let strongPeakFloor: Double
        let strongPeakBaselineMultiplier: Double
        let strongRise: Double
        let strongCrossingRate: Double
        let strongCrestFactor: Double
        let distantScoreFloor: Double
        let distantBaselineMultiplier: Double
        let distantPeakFloor: Double
        let distantPeakBaselineMultiplier: Double
        let distantRise: Double
        let distantCrossingRate: Double
        let distantCrestFactor: Double
    }

    let session = AVCaptureSession()

    @Published private(set) var statusText = "카메라 준비 중..."
    @Published private(set) var soundLevel = 0.0
    @Published private(set) var isReadyForTrigger = false
    @Published private(set) var isTriggered = false
    @Published private(set) var capturePhase = AutoCapturePhase.detecting
    @Published private(set) var saveProgress = 0.0
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var minimumZoomFactor: CGFloat = 1
    @Published private(set) var maximumZoomFactor: CGFloat = 5
    @Published private(set) var isSwitchingCamera = false
    @Published var completedCapture: AutoCaptureResult?

    private let sessionQueue = DispatchQueue(
        label: "hanclip.autoCapture.session"
    )
    private let audioQueue = DispatchQueue(label: "hanclip.autoCapture.audio")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var activeCameraPosition: AVCaptureDevice.Position = .back
    private var pendingCameraPosition: AVCaptureDevice.Position?
    private var outputURL: URL?
    private var recordingStartTime: CFTimeInterval?
    private var triggerTime: Double?
    private var baseline = 0.008
    private var recentLevel = 0.008
    private var didRequestStop = false
    private var didAnnounceReady = false
    private var isActive = false
    private var sensitivity = AutoCaptureSensitivity.automatic

    func start() async {
        let allowed = await requestPermissions()
        guard allowed else {
            updateStatus("카메라와 마이크 권한이 필요합니다.")
            return
        }

        sessionQueue.async { [weak self] in
            self?.configureAndStart()
        }
    }

    func cancel() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.isActive = false
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func markCompletedCaptureHandled(_ capture: AutoCaptureResult) {
        DispatchQueue.main.async {
            guard self.completedCapture == capture else { return }
            self.completedCapture = nil
        }
    }

    fileprivate func setSensitivity(_ sensitivity: AutoCaptureSensitivity) {
        audioQueue.async { [weak self] in
            self?.sensitivity = sensitivity
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, self.isActive, self.pendingCameraPosition == nil,
                  self.triggerTime == nil
            else { return }

            self.pendingCameraPosition = self.activeCameraPosition == .back
                ? .front
                : .back
            DispatchQueue.main.async {
                self.isSwitchingCamera = true
                self.isReadyForTrigger = false
                self.statusText = "카메라를 바꾸고 있습니다."
            }

            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            } else {
                self.finishCameraSwitchAndRestart()
            }
        }
    }

    func setZoom(_ factor: Double) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            let minimum = max(1, device.minAvailableVideoZoomFactor)
            let maximum = min(5, device.maxAvailableVideoZoomFactor)
            let zoom = min(maximum, max(minimum, CGFloat(factor)))

            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = zoom
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.zoomFactor = zoom
                }
            } catch {
                self.updateStatus("줌을 조절할 수 없습니다.")
            }
        }
    }

    func triggerManualCapture() {
        audioQueue.async { [weak self] in
            guard let self,
                  let recordingStartTime = self.recordingStartTime,
                  self.triggerTime == nil
            else { return }

            let elapsed = CACurrentMediaTime() - recordingStartTime
            guard elapsed >= Self.clipSideDuration else { return }

            self.triggerTime = elapsed
            self.requestStopAfterTrigger()
        }
    }

    private func requestPermissions() async -> Bool {
        async let camera = requestAccess(for: .video)
        async let microphone = requestAccess(for: .audio)
        let cameraAllowed = await camera
        let microphoneAllowed = await microphone
        return cameraAllowed && microphoneAllowed
    }

    private func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        default:
            return false
        }
    }

    private func configureAndStart() {
        do {
            session.beginConfiguration()
            session.sessionPreset = .high

            guard let videoDevice = cameraDevice(position: .back) else {
                throw CameraConfigurationError.cameraUnavailable
            }
            let input = try AVCaptureDeviceInput(device: videoDevice)
            guard session.canAddInput(input) else {
                throw CameraConfigurationError.cannotAddInput
            }
            session.addInput(input)
            videoInput = input
            activeCameraPosition = .back

            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let input = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
            }

            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }

            audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
            }

            session.commitConfiguration()
            publishCameraState(for: videoDevice)
            isActive = true
            session.startRunning()
            startRecording()
        } catch {
            session.commitConfiguration()
            updateStatus("자동촬영을 시작할 수 없습니다.")
        }
    }

    private enum CameraConfigurationError: Error {
        case cameraUnavailable
        case cannotAddInput
    }

    private func cameraDevice(
        position: AVCaptureDevice.Position
    ) -> AVCaptureDevice? {
        AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: position
        )
    }

    private func finishCameraSwitchAndRestart() {
        guard let position = pendingCameraPosition else { return }
        defer {
            pendingCameraPosition = nil
            DispatchQueue.main.async {
                self.isSwitchingCamera = false
            }
        }

        guard let device = cameraDevice(position: position) else {
            updateStatus("선택한 카메라를 사용할 수 없습니다.")
            startRecording()
            return
        }

        let previousInput = videoInput
        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if let previousInput {
                session.removeInput(previousInput)
            }

            guard session.canAddInput(newInput) else {
                if let previousInput, session.canAddInput(previousInput) {
                    session.addInput(previousInput)
                }
                session.commitConfiguration()
                throw CameraConfigurationError.cannotAddInput
            }

            session.addInput(newInput)
            session.commitConfiguration()
            videoInput = newInput
            activeCameraPosition = position
            publishCameraState(for: device)
        } catch {
            updateStatus("카메라를 전환할 수 없습니다.")
        }

        startRecording()
    }

    private func publishCameraState(for device: AVCaptureDevice) {
        let minimum = max(1, device.minAvailableVideoZoomFactor)
        let maximum = max(
            minimum,
            min(5, device.maxAvailableVideoZoomFactor)
        )
        let zoom = min(maximum, max(minimum, device.videoZoomFactor))

        DispatchQueue.main.async {
            self.cameraPosition = device.position
            self.minimumZoomFactor = minimum
            self.maximumZoomFactor = maximum
            self.zoomFactor = zoom
        }
    }

    private func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        outputURL = url
        recordingStartTime = CACurrentMediaTime()
        triggerTime = nil
        didRequestStop = false
        didAnnounceReady = false
        baseline = 0.008
        recentLevel = 0.008

        updateStatus("잠시만 기다려 주세요. 곧 촬영할 수 있습니다.")
        DispatchQueue.main.async {
            self.isReadyForTrigger = false
            self.isTriggered = false
            self.capturePhase = .detecting
            self.saveProgress = 0
        }
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    private func handleAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard let recordingStartTime, triggerTime == nil else { return }
        let elapsed = CACurrentMediaTime() - recordingStartTime
        let metrics = soundMetrics(from: sampleBuffer)
        let score = metrics.impactScore
        let previousRecentLevel = recentLevel

        let baselineSample = min(score, max(0.004, baseline * 1.35))
        let baselineWeight = elapsed < Self.clipSideDuration ? 0.04 : 0.012
        baseline = baseline * (1 - baselineWeight)
            + max(0.002, baselineSample) * baselineWeight
        recentLevel = recentLevel * 0.72 + max(0.002, score) * 0.28
        updateLevel(score)

        DispatchQueue.main.async { [weak self] in
            self?.isReadyForTrigger = elapsed >= Self.clipSideDuration
        }

        guard elapsed >= Self.clipSideDuration else { return }
        if !didAnnounceReady {
            didAnnounceReady = true
            updateStatus("")
        }
        let referenceLevel = max(
            0.003,
            max(baseline, previousRecentLevel * 0.82)
        )
        let suddenRise = score / referenceLevel
        let crestFactor = metrics.peak / max(0.001, metrics.rms)
        let thresholds = impactThresholds()
        let isStrongImpact = score >= max(
            thresholds.strongScoreFloor,
            baseline * thresholds.strongBaselineMultiplier
        )
            && metrics.peak >= max(
                thresholds.strongPeakFloor,
                baseline * thresholds.strongPeakBaselineMultiplier
            )
            && suddenRise >= thresholds.strongRise
            && metrics.crossingRate >= thresholds.strongCrossingRate
            && crestFactor >= thresholds.strongCrestFactor
        let isDistantSharpImpact = score >= max(
            thresholds.distantScoreFloor,
            baseline * thresholds.distantBaselineMultiplier
        )
            && metrics.peak >= max(
                thresholds.distantPeakFloor,
                baseline * thresholds.distantPeakBaselineMultiplier
            )
            && suddenRise >= thresholds.distantRise
            && metrics.crossingRate >= thresholds.distantCrossingRate
            && crestFactor >= thresholds.distantCrestFactor

        guard isStrongImpact || isDistantSharpImpact else { return }

        triggerTime = elapsed
        requestStopAfterTrigger()
    }

    private func impactThresholds() -> ImpactThresholds {
        let effectiveSensitivity: AutoCaptureSensitivity
        if sensitivity == .automatic {
            if baseline >= 0.026 {
                effectiveSensitivity = .noisy
            } else if baseline <= 0.009 {
                effectiveSensitivity = .quiet
            } else {
                effectiveSensitivity = .normal
            }
        } else {
            effectiveSensitivity = sensitivity
        }

        switch effectiveSensitivity {
        case .noisy:
            return ImpactThresholds(
                strongScoreFloor: 0.10,
                strongBaselineMultiplier: 2.7,
                strongPeakFloor: 0.18,
                strongPeakBaselineMultiplier: 4.2,
                strongRise: 2.2,
                strongCrossingRate: 0.07,
                strongCrestFactor: 2.3,
                distantScoreFloor: 0.065,
                distantBaselineMultiplier: 3.4,
                distantPeakFloor: 0.12,
                distantPeakBaselineMultiplier: 5.0,
                distantRise: 3.0,
                distantCrossingRate: 0.10,
                distantCrestFactor: 3.5
            )
        case .normal, .automatic:
            return ImpactThresholds(
                strongScoreFloor: 0.075,
                strongBaselineMultiplier: 2.3,
                strongPeakFloor: 0.13,
                strongPeakBaselineMultiplier: 3.5,
                strongRise: 1.8,
                strongCrossingRate: 0.05,
                strongCrestFactor: 2.0,
                distantScoreFloor: 0.045,
                distantBaselineMultiplier: 2.8,
                distantPeakFloor: 0.09,
                distantPeakBaselineMultiplier: 4.2,
                distantRise: 2.4,
                distantCrossingRate: 0.08,
                distantCrestFactor: 3.0
            )
        case .quiet:
            return ImpactThresholds(
                strongScoreFloor: 0.055,
                strongBaselineMultiplier: 1.9,
                strongPeakFloor: 0.095,
                strongPeakBaselineMultiplier: 3.0,
                strongRise: 1.55,
                strongCrossingRate: 0.04,
                strongCrestFactor: 1.7,
                distantScoreFloor: 0.035,
                distantBaselineMultiplier: 2.3,
                distantPeakFloor: 0.07,
                distantPeakBaselineMultiplier: 3.4,
                distantRise: 2.0,
                distantCrossingRate: 0.065,
                distantCrestFactor: 2.5
            )
        }
    }

    private func soundMetrics(
        from sampleBuffer: CMSampleBuffer
    ) -> SoundMetrics {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription =
                CMAudioFormatDescriptionGetStreamBasicDescription(format)
        else {
            return SoundMetrics(rms: 0, peak: 0, crossingRate: 0)
        }

        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr,
              let data = audioBufferList.mBuffers.mData
        else {
            return SoundMetrics(rms: 0, peak: 0, crossingRate: 0)
        }

        let byteCount = Int(audioBufferList.mBuffers.mDataByteSize)
        let flags = streamDescription.pointee.mFormatFlags
        let isFloat = (flags & kAudioFormatFlagIsFloat) != 0
        var squared = 0.0
        var peak = 0.0
        var crossings = 0
        var previousSign = 0
        var sampleCount = 0

        if isFloat {
            let values = data.assumingMemoryBound(to: Float.self)
            sampleCount = byteCount / MemoryLayout<Float>.size
            for index in 0..<sampleCount {
                let value = Double(values[index])
                let sign = value >= 0 ? 1 : -1
                squared += value * value
                peak = max(peak, abs(value))
                if index > 0, sign != previousSign {
                    crossings += 1
                }
                previousSign = sign
            }
        } else {
            let values = data.assumingMemoryBound(to: Int16.self)
            sampleCount = byteCount / MemoryLayout<Int16>.size
            for index in 0..<sampleCount {
                let value = Double(values[index]) / Double(Int16.max)
                let sign = value >= 0 ? 1 : -1
                squared += value * value
                peak = max(peak, abs(value))
                if index > 0, sign != previousSign {
                    crossings += 1
                }
                previousSign = sign
            }
        }

        let rms = sqrt(squared / Double(max(1, sampleCount)))
        let crossingRate = Double(crossings) / Double(max(1, sampleCount))
        return SoundMetrics(
            rms: min(1, rms),
            peak: min(1, peak),
            crossingRate: crossingRate
        )
    }

    private func requestStopAfterTrigger() {
        guard !didRequestStop else { return }
        didRequestStop = true

        DispatchQueue.main.async {
            self.isTriggered = true
            self.statusText = ""
            self.capturePhase = .detected
            self.saveProgress = 0
            withAnimation(.linear(duration: Self.clipSideDuration)) {
                self.saveProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard self.isTriggered else { return }
            self.capturePhase = .saving
        }

        sessionQueue.asyncAfter(
            deadline: .now() + Self.clipSideDuration
        ) { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    private func updateStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusText = text
        }
    }

    private func updateLevel(_ score: Double) {
        DispatchQueue.main.async {
            self.soundLevel = min(1, max(0.04, score * 4.5))
        }
    }
}

extension AutoCaptureCameraController: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        handleAudioSample(sampleBuffer)
    }
}

extension AutoCaptureCameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        guard let triggerTime else {
            try? FileManager.default.removeItem(at: outputFileURL)
            sessionQueue.async { [weak self] in
                guard let self, self.isActive, self.session.isRunning else {
                    return
                }
                if self.pendingCameraPosition != nil {
                    self.finishCameraSwitchAndRestart()
                } else {
                    self.startRecording()
                }
            }
            return
        }

        guard error == nil else {
            sessionQueue.async { [weak self] in
                guard let self, self.isActive, self.session.isRunning else {
                    return
                }
                self.startRecording()
            }
            return
        }

        DispatchQueue.main.async {
            self.completedCapture = AutoCaptureResult(
                url: outputFileURL,
                triggerTime: triggerTime
            )
        }

        sessionQueue.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.isActive, self.session.isRunning else { return }
            self.startRecording()
        }
    }
}
