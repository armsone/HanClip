import AVFoundation
import Combine
import CoreLocation
import Foundation
import QuickLookThumbnailing
import UIKit

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
}

@MainActor
final class MovieCollectionStore: ObservableObject {
    static let shared = MovieCollectionStore()
    static let maximumMovieCount = 20

    @Published private(set) var movies: [CollectedMovie] = []

    private let fileManager = FileManager.default
    private var attemptedPosterRepairs: Set<UUID> = []

    private init() {
        load()
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
            repairPosterIfNeeded(for: movie, at: posterURL)
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
            if let data = await Self.makePosterData(
                from: asset,
                sourceURL: destination,
                duration: duration
            ) {
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
                pinnedAt: nil
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

    private func repairPosterIfNeeded(
        for movie: CollectedMovie,
        at posterURL: URL
    ) {
        guard attemptedPosterRepairs.insert(movie.id).inserted else { return }
        let videoURL = videoURL(for: movie)
        Task { [weak self] in
            let data = await Task.detached(priority: .utility) {
                let asset = AVURLAsset(url: videoURL)
                let loadedDuration = try? await asset.load(.duration).seconds
                let duration = loadedDuration?.isFinite == true
                    ? max(0, loadedDuration ?? 0)
                    : 0
                return await Self.makePosterData(
                    from: asset,
                    sourceURL: videoURL,
                    duration: duration
                )
            }.value
            guard let data else { return }
            do {
                try data.write(to: posterURL, options: .atomic)
                self?.objectWillChange.send()
            } catch {
                return
            }
        }
    }

    private nonisolated static func makePosterData(
        from asset: AVAsset,
        sourceURL: URL,
        duration: Double
    ) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 1_080)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let safeDuration = max(duration, 0)
        let rawCandidates = safeDuration > 0
            ? [
                min(0.5, safeDuration * 0.02),
                safeDuration * 0.10,
                safeDuration * 0.30,
                safeDuration * 0.55,
                safeDuration * 0.80
            ]
            : [0]
        var visitedTimes: Set<Int64> = []
        var bestPoster: (data: Data, score: Double)?

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

            let score = posterScore(for: cgImage)
            if bestPoster == nil || score > bestPoster?.score ?? 0 {
                bestPoster = (data, score)
            }
            if score >= 54 { break }
        }
        if let bestPoster, bestPoster.score > 4 {
            return bestPoster.data
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: sourceURL,
            size: CGSize(width: 720, height: 1_080),
            scale: 1,
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)
        else { return bestPoster?.data }
        return representation.uiImage.jpegData(compressionQuality: 0.84)
    }

    private nonisolated static func posterScore(for image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        return posterScore(for: cgImage)
    }

    private nonisolated static func posterScore(for cgImage: CGImage) -> Double {
        let width = 12
        let height = 12
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
        guard rendered else { return 0 }

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
        return mean + sqrt(variance) * 0.55
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
            return "컬렉션에는 영화를 최대 20개까지 보관할 수 있습니다."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
