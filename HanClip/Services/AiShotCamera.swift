import AVFoundation
import Combine
import SwiftUI
import UIKit

private enum AiShotSensitivity: String, CaseIterable, Identifiable {
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

private extension AiShotSensitivity {
    var audioImpactSensitivity: AudioImpactSensitivity {
        switch self {
        case .noisy: .noisy
        case .normal: .normal
        case .quiet: .quiet
        case .automatic: .automatic
        }
    }
}

enum AiShotPhase {
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

private enum AiShotDurationPreset: String, CaseIterable, Identifiable, Sendable {
    case short
    case normal
    case long

    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: "짧게"
        case .normal: "일반"
        case .long: "길게"
        }
    }

    var beforeShot: CFTimeInterval {
        switch self {
        case .short: 1.5
        case .normal: 2
        case .long: 5
        }
    }

    var afterShot: CFTimeInterval {
        switch self {
        case .short: 1.5
        case .normal: 3
        case .long: 5
        }
    }

    var fullCycle: TimeInterval { beforeShot + afterShot }
    var saveProgressWeight: Double { afterShot / fullCycle }

    var timingDescription: String {
        "앞 \(durationText(beforeShot))초 · 뒤 \(durationText(afterShot))초"
    }

    var totalDurationDescription: String {
        "\(durationText(fullCycle))초"
    }

    func durationText(_ duration: TimeInterval) -> String {
        duration.rounded() == duration
            ? String(Int(duration))
            : String(format: "%.1f", duration)
    }
}

struct AiShotCameraView: View {
    private static let durationPresetStorageKey =
        "hanClipAiShotDurationPreset"
    private static let durationDirectionStorageKey =
        "hanClipAiShotDurationDirection"

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = AiShotCameraController()
    @AppStorage("hanClipAiShotSensitivity")
    private var sensitivityRaw = AiShotSensitivity.automatic.rawValue
    @State private var durationPresetRaw: String
    @State private var nextDurationEdgeRaw: String
    @State private var isShowingIntroSwing = false
    @State private var durationPresetNotice: AiShotDurationPreset?
    @State private var durationPresetNoticeTask: Task<Void, Never>?
    @State private var isZoomDialExpanded = false
    @State private var zoomBarDragStartZoom: CGFloat?
    @State private var zoomDialDismissTask: Task<Void, Never>?

    let projectID: UUID?
    let onComplete: (URL, Double) -> Void

    init(
        projectID: UUID?,
        onComplete: @escaping (URL, Double) -> Void
    ) {
        self.projectID = projectID
        self.onComplete = onComplete

        let defaults = UserDefaults.standard
        let presetRaw = projectID.flatMap {
            defaults.string(forKey: Self.storageKey(
                Self.durationPresetStorageKey,
                projectID: $0
            ))
        } ?? AiShotDurationPreset.normal.rawValue
        let directionRaw = projectID.flatMap {
            defaults.string(forKey: Self.storageKey(
                Self.durationDirectionStorageKey,
                projectID: $0
            ))
        } ?? AiShotDurationPreset.long.rawValue

        _durationPresetRaw = State(initialValue: presetRaw)
        _nextDurationEdgeRaw = State(initialValue: directionRaw)
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let previewHeight = min(
                    proxy.size.height,
                    proxy.size.width * 4.0 / 3.0
                )
                let previewTop = (proxy.size.height - previewHeight) / 2
                let previewBottom = previewTop + previewHeight
                let bottomSpace = max(0, proxy.size.height - previewBottom)
                let preferredControlY = previewBottom + bottomSpace * 0.42
                let controlBottomInset = max(
                    12,
                    proxy.safeAreaInsets.bottom + 12
                )
                let controlY = min(
                    preferredControlY,
                    proxy.size.height - controlBottomInset - 44
                )
                let zoomControlY = min(
                    previewBottom - 34,
                    controlY - 84
                )
                let sideControlWidth: CGFloat = 116
                let sideControlOffset: CGFloat = 126
                let leftControlX = max(
                    66,
                    proxy.size.width / 2 - sideControlOffset
                )
                let rightControlX = min(
                    proxy.size.width - 66,
                    proxy.size.width / 2 + sideControlOffset
                )
                let alignedControlWidth = rightControlX - leftControlX
                    + sideControlWidth

                AiShotPreviewView(camera: camera)
                    .frame(
                        width: proxy.size.width,
                        height: previewHeight
                    )
                    .clipped()
                    .position(
                        x: proxy.size.width / 2,
                        y: previewTop + previewHeight / 2
                    )

                if isZoomDialExpanded {
                    precisionZoomDial(width: proxy.size.width)
                        .transition(.opacity)
                        .position(
                            x: proxy.size.width / 2,
                            y: zoomControlY - 46
                        )
                        .zIndex(3)
                }

                zoomControls(width: alignedControlWidth)
                    .position(
                        x: proxy.size.width / 2,
                        y: zoomControlY
                    )
                    .zIndex(2)

                durationPresetPanel
                    .position(
                        x: leftControlX,
                        y: controlY
                    )

                if let durationPresetNotice {
                    durationPresetNoticePanel(durationPresetNotice)
                        .transition(
                            .scale(scale: 0.94, anchor: .center)
                                .combined(with: .opacity)
                        )
                        .position(
                            x: proxy.size.width / 2,
                            y: proxy.size.height / 2
                        )
                        .zIndex(2)
                }

                captureControl
                    .position(
                        x: proxy.size.width / 2,
                        y: controlY
                    )

                cameraSwitchButton
                    .position(
                        x: rightControlX,
                        y: controlY
                    )
            }

