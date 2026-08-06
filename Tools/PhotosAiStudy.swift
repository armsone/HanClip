import AVFoundation
import CryptoKit
import Foundation
import Photos

struct StudyFrame: Encodable {
    let time: Double
    let rms: Double
    let peak: Double
    let crossingRate: Double
    let score: Double
    let rise: Double
    let afterglow: Double
}

struct VisualStudy: Encodable {
    let sampledFrameCount: Int
    let averageMotion: Double
    let peakMotion: Double
    let averageBrightnessChange: Double
    let peakBrightnessChange: Double
}

struct VideoStudy: Encodable {
    let assetHash: String
    let duration: Double
    let favorite: Bool
    let width: Int
    let height: Int
    let topMoments: [StudyFrame]
    let visualStudy: VisualStudy
    let averageScore: Double
    let peakScore: Double
}

struct StudyReport: Encodable {
    let createdAt: String
    let requestedMinimumDuration: Double
    let scannedVideoCount: Int
    let studiedVideoCount: Int
    let videos: [VideoStudy]
}

struct Bucket {
    var energy = 0.0
    var peak = 0.0
    var crossings = 0
    var samples = 0
    var count = 0

    var rms: Double {
        count > 0 ? energy / Double(count) : 0
    }

    var crossingRate: Double {
        samples > 0 ? Double(crossings) / Double(samples) : 0
    }

    var score: Double {
        let highFrequencyWeight = min(1, crossingRate * 10)
        return min(1, rms * 0.55 + peak * 0.45 + highFrequencyWeight * rms * 0.35)
    }
}

let arguments = CommandLine.arguments
let requestedLimit = argumentValue("--limit").flatMap(Int.init) ?? 0
let outputPath = argumentValue("--output")
    ?? "docs/ai-learning/photos-video-audio-study.json"
let minimumDuration = argumentValue("--minimum-duration").flatMap(Double.init)
    ?? 0
let inputDirectory = argumentValue("--input-directory")

let studies: [VideoStudy]
let scannedVideoCount: Int

if let inputDirectory {
    let urls = videoFiles(in: URL(fileURLWithPath: inputDirectory))
    scannedVideoCount = urls.count
    let selectedURLs = requestedLimit > 0 ? Array(urls.prefix(requestedLimit)) : urls
    studies = selectedURLs.compactMap { url in
        do {
            let study = try study(url: url)
            print("studied \(url.lastPathComponent)")
            return study
        } catch {
            fputs("skip \(url.lastPathComponent): \(error)\n", stderr)
            return nil
        }
    }
} else {
    let authorization = authorizePhotos()
    guard authorization == .authorized || authorization == .limited else {
        fputs("Photos access is not authorized.\n", stderr)
        exit(2)
    }

    let fetchOptions = PHFetchOptions()
    if minimumDuration > 0 {
        fetchOptions.predicate = NSPredicate(
            format: "mediaType == %d AND duration >= %f",
            PHAssetMediaType.video.rawValue,
            minimumDuration
        )
    } else {
        fetchOptions.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.video.rawValue
        )
    }
    fetchOptions.sortDescriptors = [
        NSSortDescriptor(key: "creationDate", ascending: false)
    ]

    let assets = PHAsset.fetchAssets(with: fetchOptions)
    var photoStudies: [VideoStudy] = []
    let studyCount = requestedLimit > 0
        ? min(requestedLimit, assets.count)
        : assets.count

    for offset in 0..<studyCount {
        let asset = assets.object(at: offset)
        autoreleasepool {
            do {
                if let study = try study(asset: asset) {
                    photoStudies.append(study)
                    print("studied \(photoStudies.count)/\(studyCount)")
                }
            } catch {
                fputs("skip asset \(offset): \(error)\n", stderr)
            }
        }
    }

    scannedVideoCount = assets.count
    studies = photoStudies
}

let report = StudyReport(
    createdAt: ISO8601DateFormatter().string(from: Date()),
    requestedMinimumDuration: minimumDuration,
    scannedVideoCount: scannedVideoCount,
    studiedVideoCount: studies.count,
    videos: studies
)
let data = try JSONEncoder.prettySorted.encode(report)
let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try data.write(to: outputURL, options: .atomic)
print("wrote \(outputURL.path)")

