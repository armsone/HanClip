import SwiftUI

struct SimilarPhotoGroupPreviewItem {
    let id: UUID
    let thumbnail: UIImage
    let isIncluded: Bool
}

struct ClipRow: View {
    let position: Int?
    @Binding var clip: ClipItem
    let defaultDuration: Double
    let childSegmentCount: Int
    let childSegmentDuration: Double
    let canShowVideoSegmentSwitch: Bool
    let isSimilarPhotoGroupExpanded: Bool
    let onSelectVideoSegmentMode: (VideoSegmentMode) -> Void
    let onSelectSimilarPhotoGroupMode: (VideoSegmentMode) -> Void
    let onResetVideoSegments: () -> Void
    let onSelectParentClipPreview: () -> Void
    let onToggleSimilarPhotoGroup: () -> Void
    let onSetSimilarPhotoIncluded: (Bool) -> Void
    let similarPhotoGroupPreviewItems: [SimilarPhotoGroupPreviewItem]
    let displayAsSimilarPhotoChild: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            positionCell

            HStack(alignment: .center, spacing: 12) {
                thumbnailButton

                VStack(
                    alignment: .leading,
                    spacing: isChildRow ? 0.5 : 2
                ) {
                    Button(action: onSelect) {
                        HStack {
                            Text(primaryTimeText)
                                .font(
                                    .system(size: 12, weight: .semibold)
                                    .monospacedDigit()
                                )
                                .foregroundStyle(HanClipTheme.primaryText)
                                .padding(.leading, 8)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 16, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .offset(x: isChildRow ? 8 : 0, y: 3)
                    .buttonStyle(.plain)
                    .accessibilityLabel("편집 열기")

                    HStack(alignment: .center, spacing: 8) {
                        if clip.isLivePhoto {
                            HStack(spacing: 7) {
                                if displaysAsSimilarPhotoParent {
                                    Button(action: onSelect) {
                                        Image(systemName: "photo.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(
                                                segmentMediaIconGradient
                                            )
                                            .shadow(
                                                color: HanClipTheme.primary.opacity(0.05),
                                                radius: 1,
                                                y: 1
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
                                    .accessibilityLabel("묶음사진 편집 열기")

                                    SimilarPhotoGroupModeSegmentedControl(
                                        mode: videoSegmentModeBinding,
                                        tint: HanClipTheme.secondary,
                                        width: 90,
                                        height: 26
                                    )
                                } else if !displaysAsSimilarPhotoChild {
                                    Button(action: onSelect) {
                                        Image(systemName: "livephoto")
                                            .font(
                                                .system(
                                                    size: 16,
                                                    weight: .semibold
                                                )
                                            )
                                            .opacity(0.60)
                                            .foregroundStyle(
                                                HanClipTheme.mutedIcon
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
                                    .accessibilityLabel("Live Photo 편집 열기")

                                    LivePhotoModeSegmentedControl(
                                        mode: $clip.livePhotoMode,
                                        tint: HanClipTheme.secondary,
                                        width: 98,
                                        height: 26
                                    )
                                    .onChange(of: clip.livePhotoMode) {
                                        _,
                                        selectedMode in
                                        applyLivePhotoMode(selectedMode)
                                    }
                                } else {
                                    LivePhotoModeSegmentedControl(
                                        mode: $clip.livePhotoMode,
                                        tint: HanClipTheme.secondary,
                                        width: 98,
                                        height: 26
                                    )
                                    .onChange(of: clip.livePhotoMode) {
                                        _,
                                        selectedMode in
                                        applyLivePhotoMode(selectedMode)
                                    }
                                }
                            }
                            .offset(x: displaysAsSimilarPhotoChild ? 8 : 0)

                            editorAreaButton
                        } else {
                            if clip.isVideoClip {
                                HStack(spacing: 7) {
                                    Button(action: onSelect) {
                                        videoMediaIcon
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("영상 클립 편집 열기")

                                    if canShowVideoSegmentSwitch {
                                        VideoSegmentModeSegmentedControl(
                                            mode: videoSegmentModeBinding,
                                            tint: HanClipTheme.secondary,
                                            width: 96,
                                            height: 26
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
                                                    HanClipTheme.secondaryText
                                                )
                                                .monospacedDigit()
                                        }
                                    }
                                }
                                .frame(height: 30, alignment: .center)
                                .offset(x: clip.isVideoSegmentChild ? 8 : 0)
                            } else {
                                Button(action: onSelect) {
                                    Image(systemName: "photo.fill")
                                        .font(
                                            .system(
                                                size: 16
                                            )
                                        )
                                        .foregroundStyle(
                                            displaysAsSimilarPhotoParent
                                                ? segmentMediaIconGradient
                                                : mutedMediaIconGradient
                                        )
                                        .shadow(
                                            color: displaysAsSimilarPhotoParent
                                                ? HanClipTheme.primary.opacity(0.05)
                                                : Color.clear,
                                            radius: 1,
                                            y: 1
                                        )
                                        .frame(
                                            width: displaysAsSimilarPhotoParent
                                                ? 28
                                                : 96,
                                            height: 24,
                                            alignment: .leading
                                        )
                                        .offset(x: 8, y: 4)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    "사진 편집 열기"
                                )

                                if displaysAsSimilarPhotoParent {
                                    SimilarPhotoGroupModeSegmentedControl(
                                        mode: videoSegmentModeBinding,
                                        tint: HanClipTheme.secondary,
                                        width: 90,
                                        height: 26
                                    )
                                }
                            }

                            if isParentSummaryRow {
                                editorAreaButton
                            } else {
                                editorAreaButton
                            }
                        }

                        HStack(spacing: isParentSummaryRow ? 0 : 32) {
                            if isParentSummaryRow {
                                HStack(spacing: 8) {
                                    parentClipPreviewButton
                                    parentSegmentResetButton
                                }
                                .frame(width: 66, alignment: .trailing)
                            } else if clip.isVideoClip {
                                VideoDurationStepper(clip: $clip)
                            } else {
                                HStack(spacing: 8) {
                                    if displaysAsSimilarPhotoChild {
                                        SimilarPhotoExposureSegmentedControl(
                                            isIncluded: Binding(
                                                get: {
                                                    clip.isSimilarPhotoGroupRepresentative
                                                },
                                                set: { isIncluded in
                                                    onSetSimilarPhotoIncluded(
                                                        isIncluded
                                                    )
                                                }
                                            ),
                                            tint: HanClipTheme.secondary,
                                            width: 92,
                                            height: 26
                                        )
                                    }

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
                    .frame(height: 34, alignment: .center)
                }
                .frame(height: 52, alignment: .center)
            }
        }
        .frame(minHeight: 58, alignment: .center)
    }

    private var thumbnailButton: some View {
        Button(action: onSelect) {
            Group {
                if displaysAsSimilarPhotoParent {
                    similarPhotoBundleThumbnail
                } else {
                    standardThumbnail
                }
            }
            .contentShape(Rectangle())
        }
        .offset(x: isChildRow ? 12 : 0)
        .buttonStyle(.plain)
        .accessibilityLabel("편집 열기")
    }

    private var standardThumbnail: some View {
        Image(uiImage: clip.thumbnail)
            .resizable()
            .scaledToFill()
            .brightness(isParentSummaryRow ? 0.09 : 0)
            .saturation(isParentSummaryRow ? 1.12 : 1)
            .frame(
                width: isChildRow ? 52 : 58,
                height: isChildRow ? 50 : 54
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isChildRow
                            ? HanClipTheme.primary.opacity(0.24)
                            : Color.white.opacity(0.30),
                        lineWidth: isChildRow ? 1.2 : 0.8
                    )
            }
            .overlay(alignment: .topTrailing) {
                if clip.isLivePhoto,
                   !clip.isSimilarPhotoGroupMember {
                    Image(systemName: "livephoto")
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(.black.opacity(0.65), in: Circle())
                        .padding(3)
                }
            }
            .overlay {
                if isParentSummaryRow {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.13),
                            HanClipTheme.secondary.opacity(0.07),
                            HanClipTheme.primary.opacity(0.025)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .blendMode(.screen)
                }
            }
            .overlay {
                if isParentSummaryRow {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.025))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isParentSummaryRow {
                    summaryCountBadge
                }
            }
    }

    private var similarPhotoBundleThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            HanClipTheme.secondary.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            HanClipTheme.secondary.opacity(0.14),
                            lineWidth: 0.9
                        )
                }

            similarPhotoBundleContents

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .trim(from: 0.50, to: 1)
                .stroke(
                    HanClipTheme.secondary.opacity(0.16),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
                .frame(width: 50, height: 43)
                .rotationEffect(.degrees(180))
                .offset(y: 2)

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HanClipTheme.primary.opacity(0.38))
                .padding(5)
                .background(.ultraThinMaterial, in: Circle())
                .offset(x: -19, y: -15)
        }
        .frame(width: 58, height: 54)
        .overlay(alignment: .bottomTrailing) {
            summaryCountBadge
        }
    }

    private var similarPhotoBundleContents: some View {
        let items = similarPhotoGroupPreviewItems.isEmpty
            ? [
                SimilarPhotoGroupPreviewItem(
                    id: clip.id,
                    thumbnail: clip.thumbnail,
                    isIncluded: clip.isSimilarPhotoGroupRepresentative
                )
            ]
            : similarPhotoGroupPreviewItems
        let visibleItems = Array(items.prefix(3).enumerated())

        return ZStack {
            ForEach(visibleItems, id: \.element.id) { offset, item in
                let centerOffset = CGFloat(visibleItems.count - 1) / 2
                let xOffset = (CGFloat(offset) - centerOffset) * 9
                let yOffset = CGFloat(offset) * -2
                Image(uiImage: item.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(
                                item.isIncluded
                                    ? HanClipTheme.primary.opacity(0.28)
                                    : Color.white.opacity(0.32),
                                lineWidth: item.isIncluded ? 0.9 : 0.6
                            )
                    }
                    .overlay(alignment: .bottom) {
                        if item.isIncluded {
                            Text("사용")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(height: 11)
                                .background(
                                    HanClipTheme.primary.opacity(0.38),
                                    in: Capsule()
                                )
                                .offset(y: 5)
                        }
                    }
                    .shadow(
                        color: Color.black.opacity(0.08),
                        radius: 2,
                        y: 1
                    )
                    .rotationEffect(.degrees(Double(offset - 1) * 4))
                    .offset(x: xOffset, y: yOffset)
                    .zIndex(Double(offset))
            }
        }
        .frame(width: 50, height: 38)
    }

    private var summaryCountBadge: some View {
        Text("\(summaryChildCount)")
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
                HanClipTheme.primary.opacity(0.46),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        Color.white.opacity(0.18),
                        lineWidth: 0.8
                    )
            }
            .padding(5)
            .shadow(
                color: Color.black.opacity(0.08),
                radius: 2,
                y: 1
            )
    }

    private var parentClipPreviewButton: some View {
        ZStack {
            parentActionCircle

            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 17, weight: .semibold))

                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .bold))
                    .padding(3)
                    .background(.ultraThinMaterial, in: Circle())
                    .offset(x: 5, y: 4)
            }
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        HanClipTheme.primary.opacity(0.38),
                        HanClipTheme.secondary.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
                .shadow(
                    color: Color.clear,
                    radius: 0,
                    y: 1
                )
        }
        .frame(width: 30, height: 30, alignment: .center)
        .offset(y: -8)
        .contentShape(Circle())
        .onTapGesture(perform: onSelectParentClipPreview)
        .accessibilityLabel(
            clip.isSimilarPhotoGroupParent
                ? "묶음사진 편집 열기"
                : "모클립 편집 열기"
        )
    }

    private var parentSegmentResetButton: some View {
        Button(action: resetSummaryRow) {
            ZStack {
                parentActionCircle

                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(HanClipTheme.primary.opacity(0.38))
                    .shadow(
                        color: Color.clear,
                        radius: 0,
                        y: 1
                    )
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .offset(y: -8)
        .accessibilityLabel(
            clip.isSimilarPhotoGroupParent
                ? "자사진 선택 초기화"
                : "자클립 편집 초기화"
        )
    }

    private var parentActionCircle: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                HanClipTheme.background.opacity(0.70),
                                HanClipTheme.secondary.opacity(0.032)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        Color.white.opacity(0.025)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(Circle())
                .allowsHitTesting(false)
            }
            .overlay {
                Circle()
                    .stroke(
                        HanClipTheme.panelStroke.opacity(0.34),
                        lineWidth: 0.8
                    )
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 4.5, height: 4.5)
                    .blur(radius: 1)
                    .offset(x: 7, y: 6)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: Color.black.opacity(0.035),
                radius: 3,
                y: 2
            )
            .frame(width: 30, height: 30)
    }

    private var similarPhotoGroupToggleButton: some View {
        Button(action: onToggleSimilarPhotoGroup) {
            Image(
                systemName: isSimilarPhotoGroupExpanded
                    ? "rectangle.stack.badge.minus"
                    : "rectangle.stack.badge.plus"
            )
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(HanClipTheme.secondaryText.opacity(0.70))
            .frame(width: 32, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isSimilarPhotoGroupExpanded ? "비슷한 사진 접기" : "비슷한 사진 펼치기"
        )
    }

    private var positionText: String {
        if isParentSummaryRow {
            return "\(position ?? 0)"
        }
        if displaysAsSimilarPhotoChild {
            return ""
        }
        return "\(position ?? 0)"
    }

    private var positionAccessibilityLabel: String {
        if displaysAsSimilarPhotoParent {
            return "묶음사진"
        }
        if displaysAsSimilarPhotoChild {
            return "자사진"
        }
        if clip.isVideoSegmentParent {
            return "모클립"
        }
        return "\(position ?? 0)번째 클립"
    }

    private var positionCell: some View {
        Text(positionText)
            .font(
                .system(
                    size: 10,
                    weight: .regular,
                    design: .rounded
                )
                .monospacedDigit()
            )
            .foregroundStyle(
                isParentSummaryRow
                    ? HanClipTheme.primary.opacity(0.62)
                    : isChildRow
                        ? HanClipTheme.primary.opacity(0.50)
                        : HanClipTheme.primary.opacity(0.56)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 28, alignment: .center)
            .frame(height: 58)
            .background(alignment: .trailing) {
                if isChildRow {
                    ZStack {
                        Capsule()
                            .fill(HanClipTheme.primary.opacity(0.040))
                            .frame(width: 9, height: 58)
                            .offset(x: 20)

                        Capsule()
                            .fill(HanClipTheme.primary.opacity(0.16))
                            .frame(width: 2.5, height: 54)
                            .offset(x: 20)

                        Circle()
                            .fill(HanClipTheme.primary.opacity(0.38))
                            .frame(width: 5.5, height: 5.5)
                            .offset(x: 20)
                    }
                }
            }
            .zIndex(isChildRow ? 1 : 0)
            .accessibilityLabel(positionAccessibilityLabel)
    }

    private var primaryTimeText: String {
        if clip.isVideoSegmentParent {
            return String(
                format: "%@ / 전체 %@ / %d개",
                durationText(childSegmentDuration),
                totalSourceDurationText,
                childSegmentCount
            )
        }
        if displaysAsSimilarPhotoParent {
            return String(
                format: "%@ %d장 · %@ / 전체 %d개",
                clip.videoSegmentMode == .single ? "자동" : "수동",
                selectedSimilarPhotoCount,
                durationText(childSegmentDuration),
                clip.similarPhotoGroupCount
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
            if canShowVideoSegmentSwitch, childSegmentCount > 0 {
                return String(
                    format: "%@ / 전체 %@ / %d개",
                    durationText(clip.duration),
                    totalSourceDurationText,
                    childSegmentCount
                )
            }
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

    private func applyLivePhotoMode(_ selectedMode: LivePhotoMode) {
        if selectedMode == .motion {
            clip.duration = clip.sourceDuration
                ?? clip.livePhotoDuration
                ?? clip.duration
        } else {
            clip.photoDuration = defaultDuration
            clip.duration = defaultDuration
        }
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
                if displaysAsSimilarPhotoParent {
                    onSelectSimilarPhotoGroupMode(mode)
                } else {
                    onSelectVideoSegmentMode(mode)
                }
            }
        )
    }

    private var isParentSummaryRow: Bool {
        clip.isVideoSegmentParent || displaysAsSimilarPhotoParent
    }

    private var isChildRow: Bool {
        clip.isVideoSegmentChild || displaysAsSimilarPhotoChild
    }

    private var summaryChildCount: Int {
        displaysAsSimilarPhotoParent
            ? clip.similarPhotoGroupCount
            : childSegmentCount
    }

    private var selectedSimilarPhotoCount: Int {
        guard displaysAsSimilarPhotoParent else { return 0 }
        let count = similarPhotoGroupPreviewItems.filter(\.isIncluded).count
        return max(count, 1)
    }

    private func resetSummaryRow() {
        if displaysAsSimilarPhotoParent {
            clip.videoSegmentMode = .single
            onSelectSimilarPhotoGroupMode(.single)
        } else {
            onResetVideoSegments()
        }
    }

    private var editorAreaButton: some View {
        Button(action: onSelect) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("편집 열기")
    }

    private var rowFillSpacer: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var displaysAsSimilarPhotoParent: Bool {
        clip.isSimilarPhotoGroupParent && !displayAsSimilarPhotoChild
    }

    private var displaysAsSimilarPhotoChild: Bool {
        displayAsSimilarPhotoChild || clip.isSimilarPhotoGroupChild
    }

    private var videoMediaIcon: some View {
        Group {
            if clip.isVideoSegmentChild {
                Image(systemName: "movieclapper")
                    .font(.system(size: 18, weight: .semibold))
            } else {
                FilmCameraIcon()
                    .frame(width: 21, height: 17)
            }
        }
        .foregroundStyle(
            canShowVideoSegmentSwitch
                ? segmentMediaIconGradient
                : mutedMediaIconGradient
        )
        .shadow(
            color: canShowVideoSegmentSwitch
                ? HanClipTheme.primary.opacity(0.06)
                : Color.clear,
            radius: 1,
            y: 1
        )
        .frame(
            width: 28,
            height: 24,
            alignment: .leading
        )
        .offset(x: 10)
        .contentShape(Rectangle())
    }

    private var segmentMediaIconGradient: LinearGradient {
        LinearGradient(
            colors: [
                HanClipTheme.primary.opacity(0.38),
                HanClipTheme.secondary.opacity(0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var mutedMediaIconGradient: LinearGradient {
        LinearGradient(
            colors: [
                HanClipTheme.mutedIcon.opacity(0.72),
                HanClipTheme.mutedIcon.opacity(0.56)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                .fill(HanClipTheme.secondaryText.opacity(0.20))
                .frame(width: 1, height: 12)

            stepButton(
                systemImage: "plus",
                accessibilityLabel: "클립 시간을 1초 늘리기",
                isEnabled: canIncrease
            ) {
                adjustDuration(by: 1)
            }
        }
        .frame(width: 68, height: 20)
        .background(HanClipTheme.panelFill.opacity(0.30), in: Capsule())
        .background(stepperChromeBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(HanClipTheme.panelStroke.opacity(0.24), lineWidth: 0.8)
        }
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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(
                    HanClipTheme.secondaryText.opacity(isEnabled ? 0.54 : 0.18)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .frame(width: 32, height: 20)
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

    private var stepperChromeBackground: LinearGradient {
        LinearGradient(
            colors: [
                HanClipTheme.background.opacity(0.44),
                HanClipTheme.secondary.opacity(0.026)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct LivePhotoModeSegmentedControl: View {
    @Binding var mode: LivePhotoMode
    let tint: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HStack(spacing: 0) {
                    segment(
                        mode: .still,
                        title: "정지"
                    )

                    segment(
                        mode: .motion,
                        title: "동작"
                    )
                }
                .padding(2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(RoundedRectangle(cornerRadius: height / 2))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        if abs(value.translation.width) < 1 {
                            mode = mode == .still ? .motion : .still
                            return
                        }
                        mode = value.location.x < proxy.size.width / 2
                            ? .still
                            : .motion
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

    private func segment(
        mode segmentMode: LivePhotoMode,
        title: String
    ) -> some View {
        let isSelected = mode == segmentMode

        return HStack(spacing: 0) {
            Text(title)
                .font(
                    .system(
                        size: height <= 24 ? 10 : 11,
                        weight: isSelected ? .bold : .semibold
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(
            isSelected ? HanClipTheme.primaryText : HanClipTheme.secondaryText
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
                        RoundedRectangle(cornerRadius: max(4, height / 2 - 2))
                            .stroke(tint.opacity(0.24), lineWidth: 0.7)
                    }
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SimilarPhotoExposureSegmentedControl: View {
    @Binding var isIncluded: Bool
    let tint: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Button {
            isIncluded.toggle()
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(
                            isIncluded
                                ? tint.opacity(0.16)
                                : HanClipTheme.panelFill.opacity(0.72)
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    isIncluded
                                        ? tint.opacity(0.24)
                                        : HanClipTheme.panelStroke.opacity(0.30),
                                    lineWidth: 0.7
                                )
                        }

                    Image(systemName: isIncluded ? "checkmark" : "minus")
                        .font(.system(size: 7.5, weight: .black))
                }
                .frame(width: 14, height: 14)

                Text(isIncluded ? "사용중" : "제외됨")
                    .font(.system(size: 9.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Image(systemName: "arrow.2.squarepath")
                    .font(.system(size: 7.5, weight: .bold))
                    .opacity(0.58)
            }
            .foregroundStyle(
                isIncluded
                    ? HanClipTheme.primaryText.opacity(0.92)
                    : HanClipTheme.secondaryText.opacity(0.76)
            )
            .frame(width: width, height: height)
            .background(
                isIncluded
                    ? tint.opacity(0.055)
                    : HanClipTheme.panelFill.opacity(0.36),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        isIncluded
                            ? tint.opacity(0.18)
                            : HanClipTheme.panelStroke.opacity(0.30),
                        lineWidth: 0.8
                    )
            }
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(HanClipTheme.background.opacity(0.92))
                    .frame(width: 4, height: 4)
                    .offset(x: -7, y: 5)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isIncluded ? "자사진 사용" : "자사진 제외")
    }
}

struct SimilarPhotoGroupModeSegmentedControl: View {
    @Binding var mode: VideoSegmentMode
    let tint: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HStack(spacing: 0) {
                    segment(
                        mode: .single,
                        title: "자동"
                    )

                    segment(
                        mode: .multiple,
                        title: "수동"
                    )
                }
                .padding(2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(RoundedRectangle(cornerRadius: height / 2))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        if abs(value.translation.width) < 1 {
                            mode = mode == .single ? .multiple : .single
                            return
                        }
                        mode = value.location.x < proxy.size.width / 2
                            ? .single
                            : .multiple
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

    private func segment(
        mode segmentMode: VideoSegmentMode,
        title: String
    ) -> some View {
        let isSelected = mode == segmentMode

        return HStack(spacing: 0) {
            Text(title)
                .font(
                    .system(
                        size: height <= 24 ? 10 : 11,
                        weight: isSelected ? .bold : .semibold
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(
            isSelected ? HanClipTheme.primaryText : HanClipTheme.secondaryText
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
                        RoundedRectangle(cornerRadius: max(4, height / 2 - 2))
                            .stroke(tint.opacity(0.24), lineWidth: 0.7)
                    }
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
            ZStack {
                HStack(spacing: 0) {
                    segment(
                        mode: .single,
                        title: "한컷"
                    )

                    segment(
                        mode: .multiple,
                        title: "분할"
                    )
                }
                .padding(2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(RoundedRectangle(cornerRadius: height / 2))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        if abs(value.translation.width) < 1 {
                            mode = mode == .single ? .multiple : .single
                            return
                        }
                        mode = value.location.x < proxy.size.width / 2
                            ? .single
                            : .multiple
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

    private func segment(
        mode segmentMode: VideoSegmentMode,
        title: String
    ) -> some View {
        let isSelected = mode == segmentMode

        return HStack(spacing: 0) {
            Text(title)
                .font(
                    .system(
                        size: height <= 24 ? 10 : 11,
                        weight: isSelected ? .bold : .semibold
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(
            isSelected ? HanClipTheme.primaryText : HanClipTheme.secondaryText
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
                        RoundedRectangle(cornerRadius: max(4, height / 2 - 2))
                            .stroke(tint.opacity(0.24), lineWidth: 0.7)
                    }
            }
        }
        .accessibilityLabel("클립 나누기 \(title)")
    }
}

struct CompactDurationStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var isSmall = false
    var controlWidth: CGFloat = 68
    var controlHeight: CGFloat?
    var iconSize: CGFloat?

    private var resolvedHeight: CGFloat {
        controlHeight ?? (isSmall ? 20 : 28)
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
                .fill(HanClipTheme.secondaryText.opacity(0.20))
                .frame(width: 1, height: resolvedHeight * 0.55)

            stepButton(
                systemImage: "plus",
                isEnabled: value < range.upperBound
            ) {
                value = min(range.upperBound, value + step)
            }
        }
        .frame(width: controlWidth, height: resolvedHeight)
        .background(HanClipTheme.panelFill.opacity(0.30), in: Capsule())
        .background(stepperChromeBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(HanClipTheme.panelStroke.opacity(0.24), lineWidth: 0.8)
        }
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
                        size: iconSize ?? (isSmall ? 15 : 13),
                        weight: .bold
                    )
                )
                .foregroundStyle(HanClipTheme.secondaryText.opacity(0.54))
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

    private var stepperChromeBackground: LinearGradient {
        LinearGradient(
            colors: [
                HanClipTheme.background.opacity(0.44),
                HanClipTheme.secondary.opacity(0.026)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
