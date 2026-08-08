import Foundation
import UIKit
import Vision

struct BackgroundMusicSampleTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let resourceName: String
    let resourceExtension: String

    var url: URL? {
        Bundle.main.url(
            forResource: resourceName,
            withExtension: resourceExtension
        )
    }

    var settings: BackgroundMusicSettings? {
        guard let url else { return nil }
        var settings = BackgroundMusicSettings.empty
        settings.isEnabled = true
        settings.fileURL = url
        settings.displayName = title
        return settings
    }
}

struct BackgroundMusicSettings: Codable, Equatable {
    var isEnabled: Bool
    var fileURL: URL?
    var displayName: String
    var musicVolume: Double
    var originalAudioVolume: Double
    var loopsToFillVideo: Bool
    var fadeInEnabled: Bool
    var fadeOutEnabled: Bool

    static let defaultMusicVolume = 0.35
    static let defaultOriginalAudioVolume = 1.0
    static let sampleTracks = [
        BackgroundMusicSampleTrack(
            id: "daily-loop",
            title: "햇살 한 컷",
            subtitle: "잔잔한 생활 이야기",
            resourceName: "HanClipSampleLoop",
            resourceExtension: "wav"
        ),
        BackgroundMusicSampleTrack(
            id: "travel-joy",
            title: "여행의 설렘",
            subtitle: "밝은 피아노와 퍼커션 여행",
            resourceName: "HanClipTravelJoy",
            resourceExtension: "wav"
        ),
        BackgroundMusicSampleTrack(
            id: "ad-classical-drama",
            title: "광고 클래식 드라마",
            subtitle: "오스티나토와 텐션",
            resourceName: "HanClipAdClassicalDrama",
            resourceExtension: "wav"
        ),
        BackgroundMusicSampleTrack(
            id: "golf-lets-go",
            title: "골프치러 가자",
            subtitle: "경쾌한 출발과 기대감",
            resourceName: "HanClipGolfLetsGo",
            resourceExtension: "wav"
        ),
        BackgroundMusicSampleTrack(
            id: "jiwoo-first-snow-original",
            title: "지우에게 첫눈이란",
            subtitle: "첫눈을 본 5살 아이의 감정",
            resourceName: "HanClipJiwooFirstSnowOriginal",
            resourceExtension: "mp3"
        ),
        BackgroundMusicSampleTrack(
            id: "jiwoo-first-snow",
            title: "베이비 워킹",
            subtitle: "작고 경쾌한 첫걸음",
            resourceName: "HanClipJiwooFirstSnow",
            resourceExtension: "wav"
        )
    ]

    static var empty: BackgroundMusicSettings {
        BackgroundMusicSettings(
            isEnabled: false,
            fileURL: nil,
            displayName: "",
            musicVolume: defaultMusicVolume,
            originalAudioVolume: defaultOriginalAudioVolume,
            loopsToFillVideo: true,
            fadeInEnabled: true,
            fadeOutEnabled: true
        )
    }

    static var sampleDisplayName: String {
        sampleTracks.first?.title ?? "HanClip 샘플 음악"
    }

    static var bundledSample: BackgroundMusicSettings? {
        sampleTracks.first?.settings
    }

    static var projectDefault: BackgroundMusicSettings {
        bundledSample ?? .empty
    }

    var hasMusicFile: Bool {
        fileURL != nil
    }

    var shouldRender: Bool {
        isEnabled && hasMusicFile
    }

    var displayTitle: String {
        displayName.isEmpty ? "음악 파일" : displayName
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case fileURL
        case displayName
        case musicVolume
        case originalAudioVolume
        case loopsToFillVideo
        case fadeInEnabled
        case fadeOutEnabled
    }

