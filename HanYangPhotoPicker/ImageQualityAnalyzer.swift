import CoreImage
import Foundation
import Darwin
import ImageIO
import UIKit
import Vision
import Photos
import CryptoKit

/// 한양(HanAI) 사진 고르기 확장이 사용하는 로컬 전용 staging/채점 보조 기능.
/// 네트워크를 쓰지 않고, 원본 전체를 메모리에 올리지 않도록 항상 다운샘플된
/// 썸네일만 분석에 사용한다.
enum HanYangStaging {
    private static let folderName = "HanYangStaging"

    static func containerURL() throws -> URL {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw HanYangError.storageUnavailable
        }
        let folder = url.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder
    }

    static func batchDirectory(batchID: UUID) throws -> URL {
        let folder = try containerURL().appendingPathComponent(
            batchID.uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder
    }

    static func stage(
        fileAt sourceURL: URL,
        batchID: UUID,
        index: Int,
        fallbackExtension: String
    ) throws -> URL {
        let ext = sourceURL.pathExtension.isEmpty
            ? fallbackExtension
            : sourceURL.pathExtension
        let destination = try batchDirectory(batchID: batchID)
            .appendingPathComponent("\(index)-\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        try writeManifest(batchID: batchID, state: "staging", selectedFilenames: [])
        return destination
    }

    private struct Manifest: Codable {
        let batchID: UUID
        let state: String
        let stagedFilenames: [String]
        let selectedFilenames: [String]
        let updatedAt: Date
    }

    static func writeManifest(batchID: UUID, state: String, selectedFilenames: [String]) throws {
        let folder = try batchDirectory(batchID: batchID)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0 != "manifest.json" && $0 != "active.lock" }.sorted()
        let manifest = Manifest(batchID: batchID, state: state, stagedFilenames: names, selectedFilenames: selectedFilenames, updatedAt: Date())
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    }

    static func clearStagedMedia(batchID: UUID) {
        guard let folder = try? batchDirectory(batchID: batchID),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.lastPathComponent != "active.lock" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func deleteBatch(batchID: UUID) {
        guard let folder = try? batchDirectory(batchID: batchID) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    static func recoverAbandonedBatches(excluding currentBatchID: UUID) {
        guard let container = try? containerURL(),
              let folders = try? FileManager.default.contentsOfDirectory(at: container, includingPropertiesForKeys: [.isDirectoryKey])
        else { return }
        for folder in folders {
            guard let batch = UUID(uuidString: folder.lastPathComponent), batch != currentBatchID,
                  FileManager.default.fileExists(atPath: folder.appendingPathComponent("active.lock").path)
            else { continue }
            let descriptor = Darwin.open(folder.appendingPathComponent("active.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { continue }
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                let manifestURL = folder.appendingPathComponent("manifest.json")
                let manifest = (try? Data(contentsOf: manifestURL)).flatMap {
                    try? JSONDecoder().decode(Manifest.self, from: $0)
                }
                // PhotoKit may still be reading files after an extension was terminated.
                let mayStillBeSaving = manifest.map {
                    $0.state == "saving" && Date().timeIntervalSince($0.updatedAt) < 15 * 60
                } ?? false
                if !mayStillBeSaving { try? FileManager.default.removeItem(at: folder) }
                flock(descriptor, LOCK_UN)
            }
            Darwin.close(descriptor)
        }
    }

    enum HanYangError: LocalizedError {
        case storageUnavailable
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .storageUnavailable:
                "분석용 임시 저장소를 열 수 없습니다."
            case .decodeFailed:
                "사진을 읽을 수 없습니다."
            }
        }
    }
}

struct ImageQualityMeasurement {
    let sharpness: Double
    let exposureScore: Double
    let pixelCount: Int
    let aestheticsScore: Double?
}

enum ImageQualityAnalyzer {
    /// 채점용 다운샘플 상한. 원본 전체를 올리지 않기 위한 메모리 경계.
    private static let analysisMaxPixelSize: CGFloat = 768
    static let thumbnailMaxPixelSize: CGFloat = 160

    static func downsampledCGImage(
        at url: URL,
        maxPixelSize: CGFloat
    ) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions)
        else { return nil }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }

    static func originalPixelCount(at url: URL) -> Int {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return 0 }
        return width * height
    }

    /// 선명도/노출/해상도는 항상 계산하고, iOS18 이상에서는 Vision의
    /// 이미지 미학 점수(CalculateImageAestheticsScoresRequest)를 더한다.
    /// 그 이하에서는 이 세 지표만으로 점수를 매긴다는 점을 UI에서 알린다.
    static func measure(fileAt url: URL) async -> ImageQualityMeasurement? {
        guard let cgImage = downsampledCGImage(
            at: url,
            maxPixelSize: analysisMaxPixelSize
        ) else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let sharpness = sharpnessScore(for: ciImage, context: context)
        let exposure = exposureScore(for: ciImage, context: context)
        let pixelCount = originalPixelCount(at: url)
        let aesthetics = await aestheticsScore(for: cgImage)

        return ImageQualityMeasurement(
            sharpness: sharpness,
            exposureScore: exposure,
            pixelCount: pixelCount,
            aestheticsScore: aesthetics
        )
    }

    private static func sharpnessScore(
        for image: CIImage,
        context: CIContext
    ) -> Double {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        guard width > 2, height > 2 else { return 0 }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        context.render(image, toBitmap: &pixels, rowBytes: width * 4,
            bounds: image.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        func luminance(_ x: Int, _ y: Int) -> Double {
            let offset = (y * width + x) * 4
            return (0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1])
                + 0.0722 * Double(pixels[offset + 2])) / 255
        }
        var sum = 0.0
        var sumSquares = 0.0
        let count = Double((width - 2) * (height - 2))
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let value = luminance(x - 1, y) + luminance(x + 1, y)
                    + luminance(x, y - 1) + luminance(x, y + 1) - 4 * luminance(x, y)
                sum += value
                sumSquares += value * value
            }
        }
        let variance = max(0, sumSquares / count - pow(sum / count, 2))
        return min(1, variance * 20)
    }

    private static func exposureScore(
        for image: CIImage,
        context: CIContext
    ) -> Double {
        guard let brightness = averagePixelValue(
            of: image,
            extent: image.extent,
            context: context
        ) else { return 0.5 }
        return max(0, 1 - abs(brightness - 0.5) * 2)
    }

    private static func averagePixelValue(
        of image: CIImage,
        extent: CGRect,
        context: CIContext
    ) -> Double? {
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let r = Double(pixel[0]) / 255
        let g = Double(pixel[1]) / 255
        let b = Double(pixel[2]) / 255
        return (r + g + b) / 3
    }

    private static func aestheticsScore(for cgImage: CGImage) async -> Double? {
        guard #available(iOS 18.0, *) else { return nil }
        do {
            let request = CalculateImageAestheticsScoresRequest()
            let observation = try await request.perform(on: cgImage, orientation: nil)
            return Double(observation.overallScore)
        } catch {
            return nil
        }
    }
}

