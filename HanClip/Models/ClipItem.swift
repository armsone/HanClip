import Foundation
import UIKit

enum OutputAspectRatio: String, CaseIterable, Identifiable {
    case square = "1:1"
    case portrait3x4 = "3:4"
    case landscape4x3 = "4:3"
    case portrait9x16 = "9:16"
    case landscape16x9 = "16:9"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square:
            "정방형"
        case .portrait3x4:
            "세로 3:4"
        case .landscape4x3:
            "가로 4:3"
        case .portrait9x16:
            "세로 9:16"
        case .landscape16x9:
            "가로 16:9"
        }
    }

    var renderSize: CGSize {
        switch self {
        case .square:
            CGSize(width: 1080, height: 1080)
        case .portrait3x4:
            CGSize(width: 1080, height: 1440)
        case .landscape4x3:
            CGSize(width: 1440, height: 1080)
        case .portrait9x16:
            CGSize(width: 1080, height: 1920)
        case .landscape16x9:
            CGSize(width: 1920, height: 1080)
        }
    }

    static func renderSize(for sourceSize: CGSize) -> CGSize {
        let safeWidth = max(1, sourceSize.width)
        let safeHeight = max(1, sourceSize.height)
        let ratio = safeWidth / safeHeight
        let size: CGSize

        if ratio >= 1 {
            if ratio <= 16.0 / 9.0 {
                size = CGSize(width: 1080 * ratio, height: 1080)
            } else {
                size = CGSize(width: 1920, height: 1920 / ratio)
            }
        } else if ratio >= 9.0 / 16.0 {
            size = CGSize(width: 1080, height: 1080 / ratio)
        } else {
            size = CGSize(width: 1920 * ratio, height: 1920)
        }

        return CGSize(
            width: evenPixelValue(size.width),
            height: evenPixelValue(size.height)
        )
    }

    private static func evenPixelValue(_ value: CGFloat) -> CGFloat {
        let rounded = max(4, Int(value.rounded()))
        return CGFloat(max(4, rounded - rounded % 4))
    }
}

enum LivePhotoMode: String, CaseIterable, Identifiable {
    case still = "사진"
    case motion = "Live"

    var id: String { rawValue }
}

enum ClipSource {
    case photoAsset(localIdentifier: String)
    case imageFile(URL)
    case videoFile(URL)
    case livePhotoFiles(imageURL: URL, videoURL: URL)
}

enum ClipMediaKind: String {
    case photo
    case livePhoto
    case video
}

enum VideoSegmentMode: String, CaseIterable, Identifiable {
    case single = "단일"
    case multiple = "다중"

    var id: String { rawValue }

    init(storedValue: String) {
        switch storedValue {
        case "1개":
            self = .single
        case "여러개", "여러 개":
            self = .multiple
        default:
            self = VideoSegmentMode(rawValue: storedValue) ?? .single
        }
    }
}

struct ClipItem: Identifiable {
    let id: UUID
    let source: ClipSource
    var thumbnail: UIImage
    var duration: Double
    var photoDuration: Double
    var livePhotoDuration: Double?
    var isLivePhoto: Bool
    var livePhotoMode: LivePhotoMode
    var mediaKind: ClipMediaKind
    var sourceDuration: Double?
    var trimStart: Double
    var audioWaveform: [Double]
    var audioPeakTime: Double?
    var audioPeakTimes: [Double]
    var videoSegmentMode: VideoSegmentMode
    var isVideoSegmentParent: Bool
    var videoSegmentParentID: UUID?
    let sourcePixelSize: CGSize

    var sourceAspectRatio: CGFloat {
        sourcePixelSize.width / max(1, sourcePixelSize.height)
    }