    init(
        isEnabled: Bool,
        fileURL: URL?,
        displayName: String,
        musicVolume: Double,
        originalAudioVolume: Double,
        loopsToFillVideo: Bool,
        fadeInEnabled: Bool,
        fadeOutEnabled: Bool
    ) {
        self.isEnabled = isEnabled
        self.fileURL = fileURL
        self.displayName = displayName
        self.musicVolume = musicVolume
        self.originalAudioVolume = originalAudioVolume
        self.loopsToFillVideo = loopsToFillVideo
        self.fadeInEnabled = fadeInEnabled
        self.fadeOutEnabled = fadeOutEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decodeIfPresent(
            Bool.self,
            forKey: .isEnabled
        ) ?? false
        fileURL = try values.decodeIfPresent(URL.self, forKey: .fileURL)
        displayName = try values.decodeIfPresent(
            String.self,
            forKey: .displayName
        ) ?? ""
        musicVolume = try values.decodeIfPresent(
            Double.self,
            forKey: .musicVolume
        ) ?? Self.defaultMusicVolume
        originalAudioVolume = try values.decodeIfPresent(
            Double.self,
            forKey: .originalAudioVolume
        ) ?? Self.defaultOriginalAudioVolume
        loopsToFillVideo = try values.decodeIfPresent(
            Bool.self,
            forKey: .loopsToFillVideo
        ) ?? true
        fadeInEnabled = try values.decodeIfPresent(
            Bool.self,
            forKey: .fadeInEnabled
        ) ?? true
        fadeOutEnabled = try values.decodeIfPresent(
            Bool.self,
            forKey: .fadeOutEnabled
        ) ?? true
    }
}

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
    case all = "전체"

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

enum PhotoSimilarityFingerprint {
    private static let imageSampleCount = 16 * 16

    static func make(from image: UIImage) -> [UInt8] {
        // 16×16 keeps enough spatial information to distinguish a changed
        // camera angle while remaining cheap to calculate during import.
        let dimension = 16
        let size = CGSize(width: dimension, height: dimension)
        let bytesPerPixel = 4
        var rgba = [UInt8](
            repeating: 0,
            count: dimension * dimension * bytesPerPixel
        )

        let didRender = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: dimension,
                height: dimension,
                bitsPerComponent: 8,
                bytesPerRow: dimension * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }

            UIGraphicsPushContext(context)
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
            UIGraphicsPopContext()
            return true
        }
        guard didRender else { return [] }

        let pixelCount = dimension * dimension
        var luminance: [UInt8] = []
        luminance.reserveCapacity(pixelCount)

        for index in 0..<pixelCount {
            let offset = index * bytesPerPixel
            let red = Double(rgba[offset])
            let green = Double(rgba[offset + 1])
            let blue = Double(rgba[offset + 2])
            let value = red * 0.299 + green * 0.587 + blue * 0.114
            luminance.append(UInt8(value.rounded()))
        }

        luminance.append(UInt8(clamping: detectedFaceCount(in: image)))
        return luminance
    }

    static func faceCount(_ fingerprint: [UInt8]) -> Int? {
        guard fingerprint.count > imageSampleCount else { return nil }
        return Int(fingerprint[imageSampleCount])
    }

    static func distance(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }

        let total = zip(lhs, rhs).reduce(0.0) { partial, values in
            partial + abs(Double(values.0) - Double(values.1))
        }
        return total / Double(lhs.count)
    }

    static func alignedDistance(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        translatedDistance(lhs, rhs, subtractingMean: false)
    }

    static func structureDistance(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        translatedDistance(lhs, rhs, subtractingMean: true)
    }

    private static func translatedDistance(
        _ lhs: [UInt8],
        _ rhs: [UInt8],
        subtractingMean: Bool
    ) -> Double {
        let lhs = imageSamples(lhs)
        let rhs = imageSamples(rhs)
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }

        let lhsMean = subtractingMean ? mean(lhs) : 0
        let rhsMean = subtractingMean ? mean(rhs) : 0
        var bestDistance = zip(lhs, rhs).reduce(0.0) { partial, values in
            let lhsStructure = Double(values.0) - lhsMean
            let rhsStructure = Double(values.1) - rhsMean
            return partial + abs(lhsStructure - rhsStructure)
        } / Double(lhs.count)

        let dimension = Int(Double(lhs.count).squareRoot())
        guard dimension * dimension == lhs.count else { return bestDistance }

        // A two-cell translation at 16×16 absorbs normal hand-held framing
        // movement while the structure threshold still rejects a changed angle.
        for yOffset in -2...2 {
            for xOffset in -2...2 where xOffset != 0 || yOffset != 0 {
                var total = 0.0
                var comparedPixelCount = 0

                for y in 0..<dimension {
                    for x in 0..<dimension {
                        let shiftedX = x + xOffset
                        let shiftedY = y + yOffset
                        guard shiftedX >= 0, shiftedX < dimension,
                              shiftedY >= 0, shiftedY < dimension
                        else { continue }

                        let lhsValue = Double(lhs[y * dimension + x]) - lhsMean
                        let rhsValue = Double(
                            rhs[shiftedY * dimension + shiftedX]
                        ) - rhsMean
                        total += abs(lhsValue - rhsValue)
                        comparedPixelCount += 1
                    }
                }

                if comparedPixelCount > 0 {
                    bestDistance = min(
                        bestDistance,
                        total / Double(comparedPixelCount)
                    )
                }
            }
        }

        return bestDistance
    }

    static func mean(_ values: [UInt8]) -> Double {
        let values = imageSamples(values)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0.0) { $0 + Double($1) } / Double(values.count)
    }

    private static func imageSamples(_ fingerprint: [UInt8]) -> [UInt8] {
        guard fingerprint.count > imageSampleCount else { return fingerprint }
        return Array(fingerprint.prefix(imageSampleCount))
    }

    private static func detectedFaceCount(in image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation
        )
        guard (try? handler.perform([request])) != nil else { return 0 }
        return request.results?.count ?? 0
    }
}

