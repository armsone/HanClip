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
        self.sourcePixelSize = sourcePixelSize ?? thumbnail.size
    }

    var trimEnd: Double {
        min(sourceDuration ?? duration, trimStart + duration)
    }

    var isVideoClip: Bool {
        mediaKind == .video
    }
}
