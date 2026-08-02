import AVFoundation
import Photos
import SwiftUI

private enum PreviewSaveRequest {
    case photos(albumName: String)
    case files
}

@MainActor
final class EditorViewModel: ObservableObject {
    private static let defaultDurationStorageKey = "hanClipDefaultDuration"
    private static let defaultAspectRatioStorageKey = "hanClipDefaultAspectRatio"
    private static let automaticAspectRatioStorageValue = "automatic"
    private static let fallbackDefaultDuration = 3.0

    @Published var clips: [ClipItem] = []
    @Published var defaultDuration: Double = EditorViewModel.storedDefaultDuration() {
        didSet {
            Self.storeDefaultDuration(defaultDuration)
        }
    }
    @Published var outputAspectRatio: OutputAspectRatio? =
        EditorViewModel.storedDefaultAspectRatio()
    @Published var textOverlaySettings = WatermarkSettings.projectDefault()
    @Published private(set) var automaticSourceSize = CGSize(
        width: 1,
        height: 1
    )
    @Published var isPickerPresented = false
    @Published var isCalendarPickerPresented = false
    @Published var isFileImporterPresented = false
    @Published var isExporting = false
    @Published var isLoadingCalendarPicker = false
    @Published var calendarPickerLoadProgress = 0.0
    @Published var isImportingCalendarMedia = false
    @Published var calendarImportProgress = 0.0
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
    @Published private(set) var initialCalendarMonth = Calendar.current
        .date(
            from: Calendar.current.dateComponents(
                [.year, .month],
                from: Date()
            )
        ) ?? Date()
    @Published private(set) var initialCalendarMediaDates: Set<Date> = []
    @Published private(set) var initialCalendarMediaCounts: [Date: Int] = [:]
    private var previewTask: Task<Void, Never>?
    private var pendingThumbnailTask: Task<Void, Never>?
    private var pendingPhotoAlbumName = ""
    private var previewSaveRequest: PreviewSaveRequest?

    init() {
        reloadProjects()
        refreshPendingSharedItems()
    }

    private static func storedDefaultDuration() -> Double {
        guard UserDefaults.standard.object(
            forKey: defaultDurationStorageKey
        ) != nil else {
            return fallbackDefaultDuration
        }
        return normalizedDefaultDuration(
            UserDefaults.standard.double(forKey: defaultDurationStorageKey)
        )
    }

    private static func storeDefaultDuration(_ duration: Double) {
        UserDefaults.standard.set(
            normalizedDefaultDuration(duration),
            forKey: defaultDurationStorageKey
        )
    }

    private static func normalizedDefaultDuration(_ duration: Double) -> Double {
        min(max(duration, 0.5), 30)
    }

    private static func storedDefaultAspectRatio() -> OutputAspectRatio? {
        guard let rawValue = UserDefaults.standard.string(
            forKey: defaultAspectRatioStorageKey
        ) else { return nil }
        guard rawValue != automaticAspectRatioStorageValue else { return nil }
        return OutputAspectRatio(rawValue: rawValue)
    }

    private static func storeDefaultAspectRatio(_ ratio: OutputAspectRatio?) {
        UserDefaults.standard.set(
            ratio?.rawValue ?? automaticAspectRatioStorageValue,
            forKey: defaultAspectRatioStorageKey
        )
    }