            VStack(spacing: 0) {
                header
                statusPanel
                    .padding(.top, 8)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)
        }
        .background(Color.black)
        .task {
            camera.setSensitivity(selectedSensitivity)
            camera.setDurationPreset(selectedDurationPreset)
            await camera.start()
            isShowingIntroSwing = true
            try? await Task.sleep(
                for: .seconds(selectedDurationPreset.fullCycle)
            )
            withAnimation(.easeInOut(duration: 0.7)) {
                isShowingIntroSwing = false
            }
        }
        .onChange(of: sensitivityRaw) { _, _ in
            camera.setSensitivity(selectedSensitivity)
        }
        .onChange(of: durationPresetRaw) { _, _ in
            camera.setDurationPreset(selectedDurationPreset)
        }
        .onChange(of: camera.cameraPosition) { _, _ in
            cancelZoomDialAutoDismiss()
            isZoomDialExpanded = false
        }
        .onDisappear {
            cancelZoomDialAutoDismiss()
            durationPresetNoticeTask?.cancel()
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
            HStack(spacing: 8) {
                Group {
                    if camera.statusText.isEmpty {
                        Image("AiShotIcon")
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: headerStatusIcon)
                            .font(.system(size: 16, weight: .black))
                    }
                }
                .foregroundStyle(headerIconColor)
                .frame(width: 18, height: 18)
                Text(headerStatusTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(
                    headerFillColor,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(headerBorderColor, lineWidth: 1)
                }
                .shadow(
                    color: Color.black.opacity(0.24),
                    radius: 5,
                    y: 2
                )

            Spacer()

            Button {
                dismiss()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(captureDangerColor)
                    Text("닫기")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                    .padding(.horizontal, 15)
                    .frame(height: 40)
                    .background(
                        Color.black.opacity(0.52),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                captureDangerColor.opacity(0.58),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(0.24),
                        radius: 5,
                        y: 2
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("AiShot 닫기")
        }
    }

    private var captureDangerColor: Color {
        Color(red: 0.88, green: 0.32, blue: 0.34)
    }

    private var captureSelectionColor: Color {
        HanClipTheme.secondary
    }

    private var captureSelectionForeground: Color {
        HanClipTheme.onSecondary
    }

    private var headerFillColor: Color {
        camera.statusText.isEmpty
            ? captureSelectionColor.opacity(0.24)
            : Color(red: 0.31, green: 0.12, blue: 0.14).opacity(0.78)
    }

    private var headerBorderColor: Color {
        camera.statusText.isEmpty
            ? captureSelectionColor.opacity(0.72)
            : captureDangerColor.opacity(0.58)
    }

    private var headerIconColor: Color {
        camera.statusText.isEmpty ? captureSelectionColor : .white
    }

    private var headerStatusTitle: String {
        camera.statusText.isEmpty ? "AiShot" : camera.statusText
    }

    private var headerStatusIcon: String {
        switch camera.statusText {
        case "준비 중":
            "hourglass"
        case "권한 필요":
            "exclamationmark.shield.fill"
        case "전환 중", "카메라 전환 불가":
            "arrow.triangle.2.circlepath.camera"
        case "줌 조절 불가":
            "minus.magnifyingglass"
        case "3:4 설정 불가":
            "aspectratio"
        case "카메라 사용 불가":
            "camera.badge.ellipsis"
        case "저장 불가":
            "externaldrive.badge.exclamationmark"
        case "시작 불가":
            "exclamationmark.triangle.fill"
        default:
            "figure.golf"
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                soundMeter

                Text(statusBadgeText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)
                    .frame(minWidth: 42, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Label("감도", systemImage: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize()

                HStack(spacing: 2) {
                    ForEach(AiShotSensitivity.allCases) { sensitivity in
                        sensitivityButton(sensitivity)
                    }
                }
                .padding(2)
                .background(
                    Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
            .accessibilityHint("주변 소음에 맞는 타구음 감도를 선택합니다")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        }
    }

    private func zoomControls(width: CGFloat) -> some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(camera.lensZoomFactors, id: \.self) { factor in
                    lensZoomLabel(factor)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: width)
            .frame(height: 46)
            .background(.black.opacity(0.32), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            .opacity(isZoomDialExpanded ? 0 : 1)
            .scaleEffect(isZoomDialExpanded ? 0.94 : 1)
            .offset(y: isZoomDialExpanded ? 10 : 0)
            .animation(.easeInOut(duration: 0.16), value: isZoomDialExpanded)

            Capsule()
                .fill(Color.black.opacity(0.001))
                .frame(width: width, height: 56)
                .contentShape(Capsule())
                .highPriorityGesture(zoomBarGesture(width: width))
                .opacity(camera.isSwitchingCamera ? 0 : 1)
                .allowsHitTesting(!camera.isSwitchingCamera)
        }
        .frame(width: width)
        .frame(height: 56)
        .opacity(camera.isSwitchingCamera ? 0.55 : 1)
    }

    private func zoomBarGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if zoomBarDragStartZoom == nil {
                    zoomBarDragStartZoom = camera.zoomFactor
                    if abs(value.translation.width) < 1,
                       abs(value.translation.height) < 1 {
                        selectNearestZoomFactor(at: value.location.x, width: width)
                    }
                }
                showZoomDial()
                let start = zoomBarDragStartZoom ?? camera.zoomFactor
                let minimum = camera.lensZoomFactors.first
                    ?? camera.minimumZoomFactor
                let maximum = camera.lensZoomFactors.last
                    ?? camera.maximumZoomFactor
                let octaveOffset = -value.translation.width / 92
                let proposed = start * CGFloat(
                    pow(2, Double(octaveOffset))
                )
                camera.setZoom(
                    Double(min(maximum, max(minimum, proposed)))
                )
            }
            .onEnded { value in
                zoomBarDragStartZoom = nil
                if abs(value.translation.width) < 1,
                   abs(value.translation.height) < 1 {
                    showZoomDial()
                }
                scheduleZoomDialAutoDismiss()
            }
    }

    private func showZoomDial() {
        cancelZoomDialAutoDismiss()
        guard !isZoomDialExpanded else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            isZoomDialExpanded = true
        }
    }

    private func scheduleZoomDialAutoDismiss() {
        zoomDialDismissTask?.cancel()
        zoomDialDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isZoomDialExpanded = false
            }
            zoomDialDismissTask = nil
        }
    }

    private func cancelZoomDialAutoDismiss() {
        zoomDialDismissTask?.cancel()
        zoomDialDismissTask = nil
    }

    private func selectNearestZoomFactor(at x: CGFloat, width: CGFloat) {
        let factors = camera.lensZoomFactors
        guard !factors.isEmpty else { return }
        let segmentWidth = width / CGFloat(factors.count)
        let index = min(
            factors.count - 1,
            max(0, Int((x / max(segmentWidth, 1)).rounded(.down)))
        )
        camera.setZoom(Double(factors[index]))
    }

    private func lensZoomLabel(_ factor: CGFloat) -> some View {
        let activeFactor = activeLensZoomFactor
        let isSelected = abs(activeFactor - factor) < 0.02
        let displayedFactor = isSelected ? camera.zoomFactor : factor

        return Text(zoomFactorTitle(displayedFactor, isSelected: isSelected))
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(isSelected ? captureSelectionColor : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                isSelected ? Color.white.opacity(0.14) : Color.clear,
                in: Circle()
            )
        .accessibilityLabel(
            "\(zoomFactorTitle(displayedFactor, isSelected: true)) 확대"
        )
        .accessibilityHint(
            "누르면 해당 배율과 정밀 확대 조절이 열립니다"
        )
    }

    private var activeLensZoomFactor: CGFloat {
        let factors = camera.lensZoomFactors.sorted()
        return factors.last {
            $0 <= camera.zoomFactor + 0.02
        } ?? factors.first ?? camera.zoomFactor
    }

    private func precisionZoomDial(width: CGFloat) -> some View {
        let minimum = camera.lensZoomFactors.first
            ?? camera.minimumZoomFactor
        let maximum = camera.lensZoomFactors.last
            ?? camera.maximumZoomFactor

        return AiShotPrecisionZoomDial(
            zoom: camera.zoomFactor,
            minimumZoom: minimum,
            maximumZoom: maximum,
            accentColor: captureSelectionColor,
            onZoomChange: { zoom in
                camera.setZoom(Double(zoom))
            },
            onInteractionStart: {
                cancelZoomDialAutoDismiss()
            },
            onInteractionEnd: {
                scheduleZoomDialAutoDismiss()
            }
        )
        .frame(width: width, height: 268)
        .frame(width: width, height: 160, alignment: .top)
        .clipped()
    }

    private func zoomFactorTitle(
        _ factor: CGFloat,
        isSelected: Bool
    ) -> String {
        if abs(factor - 0.5) < 0.05 {
            return ".5"
        }
        let rounded = factor.rounded()
        let value = rounded == factor
            ? "\(Int(rounded))"
            : String(format: "%.1f", Double(factor))
        return isSelected ? "\(value)x" : value
    }

    private var cameraSwitchButton: some View {
        Button {
            camera.switchCamera()
        } label: {
            ZStack {
                Text(camera.cameraPosition == .front ? "전면" : "후면")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.interpolate)
                    .lineLimit(1)
                    .offset(x: 8)

                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            LinearGradient(
                                colors: [
                                    HanClipTheme.secondary.opacity(0.72),
                                    HanClipTheme.primary.opacity(0.52)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(.white.opacity(0.16), lineWidth: 1)
                        }

                    Spacer(minLength: 0)
                }
                .padding(.leading, 8)
                .padding(.trailing, 9)
            }
            .frame(width: 116, height: 52)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .background(
            LinearGradient(
                colors: [
                    captureSelectionColor.opacity(0.15),
                    .black.opacity(0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(captureSelectionColor.opacity(0.70), lineWidth: 1.2)
        }
        .disabled(camera.isSwitchingCamera)
        .opacity(camera.isSwitchingCamera ? 0.55 : 1)
        .accessibilityLabel("카메라 전환")
        .accessibilityValue(
            camera.cameraPosition == .front ? "전면" : "후면"
        )
        .accessibilityHint("전면과 후면 카메라를 전환합니다")
    }

    private func sensitivityButton(
        _ sensitivity: AiShotSensitivity
    ) -> some View {
        let isSelected = sensitivity == selectedSensitivity

        return Button {
            sensitivityRaw = sensitivity.rawValue
        } label: {
            Text(sensitivity.title)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(
                    isSelected
                        ? captureSelectionForeground
                        : Color.white.opacity(0.72)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(
                    isSelected
                        ? captureSelectionColor
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
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
            return camera.isReadyForTrigger
                ? Color(red: 0.31, green: 0.82, blue: 0.54)
                : Color(red: 0.95, green: 0.70, blue: 0.24)
        case .detected:
            return Color(red: 0.31, green: 0.82, blue: 0.54)
        case .saving:
            return captureDangerColor
        }
    }

    private var statusBadgeText: String {
        camera.capturePhase.title
    }

    private var selectedSensitivity: AiShotSensitivity {
        AiShotSensitivity(rawValue: sensitivityRaw) ?? .automatic
    }

    private var selectedDurationPreset: AiShotDurationPreset {
        AiShotDurationPreset(rawValue: durationPresetRaw) ?? .normal
    }

    private var durationPresetPanel: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) {
                selectNextDurationPreset()
            }
        } label: {
            ZStack {
                Text(selectedDurationPreset.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.interpolate)
                    .lineLimit(1)
                    .offset(x: 8)

                HStack {
                    Image(systemName: "timer")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            LinearGradient(
                                colors: [
                                    HanClipTheme.secondary.opacity(0.72),
                                    HanClipTheme.primary.opacity(0.52)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(.white.opacity(0.16), lineWidth: 1)
                        }

                    Spacer(minLength: 0)
                }
                .padding(.leading, 8)
                .padding(.trailing, 9)
            }
            .frame(width: 116, height: 52)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .background(
            LinearGradient(
                colors: [
                    captureSelectionColor.opacity(0.15),
                    .black.opacity(0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(captureSelectionColor.opacity(0.70), lineWidth: 1.2)
        }
        .accessibilityLabel("샷 시간")
        .accessibilityValue(
            "\(selectedDurationPreset.title), 앞 "
                + "\(selectedDurationPreset.durationText(selectedDurationPreset.beforeShot))초, 뒤 "
                + "\(selectedDurationPreset.durationText(selectedDurationPreset.afterShot))초"
        )
        .accessibilityHint("누를 때마다 짧게, 일반, 길게 순서로 변경됩니다")
    }

    private func durationPresetNoticePanel(
        _ preset: AiShotDurationPreset
    ) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        LinearGradient(
                            colors: [
                                HanClipTheme.secondary,
                                HanClipTheme.primary
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("샷 시간")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.66))

                    Text(preset.timingDescription)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.interpolate)
                }

                Spacer(minLength: 8)

                Text(preset.totalDurationDescription)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        HanClipTheme.secondary.opacity(0.48),
                        in: Capsule()
                    )
            }

            HStack(spacing: 0) {
                ForEach(AiShotDurationPreset.allCases) { option in
                    Text(option.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(
                            option == preset
                                ? Color.white
                                : Color.white.opacity(0.48)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            option == preset
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            HanClipTheme.secondary,
                                            HanClipTheme.primary
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
            }
            .padding(3)
            .background(
                Color.black.opacity(0.30),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
        }
        .padding(14)
        .frame(width: 280, height: 116)
        .background(
            LinearGradient(
                colors: [
                    HanClipTheme.primary.opacity(0.58),
                    Color.black.opacity(0.92),
                    HanClipTheme.secondary.opacity(0.40)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            HanClipTheme.secondary,
                            .white.opacity(0.28),
                            HanClipTheme.primary
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.25
                )
        }
        .shadow(
            color: HanClipTheme.secondary.opacity(0.28),
            radius: 18,
            y: 8
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private func selectNextDurationPreset() {
        let nextPreset: AiShotDurationPreset

        switch selectedDurationPreset {
        case .normal:
            let nextEdge = AiShotDurationPreset(
                rawValue: nextDurationEdgeRaw
            ) ?? .long
            nextPreset = nextEdge == .short ? .short : .long
            nextDurationEdgeRaw = nextPreset == .long
                ? AiShotDurationPreset.short.rawValue
                : AiShotDurationPreset.long.rawValue
        case .short, .long:
            nextPreset = .normal
        }

        durationPresetRaw = nextPreset.rawValue
        storeDurationSelection()
        showDurationPresetNotice(nextPreset)
    }

    private func showDurationPresetNotice(_ preset: AiShotDurationPreset) {
        durationPresetNoticeTask?.cancel()
        durationPresetNotice = preset
        durationPresetNoticeTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.7))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                durationPresetNotice = nil
            }
        }
    }

    private func storeDurationSelection() {
        guard let projectID else { return }
        let defaults = UserDefaults.standard
        defaults.set(
            durationPresetRaw,
            forKey: Self.storageKey(
                Self.durationPresetStorageKey,
                projectID: projectID
            )
        )
        defaults.set(
            nextDurationEdgeRaw,
            forKey: Self.storageKey(
                Self.durationDirectionStorageKey,
                projectID: projectID
            )
        )
    }

    private static func storageKey(
        _ base: String,
        projectID: UUID
    ) -> String {
        "\(base).\(projectID.uuidString)"
    }

    @ViewBuilder
    private var captureControl: some View {
        if camera.isTriggered {
            saveProgressIndicator
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        } else {
            manualCaptureButton
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    private var saveProgressIndicator: some View {
        VStack(spacing: 7) {
            Text("저장 중")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))

            ProgressView(value: captureRingProgress)
                .progressViewStyle(.linear)
                .tint(captureSelectionColor)
                .frame(width: 92)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(captureSelectionColor.opacity(0.70), lineWidth: 1.2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AiShot 클립 저장 중")
        .accessibilityValue("\(Int(captureRingProgress * 100))퍼센트")
    }

    private var manualCaptureButton: some View {
        Button {
            camera.triggerManualCapture()
        } label: {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.32))
                    .frame(width: 88, height: 88)

                Circle()
                    .stroke(
                        camera.isReadyForTrigger
                            ? captureSelectionColor.opacity(0.62)
                            : Color.white.opacity(0.28),
                        lineWidth: 5
                    )
                    .frame(width: 78, height: 78)

                Circle()
                    .trim(from: 0, to: captureRingProgress)
                    .stroke(
                        Color.red,
                        style: StrokeStyle(
                            lineWidth: 6,
                            lineCap: .round
                        )
                    )
                    .shadow(
                        color: Color.red.opacity(0.65),
                        radius: 3
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 78, height: 78)

                if camera.isTriggered {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(y: -39)
                        .rotationEffect(
                            .degrees(360 * camera.saveProgress)
                        )
                }

                Circle()
                    .fill(
                        camera.isReadyForTrigger
                            ? Color.red
                            : Color.red.opacity(0.42)
                    )
                    .frame(width: 62, height: 62)

                if camera.isTriggered || isShowingIntroSwing {
                    GolfSwingSpriteIndicator(
                        playbackDuration: camera.isTriggered
                            ? camera.captureAnimationDuration
                            : selectedDurationPreset.fullCycle
                    )
                        .id(
                            camera.isTriggered
                                ? "capture-\(camera.captureAnimationSequence)"
                                : "intro"
                        )
                        .frame(width: 54, height: 54)
                        .transition(.opacity)
                }
            }
            .animation(
                .easeInOut(duration: 0.7),
                value: camera.isTriggered
            )
            .animation(
                .easeInOut(duration: 0.7),
                value: isShowingIntroSwing
            )
            .contentShape(Circle())
        }
        .buttonStyle(ManualCaptureButtonStyle())
        .disabled(!camera.isReadyForTrigger || camera.isTriggered)
        .accessibilityLabel("수동 촬영")
        .accessibilityHint("현재 순간을 직접 촬영해 클립으로 저장합니다")
        .accessibilityValue(statusBadgeText)
    }

    private var captureRingProgress: Double {
        let saveWeight = camera.captureSaveProgressWeight
        if camera.isTriggered {
            if camera.saveProgress >= 0.99 {
                return saveWeight
                    + (camera.preparationProgress * (1 - saveWeight))
            }
            return camera.saveProgress * saveWeight
        }
        if camera.saveProgress >= 0.99 {
            if camera.isReadyForTrigger {
                return 1
            }
            return saveWeight
                + (camera.preparationProgress * (1 - saveWeight))
        }
        if camera.isReadyForTrigger && camera.saveProgress > 0 {
            return 1
        }
        return 0
    }

    private var soundMeter: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                Capsule()
                    .fill(statusColor)
                    .frame(width: proxy.size.width * camera.soundLevel)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

@MainActor
private struct GolfSwingSpriteIndicator: View {
    let playbackDuration: TimeInterval

    @State private var startDate = Date()

    private static let columnCount = 6
    private static let frameCount = 36
    private static let frames: [CGImage] = {
        guard let source = UIImage(named: "GolfSwingFrames")?.cgImage else {
            return []
        }

        let cellWidth = source.width / columnCount
        let cellHeight = source.height / columnCount
        return (0..<frameCount).compactMap { index in
            source.cropping(to: CGRect(
                x: (index % columnCount) * cellWidth,
                y: (index / columnCount) * cellHeight,
                width: cellWidth,
                height: cellHeight
            ))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let finishHoldDuration = min(0.3, playbackDuration * 0.2)
            let motionDuration = max(
                0.1,
                playbackDuration - finishHoldDuration
            )
            let phase = min(
                1,
                max(0, elapsed / motionDuration)
            )
            let framePosition = phase
                * Double(max(0, Self.frames.count - 1))
            let currentIndex = Int(framePosition.rounded(.down))
            let nextIndex = min(
                max(0, Self.frames.count - 1),
                currentIndex + 1
            )
            let rawBlend = framePosition - Double(currentIndex)
            let blend = rawBlend * rawBlend * (3 - 2 * rawBlend)

            if Self.frames.isEmpty {
                Image(systemName: "figure.golf")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                ZStack {
                    spriteFrame(at: nextIndex)
                    spriteFrame(at: currentIndex)
                        .opacity(1 - blend)
                }
                .background(Color.black)
                .clipShape(Circle())
                .compositingGroup()
            }
        }
        .accessibilityHidden(true)
    }

    private func spriteFrame(at index: Int) -> some View {
        rawSpriteFrame(at: index)
    }

    private func rawSpriteFrame(at index: Int) -> some View {
        Image(
            decorative: Self.frames[index],
            scale: 1,
            orientation: .up
        )
        .resizable()
        .scaledToFill()
    }
}

private struct GolfSwingIndicator: View {
    @State private var startDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = min(
                1,
                timeline.date.timeIntervalSince(startDate) / 2.65
            )
            let pose = GolfSwingPose.pose(at: phase)
            let flight = CGFloat(min(1, max(0, (phase - 0.72) / 0.18)))

            Canvas { context, size in
                let scale = min(size.width, size.height) / 42
                func point(_ value: CGPoint) -> CGPoint {
                    CGPoint(x: value.x * scale, y: value.y * scale)
                }
                let torsoVector = CGPoint(
                    x: pose.hip.x - pose.shoulder.x,
                    y: pose.hip.y - pose.shoulder.y
                )
                let torsoLength = max(1, hypot(torsoVector.x, torsoVector.y))
                let torsoAxis = CGPoint(
                    x: torsoVector.x / torsoLength,
                    y: torsoVector.y / torsoLength
                )
                let torsoPerpendicular = CGPoint(
                    x: -torsoAxis.y,
                    y: torsoAxis.x
                )

                var ground = Path()
                ground.move(to: point(CGPoint(x: 8, y: 36.5)))
                ground.addLine(to: point(CGPoint(x: 38, y: 36.5)))
                context.stroke(
                    ground,
                    with: .color(.white.opacity(0.35)),
                    lineWidth: 0.8 * scale
                )

                var legs = Path()
                legs.move(to: point(CGPoint(x: pose.hip.x - 2, y: pose.hip.y + 4)))
                legs.addLine(to: point(pose.trailKnee))
                legs.addLine(to: point(pose.trailFoot))
                legs.move(to: point(CGPoint(x: pose.hip.x + 2, y: pose.hip.y + 4)))
                legs.addLine(to: point(pose.leadKnee))
                legs.addLine(to: point(pose.leadFoot))
                context.stroke(
                    legs,
                    with: .color(.white),
                    style: StrokeStyle(
                        lineWidth: 2.7 * scale,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                var skirt = Path()
                skirt.move(to: point(CGPoint(
                    x: pose.hip.x + torsoPerpendicular.x * 2.7,
                    y: pose.hip.y + torsoPerpendicular.y * 2.7
                )))
                skirt.addLine(to: point(CGPoint(
                    x: pose.hip.x - torsoPerpendicular.x * 2.7,
                    y: pose.hip.y - torsoPerpendicular.y * 2.7
                )))
                skirt.addLine(to: point(CGPoint(
                    x: pose.hip.x + torsoAxis.x * 5 - torsoPerpendicular.x * 4.5,
                    y: pose.hip.y + torsoAxis.y * 5 - torsoPerpendicular.y * 4.5
                )))
                skirt.addLine(to: point(CGPoint(
                    x: pose.hip.x + torsoAxis.x * 5 + torsoPerpendicular.x * 4.5,
                    y: pose.hip.y + torsoAxis.y * 5 + torsoPerpendicular.y * 4.5
                )))
                skirt.closeSubpath()
                context.fill(skirt, with: .color(.white))

                var torso = Path()
                torso.move(to: point(CGPoint(
                    x: pose.shoulder.x + torsoPerpendicular.x * 3.1,
                    y: pose.shoulder.y + torsoPerpendicular.y * 3.1
                )))
                torso.addLine(to: point(CGPoint(
                    x: pose.shoulder.x - torsoPerpendicular.x * 3.1,
                    y: pose.shoulder.y - torsoPerpendicular.y * 3.1
                )))
                torso.addLine(to: point(CGPoint(
                    x: pose.hip.x - torsoPerpendicular.x * 2.6,
                    y: pose.hip.y - torsoPerpendicular.y * 2.6
                )))
                torso.addLine(to: point(CGPoint(
                    x: pose.hip.x + torsoPerpendicular.x * 2.6,
                    y: pose.hip.y + torsoPerpendicular.y * 2.6
                )))
                torso.closeSubpath()
                context.fill(torso, with: .color(.white))

                var neck = Path()
                neck.move(to: point(CGPoint(
                    x: pose.head.x + torsoAxis.x * 2,
                    y: pose.head.y + torsoAxis.y * 2
                )))
                neck.addLine(to: point(CGPoint(
                    x: pose.shoulder.x - torsoAxis.x * 1.2,
                    y: pose.shoulder.y - torsoAxis.y * 1.2
                )))
                context.stroke(
                    neck,
                    with: .color(.white),
                    style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round)
                )

                var arms = Path()
                arms.move(to: point(CGPoint(x: pose.shoulder.x - 1.5, y: pose.shoulder.y + 1)))
                arms.addLine(to: point(pose.trailElbow))
                arms.addLine(to: point(pose.hands))
                arms.move(to: point(CGPoint(x: pose.shoulder.x + 1.8, y: pose.shoulder.y + 1)))
                arms.addLine(to: point(pose.leadElbow))
                arms.addLine(to: point(pose.hands))
                context.stroke(
                    arms,
                    with: .color(.white),
                    style: StrokeStyle(
                        lineWidth: 2.3 * scale,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                var club = Path()
                club.move(to: point(pose.hands))
                club.addLine(to: point(pose.clubHead))
                context.stroke(
                    club,
                    with: .color(.white.opacity(0.95)),
                    style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round)
                )

                let clubVector = CGPoint(
                    x: pose.clubHead.x - pose.hands.x,
                    y: pose.clubHead.y - pose.hands.y
                )
                let clubLength = max(1, hypot(clubVector.x, clubVector.y))
                let clubPerpendicular = CGPoint(
                    x: -clubVector.y / clubLength * 1.7,
                    y: clubVector.x / clubLength * 1.7
                )
                var clubFace = Path()
                clubFace.move(to: point(CGPoint(
                    x: pose.clubHead.x - clubPerpendicular.x,
                    y: pose.clubHead.y - clubPerpendicular.y
                )))
                clubFace.addLine(to: point(CGPoint(
                    x: pose.clubHead.x + clubPerpendicular.x,
                    y: pose.clubHead.y + clubPerpendicular.y
                )))
                context.stroke(
                    clubFace,
                    with: .color(.white),
                    lineWidth: 1.8 * scale
                )

                let headRect = CGRect(
                    x: (pose.head.x - 2.6) * scale,
                    y: (pose.head.y - 2.6) * scale,
                    width: 5.2 * scale,
                    height: 5.2 * scale
                )
                context.fill(Path(ellipseIn: headRect), with: .color(.white))

                var ponytail = Path()
                ponytail.move(to: point(CGPoint(x: pose.head.x - 2, y: pose.head.y - 0.7)))
                ponytail.addQuadCurve(
                    to: point(CGPoint(x: pose.head.x - 5.3, y: pose.head.y + 2.4)),
                    control: point(CGPoint(x: pose.head.x - 5.2, y: pose.head.y - 1.5))
                )
                context.stroke(
                    ponytail,
                    with: .color(.white),
                    style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round)
                )

                var tee = Path()
                tee.move(to: point(CGPoint(x: 34, y: 34)))
                tee.addLine(to: point(CGPoint(x: 34, y: 36)))
                context.stroke(
                    tee,
                    with: .color(.white.opacity(0.75)),
                    lineWidth: 0.8 * scale
                )

                let ballPosition = flight > 0
                    ? CGPoint(
                        x: 34 + 15 * flight,
                        y: 33 - 17 * flight + 4 * flight * flight
                    )
                    : CGPoint(x: 34, y: 33)
                if flight < 0.76 {
                    let ballRect = CGRect(
                        x: (ballPosition.x - 1.25) * scale,
                        y: (ballPosition.y - 1.25) * scale,
                        width: 2.5 * scale,
                        height: 2.5 * scale
                    )
                    context.fill(Path(ellipseIn: ballRect), with: .color(.white))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct GolfSwingPose {
    private struct Keyframe {
        let phase: Double
        let pose: GolfSwingPose
    }

    let head: CGPoint
    let shoulder: CGPoint
    let hip: CGPoint
    let trailKnee: CGPoint
    let trailFoot: CGPoint
    let leadKnee: CGPoint
    let leadFoot: CGPoint
    let trailElbow: CGPoint
    let leadElbow: CGPoint
    let hands: CGPoint
    let clubHead: CGPoint

    private static let keyframes: [Keyframe] = [
        Keyframe(phase: 0.00, pose: address),
        Keyframe(phase: 0.14, pose: address),
        Keyframe(phase: 0.36, pose: backswing),
        Keyframe(phase: 0.48, pose: top),
        Keyframe(phase: 0.55, pose: top),
        Keyframe(phase: 0.68, pose: downswing),
        Keyframe(phase: 0.73, pose: impact),
        Keyframe(phase: 0.85, pose: followThrough),
        Keyframe(phase: 0.94, pose: finish),
        Keyframe(phase: 1.00, pose: finish),
    ]

    static func pose(at phase: Double) -> GolfSwingPose {
        for index in 0..<(keyframes.count - 1) {
            let current = keyframes[index]
            let next = keyframes[index + 1]
            let currentPhase: Double = current.phase
            let nextPhase: Double = next.phase
            guard phase >= currentPhase && phase <= nextPhase else { continue }

            let phaseDelta: Double = nextPhase - currentPhase
            let safePhaseDelta: Double = Swift.max(0.001, phaseDelta)
            let elapsedPhase: Double = phase - currentPhase
            let rawProgress: Double = elapsedPhase / safePhaseDelta
            let previousIndex = Swift.max(0, index - 1)
            let followingIndex = Swift.min(keyframes.count - 1, index + 2)
            let previousPose = keyframes[previousIndex].pose
            let followingPose = keyframes[followingIndex].pose
            return current.pose.catmullRom(
                previous: previousPose,
                to: next.pose,
                following: followingPose,
                progress: rawProgress
            )
        }
        return finish
    }

    private func catmullRom(
        previous: GolfSwingPose,
        to next: GolfSwingPose,
        following: GolfSwingPose,
        progress: Double
    ) -> GolfSwingPose {
        let t = CGFloat(progress)
        let t2 = t * t
        let t3 = t2 * t
        func value(
            _ p0: CGPoint,
            _ p1: CGPoint,
            _ p2: CGPoint,
            _ p3: CGPoint
        ) -> CGPoint {
            func coordinate(
                _ c0: CGFloat,
                _ c1: CGFloat,
                _ c2: CGFloat,
                _ c3: CGFloat
            ) -> CGFloat {
                let base = 2 * c1
                let tangent = (-c0 + c2) * t
                let curve = (2 * c0 - 5 * c1 + 4 * c2 - c3) * t2
                let cubic = (-c0 + 3 * c1 - 3 * c2 + c3) * t3
                return 0.5 * (base + tangent + curve + cubic)
            }

            return CGPoint(
                x: coordinate(p0.x, p1.x, p2.x, p3.x),
                y: coordinate(p0.y, p1.y, p2.y, p3.y)
            )
        }

        return GolfSwingPose(
            head: value(previous.head, head, next.head, following.head),
            shoulder: value(previous.shoulder, shoulder, next.shoulder, following.shoulder),
            hip: value(previous.hip, hip, next.hip, following.hip),
            trailKnee: value(previous.trailKnee, trailKnee, next.trailKnee, following.trailKnee),
            trailFoot: value(previous.trailFoot, trailFoot, next.trailFoot, following.trailFoot),
            leadKnee: value(previous.leadKnee, leadKnee, next.leadKnee, following.leadKnee),
            leadFoot: value(previous.leadFoot, leadFoot, next.leadFoot, following.leadFoot),
            trailElbow: value(previous.trailElbow, trailElbow, next.trailElbow, following.trailElbow),
            leadElbow: value(previous.leadElbow, leadElbow, next.leadElbow, following.leadElbow),
            hands: value(previous.hands, hands, next.hands, following.hands),
            clubHead: value(previous.clubHead, clubHead, next.clubHead, following.clubHead)
        )
    }

    private static let address = GolfSwingPose(
        head: CGPoint(x: 17.5, y: 8.5), shoulder: CGPoint(x: 19, y: 14),
        hip: CGPoint(x: 20, y: 23), trailKnee: CGPoint(x: 17, y: 29),
        trailFoot: CGPoint(x: 14, y: 36), leadKnee: CGPoint(x: 24, y: 29),
        leadFoot: CGPoint(x: 27, y: 36), trailElbow: CGPoint(x: 23, y: 20),
        leadElbow: CGPoint(x: 25, y: 18), hands: CGPoint(x: 28, y: 22),
        clubHead: CGPoint(x: 34, y: 34)
    )

    private static let backswing = GolfSwingPose(
        head: CGPoint(x: 17.2, y: 8.3), shoulder: CGPoint(x: 18.7, y: 14),
        hip: CGPoint(x: 19.5, y: 23), trailKnee: CGPoint(x: 16, y: 29),
        trailFoot: CGPoint(x: 14, y: 36), leadKnee: CGPoint(x: 23, y: 29),
        leadFoot: CGPoint(x: 27, y: 36), trailElbow: CGPoint(x: 14, y: 13),
        leadElbow: CGPoint(x: 17, y: 11), hands: CGPoint(x: 13, y: 9),
        clubHead: CGPoint(x: 29, y: 5)
    )

    private static let top = GolfSwingPose(
        head: CGPoint(x: 17.2, y: 8.2), shoulder: CGPoint(x: 18.8, y: 14),
        hip: CGPoint(x: 19.5, y: 23), trailKnee: CGPoint(x: 16, y: 29),
        trailFoot: CGPoint(x: 14, y: 36), leadKnee: CGPoint(x: 23, y: 29),
        leadFoot: CGPoint(x: 27, y: 36), trailElbow: CGPoint(x: 12, y: 12),
        leadElbow: CGPoint(x: 15, y: 10), hands: CGPoint(x: 12, y: 8),
        clubHead: CGPoint(x: 30, y: 6)
    )

    private static let downswing = GolfSwingPose(
        head: CGPoint(x: 17.5, y: 8.4), shoulder: CGPoint(x: 19.5, y: 14.6),
        hip: CGPoint(x: 20.5, y: 23), trailKnee: CGPoint(x: 18, y: 30),
        trailFoot: CGPoint(x: 15, y: 36), leadKnee: CGPoint(x: 24, y: 29),
        leadFoot: CGPoint(x: 27, y: 36), trailElbow: CGPoint(x: 21, y: 18),
        leadElbow: CGPoint(x: 24, y: 17), hands: CGPoint(x: 26, y: 20),
        clubHead: CGPoint(x: 12, y: 12)
    )

    private static let impact = GolfSwingPose(
        head: CGPoint(x: 17.8, y: 8.5), shoulder: CGPoint(x: 20.5, y: 14.7),
        hip: CGPoint(x: 21.3, y: 23), trailKnee: CGPoint(x: 19, y: 30),
        trailFoot: CGPoint(x: 16, y: 36), leadKnee: CGPoint(x: 25, y: 29),
        leadFoot: CGPoint(x: 27, y: 36), trailElbow: CGPoint(x: 23, y: 20),
        leadElbow: CGPoint(x: 26, y: 18), hands: CGPoint(x: 29, y: 22),
        clubHead: CGPoint(x: 35, y: 34)
    )

    private static let followThrough = GolfSwingPose(
        head: CGPoint(x: 18.2, y: 8.2), shoulder: CGPoint(x: 21.3, y: 14),
        hip: CGPoint(x: 22, y: 23), trailKnee: CGPoint(x: 20, y: 30),
        trailFoot: CGPoint(x: 19, y: 36), leadKnee: CGPoint(x: 25, y: 29),
        leadFoot: CGPoint(x: 27, y: 36), trailElbow: CGPoint(x: 22, y: 11),
        leadElbow: CGPoint(x: 25, y: 12), hands: CGPoint(x: 27, y: 10),
        clubHead: CGPoint(x: 36, y: 7)
    )

    private static let finish = GolfSwingPose(
        head: CGPoint(x: 18.5, y: 8), shoulder: CGPoint(x: 21.5, y: 14),
        hip: CGPoint(x: 22, y: 23), trailKnee: CGPoint(x: 20, y: 30),
        trailFoot: CGPoint(x: 22, y: 35), leadKnee: CGPoint(x: 25, y: 29),
        leadFoot: CGPoint(x: 27, y: 36), trailElbow: CGPoint(x: 17, y: 11),
        leadElbow: CGPoint(x: 20, y: 9), hands: CGPoint(x: 18, y: 7),
        clubHead: CGPoint(x: 7, y: 12)
    )
}

private struct AiShotPrecisionZoomDial: View {
    let zoom: CGFloat
    let minimumZoom: CGFloat
    let maximumZoom: CGFloat
    let accentColor: Color
    let onZoomChange: (CGFloat) -> Void
    let onInteractionStart: () -> Void
    let onInteractionEnd: () -> Void

    @State private var dragStartZoom: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height + 8)
                let radius = size.width * 0.65
                let startAngle = 202.0
                let endAngle = 338.0

                let discRect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(
                    Path(ellipseIn: discRect),
                    with: .color(.black.opacity(0.58))
                )
                context.stroke(
                    Path(ellipseIn: discRect),
                    with: .color(.white.opacity(0.16)),
                    lineWidth: 1
                )

                var arc = Path()
                arc.addArc(
                    center: center,
                    radius: radius - 12,
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(endAngle),
                    clockwise: false
                )
                context.stroke(
                    arc,
                    with: .color(.white.opacity(0.22)),
                    lineWidth: 0.8
                )

                let tickPhase = log2(Double(max(zoom, 0.01))) * 8
                for index in 0...56 {
                    let progress = Double(index) / 56
                    let degrees = startAngle
                        + (endAngle - startAngle) * progress
                    let phasedIndex = index + Int(tickPhase.rounded(.down))
                    let isMajor = phasedIndex.isMultiple(of: 8)
                    let outer = point(
                        center: center,
                        radius: radius - 12,
                        degrees: degrees
                    )
                    let inner = point(
                        center: center,
                        radius: radius - (isMajor ? 28 : 21),
                        degrees: degrees
                    )
                    var tick = Path()
                    tick.move(to: inner)
                    tick.addLine(to: outer)
                    context.stroke(
                        tick,
                        with: .color(.white.opacity(isMajor ? 0.82 : 0.42)),
                        lineWidth: isMajor ? 1.5 : 0.75
                    )
                }

                let markerInner = point(
                    center: center,
                    radius: radius - 30,
                    degrees: 270
                )
                let markerOuter = point(
                    center: center,
                    radius: radius - 7,
                    degrees: 270
                )
                var marker = Path()
                marker.move(to: markerInner)
                marker.addLine(to: markerOuter)
                context.stroke(
                    marker,
                    with: .color(accentColor),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )

                let referenceFactors: [CGFloat] = [
                    0.5, 1, 2, 4, 8, 16, 40
                ]
                for factor in referenceFactors {
                    guard factor >= minimumZoom * 0.95,
                          factor <= maximumZoom * 1.05,
                          abs(factor - zoom) > 0.08
                    else { continue }
                    let offset = log2(Double(factor / max(zoom, 0.01)))
                    let degrees = 270 + offset * 32
                    guard degrees > startAngle + 5,
                          degrees < endAngle - 5
                    else { continue }
                    let labelPoint = point(
                        center: center,
                        radius: radius - 48,
                        degrees: degrees
                    )
                    context.draw(
                        Text(factorTitle(factor, includesX: false))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88)),
                        at: labelPoint,
                        anchor: .center
                    )
                }

                context.draw(
                    Text(factorTitle(zoom, includesX: true))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor),
                    at: CGPoint(x: center.x, y: 63),
                    anchor: .center
                )
                context.draw(
                    Text(focalLengthTitle(zoom))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(accentColor.opacity(0.82)),
                    at: CGPoint(x: center.x, y: 80),
                    anchor: .center
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onInteractionStart()
                        let start = dragStartZoom ?? zoom
                        if dragStartZoom == nil {
                            dragStartZoom = start
                        }
                        let octaveOffset = -value.translation.width / 92
                        let proposed = start * CGFloat(
                            pow(2, Double(octaveOffset))
                        )
                        onZoomChange(
                            min(maximumZoom, max(minimumZoom, proposed))
                        )
                    }
                    .onEnded { _ in
                        dragStartZoom = nil
                        onInteractionEnd()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("정밀 확대 조절")
            .accessibilityValue(factorTitle(zoom, includesX: true))
            .accessibilityAdjustableAction { direction in
                let step: CGFloat = direction == .increment ? 1.1 : 0.9
                onZoomChange(min(maximumZoom, max(minimumZoom, zoom * step)))
            }
        }
        .clipped()
    }

    private func focalLengthTitle(_ factor: CGFloat) -> String {
        if factor < 0.75 {
            return "13 MM"
        }
        let millimeters = factor >= 4
            ? Int((factor * 24 / 10).rounded() * 10)
            : Int((factor * 24).rounded())
        return "\(millimeters) MM"
    }

    private func point(
        center: CGPoint,
        radius: CGFloat,
        degrees: Double
    ) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(cos(radians)),
            y: center.y + radius * CGFloat(sin(radians))
        )
    }

    private func factorTitle(
        _ factor: CGFloat,
        includesX: Bool
    ) -> String {
        let value: String
        if abs(factor - 0.5) < 0.01 {
            value = ".5"
        } else if abs(factor.rounded() - factor) < 0.05 {
            value = "\(Int(factor.rounded()))"
        } else {
            value = String(format: "%.1f", Double(factor))
        }
        return includesX ? "\(value)x" : value
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

private struct AiShotPreviewView: UIViewRepresentable {
    let camera: AiShotCameraController

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.videoPreviewLayer.session = camera.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        camera.attachPreviewLayer(view.videoPreviewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.videoPreviewLayer.session = camera.session
        camera.attachPreviewLayer(uiView.videoPreviewLayer)
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

struct AiShotResult: Equatable {
    let url: URL
    let triggerTime: Double
}

private struct AiShotVisualFrame {
    let time: CFTimeInterval
    let cells: [Double]
    let averageBrightness: Double
}

private struct AiShotVisualSignal {
    let time: CFTimeInterval
    let score: Double
}

final class AiShotCameraController: NSObject, ObservableObject,
    @unchecked Sendable
{
    private static let captureRenderSize = CGSize(width: 1080, height: 1440)
    private static let visualAnalysisInterval: CFTimeInterval = 0.22
    private static let readyPromptSuppressionDuration: CFTimeInterval = 1.05
    private static let defaultDisplayZoomFactor: CGFloat = 1

    private final class ExportSessionBox: @unchecked Sendable {
        let exporter: AVAssetExportSession

        init(_ exporter: AVAssetExportSession) {
            self.exporter = exporter
        }
    }

    let session = AVCaptureSession()

    @Published private(set) var statusText = "준비 중"
    @Published private(set) var soundLevel = 0.0
    @Published private(set) var isReadyForTrigger = false
    @Published private(set) var isTriggered = false
    @Published private(set) var capturePhase = AiShotPhase.detecting
    @Published private(set) var saveProgress = 0.0
    @Published private(set) var preparationProgress = 0.0
    @Published private(set) var captureSaveProgressWeight =
        AiShotDurationPreset.normal.saveProgressWeight
    @Published private(set) var captureAnimationDuration =
        AiShotDurationPreset.normal.fullCycle
    @Published private(set) var captureAnimationSequence = 0
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var minimumZoomFactor: CGFloat = 1
    @Published private(set) var maximumZoomFactor: CGFloat = 5
    @Published private(set) var lensZoomFactors: [CGFloat] = [0.5, 1, 2, 4, 8]
    @Published private(set) var isSwitchingCamera = false
    @Published var completedCapture: AiShotResult?

    private let sessionQueue = DispatchQueue(
        label: "hanclip.aiShot.session"
    )
    private let audioQueue = DispatchQueue(label: "hanclip.aiShot.audio")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var activeCameraPosition: AVCaptureDevice.Position = .back
    private var activeDisplayZoomMultiplier: CGFloat = 1
    private var pendingCameraPosition: AVCaptureDevice.Position?
    private var outputURL: URL?
    private var recordingStartTime: CFTimeInterval?
    private var triggerTime: Double?
    private var baseline = 0.008
    private var recentLevel = 0.008
    private var visualBaseline = 0.04
    private var lastVisualFrame: AiShotVisualFrame?
    private var latestVisualSignal = AiShotVisualSignal(time: 0, score: 0)
    private var lastVisualAnalysisTime: CFTimeInterval = 0
    private var didRequestStop = false
    private var didAnnounceReady = false
    private var readyPromptSuppressionUntil: CFTimeInterval = 0
    private var isActive = false
    private var isRecoveringFromInterruption = false
    private var discardNextRecordingResult = false
    private var sensitivity = AiShotSensitivity.automatic
    private var durationPreset = AiShotDurationPreset.normal
    private var activeDurationPreset: AiShotDurationPreset?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var captureRotationObservation: NSKeyValueObservation?
    private var captureRotationAngle: CGFloat = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() async {
        let allowed = await requestPermissions()
        guard allowed else {
            updateStatus("권한 필요")
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

    fileprivate func attachPreviewLayer(
        _ previewLayer: AVCaptureVideoPreviewLayer
    ) {
        guard self.previewLayer !== previewLayer else { return }
        self.previewLayer = previewLayer
        guard let device = rotationCoordinator?.device else { return }
        let angle = installRotationCoordinator(for: device)
        updateCaptureRotationAngle(angle)
    }

    private func installRotationCoordinator(
        for device: AVCaptureDevice
    ) -> CGFloat {
        let install = { [self] in
            let coordinator = AVCaptureDevice.RotationCoordinator(
                device: device,
                previewLayer: previewLayer
            )
            rotationCoordinator = coordinator

            previewRotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                guard let connection = self?.previewLayer?.connection else {
                    return
                }
                let angle = coordinator
                    .videoRotationAngleForHorizonLevelPreview
                guard connection.isVideoRotationAngleSupported(angle) else {
                    return
                }
                connection.videoRotationAngle = angle
            }

            captureRotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelCapture,
                options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                self?.updateCaptureRotationAngle(
                    coordinator.videoRotationAngleForHorizonLevelCapture
                )
            }

            return coordinator.videoRotationAngleForHorizonLevelCapture
        }

        if Thread.isMainThread {
            return install()
        }
        return DispatchQueue.main.sync(execute: install)
    }

    private func updateCaptureRotationAngle(_ angle: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureRotationAngle = angle
            self.applyCaptureRotationAngle()
        }
    }

    private func applyCaptureRotationAngle() {
        guard let connection = movieOutput.connection(with: .video),
              connection.isVideoRotationAngleSupported(captureRotationAngle)
        else { return }
        connection.videoRotationAngle = captureRotationAngle
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            self?.beginSessionRecovery()
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            self?.finishSessionRecovery()
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            guard let self, self.isActive else { return }
            self.beginSessionRecovery()
            self.finishSessionRecovery()
        }
    }

    private func beginSessionRecovery() {
        guard isActive else { return }
        isRecoveringFromInterruption = true
        discardNextRecordingResult = movieOutput.isRecording
        triggerTime = nil
        didRequestStop = false

        DispatchQueue.main.async {
            self.statusText = "준비 중"
            self.isReadyForTrigger = false
            self.isTriggered = false
            self.capturePhase = .detecting
            self.saveProgress = 0
            self.preparationProgress = 0
        }

        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
    }

    private func finishSessionRecovery() {
        guard isActive else { return }
        if !session.isRunning {
            session.startRunning()
        }
        isRecoveringFromInterruption = false
        if !movieOutput.isRecording {
            startRecording()
        }
    }

    func markCompletedCaptureHandled(_ capture: AiShotResult) {
        DispatchQueue.main.async {
            guard self.completedCapture == capture else { return }
            self.completedCapture = nil
        }
    }

    fileprivate func setSensitivity(_ sensitivity: AiShotSensitivity) {
        audioQueue.async { [weak self] in
            self?.sensitivity = sensitivity
        }
    }

    fileprivate func setDurationPreset(_ preset: AiShotDurationPreset) {
        audioQueue.async { [weak self] in
            self?.durationPreset = preset
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, self.isActive, self.pendingCameraPosition == nil
            else { return }

            let isFinishingTriggeredCapture = self.triggerTime != nil
            self.pendingCameraPosition = self.activeCameraPosition == .back
                ? .front
                : .back
            DispatchQueue.main.async {
                self.isSwitchingCamera = true
                if !isFinishingTriggeredCapture {
                    self.isReadyForTrigger = false
                    self.statusText = "전환 중"
                }
            }

            if self.movieOutput.isRecording {
                if !isFinishingTriggeredCapture {
                    self.movieOutput.stopRecording()
                }
            } else {
                self.finishCameraSwitchAndRestart()
            }
        }
    }

    func setZoom(_ factor: Double) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            let displayZoom = CGFloat(factor)
            let rawZoom = displayZoom / self.activeDisplayZoomMultiplier
            let zoom = min(
                device.maxAvailableVideoZoomFactor,
                max(device.minAvailableVideoZoomFactor, rawZoom)
            )

            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = zoom
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.zoomFactor = zoom
                        * self.activeDisplayZoomMultiplier
                }
            } catch {
                self.updateStatus("줌 조절 불가")
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
            guard elapsed >= self.durationPreset.beforeShot else { return }

            self.activeDurationPreset = self.durationPreset
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
            session.sessionPreset = .inputPriority

            guard let videoDevice = cameraDevice(position: .back) else {
                throw CameraConfigurationError.cameraUnavailable
            }
            configureFourByThreeFormat(for: videoDevice)
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

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: audioQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()
            captureRotationAngle = installRotationCoordinator(
                for: videoDevice
            )
            applyCaptureRotationAngle()
            configureDefaultZoom(for: videoDevice)
            publishCameraState(for: videoDevice)
            isActive = true
            session.startRunning()
            startRecording()
        } catch {
            session.commitConfiguration()
            updateStatus("시작 불가")
        }
    }

    private enum CameraConfigurationError: Error {
        case cameraUnavailable
        case cannotAddInput
    }

    private func cameraDevice(
        position: AVCaptureDevice.Position
    ) -> AVCaptureDevice? {
        guard position == .back else {
            return AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: position
            )
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .back
        )
        let priority: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        return priority.lazy.compactMap { type in
            discovery.devices.first { $0.deviceType == type }
        }.first
    }

    private func configureFourByThreeFormat(for device: AVCaptureDevice) {
        let targetArea = 1920.0 * 1440.0
        let candidates = device.formats.compactMap { format -> (
            format: AVCaptureDevice.Format,
            area: Double
        )? in
            let dimensions = CMVideoFormatDescriptionGetDimensions(
                format.formatDescription
            )
            guard dimensions.height > 0 else { return nil }

            let aspectRatio = Double(dimensions.width)
                / Double(dimensions.height)
            guard abs(aspectRatio - (4.0 / 3.0)) < 0.025 else {
                return nil
            }
            guard format.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
            }) else { return nil }

            return (
                format,
                Double(dimensions.width) * Double(dimensions.height)
            )
        }

        guard let selected = candidates.min(by: {
            abs(log($0.area / targetArea)) < abs(log($1.area / targetArea))
        }) else { return }

        do {
            try device.lockForConfiguration()
            device.activeFormat = selected.format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        } catch {
            updateStatus("3:4 설정 불가")
        }
    }

    private func configureDefaultZoom(for device: AVCaptureDevice) {
        let multiplier = displayZoomMultiplier(for: device)
        let rawZoom = Self.defaultDisplayZoomFactor / multiplier
        let zoom = min(
            device.maxAvailableVideoZoomFactor,
            max(device.minAvailableVideoZoomFactor, rawZoom)
        )

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = zoom
            device.unlockForConfiguration()
        } catch {
            updateStatus("줌 조절 불가")
        }
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
            updateStatus("카메라 사용 불가")
            startRecording()
            return
        }

        let previousInput = videoInput
        do {
            configureFourByThreeFormat(for: device)
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
            captureRotationAngle = installRotationCoordinator(for: device)
            applyCaptureRotationAngle()
            configureDefaultZoom(for: device)
            videoInput = newInput
            activeCameraPosition = position
            publishCameraState(for: device)
        } catch {
            updateStatus("카메라 전환 불가")
        }

        startRecording()
    }

    private func publishCameraState(for device: AVCaptureDevice) {
        let multiplier = displayZoomMultiplier(for: device)
        activeDisplayZoomMultiplier = multiplier
        let minimum = device.minAvailableVideoZoomFactor * multiplier
        let maximum = device.maxAvailableVideoZoomFactor * multiplier
        let zoom = min(
            maximum,
            max(minimum, device.videoZoomFactor * multiplier)
        )
        let factors = lensZoomFactors(for: device, multiplier: multiplier)

        DispatchQueue.main.async {
            self.cameraPosition = device.position
            self.minimumZoomFactor = minimum
            self.maximumZoomFactor = maximum
            self.zoomFactor = zoom
            self.lensZoomFactors = factors
        }
    }

    private func displayZoomMultiplier(
        for device: AVCaptureDevice
    ) -> CGFloat {
        if #available(iOS 18.0, *) {
            return device.displayVideoZoomFactorMultiplier
        }

        guard let wideIndex = device.constituentDevices.firstIndex(where: {
            $0.deviceType == .builtInWideAngleCamera
        }), wideIndex > 0 else { return 1 }
        let switchIndex = wideIndex - 1
        guard device.virtualDeviceSwitchOverVideoZoomFactors.indices
            .contains(switchIndex)
        else { return 1 }
        let wideSwitch = CGFloat(
            truncating: device.virtualDeviceSwitchOverVideoZoomFactors[
                switchIndex
            ]
        )
        return wideSwitch > 0 ? 1 / wideSwitch : 1
    }

    private func lensZoomFactors(
        for device: AVCaptureDevice,
        multiplier: CGFloat
    ) -> [CGFloat] {
        let minimum = device.minAvailableVideoZoomFactor * multiplier
        let maximum = device.maxAvailableVideoZoomFactor * multiplier
        let standardFactors: [CGFloat] = [0.5, 1, 2, 4, 8]
        return standardFactors.filter {
            $0 >= minimum - 0.05 && $0 <= maximum + 0.05
        }
    }

    private func startRecording() {
        guard isActive, session.isRunning, !movieOutput.isRecording else {
            return
        }
        applyCaptureRotationAngle()
        let continuesCaptureCycle = didRequestStop
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        outputURL = url
        recordingStartTime = CACurrentMediaTime()
        triggerTime = nil
        activeDurationPreset = nil
        didRequestStop = false
        didAnnounceReady = false
        readyPromptSuppressionUntil = 0
        baseline = 0.008
        recentLevel = 0.008
        resetVisualAnalysis()

        updateStatus("준비 중")
        DispatchQueue.main.async {
            self.isReadyForTrigger = false
            self.capturePhase = .detecting
            if !continuesCaptureCycle {
                self.isTriggered = false
                self.saveProgress = 0
            }
            self.preparationProgress = 0
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
        let beforeShot = durationPreset.beforeShot
        let baselineWeight = elapsed < beforeShot
            ? 0.04
            : 0.012
        baseline = baseline * (1 - baselineWeight)
            + max(0.002, baselineSample) * baselineWeight
        recentLevel = recentLevel * 0.72 + max(0.002, score) * 0.28
        updateLevel(score)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.preparationProgress = min(
                1,
                elapsed / beforeShot
            )
            self.isReadyForTrigger = elapsed >= beforeShot
        }

        guard elapsed >= beforeShot else { return }
        if !didAnnounceReady {
            didAnnounceReady = true
            readyPromptSuppressionUntil = elapsed
                + Self.readyPromptSuppressionDuration
            updateStatus("")
            DispatchQueue.main.async {
                self.isTriggered = false
            }
        }

        let decision = AudioImpactClassifier.detectImpact(
            metrics: metrics,
            baseline: baseline,
            previousRecentLevel: previousRecentLevel,
            sensitivity: sensitivity.audioImpactSensitivity
        )
        let visualScore = AudioImpactClassifier
            .currentModelVersion
            .supportsRealtimeVisualAssist
            ? recentVisualScore(at: elapsed)
            : 0
        let isVisuallySupportedImpact = visualScore >= 0.62
            && decision.confidence + visualScore * 0.32 >= 0.96
            && score >= max(0.04, baseline * 1.45)
        let isInsideReadyPromptWindow = elapsed < readyPromptSuppressionUntil
        let isClearlyPhysicalImpact = visualScore >= 0.5
            && score >= max(0.16, baseline * 2.4)
            && metrics.peak >= 0.25
        let isAudioTriggerAllowed = decision.isTriggered
            && (!isInsideReadyPromptWindow || isClearlyPhysicalImpact)
        let isVisualTriggerAllowed = isVisuallySupportedImpact
            && (!isInsideReadyPromptWindow || isClearlyPhysicalImpact)
        guard isAudioTriggerAllowed || isVisualTriggerAllowed else {
            return
        }

        activeDurationPreset = durationPreset
        triggerTime = elapsed
        requestStopAfterTrigger()
    }

    private func soundMetrics(
        from sampleBuffer: CMSampleBuffer
    ) -> AudioImpactMetrics {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription =
                CMAudioFormatDescriptionGetStreamBasicDescription(format)
        else {
            return AudioImpactMetrics(rms: 0, peak: 0, crossingRate: 0)
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
            return AudioImpactMetrics(rms: 0, peak: 0, crossingRate: 0)
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
        return AudioImpactMetrics(
            rms: min(1, rms),
            peak: min(1, peak),
            crossingRate: crossingRate
        )
    }

    private func resetVisualAnalysis() {
        lastVisualFrame = nil
        latestVisualSignal = AiShotVisualSignal(time: 0, score: 0)
        lastVisualAnalysisTime = 0
        visualBaseline = 0.04
    }

    private func recentVisualScore(at elapsed: CFTimeInterval) -> Double {
        guard elapsed - latestVisualSignal.time <= 0.75 else { return 0 }
        return latestVisualSignal.score
    }

    private func handleVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard let recordingStartTime, triggerTime == nil else { return }
        let elapsed = CACurrentMediaTime() - recordingStartTime
        guard elapsed - lastVisualAnalysisTime
            >= Self.visualAnalysisInterval
        else { return }
        lastVisualAnalysisTime = elapsed

        guard let frame = visualFrame(
            from: sampleBuffer,
            elapsed: elapsed
        ) else { return }

        defer {
            lastVisualFrame = frame
        }
        guard let previous = lastVisualFrame,
              previous.cells.count == frame.cells.count
        else { return }

        var motion = 0.0
        for index in frame.cells.indices {
            motion += abs(frame.cells[index] - previous.cells[index])
        }
        motion /= Double(max(1, frame.cells.count))

        let brightnessChange = abs(
            frame.averageBrightness - previous.averageBrightness
        )
        let rawVisualEnergy = motion * 2.6 + brightnessChange * 1.4
        visualBaseline = visualBaseline * 0.92
            + min(rawVisualEnergy, max(0.015, visualBaseline * 1.45)) * 0.08
        let contrast = rawVisualEnergy / max(0.018, visualBaseline)
        let score = min(
            1,
            max(0, contrast - 1) * 0.28
                + min(1, motion * 4.0) * 0.48
                + min(1, brightnessChange * 3.0) * 0.24
        )
        latestVisualSignal = AiShotVisualSignal(time: elapsed, score: score)
    }

    private func visualFrame(
        from sampleBuffer: CMSampleBuffer,
        elapsed: CFTimeInterval
    ) -> AiShotVisualFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer)
            == kCVPixelFormatType_32BGRA,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        let gridWidth = 8
        let gridHeight = 8
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        var cells: [Double] = []
        cells.reserveCapacity(gridWidth * gridHeight)
        var brightnessTotal = 0.0

        for yCell in 0..<gridHeight {
            let y = min(
                height - 1,
                max(0, (yCell * height + height / 2) / gridHeight)
            )
            for xCell in 0..<gridWidth {
                let x = min(
                    width - 1,
                    max(0, (xCell * width + width / 2) / gridWidth)
                )
                let offset = y * bytesPerRow + x * 4
                let blue = Double(bytes[offset])
                let green = Double(bytes[offset + 1])
                let red = Double(bytes[offset + 2])
                let brightness = (
                    red * 0.299 + green * 0.587 + blue * 0.114
                ) / 255.0
                cells.append(brightness)
                brightnessTotal += brightness
            }
        }

        return AiShotVisualFrame(
            time: elapsed,
            cells: cells,
            averageBrightness: brightnessTotal / Double(max(1, cells.count))
        )
    }

    private func requestStopAfterTrigger() {
        guard !didRequestStop else { return }
        didRequestStop = true
        let timing = activeDurationPreset ?? durationPreset

        DispatchQueue.main.async {
            self.isTriggered = true
            self.statusText = ""
            self.capturePhase = .detected
            self.saveProgress = 0
            self.preparationProgress = 0
            self.captureSaveProgressWeight = timing.saveProgressWeight
            self.captureAnimationDuration = timing.fullCycle
            self.captureAnimationSequence += 1
            withAnimation(.linear(duration: timing.afterShot)) {
                self.saveProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard self.isTriggered else { return }
            self.capturePhase = .saving
        }

        sessionQueue.asyncAfter(
            deadline: .now() + timing.afterShot
        ) { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }

        sessionQueue.asyncAfter(
            deadline: .now() + timing.afterShot + 4
        ) { [weak self] in
            guard let self, self.isActive, self.triggerTime != nil,
                  self.movieOutput.isRecording
            else { return }
            self.beginSessionRecovery()
            self.finishSessionRecovery()
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

    private static func trimCapture(
        at sourceURL: URL,
        triggerTime: Double,
        timing: AiShotDurationPreset
    ) async throws -> AiShotResult {
        let asset = AVURLAsset(url: sourceURL)
        let assetDuration = try await asset.load(.duration)
        let duration = assetDuration.seconds
        let start = max(0, triggerTime - timing.beforeShot)
        let end = min(duration, triggerTime + timing.afterShot)
        guard end - start >= 0.5 else {
            throw AiShotExportError.invalidTimeRange
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw AiShotExportError.cannotCreateExporter
        }

        exporter.outputURL = destination
        exporter.outputFileType = .mov
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
        )

        guard let videoTrack = try await asset.loadTracks(
            withMediaType: .video
        ).first else {
            throw AiShotExportError.videoTrackUnavailable
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = captureRenderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: assetDuration
        )
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(
            assetTrack: videoTrack
        )
        layerInstruction.setTransform(
            aspectFillTransform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                renderSize: captureRenderSize
            ),
            at: .zero
        )
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        exporter.videoComposition = videoComposition
        let exporterBox = ExportSessionBox(exporter)

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            exporterBox.exporter.exportAsynchronously {
                switch exporterBox.exporter.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(
                        throwing: exporterBox.exporter.error
                            ?? AiShotExportError.exportFailed
                    )
                default:
                    continuation.resume(
                        throwing: AiShotExportError.exportFailed
                    )
                }
            }
        }

        try? FileManager.default.removeItem(at: sourceURL)
        return AiShotResult(
            url: destination,
            triggerTime: triggerTime - start
        )
    }

    private static func aspectFillTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let originalRect = CGRect(origin: .zero, size: naturalSize)
        let orientedRect = originalRect.applying(preferredTransform)
        let orientedSize = CGSize(
            width: abs(orientedRect.width),
            height: abs(orientedRect.height)
        )
        let scale = max(
            renderSize.width / max(1, orientedSize.width),
            renderSize.height / max(1, orientedSize.height)
        )
        let scaled = preferredTransform.concatenating(
            CGAffineTransform(scaleX: scale, y: scale)
        )
        let scaledRect = originalRect.applying(scaled)
        let translation = CGAffineTransform(
            translationX:
                (renderSize.width - scaledRect.width) / 2 - scaledRect.minX,
            y:
                (renderSize.height - scaledRect.height) / 2 - scaledRect.minY
        )
        return scaled.concatenating(translation)
    }

    private enum AiShotExportError: Error {
        case invalidTimeRange
        case cannotCreateExporter
        case videoTrackUnavailable
        case exportFailed
    }
}