/// A filesystem lease distinguishes abandoned batches from another active extension.
final class HanYangBatchLease {
    private let descriptor: Int32
    init(batchID: UUID) throws {
        let folder = try HanYangStaging.batchDirectory(batchID: batchID)
        descriptor = Darwin.open(folder.appendingPathComponent("active.lock").path,
            O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw HanYangStaging.HanYangError.storageUnavailable }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw HanYangStaging.HanYangError.storageUnavailable
        }
    }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}

struct HanYangAlbumPhoto {
    let fileURL: URL
    let originalFilename: String?
    var assetIdentifier: String? = nil
}

struct HanYangAlbumSaveResult {
    let albumName: String
    let savedCount: Int
    let albumCount: Int
}

/// Adds existing Photos assets to an album. No asset creation or photo copying.
/// The selection UI must provide original PHAsset identifiers before enabling save.
enum HanYangAlbumSaver {
    enum SaveError: LocalizedError {
        case originalReferencesUnavailable, limitedAccess, denied, missingOriginal
        var errorDescription: String? {
            switch self {
            case .originalReferencesUnavailable:
                "선택한 원본 사진의 참조가 연결되지 않았습니다. 복사본은 만들지 않습니다."
            case .limitedAccess:
                "앨범에 정리하려면 사진 접근을 ‘전체 접근’으로 허용해야 합니다. 설정에서 한클립의 사진 권한을 바꿔 주세요."
            case .denied: "설정에서 한클립의 사진 접근을 허용해 주세요."
            case .missingOriginal: "일부 원본 사진을 찾지 못했습니다. 사진 선택을 다시 확인해 주세요."
            }
        }
    }

