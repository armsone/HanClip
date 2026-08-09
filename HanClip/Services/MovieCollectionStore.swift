import AVFoundation
import Combine
import CoreLocation
import Foundation
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
}

@MainActor
final class MovieCollectionStore: ObservableObject {
    static let shared = MovieCollectionStore()

    @Published private(set) var movies: [CollectedMovie] = []

    private let fileManager = FileManager.default

    private init() {
        load()
    }

    func videoURL(for movie: CollectedMovie) -> URL {
        collectionDirectory.appendingPathComponent(movie.videoFilename)
    }

    func poster(for movie: CollectedMovie) -> UIImage? {
        UIImage(
            contentsOfFile: collectionDirectory
                .appendingPathComponent(movie.posterFilename).path
        )
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
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 1_080)
            let candidateSeconds = [
                min(max(duration * 0.12, 0), 2),
                min(max(duration * 0.03, 0), 0.5),
                0
            ]
            for seconds in candidateSeconds {
                guard let image = try? await generator.image(
                    at: CMTime(seconds: seconds, preferredTimescale: 600)
                ).image else { continue }
                let poster = UIImage(cgImage: image)
                if let data = poster.jpegData(compressionQuality: 0.84) {
                    try? data.write(to: posterURL, options: .atomic)
                }
                break
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
                locationName: resolvedLocationName
            )
        }.value
        movies.insert(movie, at: 0)
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
