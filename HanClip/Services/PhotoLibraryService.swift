import AVFoundation
import Foundation
import Photos
import UIKit

enum PhotoLibraryService {
    static func requestReadAccess() async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch current {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let result = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return result == .authorized || result == .limited
        default:
            return false
        }
    }

    static func asset(localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        ).firstObject
    }

    static func mediaCounts(
        in month: Date,
        calendar: Calendar,
        progress: (@MainActor (Double) -> Void)?
    ) -> [Date: Int] {
        guard let interval = calendar.dateInterval(of: .month, for: month)
        else { return [:] }

        let options = PHFetchOptions()
        options.predicate = mediaPredicate(
            from: interval.start,
            to: interval.end
        )
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: true)
        ]

        let assets = PHAsset.fetchAssets(with: options)
        var counts: [Date: Int] = [:]
        let totalCount = max(assets.count, 1)
        assets.enumerateObjects { asset, index, _ in
            guard let creationDate = asset.creationDate else { return }
            let date = calendar.startOfDay(for: creationDate)
            counts[date, default: 0] += 1
            guard index % 25 == 0 || index == assets.count - 1
            else { return }
            Task { @MainActor in
                progress?(Double(index + 1) / Double(totalCount))
            }
        }
        if assets.count == 0 {
            Task { @MainActor in
                progress?(1)
            }
        }
        return counts
    }

    static func mediaAssets(
        on dates: Set<Date>,
        calendar: Calendar
    ) -> [PHAsset] {
        dates
            .sorted()
            .flatMap { date in
                guard let nextDay = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: date
                ) else { return [PHAsset]() }

                let options = PHFetchOptions()
                options.predicate = mediaPredicate(from: date, to: nextDay)
                options.sortDescriptors = [
                    NSSortDescriptor(key: "creationDate", ascending: true)
                ]

                let result = PHAsset.fetchAssets(with: options)
                var assets: [PHAsset] = []
                result.enumerateObjects { asset, _, _ in
                    assets.append(asset)
                }
                return assets
            }
    }

    static func closestMediaDate(to targetDate: Date, calendar: Calendar)
        -> Date?
    {
        let targetDay = calendar.startOfDay(for: targetDate)
        guard let nextDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: targetDay
        ) else { return nil }

        if mediaAssetDate(from: targetDay, to: nextDay, ascending: true)
            != nil {
            return targetDay
        }

        let previousDate = previousMediaDate(
            before: targetDay,
            calendar: calendar
        )
        let nextDate = mediaAssetDate(
            from: nextDay,
            to: Date.distantFuture,
            ascending: true,
            calendar: calendar
        )

        switch (previousDate, nextDate) {
        case let (previousDate?, nextDate?):
            let previousDistance = targetDay.timeIntervalSince(previousDate)
            let nextDistance = nextDate.timeIntervalSince(targetDay)
            return previousDistance <= nextDistance ? previousDate : nextDate
        case let (previousDate?, nil):
            return previousDate
        case let (nil, nextDate?):
            return nextDate
        case (nil, nil):
            return nil
        }
    }

    static func previousMediaDate(before targetDate: Date, calendar: Calendar)
        -> Date?
    {
        let targetDay = calendar.startOfDay(for: targetDate)
        let options = PHFetchOptions()
        options.predicate = mediaPredicate(
            from: Date.distantPast,
            to: targetDay
        )
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        options.fetchLimit = 1

        guard let asset = PHAsset.fetchAssets(with: options).firstObject,
              let creationDate = asset.creationDate
        else { return nil }

        return calendar.startOfDay(for: creationDate)
    }

    private static func mediaAssetDate(
        from start: Date,
        to end: Date,
        ascending: Bool,
        calendar: Calendar = .current
    ) -> Date? {
        let options = PHFetchOptions()
        options.predicate = mediaPredicate(from: start, to: end)
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: ascending)
        ]
        options.fetchLimit = 1

        guard let asset = PHAsset.fetchAssets(with: options).firstObject,
              let creationDate = asset.creationDate
        else { return nil }

        return calendar.startOfDay(for: creationDate)
    }

    private static func mediaPredicate(from start: Date, to end: Date)
        -> NSPredicate
    {
        NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@ AND "
                + "(mediaType == %d OR mediaType == %d)",
            start as NSDate,
            end as NSDate,
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
    }

    static func livePhotoAsset(
        matchingOriginalFilename originalFilename: String
    ) -> PHAsset? {
        let expectedName = normalizedFilename(originalFilename)
        guard !expectedName.isEmpty else { return nil }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0",
            PHAssetMediaSubtype.photoLive.rawValue
        )
        let assets = PHAsset.fetchAssets(
            with: .image,
            options: options
        )

        var matchedAsset: PHAsset?
        assets.enumerateObjects { asset, _, stop in
            let resources = PHAssetResource.assetResources(for: asset)
            let matches = resources.contains { resource in
                guard resource.type == .photo
                        || resource.type == .fullSizePhoto
                else { return false }
                return normalizedFilename(resource.originalFilename)
                    == expectedName
            }
            if matches {
                matchedAsset = asset
                stop.pointee = true
            }
        }
        return matchedAsset
    }

    private static func normalizedFilename(_ filename: String) -> String {
        URL(fileURLWithPath: filename)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()
    }

    static func thumbnail(
        for asset: PHAsset,
        size: CGSize = CGSize(width: 320, height: 320)
    ) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !didResume else { return }
                if info?[PHImageResultIsDegradedKey] as? Bool == true {
                    return
                }
                if info?[PHImageCancelledKey] as? Bool == true {
                    didResume = true
                    continuation.resume(throwing: CancellationError())
                    return
                }

                didResume = true
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: MediaError.imageUnavailable)
                }
            }
        }
    }

    static func fullImage(for asset: PHAsset) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.version = .current
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, info in
                guard !didResume else { return }
                if info?[PHImageCancelledKey] as? Bool == true {
                    didResume = true
                    continuation.resume(throwing: CancellationError())
                    return
                }

                didResume = true
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let data, let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: MediaError.imageUnavailable)
                }
            }
        }
    }

    static func exportPairedVideo(for asset: PHAsset) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: {
            $0.type == .fullSizePairedVideo || $0.type == .pairedVideo
        }) else {
            throw MediaError.livePhotoVideoUnavailable
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: url,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: url)
                }
            }
        }
    }

    static func exportVideo(for asset: PHAsset) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: {
            $0.type == .fullSizeVideo || $0.type == .video
        }) else {
            throw MediaError.videoTrackUnavailable
        }
        let fileExtension = URL(fileURLWithPath: resource.originalFilename)
            .pathExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension.isEmpty ? "mov" : fileExtension)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: url,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: url)
                }
            }
        }
    }

    static func livePhotoVideoDuration(for asset: PHAsset) async throws -> Double {
        let url = try await exportPairedVideo(for: asset)
        defer { try? FileManager.default.removeItem(at: url) }

        let duration = try await AVURLAsset(url: url).load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw MediaError.livePhotoVideoUnavailable
        }
        return max(0.5, seconds)
    }

    static func videoDuration(at url: URL) async throws -> Double {
        let duration = try await AVURLAsset(url: url).load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw MediaError.videoTrackUnavailable
        }
        return max(0.5, seconds)
    }

    static func saveVideo(
        _ url: URL,
        albumName: String? = nil
    ) async throws {
        let trimmedAlbumName = albumName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAlbumName = !(trimmedAlbumName?.isEmpty ?? true)
        let accessLevel: PHAccessLevel = hasAlbumName
            ? .readWrite
            : .addOnly
        let status = await PHPhotoLibrary.requestAuthorization(
            for: accessLevel
        )
        guard status == .authorized || status == .limited else {
            throw MediaError.photoLibraryDenied
        }

        guard let trimmedAlbumName, !trimmedAlbumName.isEmpty else {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(
                    atFileURL: url
                )
            }
            return
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "title == %@",
            trimmedAlbumName
        )
        let existingAlbum = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: fetchOptions
        ).firstObject

        try await PHPhotoLibrary.shared().performChanges {
            let assetRequest = PHAssetChangeRequest
                .creationRequestForAssetFromVideo(atFileURL: url)
            guard let assetPlaceholder = assetRequest?
                .placeholderForCreatedAsset
            else { return }

            if let existingAlbum {
                PHAssetCollectionChangeRequest(
                    for: existingAlbum
                )?.addAssets([assetPlaceholder] as NSArray)
            } else {
                let albumRequest = PHAssetCollectionChangeRequest
                    .creationRequestForAssetCollection(
                        withTitle: trimmedAlbumName
                    )
                albumRequest.addAssets(
                    [assetPlaceholder] as NSArray
                )
            }
        }
    }
}

