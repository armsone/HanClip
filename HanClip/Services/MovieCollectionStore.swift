import AVFoundation
import Combine
import CoreLocation
import Foundation
import QuickLookThumbnailing
import UIKit
import Vision

struct HanClipPlace: Equatable, Sendable {
    let countryCode: String
    let countryName: String
    let cityName: String

    var collectionDisplayName: String {
        countryCode == "KR" ? cityName : "\(countryName) \(cityName)"
    }
}

struct CollectedMovie: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let videoFilename: String
    let posterFilename: String
    let createdAt: Date
    let duration: Double
    let madeAt: Date?
    let shootingStartAt: Date?
    let shootingEndAt: Date?
    let locationName: String?
    var isPinned: Bool?
    var pinnedAt: Date?
    var posterSelectionVersion: Int?
}

enum CollectionPosterEngine: String, Sendable {
    case deviceAI
    case hanClipAI
}

struct CollectionPosterCandidate: Identifiable, Sendable {
    let id: UUID
    let imageData: Data
    let engine: CollectionPosterEngine
    let timeSeconds: Double
}

private struct AnalyzedPosterFrame {
    let data: Data
    let timeSeconds: Double
    let deviceScore: Double
    let hanClipScore: Double
    let featurePrint: VNFeaturePrintObservation?
}

@MainActor
final class MovieCollectionStore: ObservableObject {
    static let shared = MovieCollectionStore()
    static let maximumMovieCount = 30
    private nonisolated static let currentPosterSelectionVersion = 2

    @Published private(set) var movies: [CollectedMovie] = []
    @Published private(set) var aiPosterCompletedCount = 0
    @Published private(set) var aiPosterTotalCount = 0

    private let fileManager = FileManager.default
    private var attemptedPosterRepairs: Set<UUID> = []
    private var activePosterSelections: Set<UUID> = []

    private init() {
        load()
        Task { [weak self] in
            await Task.yield()
            await self?.regenerateOutdatedPosters()
        }
    }

    func videoURL(for movie: CollectedMovie) -> URL {
        collectionDirectory.appendingPathComponent(movie.videoFilename)
    }

    func poster(for movie: CollectedMovie) -> UIImage? {
        let posterURL = collectionDirectory
            .appendingPathComponent(movie.posterFilename)
        guard let image = UIImage(contentsOfFile: posterURL.path),
              Self.posterScore(for: image) > 4
        else {
            repairPosterIfNeeded(for: movie)
            return nil
        }
        return image
    }

    @discardableResult
    func importMovie(
        from sourceURL: URL,
        title: String? = nil,
        madeAt: Date? = nil,
        shootingRange: ClosedRange<Date>? = nil,
        location: CLLocation? = nil,
        locationName: String? = nil
    ) async throws
        -> CollectedMovie {
        guard movies.count < Self.maximumMovieCount else {
            throw MovieCollectionStoreError.collectionFull
        }
        let id = UUID()
        let sourceExtension = sourceURL.pathExtension.isEmpty
            ? "mov"
            : sourceURL.pathExtension.lowercased()
        let videoFilename = "\(id.uuidString).\(sourceExtension)"
        let posterFilename = "\(id.uuidString).jpg"
        let destination = collectionDirectory
            .appendingPathComponent(videoFilename)
        let posterURL = collectionDirectory
            .appendingPathComponent(posterFilename)
        let sourceMetadata = await sourceMetadata(for: sourceURL)
        let resolvedMadeAt = madeAt ?? sourceMetadata.creationDate
        let fallbackTitle = sourceURL.deletingPathExtension().lastPathComponent
        let resolvedTitle = title?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).nilIfEmpty
            ?? resolvedMadeAt.map(Self.collectionDateTitle)
            ?? fallbackTitle.nilIfEmpty
            ?? "새 영화"