func videoFiles(in directory: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    return enumerator.compactMap { item -> URL? in
        guard let url = item as? URL else { return nil }
        let ext = url.pathExtension.lowercased()
        guard ["mov", "mp4", "m4v"].contains(ext) else { return nil }
        return url
    }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

func study(url: URL) throws -> VideoStudy {
    let asset = AVURLAsset(url: url)
    let duration = try loadDuration(asset)
    let moments = try analyzeAudio(url: url, duration: duration)
    let visualStudy = analyzeVisual(url: url, duration: duration)
    let scores = moments.map(\.score)
    let tracks = asset.tracks(withMediaType: .video)
    let naturalSize = tracks.first?.naturalSize ?? .zero
    return VideoStudy(
        assetHash: hash(url.lastPathComponent + "\(duration)"),
        duration: duration,
        favorite: false,
        width: Int(abs(naturalSize.width)),
        height: Int(abs(naturalSize.height)),
        topMoments: Array(moments.prefix(12)),
        visualStudy: visualStudy,
        averageScore: scores.reduce(0, +) / Double(max(1, scores.count)),
        peakScore: scores.max() ?? 0
    )
}

func loadDuration(_ asset: AVURLAsset) throws -> Double {
    let duration = asset.duration.seconds
    guard duration.isFinite, duration > 0 else { return 0 }
    return duration
}

func argumentValue(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name),
          index + 1 < arguments.count
    else { return nil }
    return arguments[index + 1]
}

func authorizePhotos() -> PHAuthorizationStatus {
    let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard current == .notDetermined else { return current }
    let semaphore = DispatchSemaphore(value: 0)
    var result = PHAuthorizationStatus.notDetermined
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
        result = status
        semaphore.signal()
    }
    semaphore.wait()
    return result
}

func study(asset: PHAsset) throws -> VideoStudy? {
    guard let resource = PHAssetResource.assetResources(for: asset).first(
        where: { $0.type == .video || $0.type == .fullSizeVideo }
    ) else { return nil }

    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(resource.uniformTypeIdentifier.contains("mp4") ? "mp4" : "mov")
    try export(resource: resource, to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let moments = try analyzeAudio(url: tempURL, duration: asset.duration)
    let visualStudy = analyzeVisual(url: tempURL, duration: asset.duration)
    let scores = moments.map(\.score)
    return VideoStudy(
        assetHash: hash(asset.localIdentifier),
        duration: asset.duration,
        favorite: asset.isFavorite,
        width: asset.pixelWidth,
        height: asset.pixelHeight,
        topMoments: Array(moments.prefix(12)),
        visualStudy: visualStudy,
        averageScore: scores.reduce(0, +) / Double(max(1, scores.count)),
        peakScore: scores.max() ?? 0
    )
}

func export(resource: PHAssetResource, to url: URL) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var exportError: Error?
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = false
    PHAssetResourceManager.default().writeData(
        for: resource,
        toFile: url,
        options: options
    ) { error in
        exportError = error
        semaphore.signal()
    }
    semaphore.wait()
    if let exportError { throw exportError }
}

func analyzeAudio(url: URL, duration: Double, bucketCount: Int = 240) throws -> [StudyFrame] {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first else {
        return []
    }

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    )
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { return [] }
    reader.add(output)
    reader.startReading()

    var buckets = Array(repeating: Bucket(), count: bucketCount)
    while let sample = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &pointer
        ) == kCMBlockBufferNoErr,
              let pointer,
              length >= MemoryLayout<Int16>.size
        else { continue }

        let sampleCount = length / MemoryLayout<Int16>.size
        let values = UnsafeRawPointer(pointer).assumingMemoryBound(to: Int16.self)
        var sum = 0.0
        var peak = 0.0
        var crossingCount = 0
        var previousSign = 0
        for index in 0..<sampleCount {
            let value = Double(values[index]) / Double(Int16.max)
            let sign = value >= 0 ? 1 : -1
            sum += value * value
            peak = max(peak, abs(value))
            if index > 0, sign != previousSign {
                crossingCount += 1
            }
            previousSign = sign
        }

        let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        let bucketIndex = min(
            bucketCount - 1,
            max(0, Int(time / max(duration, 0.1) * Double(bucketCount)))
        )
        buckets[bucketIndex].energy += sqrt(sum / Double(max(1, sampleCount)))
        buckets[bucketIndex].peak = max(buckets[bucketIndex].peak, peak)
        buckets[bucketIndex].crossings += crossingCount
        buckets[bucketIndex].samples += sampleCount
        buckets[bucketIndex].count += 1
    }

    return rankedMoments(buckets: buckets, duration: duration)
}