    var totalDuration: Double {
        renderableClips.reduce(0) { $0 + $1.duration }
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

    var renderableClips: [ClipItem] {
        clips.filter { clip in
            guard clip.isRenderableClip else { return false }
            guard clip.isVideoSegmentChild else { return true }
            return isActiveVideoSegmentChild(clip)
        }
    }

    func shouldDisplayClip(_ clip: ClipItem) -> Bool {
        !clip.isVideoSegmentChild || isActiveVideoSegmentChild(clip)
    }

    func childSegmentCount(for parentID: UUID) -> Int {
        clips.filter { $0.videoSegmentParentID == parentID }.count
    }

    func childSegmentDuration(for parentID: UUID) -> Double {
        clips
            .filter { $0.videoSegmentParentID == parentID }
            .reduce(0) { $0 + $1.duration }
    }

    func canUseMultipleVideoSegments(for id: UUID) -> Bool {
        guard let clip = clips.first(where: { $0.id == id }),
              clip.mediaKind == .video,
              !clip.isVideoSegmentChild
        else { return false }

        let sourceDuration = clip.sourceDuration ?? clip.duration
        return normalizedPeakTimes(
            for: clip,
            sourceDuration: sourceDuration,
            selectedDuration: min(defaultDuration, sourceDuration)
        ).count > 1
    }

    func selectOutputAspectRatio(_ ratio: OutputAspectRatio?) {
        outputAspectRatio = ratio
        Self.storeDefaultAspectRatio(ratio)
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

    func openCalendarPicker() {
        if !isProjectOpen {
            beginNewProject()
            importPendingItemsIntoNewProject()
        }
        Task {
            if await PhotoLibraryService.requestReadAccess() {
                await prepareCalendarPicker()
                isCalendarPickerPresented = true
            } else {
                alertMessage = "사진 보관함 접근을 허용해 주세요."
            }
        }
    }

    private func prepareCalendarPicker() async {
        let calendar = Calendar.current
        let month = calendar.date(
            from: calendar.dateComponents(
                [.year, .month],
                from: Date()
            )
        ) ?? Date()

        isLoadingCalendarPicker = true
        calendarPickerLoadProgress = 0
        progressMessage = "달력을 불러오는 중…"

        let counts = await Task.detached {
            PhotoLibraryService.mediaCounts(
                in: month,
                calendar: calendar
            ) { progress in
                Task { @MainActor in
                    self.calendarPickerLoadProgress = progress
                }
            }
        }.value

        initialCalendarMonth = month
        initialCalendarMediaCounts = counts
        initialCalendarMediaDates = Set(counts.keys)
        calendarPickerLoadProgress = 1
        progressMessage = ""
        isLoadingCalendarPicker = false
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
            outputAspectRatio = Self.storedDefaultAspectRatio()
        }
        clips.append(contentsOf: newItems.compactMap { item in
            let stableItem: ClipItem
            do {
                stableItem = try item.replacingSource(
                    WorkingClipSourceStore.persist(item.source)
                )
            } catch {
                alertMessage = "가져온 원본 파일을 보관할 수 없습니다."
                return nil
            }

            var adjusted = stableItem
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
            } else if item.isLivePhoto,
                      item.livePhotoMode == .motion {
                let sourceDuration = item.sourceDuration
                    ?? item.livePhotoDuration
                    ?? item.duration
                adjusted.sourceDuration = sourceDuration
                adjusted.livePhotoDuration = sourceDuration
                adjusted.duration = min(defaultDuration, sourceDuration)
                adjusted.trimStart = max(
                    0,
                    (sourceDuration - adjusted.duration) / 2
                )
            }
            return adjusted
        })
        refreshLivePhotoDurations()
    }