        let resolvedShootingStart = shootingRange?.lowerBound
            ?? sourceMetadata.shootingStartAt
            ?? resolvedMadeAt
        let resolvedShootingEnd = shootingRange?.upperBound
            ?? sourceMetadata.shootingEndAt
            ?? resolvedShootingStart
        let geocodedLocationName = await placeName(
            for: location ?? sourceMetadata.location
        )
        let resolvedLocationName = locationName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).nilIfEmpty
            ?? sourceMetadata.locationName
            ?? geocodedLocationName

        let movie = try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)

            let asset = AVURLAsset(url: destination)
            let loadedDuration = try? await asset.load(.duration).seconds
            let duration = loadedDuration?.isFinite == true
                ? max(0, loadedDuration ?? 0)
                : 0
            let posterData = await Self.makePosterData(
                from: asset,
                sourceURL: destination,
                duration: duration
            )
            if let data = posterData {
                try? data.write(to: posterURL, options: .atomic)
            }
            return CollectedMovie(
                id: id,
                title: resolvedTitle,
                videoFilename: videoFilename,
                posterFilename: posterFilename,
                createdAt: Date(),
                duration: duration,
                madeAt: resolvedMadeAt,
                shootingStartAt: resolvedShootingStart,
                shootingEndAt: resolvedShootingEnd,
                locationName: resolvedLocationName,
                isPinned: false,
                pinnedAt: nil,
                posterSelectionVersion: posterData == nil
                    ? nil
                    : Self.currentPosterSelectionVersion
            )
        }.value
        movies.append(movie)
        sortMovies()
        do {
            try save()
            return movie
        } catch {
            movies.removeAll { $0.id == movie.id }
            try? fileManager.removeItem(at: destination)
            try? fileManager.removeItem(at: posterURL)
            throw error
        }
    }

    private func repairPosterIfNeeded(for movie: CollectedMovie) {
        guard attemptedPosterRepairs.insert(movie.id).inserted else { return }
        Task { [weak self] in
            await self?.reselectPosterWithAI(for: movie)
        }
    }

    func reselectPosterWithAI(
        for movie: CollectedMovie,
        preferDifferentFromCurrent: Bool = false
    ) async {
        guard activePosterSelections.insert(movie.id).inserted,
              movies.contains(where: { $0.id == movie.id })
        else { return }
        defer { activePosterSelections.remove(movie.id) }

        let videoURL = videoURL(for: movie)
        let posterURL = collectionDirectory
            .appendingPathComponent(movie.posterFilename)
        let currentPosterData = preferDifferentFromCurrent
            ? try? Data(contentsOf: posterURL)
            : nil
        let data = await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: videoURL)
            let loadedDuration = try? await asset.load(.duration).seconds
            let duration = loadedDuration?.isFinite == true
                ? max(0, loadedDuration ?? 0)
                : 0
            return await Self.makePosterData(
                from: asset,
                sourceURL: videoURL,
                duration: duration,
                avoidingPosterData: currentPosterData
            )
        }.value
        guard let data else { return }

        do {
            try data.write(to: posterURL, options: .atomic)
            guard let index = movies.firstIndex(where: { $0.id == movie.id })
            else { return }
            movies[index].posterSelectionVersion =
                Self.currentPosterSelectionVersion
            try save()
            objectWillChange.send()
        } catch {
            return
        }
    }

    func posterCandidatesWithAI(
        for movie: CollectedMovie,
        excluding previousCandidates: [CollectionPosterCandidate] = [],
        generation: Int = 0
    ) async -> [CollectionPosterCandidate] {
        guard activePosterSelections.insert(movie.id).inserted,
              movies.contains(where: { $0.id == movie.id })
        else { return [] }
        defer { activePosterSelections.remove(movie.id) }

        let videoURL = videoURL(for: movie)
        let posterURL = collectionDirectory
            .appendingPathComponent(movie.posterFilename)
        let currentPosterData = try? Data(contentsOf: posterURL)
        let excludedPosterData = previousCandidates.map(\.imageData)
            + [currentPosterData].compactMap { $0 }
        let excludedTimes = previousCandidates.map(\.timeSeconds)
        return await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: videoURL)
            let loadedDuration = try? await asset.load(.duration).seconds
            let duration = loadedDuration?.isFinite == true
                ? max(0, loadedDuration ?? 0)
                : 0
            return await Self.makeComparisonPosterCandidates(
                from: asset,
                duration: duration,
                excludedPosterData: excludedPosterData,
                excludedTimes: excludedTimes,
                generation: generation
            )
        }.value
    }

    func applyPosterCandidate(_ data: Data, to movie: CollectedMovie) throws {
        guard let index = movies.firstIndex(where: { $0.id == movie.id })
        else { return }
        let posterURL = collectionDirectory
            .appendingPathComponent(movies[index].posterFilename)
        try data.write(to: posterURL, options: .atomic)
        movies[index].posterSelectionVersion = Self.currentPosterSelectionVersion
        try save()
        objectWillChange.send()
    }

    private func regenerateOutdatedPosters() async {
        let movieIDs = movies.filter {
            ($0.posterSelectionVersion ?? 0)
                < Self.currentPosterSelectionVersion
        }.map(\.id)
        guard !movieIDs.isEmpty else { return }
        aiPosterCompletedCount = 0
        aiPosterTotalCount = movieIDs.count
        defer {
            aiPosterCompletedCount = 0
            aiPosterTotalCount = 0
        }
        for movieID in movieIDs {
            guard let movie = movies.first(where: { $0.id == movieID })
            else { continue }
            await reselectPosterWithAI(for: movie)
            aiPosterCompletedCount += 1
        }
    }

    private nonisolated static func makePosterData(
        from asset: AVAsset,
        sourceURL: URL,
        duration: Double,
        avoidingPosterData: Data? = nil
    ) async -> Data? {
        if let candidate = await makePosterCandidates(
            from: asset,
            duration: duration,
            count: 1,
            avoidingPosterData: avoidingPosterData
        ).first {
            return candidate.data
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: sourceURL,
            size: CGSize(width: 720, height: 1_080),
            scale: 1,
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)
        else { return nil }
        return representation.uiImage.jpegData(compressionQuality: 0.84)
    }

    private nonisolated static func makePosterCandidates(
        from asset: AVAsset,
        duration: Double,
        count: Int,
        avoidingPosterData: Data?
    ) async -> [AnalyzedPosterFrame] {
        let excludedData = [avoidingPosterData].compactMap { $0 }
        let analyzed = await analyzePosterFrames(
            from: asset,
            duration: duration,
            excludedPosterData: excludedData,
            excludedTimes: [],
            generation: 0
        )
        return selectDiverseFrames(
            from: analyzed,
            count: count,
            score: \.hanClipScore,
            alreadySelected: []
        )
    }

    private nonisolated static func makeComparisonPosterCandidates(
        from asset: AVAsset,
        duration: Double,
        excludedPosterData: [Data],
        excludedTimes: [Double],
        generation: Int
    ) async -> [CollectionPosterCandidate] {
        let analyzed = await analyzePosterFrames(
            from: asset,
            duration: duration,
            excludedPosterData: excludedPosterData,
            excludedTimes: excludedTimes,
            generation: generation
        )
        let deviceFrames = selectDiverseFrames(
            from: analyzed,
            count: 8,
            score: \.deviceScore,
            alreadySelected: []
        )
        let hanClipFrames = selectDiverseFrames(
            from: analyzed.filter { frame in
                !deviceFrames.contains(where: {
                    abs($0.timeSeconds - frame.timeSeconds) < 0.001
                })
            },
            count: 8,
            score: \.hanClipScore,
            alreadySelected: deviceFrames
        )
        return deviceFrames.map {
            CollectionPosterCandidate(
                id: UUID(),
                imageData: $0.data,
                engine: .deviceAI,
                timeSeconds: $0.timeSeconds
            )
        } + hanClipFrames.map {
            CollectionPosterCandidate(
                id: UUID(),
                imageData: $0.data,
                engine: .hanClipAI,
                timeSeconds: $0.timeSeconds
            )
        }
    }

    private nonisolated static func analyzePosterFrames(
        from asset: AVAsset,
        duration: Double,
        excludedPosterData: [Data],
        excludedTimes: [Double],
        generation: Int
    ) async -> [AnalyzedPosterFrame] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 1_080)
        generator.requestedTimeToleranceBefore = CMTime(
            seconds: 0.35,
            preferredTimescale: 600
        )
        generator.requestedTimeToleranceAfter = CMTime(
            seconds: 0.35,
            preferredTimescale: 600
        )

        let safeDuration = max(duration, 0)
        let sampleCount = 36
        let phase = Double(max(0, generation % 17)) * 0.011
        let samplingPositions = (0..<sampleCount).map { index in
            let base = (Double(index) + 0.5) / Double(sampleCount)
            return 0.02 + (base + phase).truncatingRemainder(
                dividingBy: 1
            ) * 0.96
        }.sorted()
        let rawCandidates = safeDuration > 0
            ? samplingPositions.map { safeDuration * $0 }
            : [0]
        var visitedTimes: Set<Int64> = []
        var candidates: [AnalyzedPosterFrame] = []
        let excludedFeaturePrints: [VNFeaturePrintObservation] =
            excludedPosterData.compactMap { data in
            guard let image = UIImage(data: data)?.cgImage else { return nil }
            return featurePrint(for: image)
        }
        let excludedTimeDistance = max(0.35, safeDuration * 0.012)

        for seconds in rawCandidates {
            let time = CMTime(
                seconds: max(0, seconds),
                preferredTimescale: 600
            )
            guard visitedTimes.insert(time.value).inserted,
                  let cgImage = try? await generator.image(at: time).image,
                  let data = UIImage(cgImage: cgImage)
                    .jpegData(compressionQuality: 0.84)
            else { continue }

            let scores = posterAIScores(for: cgImage)
            let candidateFeaturePrint = featurePrint(for: cgImage)
            let isExcludedTime = excludedTimes.contains {
                abs($0 - seconds) < excludedTimeDistance
            }
            let closestExcludedDistance = candidateFeaturePrint.flatMap {
                minimumFeatureDistance(
                    from: $0,
                    to: excludedFeaturePrints
                )
            }
            guard !isExcludedTime else { continue }
            let featureDistance = closestExcludedDistance ?? 0.35
            let exclusionBonus = min(featureDistance, 0.8) * 90
            let similarityPenalty = featureDistance < 0.075 ? 210.0 : 0
            candidates.append(
                AnalyzedPosterFrame(
                    data: data,
                    timeSeconds: seconds,
                    deviceScore: scores.device
                        + exclusionBonus - similarityPenalty,
                    hanClipScore: scores.hanClip
                        + exclusionBonus - similarityPenalty,
                    featurePrint: candidateFeaturePrint
                )
            )
        }
        return candidates
    }

    private nonisolated static func selectDiverseFrames(
        from candidates: [AnalyzedPosterFrame],
        count: Int,
        score: KeyPath<AnalyzedPosterFrame, Double>,
        alreadySelected: [AnalyzedPosterFrame]
    ) -> [AnalyzedPosterFrame] {
        var remaining = candidates.sorted { $0[keyPath: score] > $1[keyPath: score] }
        var selected: [AnalyzedPosterFrame] = []
        while selected.count < max(1, count), !remaining.isEmpty {
            let selectedIndex: Int
            if selected.isEmpty {
                selectedIndex = 0
            } else {
                selectedIndex = remaining.indices.max { lhs, rhs in
                    diverseCandidateScore(
                        remaining[lhs],
                        score: score,
                        selected: alreadySelected + selected
                    ) < diverseCandidateScore(
                        remaining[rhs],
                        score: score,
                        selected: alreadySelected + selected
                    )
                } ?? 0
            }
            selected.append(remaining.remove(at: selectedIndex))
        }
        return selected
    }

    private nonisolated static func diverseCandidateScore(
        _ candidate: AnalyzedPosterFrame,
        score: KeyPath<AnalyzedPosterFrame, Double>,
        selected: [AnalyzedPosterFrame]
    ) -> Double {
        guard let featurePrint = candidate.featurePrint else {
            return candidate[keyPath: score]
        }
        let selectedPrints = selected.compactMap(\.featurePrint)
        let minimumDistance = minimumFeatureDistance(
            from: featurePrint,
            to: selectedPrints
        ) ?? 0
        let diversityBonus = min(max(minimumDistance, 0), 0.8) * 220
        let similarityPenalty = minimumDistance < 0.08 ? 160.0 : 0
        return candidate[keyPath: score] + diversityBonus - similarityPenalty
    }

    private nonisolated static func minimumFeatureDistance(
        from featurePrint: VNFeaturePrintObservation,
        to comparisonPrints: [VNFeaturePrintObservation]
    ) -> Double? {
        comparisonPrints.compactMap { comparison -> Double? in
            var distance: Float = 0
            guard (try? featurePrint.computeDistance(
                &distance,
                to: comparison
            )) != nil else { return nil }
            return Double(distance)
        }.min()
    }

    private nonisolated static func posterScore(for image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        return posterScore(for: cgImage)
    }

    private nonisolated static func posterScore(for cgImage: CGImage) -> Double {
        imageQualityMetrics(for: cgImage).mean
    }

    private nonisolated static func posterAIScores(
        for cgImage: CGImage
    ) -> (device: Double, hanClip: Double) {
        let metrics = imageQualityMetrics(for: cgImage)
        var deviceScore = 0.0
        var hanClipScore = 0.0

        let exposureQuality = max(0, 1 - abs(metrics.mean - 128) / 128)
        deviceScore += exposureQuality * 22
        deviceScore += min(metrics.deviation / 58, 1) * 18
        deviceScore += min(metrics.edgeStrength / 42, 1) * 28
        hanClipScore += exposureQuality * 16
        hanClipScore += min(metrics.deviation / 58, 1) * 24
        hanClipScore += min(metrics.edgeStrength / 42, 1) * 22
        if metrics.mean < 16 {
            deviceScore -= 90
            hanClipScore -= 100
        }
        if metrics.mean > 244 {
            deviceScore -= 55
            hanClipScore -= 65
        }

        let faceRequest = VNDetectFaceLandmarksRequest()
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([faceRequest, saliencyRequest])

        let faces = faceRequest.results ?? []
        hanClipScore += Double(min(faces.count, 4)) * 13
        for (index, face) in faces.enumerated() {
            let box = face.boundingBox
            let area = box.width * box.height
            let center = CGPoint(x: box.midX, y: box.midY)
            let centerDistance = hypot(center.x - 0.5, center.y - 0.5)
            let prominence = min(sqrt(area) / 0.45, 1)
            let centered = max(0, 1 - centerDistance / 0.68)
            let faceWeight = index == 0 ? 1.0 : 0.58
            deviceScore += prominence * 72 * faceWeight
            deviceScore += centered * 18 * faceWeight
            deviceScore += Double(face.confidence) * 10 * faceWeight

            let thirdsPoints = [
                CGPoint(x: 1.0 / 3.0, y: 1.0 / 3.0),
                CGPoint(x: 2.0 / 3.0, y: 1.0 / 3.0),
                CGPoint(x: 1.0 / 3.0, y: 2.0 / 3.0),
                CGPoint(x: 2.0 / 3.0, y: 2.0 / 3.0)
            ]
            let thirdsDistance = thirdsPoints.map {
                hypot(center.x - $0.x, center.y - $0.y)
            }.min() ?? 1
            let thirdsQuality = max(0, 1 - thirdsDistance / 0.48)
            hanClipScore += prominence * 54 * faceWeight
            hanClipScore += thirdsQuality * 30 * faceWeight
            hanClipScore += Double(face.confidence) * 12 * faceWeight
            if face.landmarks?.leftEye != nil,
               face.landmarks?.rightEye != nil,
               face.landmarks?.outerLips != nil {
                deviceScore += 12 * faceWeight
                hanClipScore += 20 * faceWeight
            }
            if box.minX < 0.015 || box.maxX > 0.985
                || box.minY < 0.015 || box.maxY > 0.985 {
                deviceScore -= 20 * faceWeight
                hanClipScore -= 34 * faceWeight
            }
        }

        if let salientObjects = saliencyRequest.results?.first?.salientObjects {
            for (index, object) in salientObjects.prefix(3).enumerated() {
                let box = object.boundingBox
                let centerDistance = hypot(box.midX - 0.5, box.midY - 0.5)
                let centered = max(0, 1 - centerDistance / 0.7)
                deviceScore += Double(object.confidence) * 12
                deviceScore += centered * 6
                let objectWeight = index == 0 ? 1.0 : 0.62
                hanClipScore += Double(object.confidence) * 15 * objectWeight
                hanClipScore += min(box.width * box.height / 0.34, 1)
                    * 12 * objectWeight
            }
        }
        return (deviceScore, hanClipScore)
    }

    private nonisolated static func featurePrint(
        for cgImage: CGImage
    ) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.first
    }

    private nonisolated static func imageQualityMetrics(
        for cgImage: CGImage
    ) -> (mean: Double, deviation: Double, edgeStrength: Double) {
        let width = 24
        let height = 24
        let bytesPerPixel = 4
        var pixels = [UInt8](
            repeating: 0,
            count: width * height * bytesPerPixel
        )
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard rendered else { return (0, 0, 0) }

        var luminances: [Double] = []
        luminances.reserveCapacity(width * height)
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = Double(pixels[index])
            let green = Double(pixels[index + 1])
            let blue = Double(pixels[index + 2])
            luminances.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
        }
        let mean = luminances.reduce(0, +) / Double(luminances.count)
        let variance = luminances.reduce(0) {
            $0 + pow($1 - mean, 2)
        } / Double(luminances.count)
        var edgeTotal = 0.0
        var edgeCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if x + 1 < width {
                    edgeTotal += abs(luminances[index] - luminances[index + 1])
                    edgeCount += 1
                }
                if y + 1 < height {
                    edgeTotal += abs(
                        luminances[index] - luminances[index + width]
                    )
                    edgeCount += 1
                }
            }
        }
        let edgeStrength = edgeCount > 0
            ? edgeTotal / Double(edgeCount)
            : 0
        return (mean, sqrt(variance), edgeStrength)
    }

    private nonisolated static func collectionDateTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy. M. d. (EEE)"
        return formatter.string(from: date)
    }

    func remove(_ movie: CollectedMovie) {
        try? fileManager.removeItem(at: videoURL(for: movie))
        try? fileManager.removeItem(
            at: collectionDirectory.appendingPathComponent(movie.posterFilename)
        )
        movies.removeAll { $0.id == movie.id }
        try? save()
    }

    func updateTitle(_ title: String, for movie: CollectedMovie) {
        guard let index = movies.firstIndex(where: { $0.id == movie.id })
        else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        movies[index].title = trimmed
        try? save()
    }

    func togglePin(for movie: CollectedMovie) {
        guard let index = movies.firstIndex(where: { $0.id == movie.id })
        else { return }
        let willPin = !(movies[index].isPinned == true)
        movies[index].isPinned = willPin
        movies[index].pinnedAt = willPin ? Date() : nil
        sortMovies()
        try? save()
    }

    func movePinnedMovie(sourceID: UUID, onto targetID: UUID) {
        guard sourceID != targetID,
              movies.contains(where: {
                  $0.id == sourceID && $0.isPinned == true
              }),
              movies.contains(where: {
                  $0.id == targetID && $0.isPinned == true
              })
        else { return }

        var pinnedMovies = movies.filter { $0.isPinned == true }
        guard let pinnedSourceIndex = pinnedMovies.firstIndex(where: {
            $0.id == sourceID
        }),
        let pinnedTargetIndex = pinnedMovies.firstIndex(where: {
            $0.id == targetID
        }) else { return }

        let movedMovie = pinnedMovies.remove(at: pinnedSourceIndex)
        let insertionIndex: Int
        if pinnedSourceIndex < pinnedTargetIndex {
            insertionIndex = min(pinnedTargetIndex, pinnedMovies.count)
        } else {
            insertionIndex = pinnedTargetIndex
        }
        pinnedMovies.insert(movedMovie, at: insertionIndex)

        let referenceDate = Date()
        for (offset, pinnedMovie) in pinnedMovies.enumerated() {
            guard let index = movies.firstIndex(where: {
                $0.id == pinnedMovie.id
            }) else { continue }
            movies[index].pinnedAt = referenceDate.addingTimeInterval(
                -Double(offset)
            )
        }
        sortMovies()
        try? save()
    }

    func resolvedLocationName(for location: CLLocation?) async -> String? {
        await placeName(for: location)
    }

    func resolvedPlace(for location: CLLocation?) async -> HanClipPlace? {
        await place(for: location)
    }

    private func sourceMetadata(
        for url: URL
    ) async -> (
        creationDate: Date?,
        shootingStartAt: Date?,
        shootingEndAt: Date?,
        location: CLLocation?,
        locationName: String?
    ) {
        let resourceDate = try? url.resourceValues(
            forKeys: [.creationDateKey, .contentModificationDateKey]
        )
        let asset = AVURLAsset(url: url)
        let metadata = ((try? await asset.load(.metadata)) ?? [])
            + ((try? await asset.load(.commonMetadata)) ?? [])
        let hanClipMetadata = await HanClipMovieMetadata.decode(from: metadata)

        let creationItem = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .quickTimeMetadataCreationDate
        ).first
        let creationText = try? await creationItem?.load(.stringValue)
        let metadataDate = creationText.flatMap(Self.parseMetadataDate)

        let locationItem = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .quickTimeMetadataLocationISO6709
        ).first
        let locationText = try? await locationItem?.load(.stringValue)

        return (
            metadataDate
                ?? resourceDate?.creationDate
                ?? resourceDate?.contentModificationDate,
            hanClipMetadata?.shootingStartAt,
            hanClipMetadata?.shootingEndAt,
            hanClipMetadata?.location
                ?? locationText.flatMap(Self.parseISO6709Location),
            hanClipMetadata?.routeLocationNames?.isEmpty == false
                ? hanClipMetadata?.routeLocationNames?.joined(separator: " → ")
                : hanClipMetadata?.locationName
        )
    }

    private func placeName(for location: CLLocation?) async -> String? {
        if let place = await place(for: location) {
            return place.collectionDisplayName
        }
        guard let location else { return nil }
        return String(
            format: "%.4f, %.4f",
            location.coordinate.latitude,
            location.coordinate.longitude
        )
    }

    private func place(for location: CLLocation?) async -> HanClipPlace? {
        guard let location else { return nil }
        let englishPlacemark = try? await CLGeocoder().reverseGeocodeLocation(
            location,
            preferredLocale: Locale(identifier: "en_US")
        ).first
        let isKorea = englishPlacemark?.isoCountryCode == "KR"
        let placemark: CLPlacemark?
        if isKorea {
            placemark = try? await CLGeocoder().reverseGeocodeLocation(
                location,
                preferredLocale: Locale(identifier: "ko_KR")
            ).first
        } else {
            placemark = englishPlacemark
        }

        if let placemark {
            let countryCode = placemark.isoCountryCode?.nilIfEmpty
                ?? englishPlacemark?.isoCountryCode?.nilIfEmpty
                ?? ""
            let country = placemark.country?.nilIfEmpty
                ?? englishPlacemark?.country?.nilIfEmpty
            let areaCandidates = isKorea
                ? [
                    placemark.subLocality,
                    placemark.locality,
                    placemark.subAdministrativeArea,
                    placemark.administrativeArea
                ]
                : [
                    placemark.locality,
                    placemark.subAdministrativeArea,
                    placemark.administrativeArea,
                    placemark.name
                ]
            let area = areaCandidates.compactMap { $0?.nilIfEmpty }.first
            if let area {
                return HanClipPlace(
                    countryCode: countryCode,
                    countryName: country ?? countryCode,
                    cityName: area
                )
            }
        }
        return nil
    }

    private static func parseMetadataDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func parseISO6709Location(_ value: String) -> CLLocation? {
        let pattern = #"^([+-][0-9.]+)([+-][0-9.]+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ),
              let latitudeRange = Range(match.range(at: 1), in: value),
              let longitudeRange = Range(match.range(at: 2), in: value),
              let latitude = Double(value[latitudeRange]),
              let longitude = Double(value[longitudeRange])
        else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    private var collectionDirectory: URL {
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base.appendingPathComponent("MovieCollection", isDirectory: true)
    }

    private var metadataURL: URL {
        collectionDirectory.appendingPathComponent("collection.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode(
                [CollectedMovie].self,
                from: data
              ) else { return }
        movies = decoded.filter {
            fileManager.fileExists(atPath: videoURL(for: $0).path)
        }
        sortMovies()
    }

    private func sortMovies() {
        movies.sort {
            if ($0.isPinned == true) != ($1.isPinned == true) {
                return $0.isPinned == true
            }
            if $0.isPinned == true, $1.isPinned == true {
                let firstPinnedAt = $0.pinnedAt ?? $0.createdAt
                let secondPinnedAt = $1.pinnedAt ?? $1.createdAt
                if firstPinnedAt != secondPinnedAt {
                    return firstPinnedAt > secondPinnedAt
                }
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private func save() throws {
        try fileManager.createDirectory(
            at: collectionDirectory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(movies)
        try data.write(to: metadataURL, options: .atomic)
    }
}

private enum MovieCollectionStoreError: LocalizedError {
    case collectionFull

    var errorDescription: String? {
        switch self {
        case .collectionFull:
            return "컬렉션에는 영화를 최대 30개까지 보관할 수 있습니다."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