    private final class AlbumChangeSubmitted: @unchecked Sendable {
        private let lock = NSLock()
        private var submitted = false
        func mark() { lock.lock(); submitted = true; lock.unlock() }
        func value() -> Bool { lock.lock(); defer { lock.unlock() }; return submitted }
    }

    static func save(photos: [HanYangAlbumPhoto], destination: HanYangAlbumDestination) async throws -> HanYangAlbumSaveResult {
        let identifiers = photos.compactMap(\.assetIdentifier)
        guard !photos.isEmpty, identifiers.count == photos.count, Set(identifiers).count == identifiers.count else {
            throw SaveError.originalReferencesUnavailable
        }
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) {
                    continuation.resume(returning: $0)
                }
            }
        }
        guard status == .authorized else {
            throw status == .limited ? SaveError.limitedAccess : SaveError.denied
        }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var byIdentifier: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in byIdentifier[asset.localIdentifier] = asset }
        let originals = identifiers.compactMap { byIdentifier[$0] }
        guard originals.count == photos.count else { throw SaveError.missingOriginal }
        let existingAlbum: PHAssetCollection?
        let existingAssets: PHFetchResult<PHAsset>?
        if case let .existing(identifier, _) = destination {
            guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject,
                  album.canPerform(.addContent) else { throw SaveError.missingOriginal }
            existingAlbum = album
            existingAssets = PHAsset.fetchAssets(in: album, options: nil)
        } else { existingAlbum = nil; existingAssets = nil }
        let presentIDs = Set((0..<(existingAssets?.count ?? 0)).compactMap { existingAssets?.object(at: $0).localIdentifier })
        let additions = originals.filter { !presentIDs.contains($0.localIdentifier) }
        if existingAlbum == nil || !additions.isEmpty {
            let submitted = AlbumChangeSubmitted()
            try await PHPhotoLibrary.shared().performChanges {
                let request: PHAssetCollectionChangeRequest?
                if let album = existingAlbum, let snapshot = existingAssets {
                    request = PHAssetCollectionChangeRequest(for: album, assets: snapshot)
                } else {
                    request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: destination.name)
                }
                if let request {
                    request.addAssets(additions as NSArray)
                    submitted.mark()
                }
            }
            guard submitted.value() else { throw SaveError.missingOriginal }
        }
        return HanYangAlbumSaveResult(albumName: destination.name, savedCount: originals.count, albumCount: originals.count)
    }
}

enum HanYangAlbumDestination {
    case existing(identifier: String, name: String)
    case new(name: String)
    var name: String {
        switch self {
        case let .existing(_, name), let .new(name): return name
        }
    }
}

