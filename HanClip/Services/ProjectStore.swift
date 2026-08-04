import Foundation
import UIKit

struct SavedProjectSummary: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let isPinned: Bool
    let clipCount: Int
    let totalDuration: Double
    let thumbnailFilename: String?
    let thumbnailFilenames: [String]
    let memo: String
    let renderedVideoByteCount: Int64?
    let storedByteCount: Int64
}

struct LoadedProject {
    let id: UUID
    let clips: [ClipItem]
    let defaultDuration: Double
    let outputAspectRatio: OutputAspectRatio?
    let automaticSourceSize: CGSize
    let textOverlaySettings: WatermarkSettings
    let backgroundMusicSettings: BackgroundMusicSettings
}

enum ProjectStore {
    private static let maximumProjectCount = 10
    private static let maximumPinnedProjectCount = 5
    private static let metadataFilename = "project.json"

    static func listProjects() -> [SavedProjectSummary] {
        guard let root = try? projectsRoot() else { return [] }
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return directories
            .compactMap { directory in
                guard let stored = try? readStoredProject(at: directory)
                else { return nil }
                return stored.summary(
                    storedByteCount: directoryByteCount(at: directory)
                )
            }
            .sorted {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }
                return $0.updatedAt > $1.updatedAt
            }
    }

    @discardableResult
    static func save(
        clips: [ClipItem],
        defaultDuration: Double,
        outputAspectRatio: OutputAspectRatio?,
        automaticSourceSize: CGSize,
        textOverlaySettings: WatermarkSettings,
        backgroundMusicSettings: BackgroundMusicSettings,
        activeProjectID: UUID?
    ) throws -> UUID {
        let root = try projectsRoot()
        let existing = activeProjectID.flatMap {
            try? readStoredProject(at: projectDirectory(for: $0, root: root))
        }
        let projectID = existing?.id ?? UUID()
        let staging = root.appendingPathComponent(
            ".staging-\(projectID.uuidString)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: staging,
            withIntermediateDirectories: true
        )

        do {
            var storedClips: [StoredClip] = []
            for (index, clip) in clips.enumerated() {
                let thumbnailFilename = "thumbnail-\(index).jpg"
                guard let thumbnailData = clip.thumbnail.jpegData(
                    compressionQuality: 0.86
                ) else {
                    throw ProjectStoreError.thumbnailEncodingFailed
                }
                try thumbnailData.write(
                    to: staging.appendingPathComponent(thumbnailFilename),
                    options: .atomic
                )

                let storedSource = try storeSource(
                    clip.source,
                    index: index,
                    in: staging
                )
                storedClips.append(
                    StoredClip(
                        id: clip.id,
                        source: storedSource,
                        thumbnailFilename: thumbnailFilename,
                        duration: clip.duration,
                        photoDuration: clip.photoDuration,
                        livePhotoDuration: clip.livePhotoDuration,
                        isLivePhoto: clip.isLivePhoto,
                        livePhotoMode: clip.livePhotoMode.rawValue,
                        mediaKind: clip.mediaKind.rawValue,
                        sourceDuration: clip.sourceDuration,
                        trimStart: clip.trimStart,
                        audioWaveform: clip.audioWaveform,
                        audioPeakTime: clip.audioPeakTime,
                        audioPeakTimes: clip.audioPeakTimes,
                        videoSegmentMode: clip.videoSegmentMode.rawValue,
                        isVideoSegmentParent: clip.isVideoSegmentParent,
                        videoSegmentParentID: clip.videoSegmentParentID,
                        sourceWidth: clip.sourcePixelSize.width,
                        sourceHeight: clip.sourcePixelSize.height
                    )
                )
            }

            var renderedVideoFilename: String?
            var renderedVideoByteCount: Int64?
            if let filename = existing?.renderedVideoFilename {
                let existingVideo = projectDirectory(
                    for: projectID,
                    root: root
                ).appendingPathComponent(filename)
                if FileManager.default.fileExists(
                    atPath: existingVideo.path
                ) {
                    try FileManager.default.copyItem(
                        at: existingVideo,
                        to: staging.appendingPathComponent(filename)
                    )
                    renderedVideoFilename = filename
                    renderedVideoByteCount = existing?
                        .renderedVideoByteCount
                }
            }

            let storedBackgroundMusicSettings = try storeBackgroundMusic(
                backgroundMusicSettings,
                existing: existing,
                existingDirectory: projectDirectory(for: projectID, root: root),
                in: staging
            )

            let stored = StoredProject(
                id: projectID,
                createdAt: existing?.createdAt ?? Date(),
                updatedAt: Date(),
                isPinned: existing?.isPinned ?? false,
                memo: existing?.memo,
                defaultDuration: defaultDuration,
                outputAspectRatio: outputAspectRatio?.rawValue,
                automaticSourceWidth: automaticSourceSize.width,
                automaticSourceHeight: automaticSourceSize.height,
                textOverlaySettings: textOverlaySettings.withLogoEnabled(false),
                backgroundMusicSettings: storedBackgroundMusicSettings,
                clips: storedClips,
                renderedVideoFilename: renderedVideoFilename,
                renderedVideoByteCount: renderedVideoByteCount
            )
            try write(stored, to: staging)

            let destination = projectDirectory(for: projectID, root: root)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staging, to: destination)
            try enforceMaximumCount()
            return projectID
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    static func saveRenderedVideo(
        _ sourceURL: URL,
        toProject id: UUID
    ) throws -> URL {
        let directory = projectDirectory(
            for: id,
            root: try projectsRoot()
        )
        var stored = try readStoredProject(at: directory)
        let sourceFilename = sourceURL.lastPathComponent
        let filename = sourceFilename.isEmpty
            ? VideoComposer.renderedOutputFilename()
            : sourceFilename
        let destination = directory.appendingPathComponent(filename)
        let staging = directory.appendingPathComponent(
            ".rendered-video-\(UUID().uuidString).mp4"
        )

        do {
            try FileManager.default.copyItem(at: sourceURL, to: staging)
            if let oldFilename = stored.renderedVideoFilename,
               oldFilename != filename {
                try? FileManager.default.removeItem(
                    at: directory.appendingPathComponent(oldFilename)
                )
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staging, to: destination)

            let values = try destination.resourceValues(
                forKeys: [.fileSizeKey]
            )
            stored.renderedVideoFilename = filename
            stored.renderedVideoByteCount = values.fileSize.map(Int64.init)
            stored.updatedAt = Date()
            try write(stored, to: directory)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    static func load(id: UUID) throws -> LoadedProject {
        let directory = projectDirectory(
            for: id,
            root: try projectsRoot()
        )
        let stored = try readStoredProject(at: directory)
        let clips = try stored.clips.map { storedClip in
            let thumbnailURL = directory.appendingPathComponent(
                storedClip.thumbnailFilename
            )
            guard let thumbnail = UIImage(contentsOfFile: thumbnailURL.path)
            else {
                throw ProjectStoreError.missingProjectFile
            }

            let restoredSource = try restoreSource(
                storedClip.source,
                in: directory
            )
            let livePhotoMode = LivePhotoMode(
                rawValue: storedClip.livePhotoMode
            ) ?? .still
            let mediaKind = storedClip.mediaKind
                .flatMap(ClipMediaKind.init(rawValue:))
                ?? (storedClip.isLivePhoto ? .livePhoto : .photo)
            let photoDuration = storedClip.photoDuration
                ?? (storedClip.isLivePhoto
                    ? stored.defaultDuration
                    : storedClip.duration)
            let livePhotoDuration = storedClip.sourceDuration
                ?? storedClip.livePhotoDuration
                ?? (storedClip.isLivePhoto ? storedClip.duration : nil)
            let activeDuration = mediaKind == .video
                ? storedClip.duration
                : storedClip.isLivePhoto
                ? (livePhotoMode == .motion
                    ? (livePhotoDuration ?? storedClip.duration)
                    : photoDuration)
                : storedClip.duration

            return ClipItem(
                id: storedClip.id,
                source: restoredSource,
                thumbnail: thumbnail,
                duration: activeDuration,
                photoDuration: photoDuration,
                livePhotoDuration: livePhotoDuration,
                isLivePhoto: storedClip.isLivePhoto,
                livePhotoMode: livePhotoMode,
                mediaKind: mediaKind,
                sourceDuration: storedClip.sourceDuration,
                trimStart: storedClip.trimStart ?? 0,
                audioWaveform: storedClip.audioWaveform ?? [],
                audioPeakTime: storedClip.audioPeakTime,
                audioPeakTimes: storedClip.audioPeakTimes ?? [],
                videoSegmentMode: storedClip.videoSegmentMode
                    .map(VideoSegmentMode.init(storedValue:)) ?? .single,
                isVideoSegmentParent: storedClip.isVideoSegmentParent ?? false,
                videoSegmentParentID: storedClip.videoSegmentParentID,
                sourcePixelSize: CGSize(
                    width: storedClip.sourceWidth,
                    height: storedClip.sourceHeight
                )
            )
        }

        return LoadedProject(
            id: stored.id,
            clips: clips,
            defaultDuration: stored.defaultDuration,
            outputAspectRatio: stored.outputAspectRatio.flatMap(
                OutputAspectRatio.init(rawValue:)
            ),
            automaticSourceSize: CGSize(
                width: stored.automaticSourceWidth,
                height: stored.automaticSourceHeight
            ),
            textOverlaySettings: stored.textOverlaySettings
                ?? WatermarkSettings.projectDefault(),
            backgroundMusicSettings: restoreBackgroundMusic(
                stored.backgroundMusicSettings,
                in: directory
            )
        )
    }

    static func togglePin(id: UUID) throws {
        let directory = projectDirectory(
            for: id,
            root: try projectsRoot()
        )
        var stored = try readStoredProject(at: directory)

        if !stored.isPinned {
            let pinnedCount = listProjects().filter(\.isPinned).count
            guard pinnedCount < maximumPinnedProjectCount else {
                throw ProjectStoreError.pinLimitReached
            }
        }

        stored.isPinned.toggle()
        try write(stored, to: directory)
    }

    static func delete(id: UUID) throws {
        let directory = projectDirectory(
            for: id,
            root: try projectsRoot()
        )
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw ProjectStoreError.missingProjectFile
        }
        try FileManager.default.removeItem(at: directory)
    }

    static func updateMemo(id: UUID, memo: String) throws {
        let directory = projectDirectory(
            for: id,
            root: try projectsRoot()
        )
        var stored = try readStoredProject(at: directory)
        let trimmedMemo = memo.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        stored.memo = trimmedMemo.isEmpty ? nil : trimmedMemo
        try write(stored, to: directory)
    }

    static func thumbnailImage(
        for summary: SavedProjectSummary
    ) -> UIImage? {
        guard let filename = summary.thumbnailFilename,
              let root = try? projectsRoot()
        else { return nil }

        let url = projectDirectory(for: summary.id, root: root)
            .appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }

    static func thumbnailImages(
        for summary: SavedProjectSummary
    ) -> [UIImage] {
        guard let root = try? projectsRoot() else { return [] }
        let directory = projectDirectory(for: summary.id, root: root)
        return summary.thumbnailFilenames.compactMap { filename in
            UIImage(
                contentsOfFile: directory
                    .appendingPathComponent(filename)
                    .path
            )
        }
    }

    private static func directoryByteCount(at directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func enforceMaximumCount() throws {
        var projects = listProjects()
        while projects.count > maximumProjectCount {
            guard let candidate = projects
                .filter({ !$0.isPinned })
                .min(by: { $0.createdAt < $1.createdAt })
            else { break }

            let root = try projectsRoot()
            try FileManager.default.removeItem(
                at: projectDirectory(for: candidate.id, root: root)
            )
            projects.removeAll { $0.id == candidate.id }
        }
    }

    private static func storeSource(
        _ source: ClipSource,
        index: Int,
        in directory: URL
    ) throws -> StoredSource {
        switch source {
        case .photoAsset(let localIdentifier):
            return StoredSource(
                kind: .photoAsset,
                localIdentifier: localIdentifier,
                primaryFilename: nil,
                secondaryFilename: nil
            )

        case .imageFile(let url):
            let filename = try copySourceFile(
                url,
                prefix: "image-\(index)",
                fallbackExtension: "jpg",
                to: directory
            )
            return StoredSource(
                kind: .imageFile,
                localIdentifier: nil,
                primaryFilename: filename,
                secondaryFilename: nil
            )

        case .videoFile(let url):
            let filename = try copySourceFile(
                url,
                prefix: "video-\(index)",
                fallbackExtension: "mov",
                to: directory
            )
            return StoredSource(
                kind: .videoFile,
                localIdentifier: nil,
                primaryFilename: filename,
                secondaryFilename: nil
            )

        case .livePhotoFiles(let imageURL, let videoURL):
            let imageFilename = try copySourceFile(
                imageURL,
                prefix: "live-image-\(index)",
                fallbackExtension: "jpg",
                to: directory
            )
            let videoFilename = try copySourceFile(
                videoURL,
                prefix: "live-video-\(index)",
                fallbackExtension: "mov",
                to: directory
            )
            return StoredSource(
                kind: .livePhotoFiles,
                localIdentifier: nil,
                primaryFilename: imageFilename,
                secondaryFilename: videoFilename
            )
        }
    }

    private static func restoreSource(
        _ source: StoredSource,
        in directory: URL
    ) throws -> ClipSource {
        switch source.kind {
        case .photoAsset:
            guard let identifier = source.localIdentifier else {
                throw ProjectStoreError.missingProjectFile
            }
            return .photoAsset(localIdentifier: identifier)

        case .imageFile:
            return .imageFile(
                try sourceURL(source.primaryFilename, in: directory)
            )

        case .videoFile:
            return .videoFile(
                try sourceURL(source.primaryFilename, in: directory)
            )

        case .livePhotoFiles:
            return .livePhotoFiles(
                imageURL: try sourceURL(
                    source.primaryFilename,
                    in: directory
                ),
                videoURL: try sourceURL(
                    source.secondaryFilename,
                    in: directory
                )
            )
        }
    }

    private static func storeBackgroundMusic(
        _ settings: BackgroundMusicSettings,
        existing: StoredProject?,
        existingDirectory: URL,
        in staging: URL
    ) throws -> BackgroundMusicSettings? {
        guard settings.hasMusicFile, let sourceURL = settings.fileURL else {
            return nil
        }

        let ext = sourceURL.pathExtension.isEmpty
            ? "m4a"
            : sourceURL.pathExtension
        let filename = "background-music.\(ext)"
        let destination = staging.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: sourceURL.path) {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } else if let existingFilename = existing?
            .backgroundMusicSettings?
            .fileURL?
            .lastPathComponent {
            let existingURL = existingDirectory
                .appendingPathComponent(existingFilename)
            guard FileManager.default.fileExists(atPath: existingURL.path)
            else { return nil }
            try FileManager.default.copyItem(at: existingURL, to: destination)
        } else {
            return nil
        }

        var stored = settings
        stored.fileURL = URL(fileURLWithPath: filename)
        return stored
    }

    private static func restoreBackgroundMusic(
        _ settings: BackgroundMusicSettings?,
        in directory: URL
    ) -> BackgroundMusicSettings {
        guard var settings, let filename = settings.fileURL?.lastPathComponent
        else {
            return .projectDefault
        }
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .projectDefault
        }
        settings.fileURL = url
        return settings
    }

    private static func sourceURL(
        _ filename: String?,
        in directory: URL
    ) throws -> URL {
        guard let filename else {
            throw ProjectStoreError.missingProjectFile
        }
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectStoreError.missingProjectFile
        }
        return url
    }

    private static func copySourceFile(
        _ source: URL,
        prefix: String,
        fallbackExtension: String,
        to directory: URL
    ) throws -> String {
        let ext = source.pathExtension.isEmpty
            ? fallbackExtension
            : source.pathExtension
        let filename = "\(prefix).\(ext)"
        let destination = directory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: source, to: destination)
        return filename
    }

    private static func projectsRoot() throws -> URL {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ProjectStoreError.storageUnavailable
        }
        let root = support.appendingPathComponent(
            "HanClipProjects",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private static func projectDirectory(
        for id: UUID,
        root: URL
    ) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private static func readStoredProject(
        at directory: URL
    ) throws -> StoredProject {
        let data = try Data(
            contentsOf: directory.appendingPathComponent(metadataFilename)
        )
        return try decoder.decode(StoredProject.self, from: data)
    }

    private static func write(
        _ project: StoredProject,
        to directory: URL
    ) throws {
        let data = try encoder.encode(project)
        try data.write(
            to: directory.appendingPathComponent(metadataFilename),
            options: .atomic
        )
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct StoredProject: Codable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var memo: String?
    let defaultDuration: Double
    let outputAspectRatio: String?
    let automaticSourceWidth: Double
    let automaticSourceHeight: Double
    let textOverlaySettings: WatermarkSettings?
    let backgroundMusicSettings: BackgroundMusicSettings?
    let clips: [StoredClip]
    var renderedVideoFilename: String?
    var renderedVideoByteCount: Int64?

    func summary(storedByteCount: Int64) -> SavedProjectSummary {
        SavedProjectSummary(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isPinned: isPinned,
            clipCount: clips.filter { $0.isVideoSegmentParent != true }.count,
            totalDuration: clips
                .filter { $0.isVideoSegmentParent != true }
                .reduce(0) { $0 + $1.duration },
            thumbnailFilename: clips
                .first { $0.isVideoSegmentParent != true }?
                .thumbnailFilename,
            thumbnailFilenames: clips
                .filter { $0.isVideoSegmentParent != true }
                .dropFirst()
                .prefix(8)
                .map(\.thumbnailFilename),
            memo: memo ?? "",
            renderedVideoByteCount: renderedVideoByteCount,
            storedByteCount: storedByteCount
        )
    }
}

private struct StoredClip: Codable {
    let id: UUID
    let source: StoredSource
    let thumbnailFilename: String
    let duration: Double
    let photoDuration: Double?
    let livePhotoDuration: Double?
    let isLivePhoto: Bool
    let livePhotoMode: String
    let mediaKind: String?
    let sourceDuration: Double?
    let trimStart: Double?
    let audioWaveform: [Double]?
    let audioPeakTime: Double?
    let audioPeakTimes: [Double]?
    let videoSegmentMode: String?
    let isVideoSegmentParent: Bool?
    let videoSegmentParentID: UUID?
    let sourceWidth: Double
    let sourceHeight: Double
}

private struct StoredSource: Codable {
    let kind: StoredSourceKind
    let localIdentifier: String?
    let primaryFilename: String?
    let secondaryFilename: String?
}

private enum StoredSourceKind: String, Codable {
    case photoAsset
    case imageFile
    case videoFile
    case livePhotoFiles
}

private enum ProjectStoreError: LocalizedError {
    case storageUnavailable
    case thumbnailEncodingFailed
    case missingProjectFile
    case pinLimitReached

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "영화 저장 공간을 열 수 없습니다."
        case .thumbnailEncodingFailed:
            return "영화 대표 이미지를 저장할 수 없습니다."
        case .missingProjectFile:
            return "영화의 원본 파일을 찾을 수 없습니다."
        case .pinLimitReached:
            return "영화는 최대 5개까지 상단에 고정할 수 있습니다."
        }
    }
}