    init(
        id: UUID = UUID(),
        source: ClipSource,
        thumbnail: UIImage,
        duration: Double = 4,
        photoDuration: Double? = nil,
        livePhotoDuration: Double? = nil,
        isLivePhoto: Bool = false,
        livePhotoMode: LivePhotoMode = .still,
        mediaKind: ClipMediaKind? = nil,
        sourceDuration: Double? = nil,
        trimStart: Double = 0,
        audioWaveform: [Double] = [],
        audioPeakTime: Double? = nil,
        audioPeakTimes: [Double] = [],
        videoSegmentMode: VideoSegmentMode = .single,
        isVideoSegmentParent: Bool = false,
        videoSegmentParentID: UUID? = nil,
        sourcePixelSize: CGSize? = nil
    ) {
        self.id = id
        self.source = source
        self.thumbnail = thumbnail
        self.duration = duration
        self.photoDuration = photoDuration
            ?? (isLivePhoto && livePhotoMode == .still ? 4 : duration)
        self.livePhotoDuration = livePhotoDuration
            ?? (isLivePhoto ? duration : nil)
        self.isLivePhoto = isLivePhoto
        self.livePhotoMode = livePhotoMode
        self.mediaKind = mediaKind
            ?? (isLivePhoto ? .livePhoto : .photo)
        self.sourceDuration = sourceDuration
            ?? (isLivePhoto ? self.livePhotoDuration : nil)
        self.trimStart = trimStart
        self.audioWaveform = audioWaveform
        self.audioPeakTime = audioPeakTime
        self.audioPeakTimes = audioPeakTimes
        self.videoSegmentMode = videoSegmentMode
        self.isVideoSegmentParent = isVideoSegmentParent
        self.videoSegmentParentID = videoSegmentParentID
        self.sourcePixelSize = sourcePixelSize ?? thumbnail.size
    }

    var trimEnd: Double {
        min(sourceDuration ?? duration, trimStart + duration)
    }

    var isVideoClip: Bool {
        mediaKind == .video
    }

    var isVideoSegmentChild: Bool {
        videoSegmentParentID != nil
    }

    var isRenderableClip: Bool {
        !isVideoSegmentParent
    }
}

enum VideoClipSegmenter {
    static let allowedSegmentCounts = 1...12

    static func normalizedSegmentCount(_ count: Int) -> Int {
        min(
            max(count, allowedSegmentCounts.lowerBound),
            allowedSegmentCounts.upperBound
        )
    }

    static func makeClips(
        source: ClipSource,
        thumbnail: UIImage,
        sourceDuration: Double,
        selectedDuration: Double,
        segmentCount: Int,
        analysis: AudioAnalysisResult?,
        sourcePixelSize: CGSize
    ) -> [ClipItem] {
        let safeDuration = min(max(0.5, selectedDuration), sourceDuration)
        let safeSegmentCount = normalizedSegmentCount(segmentCount)
        let fallbackPeak = sourceDuration / 2
        let rankedPeaks = analysis?.peakTimes.isEmpty == false
            ? analysis?.peakTimes ?? [fallbackPeak]
            : [analysis?.peakTime ?? fallbackPeak]
        let peaks = nonOverlappingPeaks(
            rankedPeaks: rankedPeaks,
            sourceDuration: sourceDuration,
            selectedDuration: safeDuration,
            limit: safeSegmentCount
        )

        return peaks.map { peak in
            let start = max(
                0,
                min(sourceDuration - safeDuration, peak - safeDuration / 2)
            )
            return ClipItem(
                source: source,
                thumbnail: thumbnail,
                duration: safeDuration,
                photoDuration: safeDuration,
                mediaKind: .video,
                sourceDuration: sourceDuration,
                trimStart: start,
                audioWaveform: analysis?.waveform ?? [],
                audioPeakTime: peak,
                audioPeakTimes: rankedPeaks,
                videoSegmentMode: segmentCount > 1 ? .multiple : .single,
                sourcePixelSize: sourcePixelSize
            )
        }
    }

    static func nonOverlappingPeaks(
        rankedPeaks: [Double],
        sourceDuration: Double,
        selectedDuration: Double,
        limit: Int
    ) -> [Double] {
        let safeDuration = min(max(0.5, selectedDuration), sourceDuration)
        let safeLimit = normalizedSegmentCount(limit)
        var selected: [(peak: Double, start: Double, end: Double)] = []

        for peak in rankedPeaks {
            let clampedPeak = min(max(0, peak), sourceDuration)
            let start = max(
                0,
                min(
                    sourceDuration - safeDuration,
                    clampedPeak - safeDuration / 2
                )
            )
            let end = start + safeDuration

            guard selected.allSatisfy({
                end <= $0.start + 0.001 || start >= $0.end - 0.001
            }) else { continue }

            selected.append((clampedPeak, start, end))
            if selected.count >= safeLimit {
                break
            }
        }

        return selected.map(\.peak).sorted()
    }
}