/// Strict byte matching of shared files against existing Photos resources.
/// No visual similarity guesses, library imports, or network downloads.
actor HanYangOriginalResolver {
    enum MatchError: LocalizedError {
        case notFound, ambiguous, unavailableResource
        var errorDescription: String? {
            switch self {
            case .notFound:
                "공유된 파일과 정확히 같은 원본을 찾지 못했습니다. 변환되지 않은 원본 형식으로 다시 공유해 주세요. 앨범은 변경하지 않았습니다."
            case .ambiguous:
                "내용이 같은 원본이 여러 개여서 선택한 사진을 확정하지 못했습니다. 앨범은 변경하지 않았습니다."
            case .unavailableResource:
                "기기에 내려받지 않은 원본이 있어 일치 여부를 확정하지 못했습니다. 사진 앱에서 원본을 내려받은 뒤 다시 공유해 주세요. 앨범은 변경하지 않았습니다."
            }
        }
    }
    private var resourceDigests: [String: Data] = [:]

    func resolve(fileURL: URL, suggestedFilename: String?, progress: @escaping @Sendable (Int, Int) async -> Void) async throws -> String {
        try Task.checkCancellation()
        let target = try Self.fileDigest(fileURL)
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        options.includeAllBurstAssets = true
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        let suggestedBase = suggestedFilename.map {
            (URL(fileURLWithPath: $0).lastPathComponent as NSString).deletingPathExtension.lowercased()
        }
        var preferredIndices: [Int] = []
        var otherIndices: [Int] = []
        for index in 0..<assets.count {
            try Task.checkCancellation()
            let resources = PHAssetResource.assetResources(for: assets.object(at: index))
            if let name = suggestedBase, resources.contains(where: {
                ($0.originalFilename as NSString).deletingPathExtension.lowercased() == name
            }) { preferredIndices.append(index) }
            else { otherIndices.append(index) }
        }
        // Filenames set read priority only. No asset is omitted from uniqueness checking.
        let search = preferredIndices + otherIndices
        var matches = Set<String>()
        var unresolved = false
        for (position, index) in search.enumerated() {
            let asset = assets.object(at: index)
            let resources = PHAssetResource.assetResources(for: asset).filter {
                $0.type == .photo || $0.type == .fullSizePhoto || $0.type == .alternatePhoto
            }
            try Task.checkCancellation()
            var matched = false
            var readFailed = false
            for resource in resources {
                let key = asset.localIdentifier + "|" + String(resource.type.rawValue) + "|" + resource.originalFilename
                do {
                    let digest: Data
                    if let cached = resourceDigests[key] { digest = cached }
                    else {
                        digest = try await Self.resourceDigest(resource)
                        resourceDigests[key] = digest
                    }
                    if digest == target { matched = true; break }
                } catch {
                    try Task.checkCancellation()
                    readFailed = true
                }
            }
            if matched { matches.insert(asset.localIdentifier) }
            if matches.count > 1 { throw MatchError.ambiguous }
            if position.isMultiple(of: 16) || position + 1 == search.count {
                await progress(position + 1, search.count)
            }
            if !matched && readFailed { unresolved = true }
        }
        guard matches.count <= 1 else { throw MatchError.ambiguous }
        guard !unresolved else { throw MatchError.unavailableResource }
        guard let identifier = matches.first else { throw MatchError.notFound }
        return identifier
    }

    private static func fileDigest(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        return Data(hash.finalize())
    }

    private final class ResourceRequest: @unchecked Sendable {
        private let lock = NSLock()
        private var hash = SHA256()
        private var requestID: PHAssetResourceDataRequestID = 0
        private var cancelled = false
        func update(_ data: Data) { lock.lock(); hash.update(data: data); lock.unlock() }
        func digest() -> Data { lock.lock(); defer { lock.unlock() }; return Data(hash.finalize()) }
        func setID(_ id: PHAssetResourceDataRequestID) {
            lock.lock(); requestID = id; let shouldCancel = cancelled; lock.unlock()
            if shouldCancel { PHAssetResourceManager.default().cancelDataRequest(id) }
        }
        func cancel() {
            lock.lock(); cancelled = true; let id = requestID; lock.unlock()
            if id != 0 { PHAssetResourceManager.default().cancelDataRequest(id) }
        }
    }

    private static func resourceDigest(_ resource: PHAssetResource) async throws -> Data {
        let request = ResourceRequest()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = false
                let id = PHAssetResourceManager.default().requestData(for: resource, options: options,
                    dataReceivedHandler: { request.update($0) }, completionHandler: { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: request.digest()) }
                    })
                request.setID(id)
            }
        } onCancel: { request.cancel() }
    }
}
