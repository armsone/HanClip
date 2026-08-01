import SwiftUI

struct ClipRow: View {
    let position: Int?
    @Binding var clip: ClipItem
    let defaultDuration: Double
    let childSegmentCount: Int
    let childSegmentDuration: Double
    let canShowVideoSegmentSwitch: Bool
    let onSelectVideoSegmentMode: (VideoSegmentMode) -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            positionCell

            HStack(spacing: 14) {
                Button(action: onSelect) {
                    Image(uiImage: clip.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(alignment: .topTrailing) {
                            if clip.isLivePhoto {
                                Image(systemName: "livephoto")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(.black.opacity(0.65), in: Circle())
                                    .padding(3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .offset(x: clip.isVideoSegmentChild ? 10 : 0)
                .buttonStyle(.plain)
                .accessibilityLabel("에디터 열기")

                VStack(alignment: .leading, spacing: 2) {
                    Button(action: onSelect) {
                        HStack {
                            Text(primaryTimeText)
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(HanClipTheme.defaultTextBlack)
                                .offset(x: 8, y: 6)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("에디터 열기")

                    HStack(spacing: 8) {
                        if clip.isLivePhoto {
                            HStack(spacing: 7) {
                                Button(action: onSelect) {
                                    Image(systemName: "livephoto")
                                        .font(.system(size: 16, weight: .semibold))
                                        .opacity(0.60)
                                        .foregroundStyle(
                                            HanClipTheme.defaultTextBlack
                                        )
                                        .frame(
                                            width: 28,
                                            height: 24,
                                            alignment: .leading
                                        )
                                        .offset(x: 10)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Live Photo 에디터 열기")

                                LivePhotoModeSegmentedControl(
                                    mode: $clip.livePhotoMode,
                                    tint: HanClipTheme.secondary,
                                    width: 112,
                                    height: 30
                                )
                                .onChange(of: clip.livePhotoMode) {
                                    _,
                                    selectedMode in
                                    if selectedMode == .motion {
                                        clip.duration = clip.sourceDuration
                                            ?? clip.livePhotoDuration
                                            ?? clip.duration
                                    } else {
                                        clip.photoDuration = defaultDuration
                                        clip.duration = defaultDuration
                                    }
                                }
                            }

                            editorAreaButton
                        } else {
                            if clip.isVideoClip {
                                HStack(spacing: 7) {
                                    Button(action: onSelect) {
                                        FilmCameraIcon()
                                            .frame(width: 21, height: 17)
                                            .opacity(0.60)
                                            .foregroundStyle(
                                                HanClipTheme.defaultTextBlack
                                            )
                                            .frame(
                                                width: 28,
                                                height: 24,
                                                alignment: .leading
                                            )
                                            .offset(x: 10)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("영상 클립 에디터 열기")

                                    if canShowVideoSegmentSwitch {
                                        VideoSegmentModeSegmentedControl(
                                            mode: videoSegmentModeBinding,
                                            tint: HanClipTheme.secondary,
                                            width: 102,
                                            height: 30
                                        )

                                        if clip.isVideoSegmentParent {
                                            Text("(\(childSegmentCount)개)")
                                                .font(
                                                    .system(
                                                        size: 12,
                                                        weight: .semibold
                                                    )
                                                )
                                                .foregroundStyle(
                                                    HanClipTheme.secondary
                                                )
                                                .monospacedDigit()
                                        }
                                    }
                                }
                            } else {
                                Button(action: onSelect) {
                                    Image(systemName: "photo.fill")
                                        .font(
                                            .system(
                                                size: 16
                                            )
                                        )
                                        .opacity(0.60)
                                        .foregroundStyle(
                                            HanClipTheme.defaultTextBlack
                                        )
                                        .frame(
                                            width: 96,
                                            height: 24,
                                            alignment: .leading
                                        )
                                        .offset(x: 8, y: 4)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("사진 에디터 열기")
                            }

                            if clip.isVideoSegmentParent {
                                rowFillSpacer
                            } else {
                                editorAreaButton
                            }
                        }

                        HStack(spacing: 32) {
                            if clip.isVideoSegmentParent {
                                EmptyView()
                            } else if clip.isVideoClip {
                                VideoDurationStepper(clip: $clip)
                            } else {
                                CompactDurationStepper(
                                    value: durationBinding,
                                    range: 0.5...30,
                                    step: 0.5,
                                    isSmall: true
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(minHeight: 62)
    }

    private var positionText: String {
        if clip.isVideoSegmentParent {
            return "·"
        }
        return "\(position ?? 0)"
    }

    private var positionAccessibilityLabel: String {
        if clip.isVideoSegmentParent {
            return "모영상"
        }
        return "\(position ?? 0)번째 클립"
    }

    private var positionCell: some View {
        Text(positionText)
            .font(.system(size: 14).monospacedDigit())
            .foregroundStyle(HanClipTheme.primary)
            .frame(width: 18, alignment: .center)
            .frame(height: 62)
            .background(alignment: .trailing) {
                if clip.isVideoSegmentChild {
                    Rectangle()
                        .fill(HanClipTheme.secondary.opacity(0.16))
                        .frame(width: 22)
                }
            }
            .accessibilityLabel(positionAccessibilityLabel)
    }

    private var primaryTimeText: String {
        if clip.isVideoSegmentParent {
            return String(
                format: "%@ / 전체 %@",
                durationText(childSegmentDuration),
                totalSourceDurationText
            )
        }
        if clip.isLivePhoto, clip.livePhotoMode == .motion {
            return String(
                format: "%@ / 전체 %@",
                durationText(clip.duration),
                totalSourceDurationText
            )
        }
        if clip.isVideoClip {
            return String(
                format: "%@ / 전체 %@",
                durationText(clip.duration),
                totalSourceDurationText
            )
        }
        return String(format: "%.1f초", clip.duration)
    }

    private var totalSourceDurationText: String {
        durationText(clip.sourceDuration ?? clip.duration)
    }

    private func durationText(_ seconds: Double) -> String {
        let tenths = max(Int((seconds * 10).rounded()), 0)
        let minutes = tenths / 600
        let remainingSeconds = Double(tenths % 600) / 10
        return String(format: "%d:%04.1f", minutes, remainingSeconds)
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { clip.duration },
            set: { duration in
                clip.duration = duration

                if clip.isLivePhoto, clip.livePhotoMode == .motion {
                    return
                } else {
                    clip.photoDuration = duration
                }
            }
        )
    }

    private var videoSegmentModeBinding: Binding<VideoSegmentMode> {
        Binding(
            get: { clip.videoSegmentMode },
            set: { mode in
                clip.videoSegmentMode = mode
                onSelectVideoSegmentMode(mode)
            }
        )
    }

    private var editorAreaButton: some View {
        Button(action: onSelect) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("에디터 열기")
    }

    private var rowFillSpacer: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct FilmCameraIcon: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let reelSize = height * 0.56
            let bodyHeight = height * 0.56
            let bodyY = height * 0.40

            ZStack {
                CameraReel()
                    .fill(style: FillStyle(eoFill: true))
                    .frame(width: reelSize, height: reelSize)
                    .position(x: width * 0.26, y: height * 0.26)

                CameraReel()
                    .fill(style: FillStyle(eoFill: true))
                    .frame(width: reelSize, height: reelSize)
                    .position(x: width * 0.58, y: height * 0.26)

                RoundedRectangle(cornerRadius: height * 0.13)
                    .frame(
                        width: width * 0.64,
                        height: bodyHeight
                    )
                    .position(x: width * 0.38, y: bodyY + bodyHeight / 2)

                CameraLens()
                    .frame(width: width * 0.30, height: bodyHeight * 0.86)
                    .position(x: width * 0.80, y: bodyY + bodyHeight / 2)
            }
        }
        .aspectRatio(21 / 17, contentMode: .fit)
    }
}

struct CameraReel: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)

        let holeSize = min(rect.width, rect.height) * 0.34
        let holeRect = CGRect(
            x: rect.midX - holeSize / 2,
            y: rect.midY - holeSize / 2,
            width: holeSize,
            height: holeSize
        )
        path.addEllipse(in: holeRect)

        return path
    }
}

struct CameraLens: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.82, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.18))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX * 0.82, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct VideoDurationStepper: View {
    @Binding var clip: ClipItem

    private var sourceDuration: Double {
        max(0.5, clip.sourceDuration ?? clip.duration)
    }

    private var canDecrease: Bool {
        clip.duration - 1 >= 0.5
    }

    private var canIncrease: Bool {
        clip.duration + 1 <= sourceDuration + 0.000_1
    }

    var body: some View {
        HStack(spacing: 0) {
            stepButton(
                systemImage: "minus",
                accessibilityLabel: "클립 시간을 1초 줄이기",
                isEnabled: canDecrease
            ) {
                adjustDuration(by: -1)
            }

            Rectangle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 1, height: 12)

            stepButton(
                systemImage: "plus",
                accessibilityLabel: "클립 시간을 1초 늘리기",
                isEnabled: canIncrease
            ) {
                adjustDuration(by: 1)
            }
        }
        .frame(width: 80, height: 22)
        .background(HanClipTheme.secondary, in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private func stepButton(
        systemImage: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(HanClipTheme.onSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .frame(width: 38, height: 22)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func adjustDuration(by change: Double) {
        let previousDuration = clip.duration
        let previousCenter = clip.trimStart + previousDuration / 2
        let newDuration = min(
            sourceDuration,
            max(0.5, previousDuration + change)
        )
        let centeredStart = previousCenter - newDuration / 2

        clip.trimStart = max(
            0,
            min(sourceDuration - newDuration, centeredStart)
        )
        clip.duration = newDuration
        clip.photoDuration = newDuration
    }
}

struct LivePhotoModeSegmentedControl: View {
    @Binding var mode: LivePhotoMode
    let tint: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                segment(
                    mode: .still,
                    title: "포토",
                    systemImage: "photo"
                )

                segment(
                    mode: .motion,
                    title: "Live",
                    systemImage: "livephoto"
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        mode = value.location.x < proxy.size.width / 2
                            ? .still
                            : .motion
                    }
            )
        }
        .padding(2)
        .frame(width: width, height: height)
        .background(
            tint.opacity(0.12),
            in: RoundedRectangle(cornerRadius: height / 2)
        )
        .accessibilityElement(children: .contain)
    }

    private func segment(
        mode segmentMode: LivePhotoMode,
        title: String,
        systemImage: String
    ) -> some View {
        let isSelected = mode == segmentMode

        return HStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size: height <= 24 ? 9 : 10,
                        weight: .semibold
                    )
                )

            Text(title)
                .font(
                    .system(
                        size: height <= 24 ? 10 : 11,
                        weight: .semibold
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(isSelected ? .white : HanClipTheme.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: max(4, height / 2 - 2))
                    .fill(tint)
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct VideoSegmentModeSegmentedControl: View {
    @Binding var mode: VideoSegmentMode
    let tint: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                segment(
                    mode: .single,
                    title: VideoSegmentMode.single.rawValue,
                    systemImage: "film"
                )

                segment(
                    mode: .multiple,
                    title: VideoSegmentMode.multiple.rawValue,
                    systemImage: "film.stack"
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        mode = value.location.x < proxy.size.width / 2
                            ? .single
                            : .multiple
                    }
            )
        }
        .padding(2)
        .frame(width: width, height: height)
        .background(
            tint.opacity(0.12),
            in: RoundedRectangle(cornerRadius: height / 2)
        )
        .accessibilityElement(children: .contain)
    }

    private func segment(
        mode segmentMode: VideoSegmentMode,
        title: String,
        systemImage: String
    ) -> some View {
        let isSelected = mode == segmentMode

        return HStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size: height <= 24 ? 9 : 10,
                        weight: .semibold
                    )
                )

            Text(title)
                .font(
                    .system(
                        size: height <= 24 ? 10 : 12,
                        weight: .semibold
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(isSelected ? .white : HanClipTheme.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: max(4, height / 2 - 2))
                    .fill(tint)
            }
        }
        .accessibilityLabel("영상 세그먼트 \(title)")
    }
}

struct CompactDurationStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var isSmall = false
    var controlWidth: CGFloat = 80
    var controlHeight: CGFloat?
    var iconSize: CGFloat?

    private var resolvedHeight: CGFloat {
        controlHeight ?? (isSmall ? 22 : 30)
    }

    var body: some View {
        HStack(spacing: 0) {
            stepButton(
                systemImage: "minus",
                isEnabled: value > range.lowerBound
            ) {
                value = max(range.lowerBound, value - step)
            }

            Rectangle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 1, height: resolvedHeight * 0.55)

            stepButton(
                systemImage: "plus",
                isEnabled: value < range.upperBound
            ) {
                value = min(range.upperBound, value + step)
            }
        }
        .frame(width: controlWidth, height: resolvedHeight)
        .background(HanClipTheme.secondary, in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private func stepButton(
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size: iconSize ?? (isSmall ? 18 : 14),
                        weight: .bold
                    )
                )
                .foregroundStyle(HanClipTheme.onSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .frame(
            width: isSmall ? controlWidth / 2 - 2 : nil,
            height: isSmall ? resolvedHeight : nil
        )
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(systemImage == "plus" ? "시간 늘리기" : "시간 줄이기")
    }
}