func analyzeVisual(
    url: URL,
    duration: Double,
    sampleCount: Int = 24
) -> VisualStudy {
    guard duration > 0 else {
        return VisualStudy(
            sampledFrameCount: 0,
            averageMotion: 0,
            peakMotion: 0,
            averageBrightnessChange: 0,
            peakBrightnessChange: 0
        )
    }

    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.08, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)
    generator.maximumSize = CGSize(width: 160, height: 160)

    var previous: VisualFrame?
    var motions: [Double] = []
    var brightnessChanges: [Double] = []
    let count = max(2, sampleCount)

    for index in 0..<count {
        let seconds = duration * (Double(index) + 0.5) / Double(count)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil),
              let frame = visualFrame(from: cgImage)
        else { continue }

        if let previous, previous.cells.count == frame.cells.count {
            var motion = 0.0
            for cellIndex in frame.cells.indices {
                motion += abs(frame.cells[cellIndex] - previous.cells[cellIndex])
            }
            motion /= Double(max(1, frame.cells.count))
            motions.append(motion)
            brightnessChanges.append(
                abs(frame.averageBrightness - previous.averageBrightness)
            )
        }
        previous = frame
    }

    return VisualStudy(
        sampledFrameCount: motions.count + (previous == nil ? 0 : 1),
        averageMotion: average(motions),
        peakMotion: motions.max() ?? 0,
        averageBrightnessChange: average(brightnessChanges),
        peakBrightnessChange: brightnessChanges.max() ?? 0
    )
}

struct VisualFrame {
    let cells: [Double]
    let averageBrightness: Double
}

func visualFrame(from image: CGImage) -> VisualFrame? {
    let gridWidth = 8
    let gridHeight = 8
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }

    var pixels = [UInt8](
        repeating: 0,
        count: gridWidth * gridHeight * 4
    )
    guard let context = CGContext(
        data: &pixels,
        width: gridWidth,
        height: gridHeight,
        bitsPerComponent: 8,
        bytesPerRow: gridWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .low
    context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight)
    )

    var cells: [Double] = []
    cells.reserveCapacity(gridWidth * gridHeight)
    var brightnessTotal = 0.0
    for index in 0..<(gridWidth * gridHeight) {
        let offset = index * 4
        let red = Double(pixels[offset])
        let green = Double(pixels[offset + 1])
        let blue = Double(pixels[offset + 2])
        let brightness = (
            red * 0.299 + green * 0.587 + blue * 0.114
        ) / 255.0
        cells.append(brightness)
        brightnessTotal += brightness
    }

    return VisualFrame(
        cells: cells,
        averageBrightness: brightnessTotal / Double(max(1, cells.count))
    )
}

func average(_ values: [Double]) -> Double {
    values.reduce(0, +) / Double(max(1, values.count))
}

func rankedMoments(buckets: [Bucket], duration: Double) -> [StudyFrame] {
    var frames: [StudyFrame] = []
    for index in buckets.indices {
        let bucket = buckets[index]
        let start = max(0, index - 8)
        let end = min(buckets.count, index + 9)
        let history = buckets[start..<index].map(\.score)
        let future = buckets[(index + 1)..<end].map(\.score)
        guard history.count >= 2, future.count >= 2 else { continue }
        let baseline = history.reduce(0, +) / Double(max(1, history.count))
        let after = future.reduce(0, +) / Double(max(1, future.count))
        let rise = max(0, bucket.score - baseline)
        let afterglow = max(0, after / max(0.008, baseline) - 1)
        let audibleResponseWeight = min(1, after / 0.045)
        let distanceFromEdge = min(index, buckets.count - 1 - index)
        let edgeConfidence = min(1, Double(distanceFromEdge) / 6.0)
        let memorableScore = (
            bucket.score + rise * 2.2 + afterglow * 0.25 * audibleResponseWeight
        ) * edgeConfidence
        frames.append(
            StudyFrame(
                time: (Double(index) + 0.5) / Double(buckets.count) * duration,
                rms: bucket.rms,
                peak: bucket.peak,
                crossingRate: bucket.crossingRate,
                score: memorableScore,
                rise: rise,
                afterglow: afterglow
            )
        )
    }

    let minimumSeparation = max(0.75, duration / 180)
    var selected: [StudyFrame] = []
    for frame in frames.sorted(by: { $0.score > $1.score }) {
        guard selected.allSatisfy({ abs($0.time - frame.time) >= minimumSeparation })
        else { continue }
        selected.append(frame)
        if selected.count >= 24 { break }
    }
    return selected
}

func hash(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
}

extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