    func applyDefaultDurationToAll() {
        for index in clips.indices {
            if clips[index].isLivePhoto {
                if clips[index].livePhotoMode == .still {
                    clips[index].photoDuration = defaultDuration
                    clips[index].duration = defaultDuration
                    clips[index].trimStart = 0
                    continue
                }

                let sourceDuration = clips[index].sourceDuration
                    ?? clips[index].livePhotoDuration
                    ?? clips[index].duration
                let selectedDuration = min(defaultDuration, sourceDuration)
                clips[index].sourceDuration = sourceDuration
                clips[index].livePhotoDuration = sourceDuration
                clips[index].duration = selectedDuration
                clips[index].photoDuration = selectedDuration
                clips[index].trimStart = max(
                    0,
                    (sourceDuration - selectedDuration) / 2
                )
                continue
            }

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

    func applyLivePhotoModeToAll(_ mode: LivePhotoMode) {
        for index in clips.indices where clips[index].isLivePhoto {
            clips[index].livePhotoMode = mode

            if mode == .motion {
                applyLivePhotoPlaybackWindow(at: index)
            } else {
                clips[index].photoDuration = defaultDuration
                clips[index].duration = defaultDuration
                clips[index].trimStart = 0
            }
        }
    }

    func selectFullRangeForAllVideoClips() {
        for index in clips.indices where
            !clips[index].isVideoSegmentChild {
            if clips[index].mediaKind == .video {
                let sourceDuration = clips[index].sourceDuration
                    ?? clips[index].duration
                clips[index].videoSegmentMode = .single
                clips[index].isVideoSegmentParent = false
                clips[index].trimStart = 0
                clips[index].duration = sourceDuration
                clips[index].photoDuration = sourceDuration
            } else if clips[index].isLivePhoto {
                let sourceDuration = clips[index].sourceDuration
                    ?? clips[index].livePhotoDuration
                    ?? clips[index].duration
                clips[index].livePhotoMode = .motion
                clips[index].sourceDuration = sourceDuration
                clips[index].livePhotoDuration = sourceDuration
                clips[index].trimStart = 0
                clips[index].duration = sourceDuration
                clips[index].photoDuration = sourceDuration
            } else {
                clips[index].trimStart = 0
                clips[index].duration = defaultDuration
                clips[index].photoDuration = defaultDuration
            }
        }
    }

    func removeClip(id: UUID) {
        clips.removeAll { clip in
            clip.id == id || clip.videoSegmentParentID == id
        }
    }

    func removeClips(at offsets: IndexSet) {
        let ids = offsets.compactMap { offset in
            clips.indices.contains(offset) ? clips[offset].id : nil
        }
        ids.forEach(removeClip)
    }

    func moveVideoSegmentChild(draggedID: UUID, targetID: UUID) {
        guard draggedID != targetID,
              let sourceIndex = clips.firstIndex(where: {
                  $0.id == draggedID
              }),
              let targetIndex = clips.firstIndex(where: {
                  $0.id == targetID
              }),
              clips[sourceIndex].isVideoSegmentChild,
              clips[targetIndex].isVideoSegmentChild,
              clips[sourceIndex].videoSegmentParentID
                  == clips[targetIndex].videoSegmentParentID
        else { return }

        clips.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: targetIndex > sourceIndex
                ? targetIndex + 1
                : targetIndex
        )
    }

    func reset() {
        previewTask?.cancel()
        previewTask = nil
        releaseEditingMemory()
        isPickerPresented = false
        isCalendarPickerPresented = false
        isFileImporterPresented = false
        isExporting = false
        isLoadingCalendarPicker = false
        calendarPickerLoadProgress = 0
        isImportingCalendarMedia = false
        calendarImportProgress = 0
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

    func returnHomeWithoutSaving() {
        clips = []
        reset()
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
                textOverlaySettings: textOverlaySettings,
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
        guard !renderableClips.isEmpty, !isExporting else { return }
        isExporting = true
        isPreviewRendering = true
        previewProgress = 0
        previewThumbnail = renderableClips.first?.thumbnail
        progressMessage = "프로젝트를 저장하는 중…"

        previewTask = Task {
            do {
                let savedID = try ProjectStore.save(
                    clips: clips,
                    defaultDuration: defaultDuration,
                    outputAspectRatio: outputAspectRatio,
                    automaticSourceSize: automaticSourceSize,
                    textOverlaySettings: textOverlaySettings,
                    activeProjectID: activeProjectID
                )
                try Task.checkCancellation()
                let savedProject = try ProjectStore.load(id: savedID)
                clips = savedProject.clips
                defaultDuration = savedProject.defaultDuration
                outputAspectRatio = savedProject.outputAspectRatio
                automaticSourceSize = savedProject.automaticSourceSize
                textOverlaySettings = savedProject.textOverlaySettings
                reloadProjects()
                activeProjectID = savedProjects.contains {
                    $0.id == savedID
                } ? savedID : nil

                let compositionItems = savedProject.clips.filter(
                    \.isRenderableClip
                )
                previewProgress = 0.10
                progressMessage = "미리보기 영상을 만드는 중…"
                let output = try await VideoComposer().compose(
                    items: compositionItems,
                    renderSize: outputRenderSize,
                    watermarkSettings: textOverlaySettings
                        .withCopyrightSettings(WatermarkSettings.stored())
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
        if progress >= 0.86 {
            progressMessage = "Rendering in progress"
        }
        let compositionItems = renderableClips
        guard !compositionItems.isEmpty else { return }
        let index = min(
            Int(progress * Double(compositionItems.count)),
            compositionItems.count - 1
        )
        previewThumbnail = compositionItems[index].thumbnail
    }

    private func releaseEditingMemory() {
        clips = []
        WorkingClipSourceStore.clear()
        defaultDuration = Self.storedDefaultDuration()
        outputAspectRatio = Self.storedDefaultAspectRatio()
        textOverlaySettings = WatermarkSettings.projectDefault()
        automaticSourceSize = CGSize(width: 1, height: 1)
        isPickerPresented = false
        isFileImporterPresented = false
        isCalendarPickerPresented = false
        isLoadingCalendarPicker = false
        calendarPickerLoadProgress = 0
        activeProjectID = nil
    }

    func loadProject(id: UUID) {
        do {
            let project = try ProjectStore.load(id: id)
            clips = project.clips
            defaultDuration = project.defaultDuration
            outputAspectRatio = project.outputAspectRatio
            automaticSourceSize = project.automaticSourceSize
            textOverlaySettings = project.textOverlaySettings
            exportedURL = nil
            showPreview = false
            activeProjectID = project.id
            isProjectOpen = true
            refreshLivePhotoDurations()
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
                textOverlaySettings: textOverlaySettings,
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
                            contentsOf: try await makeVideoClips(from: primary)
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
                                    sourceDuration: duration,
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
                                    sourceDuration: duration,
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
                textOverlaySettings: textOverlaySettings,
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
                    imported.append(
                        contentsOf: try await makeVideoClips(from: local)
                    )
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

    func importMediaFromCalendarDates(_ dates: Set<Date>) {
        guard !dates.isEmpty else { return }
        let selectedDates = Set(
            dates.map { Calendar.current.startOfDay(for: $0) }
        )
        isCalendarPickerPresented = false
        isImportingCalendarMedia = true
        calendarImportProgress = 0
        progressMessage = "선택한 날짜의 미디어를 불러오는 중…"

        Task {
            let assets = PhotoLibraryService.mediaAssets(
                on: selectedDates,
                calendar: .current
            )
            var imported: [ClipItem] = []

            for (index, asset) in assets.enumerated() {
                do {
                    let thumbnail = try await PhotoLibraryService.thumbnail(
                        for: asset
                    )
                    let items = try await makeClips(from: asset, thumbnail)
                    if !items.isEmpty {
                        imported.append(contentsOf: items)
                    }
                } catch {
                    continue
                }

                calendarImportProgress = assets.isEmpty
                    ? 1
                    : Double(index + 1) / Double(assets.count)
                progressMessage =
                    "선택한 날짜의 미디어 \(index + 1)/\(assets.count)개를 "
                    + "불러오는 중…"
            }

            isImportingCalendarMedia = false
            calendarImportProgress = 0
            progressMessage = ""
            addPickedItems(imported)

            alertMessage = imported.isEmpty
                ? "선택한 날짜에 가져올 수 있는 미디어가 없습니다."
                : "선택한 날짜의 미디어 \(imported.count)개를 가져왔습니다."
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

    func setVideoSegmentMode(id: UUID, mode: VideoSegmentMode) {
        guard let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].mediaKind == .video,
              !clips[index].isVideoSegmentChild
        else { return }

        guard mode == .single || canUseMultipleVideoSegments(for: id) else {
            clips[index].videoSegmentMode = .single
            clips[index].isVideoSegmentParent = false
            return
        }

        clips[index].videoSegmentMode = mode
        guard mode == .multiple else {
            clips[index].isVideoSegmentParent = false
            return
        }

        if clips.contains(where: { $0.videoSegmentParentID == id }) {
            clips[index].isVideoSegmentParent = true
            return
        }

        let sourceClip = clips[index]
        let sourceDuration = sourceClip.sourceDuration
            ?? sourceClip.duration
        let peaks = normalizedPeakTimes(
            for: sourceClip,
            sourceDuration: sourceDuration,
            selectedDuration: segmentSelectionDuration(
                for: sourceClip,
                sourceDuration: sourceDuration
            )
        )
        guard peaks.count > 1 else {
            reanalyzeAndSplitVideoClip(sourceClip)
            return
        }

        splitVideoClip(at: index, sourceClip: sourceClip, peaks: peaks)
    }

    private func reanalyzeAndSplitVideoClip(_ sourceClip: ClipItem) {
        guard case .videoFile(let url) = sourceClip.source else {
            resetVideoSegmentModeAfterMissingPeaks(id: sourceClip.id)
            return
        }

        Task {
            let analysis = try? await AudioAnalysisService.analyze(url: url)
            guard let index = clips.firstIndex(where: { $0.id == sourceClip.id })
            else { return }

            if let analysis {
                clips[index].audioWaveform = analysis.waveform
                clips[index].audioPeakTime = analysis.peakTime
                clips[index].audioPeakTimes = analysis.peakTimes
            }

            let updatedClip = clips[index]
            let sourceDuration = updatedClip.sourceDuration
                ?? updatedClip.duration
            let peaks = normalizedPeakTimes(
                for: updatedClip,
                sourceDuration: sourceDuration
            )

            guard peaks.count > 1 else {
                resetVideoSegmentModeAfterMissingPeaks(id: updatedClip.id)
                return
            }

            splitVideoClip(at: index, sourceClip: updatedClip, peaks: peaks)
        }
    }

    private func resetVideoSegmentModeAfterMissingPeaks(id: UUID) {
        if let index = clips.firstIndex(where: { $0.id == id }) {
            clips[index].videoSegmentMode = .single
            clips[index].isVideoSegmentParent = false
        }
        alertMessage = "이 영상에서 나눌 수 있는 추가 사운드 피크를 찾지 못했습니다."
    }

    func resetVideoSegments(id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].mediaKind == .video,
              !clips[index].isVideoSegmentChild
        else { return }

        let sourceClip = clips[index]
        let sourceDuration = sourceClip.sourceDuration
            ?? sourceClip.duration
        let peaks = normalizedPeakTimes(
            for: sourceClip,
            sourceDuration: sourceDuration,
            selectedDuration: segmentSelectionDuration(
                for: sourceClip,
                sourceDuration: sourceDuration
            )
        )
        guard peaks.count > 1 else {
            resetVideoSegmentModeAfterMissingPeaks(id: id)
            return
        }

        splitVideoClip(at: index, sourceClip: sourceClip, peaks: peaks)
    }

    private func isActiveVideoSegmentChild(_ clip: ClipItem) -> Bool {
        guard let parentID = clip.videoSegmentParentID,
              let parent = clips.first(where: { $0.id == parentID })
        else { return false }

        return parent.isVideoSegmentParent
            && parent.videoSegmentMode == .multiple
    }

    private func splitVideoClip(
        at index: Int,
        sourceClip: ClipItem,
        peaks: [Double]
    ) {
        let sourceDuration = sourceClip.sourceDuration
            ?? sourceClip.duration
        clips.removeAll { $0.videoSegmentParentID == sourceClip.id }
        guard let parentIndex = clips.firstIndex(where: { $0.id == sourceClip.id })
        else { return }

        clips[parentIndex].videoSegmentMode = .multiple
        clips[parentIndex].isVideoSegmentParent = true
        let segmentDuration = segmentSelectionDuration(
            for: sourceClip,
            sourceDuration: sourceDuration
        )

        let childClips = peaks.map { peak in
            let duration = min(segmentDuration, sourceDuration)
            let start = max(
                0,
                min(sourceDuration - duration, peak - duration / 2)
            )
            return ClipItem(
                source: sourceClip.source,
                thumbnail: sourceClip.thumbnail,
                duration: duration,
                photoDuration: duration,
                mediaKind: .video,
                sourceDuration: sourceDuration,
                trimStart: start,
                audioWaveform: sourceClip.audioWaveform,
                audioPeakTime: peak,
                audioPeakTimes: peaks,
                videoSegmentMode: .single,
                videoSegmentParentID: sourceClip.id,
                sourcePixelSize: sourceClip.sourcePixelSize
            )
        }

        clips.insert(
            contentsOf: childClips,
            at: clips.index(after: parentIndex)
        )
        refreshSegmentChildThumbnails(
            parentID: sourceClip.id,
            sourceClip: sourceClip
        )
    }

    private func refreshSegmentChildThumbnails(
        parentID: UUID,
        sourceClip: ClipItem
    ) {
        guard case .videoFile(let url) = sourceClip.source else { return }
        let childTargets = clips
            .filter { $0.videoSegmentParentID == parentID }
            .map { ($0.id, $0.trimStart + $0.duration / 2) }
        guard !childTargets.isEmpty else { return }

        Task {
            for (id, midpoint) in childTargets {
                guard let thumbnail = try? await videoThumbnail(
                    for: url,
                    at: midpoint
                ) else { continue }
                guard let index = clips.firstIndex(where: { $0.id == id }),
                      clips[index].videoSegmentParentID == parentID
                else { continue }
                clips[index].thumbnail = thumbnail
            }
        }
    }

    private func normalizedPeakTimes(
        for clip: ClipItem,
        sourceDuration: Double,
        selectedDuration: Double? = nil
    ) -> [Double] {
        let fallbackPeak = clip.audioPeakTime
            ?? (clip.trimStart + clip.duration / 2)
        let rawPeaks = clip.audioPeakTimes.isEmpty
            ? [fallbackPeak]
            : clip.audioPeakTimes
        let deduplicatedPeaks = rawPeaks
            .map { min(max(0, $0), sourceDuration) }
            .reduce(into: [Double]()) { result, peak in
                guard !result.contains(where: { abs($0 - peak) < 0.05 })
                else { return }
                result.append(peak)
            }

        return VideoClipSegmenter.nonOverlappingPeaks(
            rankedPeaks: deduplicatedPeaks,
            sourceDuration: sourceDuration,
            selectedDuration: min(
                selectedDuration ?? clip.duration,
                sourceDuration
            ),
            limit: VideoClipSegmenter.allowedSegmentCounts.upperBound
        )
    }

    private func segmentSelectionDuration(
        for clip: ClipItem,
        sourceDuration: Double
    ) -> Double {
        if clip.duration >= sourceDuration - 0.000_1 {
            return min(defaultDuration, sourceDuration)
        }
        return min(clip.duration, sourceDuration)
    }

    private func refreshLivePhotoDurations() {
        let liveClipIDs = clips
            .filter(\.isLivePhoto)
            .map(\.id)
        guard !liveClipIDs.isEmpty else { return }

        Task {
            for id in liveClipIDs {
                guard let clip = clips.first(where: { $0.id == id }),
                      let duration = await livePhotoDuration(for: clip)
                else { continue }

                guard let index = clips.firstIndex(where: { $0.id == id })
                else { continue }

                clips[index].sourceDuration = duration
                clips[index].livePhotoDuration = duration
                if clips[index].livePhotoMode == .motion {
                    applyLivePhotoPlaybackWindow(at: index)
                }
            }
        }
    }

    private func applyLivePhotoPlaybackWindow(at index: Int) {
        guard clips.indices.contains(index),
              clips[index].isLivePhoto,
              clips[index].livePhotoMode == .motion
        else { return }

        let sourceDuration = clips[index].sourceDuration
            ?? clips[index].livePhotoDuration
            ?? clips[index].duration
        let selectedDuration = min(defaultDuration, sourceDuration)
        clips[index].sourceDuration = sourceDuration
        clips[index].livePhotoDuration = sourceDuration
        clips[index].duration = selectedDuration
        clips[index].trimStart = max(0, (sourceDuration - selectedDuration) / 2)
    }

    private func livePhotoDuration(for clip: ClipItem) async -> Double? {
        switch clip.source {
        case .photoAsset(let identifier):
            guard let asset = PhotoLibraryService.asset(
                localIdentifier: identifier
            ) else { return nil }
            return try? await PhotoLibraryService.livePhotoVideoDuration(
                for: asset
            )

        case .livePhotoFiles(_, let videoURL):
            return try? await PhotoLibraryService.videoDuration(at: videoURL)

        case .imageFile, .videoFile:
            return nil
        }
    }

    private func makeVideoClips(from url: URL) async throws -> [ClipItem] {
        let thumbnail = try await videoThumbnail(for: url)
        let duration = try await PhotoLibraryService.videoDuration(at: url)
        let analysis = try? await AudioAnalysisService.analyze(url: url)
        return VideoClipSegmenter.makeClips(
            source: .videoFile(url),
            thumbnail: thumbnail,
            sourceDuration: duration,
            selectedDuration: min(defaultDuration, duration),
            segmentCount: 1,
            analysis: analysis,
            sourcePixelSize: thumbnail.size
        )
    }

    private func makeClips(
        from asset: PHAsset,
        _ thumbnail: UIImage
    ) async throws -> [ClipItem] {
        if asset.mediaType == .video {
            let url = try await PhotoLibraryService.exportVideo(for: asset)
            let duration = try await PhotoLibraryService.videoDuration(at: url)
            let analysis = try? await AudioAnalysisService.analyze(url: url)
            return VideoClipSegmenter.makeClips(
                source: .videoFile(url),
                thumbnail: thumbnail,
                sourceDuration: duration,
                selectedDuration: min(defaultDuration, duration),
                segmentCount: 1,
                analysis: analysis,
                sourcePixelSize: CGSize(
                    width: asset.pixelWidth,
                    height: asset.pixelHeight
                )
            )
        }

        guard asset.mediaType == .image else { return [] }
        let isLive = asset.mediaSubtypes.contains(.photoLive)
        let duration = isLive
            ? (try? await PhotoLibraryService.livePhotoVideoDuration(
                for: asset
            )) ?? defaultDuration
            : defaultDuration
        return [
            ClipItem(
                source: .photoAsset(localIdentifier: asset.localIdentifier),
                thumbnail: thumbnail,
                duration: duration,
                photoDuration: defaultDuration,
                livePhotoDuration: isLive ? duration : nil,
                isLivePhoto: isLive,
                livePhotoMode: isLive ? .motion : .still,
                mediaKind: isLive ? .livePhoto : .photo,
                sourceDuration: isLive ? duration : nil,
                sourcePixelSize: CGSize(
                    width: asset.pixelWidth,
                    height: asset.pixelHeight
                )
            )
        ]
    }

    private func videoThumbnail(
        for url: URL,
        at seconds: Double = 0
    ) async throws -> UIImage {
        try await Task.detached {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let image = try generator.copyCGImage(
                at: CMTime(
                    seconds: max(0, seconds),
                    preferredTimescale: 600
                ),
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

private enum WorkingClipSourceStore {
    static func persist(_ source: ClipSource) throws -> ClipSource {
        switch source {
        case .photoAsset:
            return source
        case .imageFile(let url):
            return .imageFile(try copy(url, fallbackExtension: "jpg"))
        case .videoFile(let url):
            return .videoFile(try copy(url, fallbackExtension: "mov"))
        case .livePhotoFiles(let imageURL, let videoURL):
            return .livePhotoFiles(
                imageURL: try copy(imageURL, fallbackExtension: "jpg"),
                videoURL: try copy(videoURL, fallbackExtension: "mov")
            )
        }
    }

    static func clear() {
        guard let directory = try? directory(createIfNeeded: false),
              FileManager.default.fileExists(atPath: directory.path)
        else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func copy(
        _ source: URL,
        fallbackExtension: String
    ) throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let ext = source.pathExtension.isEmpty
            ? fallbackExtension
            : source.pathExtension
        let destination = try directory(createIfNeeded: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private static func directory(createIfNeeded: Bool) throws -> URL {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = support.appendingPathComponent(
            "HanClipWorkingSources",
            isDirectory: true
        )
        if createIfNeeded {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return directory
    }
}