enum KoreanHolidayService {
    private static let cacheKey = "hanClipKoreanHolidayJSON"
    private static let endpoint =
        "https://holidays.hyunbin.page/basic.json"

    static func cachedHolidayNames(for year: Int, calendar: Calendar)
        -> [Date: String]
    {
        holidayNames(
            from: cachedHolidayMap(),
            year: year,
            calendar: calendar
        )
    }

    static func refreshedHolidayNames(for year: Int, calendar: Calendar)
        async -> [Date: String]
    {
        do {
            let holidayMap = try await fetchHolidayMap()
            cache(holidayMap)
            return holidayNames(
                from: holidayMap,
                year: year,
                calendar: calendar
            )
        } catch {
            return cachedHolidayNames(for: year, calendar: calendar)
        }
    }

    private static func fetchHolidayMap() async throws
        -> [String: [String]]
    {
        guard let url = URL(string: endpoint) else { return [:] }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else { return [:] }

        return try decodeHolidayMap(from: data)
    }

    private static func cachedHolidayMap() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let dates = try? decodeHolidayMap(from: data)
        else { return [:] }
        return dates
    }

    private static func cache(_ holidayMap: [String: [String]]) {
        guard let data = try? JSONEncoder().encode(holidayMap) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private static func decodeHolidayMap(from data: Data) throws
        -> [String: [String]]
    {
        if let years = try? JSONDecoder()
            .decode([String: [String: [String]]].self, from: data) {
            return years.values.reduce(into: [String: [String]]()) {
                result,
                holidays in
                holidays.forEach { date, names in
                    result[date] = names
                }
            }
        }

        if let dates = try? JSONDecoder().decode([String: [String]].self, from: data) {
            return dates
        }

        return try JSONDecoder()
            .decode([String: String].self, from: data)
            .mapValues { [$0] }
    }

    private static func holidayNames(
        from holidayMap: [String: [String]],
        year: Int,
        calendar: Calendar
    ) -> [Date: String] {
        let prefix = "\(year)-"
        return holidayMap.reduce(into: [Date: String]()) { result, item in
            let key = item.key
            guard key.hasPrefix(prefix) else { return }
            let parts = key.split(separator: "-").compactMap {
                Int(String($0))
            }
            guard parts.count == 3 else { return }
            guard let date = calendar.date(
                from: DateComponents(
                    year: parts[0],
                    month: parts[1],
                    day: parts[2]
                )
            ) else { return }
            guard let name = item.value.first else { return }
            result[calendar.startOfDay(for: date)] = name
        }
    }
}

enum MediaError: LocalizedError {
    case imageUnavailable
    case livePhotoVideoUnavailable
    case photoLibraryDenied
    case videoTrackUnavailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            "사진을 읽을 수 없습니다."
        case .livePhotoVideoUnavailable:
            "Live Photo의 움직임 영상을 읽을 수 없습니다."
        case .photoLibraryDenied:
            "사진 보관함 사용 권한이 필요합니다."
        case .videoTrackUnavailable:
            "영상 트랙을 읽을 수 없습니다."
        case .exportFailed(let message):
            "영상 생성에 실패했습니다. \(message)"
        }
    }
}
