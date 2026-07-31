import SwiftUI

struct ClipRow: View {
    let position: Int
    @Binding var clip: ClipItem
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("\(position)")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(HanClipTheme.primary)
                .frame(width: 18, alignment: .center)
                .accessibilityLabel("\(position)번째 클립")

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
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(.black.opacity(0.65), in: Circle())
                                    .padding(3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("에디터 열기")

                VStack(alignment: .leading, spacing: 2) {
                    Button(action: onSelect) {
                        HStack {
                            Text("\(clip.duration, specifier: "%.1f")초")
                                .font(.system(size: 12).monospacedDigit())
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("에디터 열기")

                    HStack(spacing: 8) {
                        if clip.isLivePhoto {
                            Picker("Live Photo 사용 방식", selection: $clip.livePhotoMode) {
                                ForEach(LivePhotoMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .frame(width: 96, height: 24)
                            .tint(HanClipTheme.secondary)
                            .onChange(of: clip.livePhotoMode) {
                                previousMode,
                                selectedMode in
                                if previousMode == .motion {
                                    clip.livePhotoDuration = clip.duration
                                } else {
                                    clip.photoDuration = clip.duration
                                }

                                clip.duration = selectedMode == .motion
                                    ? (clip.livePhotoDuration ?? clip.duration)
                                    : clip.photoDuration
                            }

                            editorAreaButton
                        } else {
                            Button(action: onSelect) {
                                Group {
                                    if clip.isVideoClip {
                                        Image(
                                            systemName:
                                                "rectangle.stack.badge.play.fill"
                                        )
                                        .font(
                                            .system(
                                                size: 16,
                                                weight: .bold
                                            )
                                        )
                                        .opacity(0.60)
                                    } else {
                                        Image(systemName: "photo.fill")
                                            .font(
                                                .system(
                                                    size: 16,
                                                    weight: .bold
                                                )
                                            )
                                            .opacity(0.60)
                                    }
                                }
                                .frame(
                                    width: 96,
                                    height: 24,
                                    alignment: .leading
                                )
                                .offset(y: 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                clip.isVideoClip
                                    ? "영상 클립 에디터 열기"
                                    : "사진 에디터 열기"
                            )

                            editorAreaButton
                        }

                        HStack(spacing: 32) {
                            if clip.isVideoClip {
                                VideoDurationStepper(clip: $clip)
                            } else {
                                CompactDurationStepper(
                                    value: $clip.duration,
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
        .onChange(of: clip.duration) { _, duration in
            if clip.isLivePhoto, clip.livePhotoMode == .motion {
                clip.livePhotoDuration = duration
            } else {
                clip.photoDuration = duration
            }
        }
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

struct CompactDurationStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var isSmall = false

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
                .frame(width: 1, height: isSmall ? 12 : 18)

            stepButton(
                systemImage: "plus",
                isEnabled: value < range.upperBound
            ) {
                value = min(range.upperBound, value + step)
            }
        }
        .frame(width: 80, height: isSmall ? 22 : 30)
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
                        size: isSmall ? 18 : 14,
                        weight: .bold
                    )
                )
                .foregroundStyle(HanClipTheme.onSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .frame(
            width: isSmall ? 38 : nil,
            height: isSmall ? 22 : nil
        )
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(systemImage == "plus" ? "시간 늘리기" : "시간 줄이기")
    }
}
