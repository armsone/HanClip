import AVFoundation
import Photos
import SwiftUI

private enum PreviewSaveRequest {
    case photos(albumName: String)
    case files
}

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var clips: [ClipItem] = []
    @Published var defaultDuration: Double = 3
    @Published var outputAspectRatio: OutputAspectRatio?
    @Published private(set) var automaticSourceSize = CGSize(
        width: 1,
        height: 1
    )
    @Published var isPickerPresented = false
    @Published var isFileImporterPresented = false
    @Published var isExporting = false
    @Published var progressMessage = ""
    @Published var previewProgress = 0.0
    @Published var isPreviewRendering = false
    @Published var isImportingSharedItems = false
    @Published var sharedImportProgress = 0.0
    @Published var previewThumbnail: UIImage?
    @Published var exportedURL: URL?
    @Published var showPreview = false
    @Published var showFileExporter = false
    @Published var alertMessage: String?
    @Published private(set) var savedProjects: [SavedProjectSummary] = []
    @Published private(set) var activeProjectID: UUID?
    @Published private(set) var isProjectOpen = false
    @Published private(set) var pendingSharedItemCount = 0
    @Published private(set) var pendingSharedThumbnails: [UIImage] = []
    @Published private(set) var newlySavedProjectID: UUID?
    private var previewTask: Task<Void, Never>?
    private var pendingThumbnailTask: Task<Void, Never>?
    private var pendingPhotoAlbumName = ""
    private var previewSaveRequest: PreviewSaveRequest?

    init() {
        reloadProjects()
        refreshPendingSharedItems()
    }

    var totalDuration: Double {
        clips.reduce(0) { $0 + $1.duration }
    }

    var totalDurationText: String {
        let minutes = Int(totalDuration) / 60
        let seconds = totalDuration - Double(minutes * 60)
        if minutes > 0 {
            return String(format: "%d분 %.1f초", minutes, seconds)
        }
        return String(format: "%.1f초", seconds)
    }

    var fileDocument: VideoFileDocument? {
        exportedURL.map(VideoFileDocument.init(sourceURL:))
    }

    var outputRenderSize: CGSize {
        outputAspectRatio?.renderSize
            ?? OutputAspectRatio.renderSize(for: automaticSourceSize)
    }

    var automaticAspectRatioTitle: String {
        "첫 사진"
    }

    func beginNewProject() {
        guard !isProjectOpen else { return }
        previewTask?.cancel()
        previewTask = nil
        releaseEditingMemory()
        exportedURL = nil
        showPreview = false
        previewSaveRequest = nil
        showFileExporter = false
        alertMessage = nil
        isProjectOpen = true
    }

    func openPicker() {
        if !isProjectOpen {
            beginNewProject()
            importPendingItemsIntoNewProject()
        }
        Task {
            if await PhotoLibraryService.requestReadAccess() {
                isPickerPresented = true
            } else {
                alertMessage = "사진 보관함 접근을 허용해 주세요."
            }
        }
    }

    func openFilePicker() {
        if !isProjectOpen {
            beginNewProject()
            importPendingItemsIntoNewProject()
        }
        isFileImporterPresented = true
    }

    func addPickedItems(_ newItems: [ClipItem]) {
        if !newItems.isEmpty {
            isProjectOpen = true
        }
        if clips.isEmpty, let first = newItems.first {
            automaticSourceSize = first.sourcePixelSize
            outputAspectRatio = nil
        }
        clips.append(contentsOf: newItems.map { item in
            var adjusted = item
            if item.mediaKind == .photo
                || (item.isLivePhoto && item.livePhotoMode == .still) {
                adjusted.duration = defaultDuration
                adjusted.photoDuration = defaultDuration
            } else if item.mediaKind == .video,
                      let sourceDuration = item.sourceDuration {
                let selectedDuration = min(defaultDuration, sourceDuration)
                adjusted.duration = selectedDuration
                adjusted.photoDuration = selectedDuration
                let peak = item.audioPeakTime ?? sourceDuration / 2
                adjusted.trimStart = max(
                    0,
                    min(
                        sourceDuration - selectedDuration,
                        peak - selectedDuration / 2
                    )
                )
            }
            return adjusted
        })
    }

    func applyDefaultDurationToAll() {
        for index in clips.indices {
            if clips[index].mediaKind == .video {
                let sourceDuration = clips[index].sourceDuration
                    ?? clips[index].duration
                let selectedDuration = min(defaultDuration, sourceDuration)
                let center = clips[index].trimStart
                    + clips[index].duration / 2
                clips[index].duration = selectedDuration
                clips[index].photoDuration = selectedDuration
                clips[index].trimStart = max(
                    0,
                    min(
                        sourceDuration - selectedDuration,
                        center - selectedDuration / 2
                    )
                )
                continue
            }
            clips[index].photoDuration = defaultDuration
            if !clips[index].isLivePhoto
                || clips[index].livePhotoMode == .still {
                clips[index].duration = defaultDuration
            }
        }
    }

    func selectFullRangeForAllVideoClips() {
        for index in clips.indices
        where clips[index].mediaKind == .video {
            let sourceDuration = clips[index].sourceDuration
                ?? clips[index].duration
            clips[index].trimStart = 0
            clips[index].duration = sourceDuration
            clips[index].photoDuration = sourceDuration
        }
    }

    func resetAllVideoClipRanges() {
        for index in clips.indices
        where clips[index].mediaKind == .video {
            let sourceDuration = clips[index].sourceDuration
                ?? clips[index].duration
            let selectedDuration = min(defaultDuration, sourceDuration)
            let peak = clips[index].audioPeakTime
                ?? sourceDuration / 2

            clips[index].duration = selectedDuration
            clips[index].photoDuration = selectedDuration
            clips[index].trimStart = max(
                0,
                min(
                    sourceDuration - selectedDuration,
                    peak - selectedDuration / 2
                )
            )
        }
    }

    func removeClips(at offsets: IndexSet) {
        clips.remove(atOffsets: offsets)
    }

    func removeClip(id: UUID) {
        clips.removeAll { $0.id == id }
    }

    func moveClips(from offsets: IndexSet, to destination: Int) {
        clips.move(fromOffsets: offsets, toOffset: destination)
    }

    func reset() {
        previewTask?.cancel()
        previewTask = nil
        releaseEditingMemory()
        isPickerPresented = false
        isFileImporterPresented = false
        isExporting = false
        progressMessage = ""
        previewProgress = 0
        isPreviewRendering = false
        isImportingSharedItems = false
        sharedImportProgress = 0
        previewThumbnail = nil
        exportedURL = nil
        showPreview = false
        previewSaveRequest = nil
        showFileExporter = false
        alertMessage = nil
        activeProjectID = nil
        isProjectOpen = false
        reloadProjects()
    }

    func saveProjectAndReturnHome() {
        guard !clips.isEmpty, !isExporting else {
            if clips.isEmpty {
                reset()
            }
            return
        }

        isExporting = true
        progressMessage = "프로젝트를 저장하는 중…"

        do {
            _ = try ProjectStore.save(
                clips: clips,
                defaultDuration: defaultDuration,
                outputAspectRatio: outputAspectRatio,
                automaticSourceSize: automaticSourceSize,
                activeProjectID: activeProjectID
            )
            reset()
        } catch {
            isExporting = false
            progressMessage = ""
            alertMessage = error.localizedDescription
        }
    }

    func saveProjectAndOpenPreview() {
        guard !clips.isEmpty, !isExporting else { return }
        isExporting = true
        isPreviewRendering = true
        previewProgress = 0
        previewThumbnail = clips.first?.thumbnail
        progressMessage = "프로젝트를 저장하는 중…"

        previewTask = Task {
            do {
                let savedID = try ProjectStore.save(
                    clips: clips,
                    defaultDuration: defaultDuration,
                    outputAspectRatio: outputAspectRatio,
                    automaticSourceSize: automaticSourceSize,
                    activeProjectID: activeProjectID
                )
                try Task.checkCancellation()
                reloadProjects()
                activeProjectID = savedProjects.contains {
                    $0.id == savedID
                } ? savedID : nil

                previewProgress = 0.10
                progressMessage = "미리보기 영상을 만드는 중…"
                let output = try await VideoComposer().compose(
                    items: clips,
                    renderSize: outputRenderSize
                ) { [self] progress in
                    await updatePreviewProgress(progress)
                }
                try Task.checkCancellation()
                previewProgress = 0.96
                progressMessage = "영상 파일을 저장하는 중…"
                let storedOutput = try ProjectStore.saveRenderedVideo(
                    output,
                    toProject: savedID
                )
                try? FileManager.default.removeItem(at: output)
                exportedURL = storedOutput
                reloadProjects()
                releaseEditingMemory()
                isProjectOpen = false
                previewProgress = 1
                progressMessage = ""
                isExporting = false
                isPreviewRendering = false
                previewThumbnail = nil
                previewTask = nil
                showPreview = true
            } catch is CancellationError {
                progressMessage = ""
                previewProgress = 0
                isExporting = false
                isPreviewRendering = false
                previewThumbnail = nil
                previewTask = nil
            } catch {
                progressMessage = ""
                previewProgress = 0
                isExporting = false
                isPreviewRendering = false
                previewThumbnail = nil
                previewTask = nil
                alertMessage = error.localizedDescription
            }
        }
    }

    func cancelPreviewGeneration() {
        guard isPreviewRendering else { return }
        progressMessage = "미리보기 생성을 취소하는 중…"
        previewTask?.cancel()
    }

    private func updatePreviewProgress(_ progress: Double) {
        previewProgress = 0.10 + progress * 0.85
        guard !clips.isEmpty else { return }
        let index = min(
            Int(progress * Double(clips.count)),
            clips.count - 1
        )
        previewThumbnail = clips[index].thumbnail
    }

    private func releaseEditingMemory() {
        clips = []
        defaultDuration = 3
        outputAspectRatio = nil
        automaticSourceSize = CGSize(width: 1, height: 1)
        isPickerPresented = false
        isFileImporterPresented = false
        activeProjectID = nil
    }

    func loadProject(id: UUID) {
        do {
            let project = try ProjectStore.load(id: id)
            clips = project.clips
            defaultDuration = project.defaultDuration
            outputAspectRatio = project.outputAspectRatio
            automaticSourceSize = project.automaticSourceSize
            exportedURL = nil
            showPreview = false
            activeProjectID = project.id
            isProjectOpen = true
        } catch {
            alertMessage = error.localizedDescription
            reloadProjects()
        }
    }

    func editLastSavedProject() {
        showPreview = false
        let projectID = activeProjectID
            ?? savedProjects.max(by: {
                $0.updatedAt < $1.updatedAt
            })?.id
        guard let projectID else { return }
        loadProject(id: projectID)
    }

    func toggleProjectPin(id: UUID) {
        do {
            try ProjectStore.togglePin(id: id)
            reloadProjects()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func deleteProject(id: UUID) {
        do {
            try ProjectStore.delete(id: id)
            if activeProjectID == id {
                activeProjectID = nil
            }
            reloadProjects()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func updateProjectMemo(id: UUID, memo: String) {
        do {
            try ProjectStore.updateMemo(id: id, memo: memo)
            reloadProjects()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func reloadProjects() {
        savedProjects = ProjectStore.listProjects()
    }

    func refreshPendingSharedItems() {
        let records = SharedInbox.pendingRecords()
        let thumbnailRecords = Array(records.prefix(5))
        pendingSharedItemCount = records.count
        pendingSharedThumbnails = []
        pendingThumbnailTask?.cancel()

        guard !thumbnailRecords.isEmpty else { return }
        let recordIDs = records.map(\.id)
        pendingThumbnailTask = Task {
            let thumbnails = await Self.makePendingSharedThumbnails(
                for: thumbnailRecords
            )
            guard !Task.isCancelled,
                  SharedInbox.pendingRecords().map(\.id) == recordIDs
            else { return }
            pendingSharedThumbnails = thumbnails
        }
    }

    func handlePendingSharedItemsOnActivation() {
        refreshPendingSharedItems()
        guard pendingSharedItemCount > 0 else { return }
        guard isProjectOpen, !isExporting else { return }

        guard !clips.isEmpty else {
            reset()
            refreshPendingSharedItems()
            return
        }

        do {
            let savedID = try ProjectStore.save(
                clips: clips,
                defaultDuration: defaultDuration,
                outputAspectRatio: outputAspectRatio,
                automaticSourceSize: automaticSourceSize,
                activeProjectID: activeProjectID
            )
            reset()
            newlySavedProjectID = savedID
            refreshPendingSharedItems()
        } catch {
            alertMessage =
                "현재 프로젝트를 저장하지 못해 공유 파일 대기 화면으로 "
                + "이동하지 못했습니다. \(error.localizedDescription)"
        }
    }

    func deletePendingSharedItems() {
        SharedInbox.clearPendingImports()
        pendingSharedItemCount = 0
        pendingSharedThumbnails = []
    }

    func loadProjectAndImportPending(id: UUID) {
        loadProject(id: id)
        guard isProjectOpen, pendingSharedItemCount > 0 else { return }
        importSharedItems(destination: .existingProject)
    }

    private func importPendingItemsIntoNewProject() {
        refreshPendingSharedItems()
        guard pendingSharedItemCount > 0 else { return }
        importSharedItems(destination: .newProject)
    }

    func saveToPhotosFromPreview(albumName: String) {
        previewSaveRequest = .photos(
            albumName: albumName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )
        showPreview = false
    }

    func saveToFilesFromPreview() {
        previewSaveRequest = .files
        showPreview = false
    }

    func previewDidDismiss() {
        guard let previewSaveRequest else {
            if clips.isEmpty {
                editLastSavedProject()
            }
            return
        }
        self.previewSaveRequest = nil

        switch previewSaveRequest {
        case .photos(let albumName):
            pendingPhotoAlbumName = albumName
            saveToPhotos()
        case .files:
            showFileExporter = true
        }
    }

    func saveToPhotos() {
        guard let exportedURL else { return }
        let albumName = pendingPhotoAlbumName
        isExporting = true
        progressMessage = "사진 앱에 저장하는 중…"

        Task {
            do {
                try await PhotoLibraryService.saveVideo(
                    exportedURL,
                    albumName: albumName
                )
                isExporting = false
                progressMessage = ""
                pendingPhotoAlbumName = ""
                alertMessage = albumName.isEmpty
                    ? "사진 앱에 저장했습니다."
                    : "\(albumName) 앨범에 저장했습니다."
            } catch {
                isExporting = false
                progressMessage = ""
                alertMessage = error.localizedDescription
            }
        }
    }

    func importSharedItems(
        destination: SharedImportDestination? = nil
    ) {
        let storedDestination = SharedInbox.consumeImportDestination()
        let requestedDestination = destination ?? storedDestination
        let records = SharedInbox.consumePendingRecords()
        guard !records.isEmpty else { return }
        pendingSharedItemCount = 0
        isImportingSharedItems = true
        sharedImportProgress = 0
        progressMessage =
            "공유한 파일 \(records.count)개를 불러오는 중…"

        Task {
            var imported: [ClipItem] = []
            var unresolvedLivePhotoCount = 0
            for (index, record) in records.enumerated() {
                do {
                    let primary = try SharedInbox.fileURL(
                        named: record.primaryFilename
                    )
                    switch record.kind {
                    case .image:
                        guard let image = UIImage(
                            contentsOfFile: primary.path
                        ) else { continue }
                        imported.append(
                            ClipItem(
                                source: .imageFile(primary),
                                thumbnail: image,
                                duration: defaultDuration,
                                sourcePixelSize: image.size
                            )
                        )

                    case .video:
                        imported.append(
                            try await makeVideoClip(from: primary)
                        )

                    case .livePhoto:
                        guard let image = UIImage(
                                contentsOfFile: primary.path
                              )
                        else { continue }

                        if let secondaryName = record.secondaryFilename {
                            let secondary = try SharedInbox.fileURL(
                                named: secondaryName
                            )
                            let duration = try await PhotoLibraryService
                                .videoDuration(at: secondary)
                            imported.append(
                                ClipItem(
                                    source: .livePhotoFiles(
                                        imageURL: primary,
                                        videoURL: secondary
                                    ),
                                    thumbnail: image,
                                    duration: duration,
                                    photoDuration: defaultDuration,
                                    livePhotoDuration: duration,
                                    isLivePhoto: true,
                                    livePhotoMode: .motion,
                                    sourcePixelSize: image.size
                                )
                            )
                            continue
                        }

                        if let originalFilename = record.originalFilename,
                           await PhotoLibraryService.requestReadAccess(),
                           let asset = PhotoLibraryService.livePhotoAsset(
                            matchingOriginalFilename: originalFilename
                           ) {
                            let duration = try await PhotoLibraryService
                                .livePhotoVideoDuration(for: asset)
                            imported.append(
                                ClipItem(
                                    source: .photoAsset(
                                        localIdentifier:
                                            asset.localIdentifier
                                    ),
                                    thumbnail: image,
                                    duration: duration,
                                    photoDuration: defaultDuration,
                                    livePhotoDuration: duration,
                                    isLivePhoto: true,
                                    livePhotoMode: .motion,
                                    mediaKind: .livePhoto,
                                    sourcePixelSize: CGSize(
                                        width: asset.pixelWidth,
                                        height: asset.pixelHeight
                                    )
                                )
                            )
                        } else {
                            unresolvedLivePhotoCount += 1
                            imported.append(
                                ClipItem(
                                    source: .imageFile(primary),
                                    thumbnail: image,
                                    duration: defaultDuration,
                                    photoDuration: defaultDuration,
                                    sourcePixelSize: image.size
                                )
                            )
                        }
                    }
                } catch {
                    continue
                }

                let completedCount = index + 1
                sharedImportProgress =
                    Double(completedCount) / Double(records.count)
                progressMessage =
                    "공유한 파일 \(completedCount)/\(records.count)개를 "
                    + "불러오는 중…"
            }

            isImportingSharedItems = false
            progressMessage = ""
            sharedImportProgress = 0

            if !imported.isEmpty {
                switch requestedDestination {
                case .newProject:
                    prepareNewProjectForSharedImport()
                case .existingProject:
                    prepareExistingProjectForSharedImport()
                case nil:
                    if !isProjectOpen {
                        beginNewProject()
                    }
                }
                addPickedItems(imported)
                if unresolvedLivePhotoCount > 0 {
                    alertMessage =
                        "공유한 항목 \(imported.count)개를 가져왔습니다. "
                        + "Live Photo \(unresolvedLivePhotoCount)개는 "
                        + "사진 보관함에서 원본을 찾지 못해 사진으로 "
                        + "가져왔습니다."
                } else {
                    alertMessage =
                        "공유한 항목 \(imported.count)개를 가져왔습니다."
                }
            } else {
                alertMessage =
                    "공유한 항목을 불러오지 못했습니다."
            }
        }
    }

    private func prepareNewProjectForSharedImport() {
        if isProjectOpen, !clips.isEmpty {
            _ = try? ProjectStore.save(
                clips: clips,
                defaultDuration: defaultDuration,
                outputAspectRatio: outputAspectRatio,
                automaticSourceSize: automaticSourceSize,
                activeProjectID: activeProjectID
            )
        }

        previewTask?.cancel()
        previewTask = nil
        releaseEditingMemory()
        exportedURL = nil
        showPreview = false
        previewSaveRequest = nil
        showFileExporter = false
        isProjectOpen = true
        reloadProjects()
    }

    private func prepareExistingProjectForSharedImport() {
        guard !isProjectOpen else { return }
        reloadProjects()
        if let latestProject = savedProjects.max(by: {
            $0.updatedAt < $1.updatedAt
        }) {
            loadProject(id: latestProject.id)
        } else {
            beginNewProject()
            alertMessage =
                "기존 프로젝트가 없어 새 프로젝트에 추가했습니다."
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            var imported: [ClipItem] = []
            for source in urls {
                let hasAccess = source.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        source.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let ext = source.pathExtension.isEmpty
                        ? "mov"
                        : source.pathExtension
                    let local = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                    try FileManager.default.copyItem(at: source, to: local)
                    imported.append(try await makeVideoClip(from: local))
                } catch {
                    continue
                }
            }
            addPickedItems(imported)
            if imported.isEmpty {
                alertMessage = "선택한 영상 파일을 가져올 수 없습니다."
            }
        }
    }

    func updateVideoTrim(
        id: UUID,
        start: Double,
        duration: Double
    ) {
        guard let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].mediaKind == .video
        else { return }
        let sourceDuration = clips[index].sourceDuration
            ?? clips[index].duration
        let safeDuration = min(
            sourceDuration,
            max(0.5, duration)
        )
        clips[index].duration = safeDuration
        clips[index].photoDuration = safeDuration
        clips[index].trimStart = max(
            0,
            min(sourceDuration - safeDuration, start)
        )
    }

    private func makeVideoClip(from url: URL) async throws -> ClipItem {
        let thumbnail = try await videoThumbnail(for: url)
        let duration = try await PhotoLibraryService.videoDuration(at: url)
        let analysis = try? await AudioAnalysisService.analyze(url: url)
        let selectedDuration = min(defaultDuration, duration)
        let peak = analysis?.peakTime ?? duration / 2
        let start = max(
            0,
            min(duration - selectedDuration, peak - selectedDuration / 2)
        )
        return ClipItem(
            source: .videoFile(url),
            thumbnail: thumbnail,
            duration: selectedDuration,
            photoDuration: selectedDuration,
            mediaKind: .video,
            sourceDuration: duration,
            trimStart: start,
            audioWaveform: analysis?.waveform ?? [],
            audioPeakTime: peak,
            sourcePixelSize: thumbnail.size
        )
    }

    private func videoThumbnail(for url: URL) async throws -> UIImage {
        try await Task.detached {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let image = try generator.copyCGImage(
                at: .zero,
                actualTime: nil
            )
            return UIImage(cgImage: image)
        }.value
    }

    private static func makePendingSharedThumbnails(
        for records: [SharedImportRecord]
    ) async -> [UIImage] {
        await Task.detached {
            records.compactMap { record in
                guard let url = try? SharedInbox.fileURL(
                    named: record.primaryFilename
                ) else { return nil }

                switch record.kind {
                case .image, .livePhoto:
                    return UIImage(contentsOfFile: url.path)
                case .video:
                    let asset = AVURLAsset(url: url)
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    guard let image = try? generator.copyCGImage(
                        at: .zero,
                        actualTime: nil
                    ) else { return nil }
                    return UIImage(cgImage: image)
                }
            }
        }.value
    }

}