private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
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
    var isVideoSegmentSelected: Bool
    var photoSimilarityFingerprint: [UInt8]
    var similarPhotoGroupID: UUID?
    var similarPhotoGroupIndex: Int
    var similarPhotoGroupCount: Int
    var isSimilarPhotoGroupRepresentative: Bool
    var sourceCreatedAt: Date?
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
        isVideoSegmentSelected: Bool = true,
        photoSimilarityFingerprint: [UInt8]? = nil,
        similarPhotoGroupID: UUID? = nil,
        similarPhotoGroupIndex: Int = 0,
        similarPhotoGroupCount: Int = 1,
        isSimilarPhotoGroupRepresentative: Bool = true,
        sourceCreatedAt: Date? = nil,
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
        self.isVideoSegmentSelected = isVideoSegmentSelected
        self.photoSimilarityFingerprint = photoSimilarityFingerprint
            ?? PhotoSimilarityFingerprint.make(from: thumbnail)
        self.similarPhotoGroupID = similarPhotoGroupID
        self.similarPhotoGroupIndex = similarPhotoGroupIndex
        self.similarPhotoGroupCount = max(1, similarPhotoGroupCount)
        self.isSimilarPhotoGroupRepresentative = isSimilarPhotoGroupRepresentative
        self.sourceCreatedAt = sourceCreatedAt
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

    var isHiddenVideoSegmentChild: Bool {
        isVideoSegmentChild && !isVideoSegmentSelected
    }

    var isSimilarPhotoGroupMember: Bool {
        similarPhotoGroupID != nil
    }

    var isSimilarPhotoGroupParent: Bool {
        similarPhotoGroupID != nil
            && similarPhotoGroupCount > 1
            && similarPhotoGroupIndex == 0
    }

    var isSimilarPhotoGroupChild: Bool {
        similarPhotoGroupID != nil
            && similarPhotoGroupCount > 1
            && similarPhotoGroupIndex > 0
    }

    var isHiddenSimilarPhotoGroupMember: Bool {
        similarPhotoGroupID != nil && !isSimilarPhotoGroupRepresentative
    }

    var isRenderableClip: Bool {
        !isVideoSegmentParent
            && !isHiddenVideoSegmentChild
            && !isHiddenSimilarPhotoGroupMember
    }

    func replacingSource(_ source: ClipSource) -> ClipItem {
        ClipItem(
            id: id,
            source: source,
            thumbnail: thumbnail,
            duration: duration,
            photoDuration: photoDuration,
            livePhotoDuration: livePhotoDuration,
            isLivePhoto: isLivePhoto,
            livePhotoMode: livePhotoMode,
            mediaKind: mediaKind,
            sourceDuration: sourceDuration,
            trimStart: trimStart,
            audioWaveform: audioWaveform,
            audioPeakTime: audioPeakTime,
            audioPeakTimes: audioPeakTimes,
            videoSegmentMode: videoSegmentMode,
            isVideoSegmentParent: isVideoSegmentParent,
            videoSegmentParentID: videoSegmentParentID,
            isVideoSegmentSelected: isVideoSegmentSelected,
            photoSimilarityFingerprint: photoSimilarityFingerprint,
            similarPhotoGroupID: similarPhotoGroupID,
            similarPhotoGroupIndex: similarPhotoGroupIndex,
            similarPhotoGroupCount: similarPhotoGroupCount,
            isSimilarPhotoGroupRepresentative: isSimilarPhotoGroupRepresentative,
            sourceCreatedAt: sourceCreatedAt,
            sourcePixelSize: sourcePixelSize
        )
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
        let safeDuration = min(max(0.1, selectedDuration), sourceDuration)
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
        let safeDuration = min(max(0.1, selectedDuration), sourceDuration)
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