extension AiShotCameraController: AVCaptureAudioDataOutputSampleBufferDelegate,
    AVCaptureVideoDataOutputSampleBufferDelegate
{
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output === audioOutput {
            handleAudioSample(sampleBuffer)
        } else if output === videoOutput {
            handleVideoSample(sampleBuffer)
        }
    }
}

extension AiShotCameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        guard isActive else {
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        if discardNextRecordingResult {
            discardNextRecordingResult = false
            try? FileManager.default.removeItem(at: outputFileURL)
            sessionQueue.async { [weak self] in
                guard let self, self.isActive,
                      !self.isRecoveringFromInterruption,
                      self.session.isRunning,
                      !self.movieOutput.isRecording
                else { return }
                self.startRecording()
            }
            return
        }

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
        let captureTiming = activeDurationPreset ?? durationPreset

        guard error == nil else {
            sessionQueue.async { [weak self] in
                guard let self, self.isActive, self.session.isRunning else {
                    return
                }
                self.startRecording()
            }
            return
        }

        Task { [weak self] in
            guard let self else {
                try? FileManager.default.removeItem(at: outputFileURL)
                return
            }

            do {
                let capture = try await Self.trimCapture(
                    at: outputFileURL,
                    triggerTime: triggerTime,
                    timing: captureTiming
                )
                await MainActor.run {
                    self.completedCapture = capture
                }
            } catch {
                try? FileManager.default.removeItem(at: outputFileURL)
                self.updateStatus("저장 불가")
            }
        }

        sessionQueue.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.isActive, self.session.isRunning else { return }
            if self.pendingCameraPosition != nil {
                self.finishCameraSwitchAndRestart()
            } else {
                self.startRecording()
            }
        }
    }
}
