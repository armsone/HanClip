import AVFoundation
import Combine
import ImageIO
import Photos
import SwiftUI

private enum PreviewSaveRequest {
    case photos(albumName: String)
    case files
}

private struct ProjectEditSignature: Equatable {
    let clips: [ClipEditSignature]
    let defaultDuration: Double
    let defaultVideoSegmentMode: VideoSegmentMode
    let outputAspectRatio: OutputAspectRatio?
    let automaticSourceSize: CGSize
    let textOverlaySettings: String
    let backgroundMusicSettings: BackgroundMusicSettings
}

enum MoviePreset {
    case newMovie
    case aiShot
    case travel
    case golf
}

    private struct ClipEditSignature: Equatable {
    let id: UUID
    let source: String
    let duration: Double
    let photoDuration: Double
    let livePhotoDuration: Double?
    let isLivePhoto: Bool
    let livePhotoMode: LivePhotoMode
    let mediaKind: ClipMediaKind
    let sourceDuration: Double?
    let trimStart: Double
    let audioPeakTime: Double?
    let audioPeakTimes: [Double]
    let videoSegmentMode: VideoSegmentMode
    let isVideoSegmentParent: Bool
    let videoSegmentParentID: UUID?
    let isVideoSegmentSelected: Bool
    let similarPhotoGroupID: UUID?
    let similarPhotoGroupIndex: Int
    let similarPhotoGroupCount: Int
    let isSimilarPhotoGroupRepresentative: Bool
    let sourceCreatedAt: Date?
    let sourcePixelSize: CGSize
}

@MainActor
final class EditorViewModel: ObservableObject {
    private static let defaultDurationStorageKey = "hanClipDefaultDuration"
    private static let defaultAspectRatioStorageKey = "hanClipDefaultAspectRatio"
    private static let similarPhotoRepresentativeIntervalStorageKey =
        "hanClipSimilarPhotoRepresentativeInterval"
    private static let automaticAspectRatioStorageValue = "automatic"
    private static let fallbackDefaultDuration = 3.0
    private static let fallbackSimilarPhotoRepresentativeInterval = 6

    @Published var clips: [ClipItem] = []
    @Published var defaultDuration: Double = EditorViewModel.storedDefaultDuration() {
        didSet {
            Self.storeDefaultDuration(defaultDuration)
        }
    }
    @Published private(set) var defaultVideoSegmentMode: VideoSegmentMode = .multiple
    @Published private(set) var similarPhotoRepresentativeInterval =
        EditorViewModel.storedSimilarPhotoRepresentativeInterval()
    @Published var outputAspectRatio: OutputAspectRatio? =
        EditorViewModel.storedDefaultAspectRatio()
    @Published var textOverlaySettings = WatermarkSettings.projectDefault()
    @Published var backgroundMusicSettings = BackgroundMusicSettings.projectDefault
    @Published private(set) var automaticSourceSize = CGSize(
        width: 1,
        height: 1
    )
    @Published var isPickerPresented = false
    @Published var isCalendarPickerPresented = false
    @Published var isFileImporterPresented = false
    @Published var isBackgroundMusicImporterPresented = false
    @Published var isExporting = false
    @Published var isLoadingCalendarPicker = false
    @Published var calendarPickerLoadProgress = 0.0
    @Published var isImportingCalendarMedia = false
    @Published var calendarImportProgress = 0.0
    @Published var progressMessage = ""
    @Published var isSavingProject = false
    @Published var projectSaveProgress = 0.0
    @Published var isLoadingProject = false
    @Published var projectLoadProgress = 0.0
    @Published var previewProgress = 0.0
    @Published var isPreviewRendering = false
    @Published var isImportingFiles = false
    @Published var isImportingPhotoLibraryMedia = false
    @Published var isImportingSharedItems = false
    @Published var sharedImportProgress = 0.0
    @Published var sharedImportThumbnail: UIImage?
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
    @Published private var expandedSimilarPhotoGroupIDs: Set<UUID> = []

    var isActiveAiShotProject: Bool {
        guard let activeProjectID else { return false }
        return savedProjects.first {
            $0.id == activeProjectID
        }?.kind == .aiShot
    }

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
    private var projectSaveTask: Task<Void, Never>?
    private var projectLoadTask: Task<Void, Never>?
    private var pendingThumbnailTask: Task<Void, Never>?
    private var calendarImportTask: Task<Void, Never>?
    private var sharedImportTask: Task<Void, Never>?
    private var pendingPhotoAlbumName = ""
    private var previewSaveRequest: PreviewSaveRequest?
    private var openedProjectSignature: ProjectEditSignature?

    init() {
        _ = try? ProjectStore.removeExcessAiShotProjects()
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
        min(max(duration, 0.1), 30)
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

    private static func storedSimilarPhotoRepresentativeInterval() -> Int {
        let stored = UserDefaults.standard.integer(
            forKey: similarPhotoRepresentativeIntervalStorageKey
        )
        guard stored > 0 else {
            return fallbackSimilarPhotoRepresentativeInterval
        }
        return normalizedSimilarPhotoRepresentativeInterval(stored)
    }

    private static func storeSimilarPhotoRepresentativeInterval(_ value: Int) {
        UserDefaults.standard.set(
            normalizedSimilarPhotoRepresentativeInterval(value),
            forKey: similarPhotoRepresentativeIntervalStorageKey
        )
    }

    private static func normalizedSimilarPhotoRepresentativeInterval(
        _ value: Int
    ) -> Int {
        min(max(value, 1), 20)
    }

    var totalDuration: Double {
        clips.reduce(0) { total, clip in
            clip.isRenderableClip ? total + clip.duration : total
        }
    }

    var totalDurationText: String {
        let minutes = Int(totalDuration) / 60
        let seconds = totalDuration - Double(minutes * 60)
        if minutes > 0 {
            return String(format: "%d분 %.1f초", minutes, seconds)
        }
        return String(format: "%.1f초", seconds)
    }

    var hasUnsavedProjectChanges: Bool {
        guard let openedProjectSignature else { return true }
        return currentProjectSignature() != openedProjectSignature
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
            return true
        }
    }

    func shouldDisplayClip(_ clip: ClipItem) -> Bool {
        if clip.isSimilarPhotoGroupChild {
            guard let groupID = clip.similarPhotoGroupID,
                  let parent = clips.first(where: {
                      $0.similarPhotoGroupID == groupID
                          && $0.isSimilarPhotoGroupParent
                  })
            else { return false }
            return parent.videoSegmentMode == .multiple
                || parent.videoSegmentMode == .all
        }
        if clip.isVideoSegmentChild {
            guard let parentID = clip.videoSegmentParentID,
                  let parent = clips.first(where: { $0.id == parentID })
            else { return false }
            return parent.isVideoSegmentParent
                && parent.videoSegmentMode == .multiple
        }
        return true
    }

    func isSimilarPhotoGroupExpanded(for clip: ClipItem) -> Bool {
        if clip.isSimilarPhotoGroupParent {
            return clip.videoSegmentMode == .multiple
                || clip.videoSegmentMode == .all
        }
        guard let groupID = clip.similarPhotoGroupID,
              let parent = clips.first(where: {
                  $0.similarPhotoGroupID == groupID
                      && $0.isSimilarPhotoGroupParent
              })
        else { return false }
        return parent.videoSegmentMode == .multiple
            || parent.videoSegmentMode == .all
    }

    func toggleSimilarPhotoGroup(for id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].isSimilarPhotoGroupParent
        else { return }

        clips[index].videoSegmentMode = clips[index].videoSegmentMode == .multiple
            ? .single
            : .multiple
    }

    func setSimilarPhotoGroupMode(id: UUID, mode: VideoSegmentMode) {
        guard let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].isSimilarPhotoGroupParent
        else { return }

        clips[index].videoSegmentMode = mode
        guard let groupID = clips[index].similarPhotoGroupID else { return }

        switch mode {
        case .single:
            applyAutomaticSimilarPhotoSelection(groupID: groupID)
        case .multiple:
            break
        case .all:
            setAllSimilarPhotosIncluded(groupID: groupID)
        }
        rebalanceSimilarPhotoGroup(groupID)
    }

    func applySimilarPhotoGroupModeToAll(_ mode: VideoSegmentMode) {
        let parentIDs = clips.filter(\.isSimilarPhotoGroupParent).map(\.id)
        parentIDs.forEach { setSimilarPhotoGroupMode(id: $0, mode: mode) }
    }

    func setSimilarPhotoRepresentativeInterval(_ value: Int) {
        let normalized = Self.normalizedSimilarPhotoRepresentativeInterval(value)
        guard normalized != similarPhotoRepresentativeInterval else { return }

        similarPhotoRepresentativeInterval = normalized
        Self.storeSimilarPhotoRepresentativeInterval(normalized)

        let automaticGroupIDs = Set(
            clips.compactMap { clip -> UUID? in
                guard clip.isSimilarPhotoGroupParent,
                      clip.videoSegmentMode == .single
                else { return nil }
                return clip.similarPhotoGroupID
            }
        )
        for groupID in automaticGroupIDs {
            applyAutomaticSimilarPhotoSelection(groupID: groupID)
        }
    }

    func includeSimilarPhoto(id: UUID) {
        setSimilarPhotoIncluded(id: id, isIncluded: true)
    }

    func setSimilarPhotoIncluded(id: UUID, isIncluded: Bool) {
        guard let index = clips.firstIndex(where: { $0.id == id }),
              let groupID = clips[index].similarPhotoGroupID
        else { return }

        if !isIncluded {
            let includedCount = clips.filter {
                $0.similarPhotoGroupID == groupID
                    && $0.isSimilarPhotoGroupRepresentative
            }.count
            guard includedCount > 1 else { return }
        }

        clips[index].isSimilarPhotoGroupRepresentative = isIncluded
        rebalanceSimilarPhotoGroup(groupID)
    }

    func childSegmentCount(for parentID: UUID) -> Int {
        clips.filter {
            $0.videoSegmentParentID == parentID
                && $0.isVideoSegmentSelected
        }.count
    }

    func childSegmentDuration(for parentID: UUID) -> Double {
        clips
            .filter {
                $0.videoSegmentParentID == parentID
                    && $0.isVideoSegmentSelected
            }
            .reduce(0) { $0 + $1.duration }
    }

    func videoSegmentPreviewItems(for parentID: UUID)
        -> [SimilarPhotoGroupPreviewItem] {
        clips
            .filter { $0.videoSegmentParentID == parentID }
            .map {
                SimilarPhotoGroupPreviewItem(
                    id: $0.id,
                    thumbnail: $0.thumbnail,
                    isIncluded: $0.isVideoSegmentSelected
                )
            }
    }

    func setVideoSegmentIncluded(id: UUID, isIncluded: Bool) {
        guard let index = clips.firstIndex(where: { $0.id == id }),
              let parentID = clips[index].videoSegmentParentID
        else { return }

        if !isIncluded {
            let includedCount = clips.filter {
                $0.videoSegmentParentID == parentID
                    && $0.isVideoSegmentSelected
            }.count
            guard includedCount > 1 else { return }
        }

        clips[index].isVideoSegmentSelected = isIncluded
    }

    func similarPhotoGroupDuration(for id: UUID) -> Double {
        guard let groupID = clips.first(where: { $0.id == id })?
            .similarPhotoGroupID
        else { return 0 }

        return clips
            .filter {
                $0.similarPhotoGroupID == groupID
                    && $0.isSimilarPhotoGroupRepresentative
            }
            .reduce(0) { $0 + $1.duration }
    }

    func similarPhotoGroupPreviewItems(
        for id: UUID
    ) -> [SimilarPhotoGroupPreviewItem] {
        guard let groupID = clips.first(where: { $0.id == id })?
            .similarPhotoGroupID
        else { return [] }

        return clips
            .filter { $0.similarPhotoGroupID == groupID }
            .sorted {
                $0.similarPhotoGroupIndex < $1.similarPhotoGroupIndex
            }
            .map {
                SimilarPhotoGroupPreviewItem(
                    id: $0.id,
                    thumbnail: $0.thumbnail,
                    isIncluded: $0.isSimilarPhotoGroupRepresentative
                )
            }
    }

    func similarPhotoGroupClipIDs(for id: UUID) -> [UUID] {
        guard let groupID = clips.first(where: { $0.id == id })?
            .similarPhotoGroupID
        else { return [] }

        return clips
            .filter { $0.similarPhotoGroupID == groupID }
            .sorted {
                $0.similarPhotoGroupIndex < $1.similarPhotoGroupIndex
            }
            .map(\.id)
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

    func openMoviePreset(_ preset: MoviePreset) {
        guard !isProjectOpen else { return }
        beginNewProject()
        applyMoviePreset(preset)
        importPendingItemsIntoNewProject()
        if preset == .travel {
            openCalendarPicker()
        } else {
            openPicker()
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

    @discardableResult
    func openAiShot() -> Bool {
        if !isProjectOpen {
            beginNewProject()
            applyMoviePreset(.aiShot)
        }

        return true
    }

    private func applyMoviePreset(_ preset: MoviePreset) {
        var overlay = WatermarkSettings.projectDefault()
        let musicTrackID: String?

        switch preset {
        case .newMovie:
            defaultDuration = 2
            defaultVideoSegmentMode = .multiple
            overlay.isEnabled = false
            musicTrackID = nil
        case .aiShot:
            defaultDuration = 4
            defaultVideoSegmentMode = .multiple
            overlay = .greenGolfPreset(text: Self.movieDateCaptionText())
            musicTrackID = nil
        case .golf:
            defaultDuration = 4
            defaultVideoSegmentMode = .multiple
            overlay = .greenGolfPreset(text: Self.movieDateCaptionText())
            musicTrackID = "golf-lets-go"
        case .travel:
            defaultDuration = 1.5
            defaultVideoSegmentMode = .multiple
            overlay = .travelPreset(text: Self.movieDateCaptionText())
            musicTrackID = "travel-joy"
        }

        textOverlaySettings = overlay
        backgroundMusicSettings = musicTrackID.flatMap { trackID in
            BackgroundMusicSettings.sampleTracks
                .first { $0.id == trackID }?
                .settings
        } ?? .empty
    }

    private static func movieDateCaptionText(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yy.MM.dd(EEE)"
        return formatter.string(from: date)
    }

    func openBackgroundMusicPicker() {
        if !isProjectOpen {
            beginNewProject()
            importPendingItemsIntoNewProject()
        }
        isBackgroundMusicImporterPresented = true
    }

    @discardableResult
    func importBackgroundMusic(_ urls: [URL]) -> Bool {
        guard let source = urls.first else { return false }
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let ext = source.pathExtension.isEmpty
                ? "m4a"
                : source.pathExtension
            let local = FileManager.default.temporaryDirectory
                .appendingPathComponent("HanClip-BGM-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: source, to: local)
            backgroundMusicSettings.fileURL = local
            backgroundMusicSettings.displayName =
                source.deletingPathExtension().lastPathComponent
            backgroundMusicSettings.isEnabled = true
            return true
        } catch {
            alertMessage = "음악 파일을 가져올 수 없습니다."
            return false
        }
    }

    func useSampleBackgroundMusic(_ sampleTrack: BackgroundMusicSampleTrack) {
        guard let sample = sampleTrack.settings else {
            alertMessage = "샘플 음악을 찾을 수 없습니다."
            return
        }
        backgroundMusicSettings = sample
    }

    func removeBackgroundMusic() {
        backgroundMusicSettings = .projectDefault
    }

    @discardableResult
    func addPickedItems(
        _ newItems: [ClipItem],
        sourcesAlreadyPersisted: Bool = false
    ) -> Task<Void, Never>? {
        guard !newItems.isEmpty else { return nil }

        if clips.isEmpty, let first = newItems.first {
            automaticSourceSize = first.sourcePixelSize
            outputAspectRatio = Self.storedDefaultAspectRatio()
        }

        var updatedClips = clips
        var newClipIDs: [UUID] = []
        newClipIDs.reserveCapacity(newItems.count)
        updatedClips.reserveCapacity(updatedClips.count + newItems.count)

        for item in newItems {
            let stableItem: ClipItem
            do {
                stableItem = sourcesAlreadyPersisted
                    ? item
                    : item.replacingSource(
                        try WorkingClipSourceStore.persist(item.source)
                    )
            } catch {
                alertMessage = "가져온 원본 파일을 보관할 수 없습니다."
                continue
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
            adjusted.videoSegmentMode = .single
            updatedClips.append(adjusted)
            newClipIDs.append(adjusted.id)
        }

        guard !newClipIDs.isEmpty else { return nil }
        applySimilarPhotoGrouping(to: newClipIDs, in: &updatedClips)
        let segmentedParentIDs = defaultVideoSegmentMode == .multiple
            ? applyDefaultVideoSegmentation(
                to: newClipIDs,
                in: &updatedClips
            )
            : []
        clips = updatedClips
        isProjectOpen = true

        let thumbnailRefreshTask = segmentedParentIDs.isEmpty
            ? nil
            : refreshSegmentChildThumbnails(parentIDs: segmentedParentIDs)
        refreshLivePhotoDurations()
        return thumbnailRefreshTask
    }

    private func applyDefaultVideoSegmentation(
        to ids: [UUID],
        in workingClips: inout [ClipItem]
    ) -> [UUID] {
        var segmentedParentIDs: [UUID] = []

        for id in ids {
            guard let parentIndex = workingClips.firstIndex(where: {
                $0.id == id
            }) else { continue }

            let sourceClip = workingClips[parentIndex]
            guard sourceClip.mediaKind == .video,
                  !sourceClip.isVideoSegmentChild
            else { continue }

            let sourceDuration = sourceClip.sourceDuration
                ?? sourceClip.duration
            let segmentDuration = segmentSelectionDuration(
                for: sourceClip,
                sourceDuration: sourceDuration
            )
            let peaks = normalizedPeakTimes(
                for: sourceClip,
                sourceDuration: sourceDuration,
                selectedDuration: segmentDuration
            )
            guard peaks.count > 1 else { continue }

            workingClips[parentIndex].videoSegmentMode = .multiple
            workingClips[parentIndex].isVideoSegmentParent = true
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
                    isVideoSegmentSelected: true,
                    sourcePixelSize: sourceClip.sourcePixelSize
                )
            }
            workingClips.insert(
                contentsOf: childClips,
                at: workingClips.index(after: parentIndex)
            )
            segmentedParentIDs.append(sourceClip.id)
        }

        return segmentedParentIDs
    }

    private func applySimilarPhotoGrouping(to ids: [UUID]) {
        var updatedClips = clips
        applySimilarPhotoGrouping(to: ids, in: &updatedClips)
        clips = updatedClips
    }

    private func applySimilarPhotoGrouping(
        to ids: [UUID],
        in workingClips: inout [ClipItem]
    ) {
        let newIDSet = Set(ids)
        let newIndices = workingClips.indices.filter {
            newIDSet.contains(workingClips[$0].id)
        }
        guard newIndices.count > 1 else { return }

        for index in newIndices {
            workingClips[index].similarPhotoGroupID = nil
            workingClips[index].similarPhotoGroupIndex = 0
            workingClips[index].similarPhotoGroupCount = 1
            workingClips[index].isSimilarPhotoGroupRepresentative = true
        }

        var currentGroup: [Int] = []

        for index in newIndices {
            guard canGroupAsSimilarPhoto(workingClips[index]) else {
                commitSimilarPhotoGroup(currentGroup, in: &workingClips)
                currentGroup = []
                continue
            }

            guard let previousIndex = currentGroup.last,
                  areSimilarPhotos(
                    workingClips[previousIndex],
                    workingClips[index]
                  )
            else {
                commitSimilarPhotoGroup(currentGroup, in: &workingClips)
                currentGroup = [index]
                continue
            }

            currentGroup.append(index)
        }
        commitSimilarPhotoGroup(currentGroup, in: &workingClips)
    }

    private func commitSimilarPhotoGroup(
        _ group: [Int],
        in workingClips: inout [ClipItem]
    ) {
        guard group.count > 1 else { return }

        let groupID = UUID()
        let rankedIndices = group.sorted {
            photoRepresentativeScore(for: workingClips[$0])
                > photoRepresentativeScore(for: workingClips[$1])
        }
        let representativeIndex = rankedIndices.first
        let representativeCount = automaticSimilarPhotoRepresentativeCount(
            total: group.count
        )
        let representativeIDs = Set(
            rankedIndices.prefix(representativeCount).map {
                workingClips[$0].id
            }
        )
        var orderedGroup = group
        if let representativeIndex,
           let representativeOffset = orderedGroup.firstIndex(
            of: representativeIndex
           ) {
            orderedGroup.remove(at: representativeOffset)
            orderedGroup.insert(representativeIndex, at: 0)
        }

        let groupRange = group[0]...group[group.count - 1]
        let groupClips = orderedGroup.map { workingClips[$0] }
        workingClips.replaceSubrange(groupRange, with: groupClips)

        for offset in 0..<groupClips.count {
            let clipIndex = groupRange.lowerBound + offset
            workingClips[clipIndex].similarPhotoGroupID = groupID
            workingClips[clipIndex].similarPhotoGroupIndex = offset
            workingClips[clipIndex].similarPhotoGroupCount = groupClips.count
            workingClips[clipIndex].isSimilarPhotoGroupRepresentative =
                representativeIDs.contains(workingClips[clipIndex].id)
            workingClips[clipIndex].videoSegmentMode = .single
            if workingClips[clipIndex].isLivePhoto {
                workingClips[clipIndex].livePhotoMode = .still
                workingClips[clipIndex].photoDuration = defaultDuration
                workingClips[clipIndex].duration = defaultDuration
                workingClips[clipIndex].trimStart = 0
            }
        }
    }

    private func reapplyCurrentProjectCriteria() {
        let previousGroupByClip = Dictionary(
            uniqueKeysWithValues: clips.compactMap { clip in
                clip.similarPhotoGroupID.map { (clip.id, $0) }
            }
        )
        let previouslyIncluded = Set(
            clips.filter(\.isSimilarPhotoGroupRepresentative).map(\.id)
        )
        var previousModeByGroup: [UUID: VideoSegmentMode] = [:]
        for clip in clips where clip.similarPhotoGroupIndex == 0 {
            if let groupID = clip.similarPhotoGroupID {
                previousModeByGroup[groupID] = clip.videoSegmentMode
            }
        }

        applySimilarPhotoGrouping(to: clips.map(\.id))

        let currentGroupIDs = Set(clips.compactMap(\.similarPhotoGroupID))
        for groupID in currentGroupIDs {
            let indices = clips.indices.filter {
                clips[$0].similarPhotoGroupID == groupID
            }
            let previousGroupIDs = Set(indices.compactMap {
                previousGroupByClip[clips[$0].id]
            })
            guard previousGroupIDs.count == 1,
                  let previousGroupID = previousGroupIDs.first,
                  let previousMode = previousModeByGroup[previousGroupID],
                  let parentIndex = indices.first
            else { continue }

            clips[parentIndex].videoSegmentMode = previousMode
            if previousMode == .multiple {
                for index in indices {
                    clips[index].isSimilarPhotoGroupRepresentative =
                        previouslyIncluded.contains(clips[index].id)
                }
            }
            rebalanceSimilarPhotoGroup(groupID)
        }
    }

    private func canGroupAsSimilarPhoto(_ clip: ClipItem) -> Bool {
        switch clip.mediaKind {
        case .photo:
            return true
        case .livePhoto:
            return true
        case .video:
            return false
        }
    }

    private func areSimilarPhotos(
        _ lhs: ClipItem,
        _ rhs: ClipItem
    ) -> Bool {
        guard areContinuousPhotoMoments(lhs, rhs) else { return false }

        let aspectDifference = abs(lhs.sourceAspectRatio - rhs.sourceAspectRatio)
        guard aspectDifference <= 0.06 else { return false }

        let lhsFaceCount = PhotoSimilarityFingerprint.faceCount(
            lhs.photoSimilarityFingerprint
        )
        let rhsFaceCount = PhotoSimilarityFingerprint.faceCount(
            rhs.photoSimilarityFingerprint
        )
        if let lhsFaceCount, let rhsFaceCount,
           lhsFaceCount != rhsFaceCount {
            return false
        }

        let luminanceDistance = PhotoSimilarityFingerprint.alignedDistance(
            lhs.photoSimilarityFingerprint,
            rhs.photoSimilarityFingerprint
        )
        guard luminanceDistance <= 28 else { return false }

        let structureDistance = PhotoSimilarityFingerprint.structureDistance(
            lhs.photoSimilarityFingerprint,
            rhs.photoSimilarityFingerprint
        )
        guard structureDistance <= 30 else { return false }

        let averageDifference = abs(
            PhotoSimilarityFingerprint.mean(lhs.photoSimilarityFingerprint)
                - PhotoSimilarityFingerprint.mean(rhs.photoSimilarityFingerprint)
        )
        return averageDifference <= 28
    }

    private func areContinuousPhotoMoments(
        _ lhs: ClipItem,
        _ rhs: ClipItem
    ) -> Bool {
        guard let lhsDate = lhs.sourceCreatedAt,
              let rhsDate = rhs.sourceCreatedAt
        else { return false }

        return abs(lhsDate.timeIntervalSince(rhsDate)) <= 45
    }

    private func photoRepresentativeScore(for clip: ClipItem) -> Double {
        let fingerprint = clip.photoSimilarityFingerprint.map(Double.init)
        guard !fingerprint.isEmpty else { return 0 }

        let average = fingerprint.reduce(0, +) / Double(fingerprint.count)
        let exposureScore = max(0, 1 - abs(average - 138) / 138)
        let contrast = sqrt(
            fingerprint.reduce(0) { partial, value in
                partial + pow(value - average, 2)
            } / Double(fingerprint.count)
        ) / 80
        let detail = zip(fingerprint, fingerprint.dropFirst()).reduce(0.0) {
            $0 + abs($1.0 - $1.1)
        } / Double(max(1, fingerprint.count - 1)) / 55

        return exposureScore * 0.42
            + min(1, contrast) * 0.34
            + min(1, detail) * 0.24
    }

    private func rebalanceSimilarPhotoGroup(_ groupID: UUID) {
        let groupIndices = clips.indices.filter {
            clips[$0].similarPhotoGroupID == groupID
        }

        guard groupIndices.count > 1 else {
            for index in groupIndices {
                clips[index].similarPhotoGroupID = nil
                clips[index].similarPhotoGroupIndex = 0
                clips[index].similarPhotoGroupCount = 1
                clips[index].isSimilarPhotoGroupRepresentative = true
            }
            return
        }

        let groupMode = clips[groupIndices[0]].videoSegmentMode
        switch groupMode {
        case .single:
            applyAutomaticSimilarPhotoSelection(groupID: groupID)
        case .multiple:
            break
        case .all:
            setAllSimilarPhotosIncluded(groupID: groupID)
        }

        let includedIndices = groupIndices.filter {
            clips[$0].isSimilarPhotoGroupRepresentative
        }
        let fallbackIncludedIndex = groupIndices.max {
            photoRepresentativeScore(for: clips[$0])
                < photoRepresentativeScore(for: clips[$1])
        }
        if includedIndices.isEmpty, let fallbackIncludedIndex {
            clips[fallbackIncludedIndex].isSimilarPhotoGroupRepresentative = true
        }
        for (offset, index) in groupIndices.enumerated() {
            clips[index].similarPhotoGroupIndex = offset
            clips[index].similarPhotoGroupCount = groupIndices.count
            if offset > 0 {
                clips[index].videoSegmentMode = .single
            }
        }
    }

    private func automaticSimilarPhotoRepresentativeCount(total: Int) -> Int {
        max(
            1,
            Int(
                ceil(
                    Double(total)
                        / Double(similarPhotoRepresentativeInterval)
                )
            )
        )
    }

    private func applyAutomaticSimilarPhotoSelection(groupID: UUID) {
        let rankedIndices = clips.indices
            .filter { clips[$0].similarPhotoGroupID == groupID }
            .sorted {
                photoRepresentativeScore(for: clips[$0])
                    > photoRepresentativeScore(for: clips[$1])
            }
        let count = automaticSimilarPhotoRepresentativeCount(
            total: rankedIndices.count
        )
        let selected = Set(rankedIndices.prefix(count))
        for index in rankedIndices {
            clips[index].isSimilarPhotoGroupRepresentative = selected.contains(index)
        }
    }

    private func setAllSimilarPhotosIncluded(groupID: UUID) {
        for index in clips.indices where clips[index].similarPhotoGroupID == groupID {
            clips[index].isSimilarPhotoGroupRepresentative = true
        }
    }

    func addAiShotVideo(url: URL, triggerTime: Double) {
        Task {
            defer {
                try? FileManager.default.removeItem(at: url)
            }

            do {
                let thumbnail = try await videoThumbnail(
                    for: url,
                    at: max(0, triggerTime)
                )
                let sourceDuration = try await PhotoLibraryService
                    .videoDuration(at: url)
                let analysis = try? await AudioAnalysisService.analyze(url: url)
                let selectedDuration = min(
                    defaultDuration,
                    max(0.1, sourceDuration)
                )
                let trimStart = max(
                    0,
                    min(
                        sourceDuration - selectedDuration,
                        triggerTime - selectedDuration / 2
                    )
                )
                let stableSource = try WorkingClipSourceStore.persist(
                    .videoFile(url)
                )
                let clip = ClipItem(
                    source: stableSource,
                    thumbnail: thumbnail,
                    duration: selectedDuration,
                    photoDuration: selectedDuration,
                    mediaKind: .video,
                    sourceDuration: sourceDuration,
                    trimStart: trimStart,
                    audioWaveform: analysis?.waveform ?? [],
                    audioPeakTime: triggerTime,
                    audioPeakTimes: analysis?.peakTimes ?? [triggerTime],
                    sourcePixelSize: thumbnail.size
                )

                if clips.isEmpty {
                    automaticSourceSize = clip.sourcePixelSize
                    outputAspectRatio = Self.storedDefaultAspectRatio()
                }
                clips.append(clip)
                isProjectOpen = true
                saveProjectSnapshotAfterAiShot()
            } catch {
                alertMessage = "AiShot 클립을 추가할 수 없습니다."
            }
        }
    }

    func discardEmptyAiShotProject() {
        guard clips.isEmpty, let projectID = activeProjectID else { return }
        let project = ProjectStore.listProjects().first { $0.id == projectID }
        guard project?.kind == .aiShot else { return }

        do {
            try ProjectStore.delete(id: projectID)
            reset()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func saveProjectSnapshotAfterAiShot() {
        guard !clips.isEmpty, !isExporting else { return }

        do {
            let savedID = try ProjectStore.save(
                clips: clips,
                defaultDuration: defaultDuration,
                defaultVideoSegmentMode: defaultVideoSegmentMode,
                outputAspectRatio: outputAspectRatio,
                automaticSourceSize: automaticSourceSize,
                textOverlaySettings: textOverlaySettings,
                backgroundMusicSettings: backgroundMusicSettings,
                activeProjectID: activeProjectID,
                kind: .aiShot
            )
            activeProjectID = savedID
            newlySavedProjectID = savedID
            openedProjectSignature = currentProjectSignature()
            reloadProjects()
        } catch {
            alertMessage = error.localizedDescription
        }
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
        let removedClip = clips.first { $0.id == id }
        let similarPhotoGroupID = removedClip?.similarPhotoGroupID
        let removesWholeSimilarGroup = removedClip?
            .similarPhotoGroupIndex == 0
        clips.removeAll { clip in
            clip.id == id
                || clip.videoSegmentParentID == id
                || (removesWholeSimilarGroup
                    && similarPhotoGroupID != nil
                    && clip.similarPhotoGroupID == similarPhotoGroupID)
        }
        if let similarPhotoGroupID {
            rebalanceSimilarPhotoGroup(similarPhotoGroupID)
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
        projectSaveTask?.cancel()
        projectSaveTask = nil
        projectLoadTask?.cancel()
        projectLoadTask = nil
        calendarImportTask?.cancel()
        calendarImportTask = nil
        sharedImportTask?.cancel()
        sharedImportTask = nil
        releaseEditingMemory()
        isPickerPresented = false
        isCalendarPickerPresented = false
        isFileImporterPresented = false
        isBackgroundMusicImporterPresented = false
        isExporting = false
        isLoadingCalendarPicker = false
        calendarPickerLoadProgress = 0
        isImportingCalendarMedia = false
        calendarImportProgress = 0
        progressMessage = ""
        isSavingProject = false
        projectSaveProgress = 0
        isLoadingProject = false
        projectLoadProgress = 0
        previewProgress = 0
        isPreviewRendering = false
        isImportingFiles = false
        isImportingPhotoLibraryMedia = false
        isImportingSharedItems = false
        sharedImportProgress = 0
        sharedImportThumbnail = nil
        previewThumbnail = nil
        exportedURL = nil
        showPreview = false
        previewSaveRequest = nil
        showFileExporter = false
        alertMessage = nil
        activeProjectID = nil
        openedProjectSignature = nil
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

        startProjectSave(returnHomeAfterSaving: true)
    }

    func saveProjectOnly() {
        guard !clips.isEmpty, !isExporting else { return }

        startProjectSave(returnHomeAfterSaving: false)
    }

    private func startProjectSave(returnHomeAfterSaving: Bool) {
        isExporting = true
        isSavingProject = true
        projectSaveProgress = 0
        progressMessage = "영화 프로젝트를 저장하는 중…"

        let clipsToSave = clips
        let duration = defaultDuration
        let segmentMode = defaultVideoSegmentMode
        let aspectRatio = outputAspectRatio
        let sourceSize = automaticSourceSize
        let overlaySettings = textOverlaySettings
        let musicSettings = backgroundMusicSettings
        let projectID = activeProjectID

        projectSaveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let savedID = try await ProjectStore.saveWithProgress(
                    clips: clipsToSave,
                    defaultDuration: duration,
                    defaultVideoSegmentMode: segmentMode,
                    outputAspectRatio: aspectRatio,
                    automaticSourceSize: sourceSize,
                    textOverlaySettings: overlaySettings,
                    backgroundMusicSettings: musicSettings,
                    activeProjectID: projectID,
                    projectKindOverride: .standard
                ) { [self] progress in
                    Task { @MainActor in
                        self.projectSaveProgress = progress
                    }
                }
                try Task.checkCancellation()
                activeProjectID = savedID
                newlySavedProjectID = savedID
                openedProjectSignature = returnHomeAfterSaving
                    ? nil
                    : currentProjectSignature()
                projectSaveTask = nil
                if returnHomeAfterSaving {
                    reset()
                } else {
                    finishProjectSave()
                    reloadProjects()
                }
            } catch is CancellationError {
                finishProjectSave()
            } catch {
                finishProjectSave()
                alertMessage = error.localizedDescription
            }
        }
    }

    func cancelProjectSave() {
        guard isSavingProject else { return }
        progressMessage = "영화 저장을 취소하는 중…"
        projectSaveTask?.cancel()
    }

    private func finishProjectSave() {
        projectSaveTask = nil
        isExporting = false
        isSavingProject = false
        projectSaveProgress = 0
        progressMessage = ""
    }

    func saveProjectAndOpenPreview() {
        guard !renderableClips.isEmpty, !isExporting else { return }
        isExporting = true
        isPreviewRendering = true
        previewProgress = 0
        previewThumbnail = renderableClips.first?.thumbnail
        progressMessage = "영화를 저장하는 중…"

        previewTask = Task {
            do {
                let savedID = try await ProjectStore.saveWithProgress(
                    clips: clips,
                    defaultDuration: defaultDuration,
                    defaultVideoSegmentMode: defaultVideoSegmentMode,
                    outputAspectRatio: outputAspectRatio,
                    automaticSourceSize: automaticSourceSize,
                    textOverlaySettings: textOverlaySettings,
                    backgroundMusicSettings: backgroundMusicSettings,
                    activeProjectID: activeProjectID
                ) { [self] progress in
                    Task { @MainActor in
                        self.previewProgress = progress * 0.10
                    }
                }
                try Task.checkCancellation()
                let savedProject = try ProjectStore.load(id: savedID)
                clips = savedProject.clips
                defaultDuration = savedProject.defaultDuration
                defaultVideoSegmentMode = savedProject.defaultVideoSegmentMode
                outputAspectRatio = savedProject.outputAspectRatio
                automaticSourceSize = savedProject.automaticSourceSize
                textOverlaySettings = savedProject.textOverlaySettings
                backgroundMusicSettings = savedProject.backgroundMusicSettings
                reloadProjects()
                activeProjectID = savedProjects.contains {
                    $0.id == savedID
                } ? savedID : nil
                newlySavedProjectID = savedID
                openedProjectSignature = currentProjectSignature()

                let compositionItems = savedProject.clips.filter(
                    \.isRenderableClip
                )
                previewProgress = 0.10
                progressMessage = "시사회 영화를 준비하는 중…"
                let output = try await VideoComposer().compose(
                    items: compositionItems,
                    renderSize: outputRenderSize,
                    watermarkSettings: textOverlaySettings
                        .withCopyrightSettings(
                            CopyrightPurchaseManager.shared.isPurchased
                                ? WatermarkSettings.stored()
                                : WatermarkSettings.stored()
                                    .withLogoEnabled(false)
                        ),
                    backgroundMusicSettings: backgroundMusicSettings
                ) { [self] progress in
                    await updatePreviewProgress(progress)
                }
                try Task.checkCancellation()
                previewProgress = 0.96
                progressMessage = "개봉 파일을 준비하는 중…"
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

    func startPhotoLibraryImport() {
        isImportingPhotoLibraryMedia = true
    }

    func finishPhotoLibraryImport() {
        isImportingPhotoLibraryMedia = false
    }

    func cancelPreviewGeneration() {
        guard isPreviewRendering else { return }
        progressMessage = "시사회 준비를 취소하는 중…"
        previewTask?.cancel()
    }

    private func updatePreviewProgress(_ progress: Double) {
        previewProgress = 0.10 + progress * 0.85
        if progress >= 0.86 {
            progressMessage = "필름을 전달 하는 중"
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
        defaultVideoSegmentMode = .multiple
        outputAspectRatio = Self.storedDefaultAspectRatio()
        textOverlaySettings = WatermarkSettings.projectDefault()
        backgroundMusicSettings = .projectDefault
        automaticSourceSize = CGSize(width: 1, height: 1)
        isPickerPresented = false
        isFileImporterPresented = false
        isBackgroundMusicImporterPresented = false
        isCalendarPickerPresented = false
        isLoadingCalendarPicker = false
        calendarPickerLoadProgress = 0
        activeProjectID = nil
        openedProjectSignature = nil
    }

    func loadProject(
        id: UUID,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        guard !isLoadingProject else { return }
        isLoadingProject = true
        projectLoadProgress = 0
        progressMessage = "저장된 영화 파일을 불러오는 중…"

        projectLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let project = try await ProjectStore.loadWithProgress(
                    id: id
                ) { [self] progress in
                    Task { @MainActor in
                        self.projectLoadProgress = progress
                    }
                }
                try Task.checkCancellation()
                projectLoadProgress = 0.97
                progressMessage = "영화 설정과 묶음사진을 정리하는 중…"
                await Task.yield()
                applyLoadedProject(project)
                finishProjectLoad()
                completion?(true)
            } catch is CancellationError {
                finishProjectLoad()
                completion?(false)
            } catch {
                finishProjectLoad()
                alertMessage = error.localizedDescription
                reloadProjects()
                completion?(false)
            }
        }
    }

    private func applyLoadedProject(_ project: LoadedProject) {
        clips = project.clips
        defaultDuration = Self.normalizedDefaultDuration(
            project.defaultDuration
        )
        defaultVideoSegmentMode = project.defaultVideoSegmentMode
        outputAspectRatio = project.outputAspectRatio
        automaticSourceSize = project.automaticSourceSize
        textOverlaySettings = project.textOverlaySettings
        backgroundMusicSettings = project.backgroundMusicSettings
        exportedURL = nil
        showPreview = false
        activeProjectID = project.id
        isProjectOpen = true
        reapplyCurrentProjectCriteria()
        refreshLivePhotoDurations()
        openedProjectSignature = currentProjectSignature()
    }

    private func loadProjectImmediately(id: UUID) {
        do {
            let project = try ProjectStore.load(id: id)
            applyLoadedProject(project)
        } catch {
            alertMessage = error.localizedDescription
            reloadProjects()
        }
    }

    func cancelProjectLoad() {
        guard isLoadingProject else { return }
        progressMessage = "영화 불러오기를 취소하는 중…"
        projectLoadTask?.cancel()
    }

    private func finishProjectLoad() {
        projectLoadTask = nil
        isLoadingProject = false
        projectLoadProgress = 0
        progressMessage = ""
    }

    func editLastSavedProject() {
        showPreview = false
        guard !isLoadingProject else { return }
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
        let projects = ProjectStore.listProjects()
        let emptyAiShotIDs = projects
            .filter { $0.kind == .aiShot && $0.clipCount == 0 }
            .map(\.id)
        for id in emptyAiShotIDs {
            try? ProjectStore.delete(id: id)
        }
        savedProjects = emptyAiShotIDs.isEmpty
            ? projects
            : ProjectStore.listProjects()
    }

    func removeExcessAiShotProjects() {
        _ = try? ProjectStore.removeExcessAiShotProjects()
        reloadProjects()
    }

    private func currentProjectSignature() -> ProjectEditSignature {
        ProjectEditSignature(
            clips: clips.map(clipSignature),
            defaultDuration: roundedSignatureValue(defaultDuration),
            defaultVideoSegmentMode: defaultVideoSegmentMode,
            outputAspectRatio: outputAspectRatio,
            automaticSourceSize: automaticSourceSize,
            textOverlaySettings: watermarkSignature(textOverlaySettings),
            backgroundMusicSettings: backgroundMusicSettings
        )
    }

    private func clipSignature(_ clip: ClipItem) -> ClipEditSignature {
        ClipEditSignature(
            id: clip.id,
            source: sourceSignature(clip.source),
            duration: roundedSignatureValue(clip.duration),
            photoDuration: roundedSignatureValue(clip.photoDuration),
            livePhotoDuration: clip.livePhotoDuration.map(roundedSignatureValue),
            isLivePhoto: clip.isLivePhoto,
            livePhotoMode: clip.livePhotoMode,
            mediaKind: clip.mediaKind,
            sourceDuration: clip.sourceDuration.map(roundedSignatureValue),
            trimStart: roundedSignatureValue(clip.trimStart),
            audioPeakTime: clip.audioPeakTime.map(roundedSignatureValue),
            audioPeakTimes: clip.audioPeakTimes.map(roundedSignatureValue),
            videoSegmentMode: clip.videoSegmentMode,
            isVideoSegmentParent: clip.isVideoSegmentParent,
            videoSegmentParentID: clip.videoSegmentParentID,
            isVideoSegmentSelected: clip.isVideoSegmentSelected,
            similarPhotoGroupID: clip.similarPhotoGroupID,
            similarPhotoGroupIndex: clip.similarPhotoGroupIndex,
            similarPhotoGroupCount: clip.similarPhotoGroupCount,
            isSimilarPhotoGroupRepresentative: clip
                .isSimilarPhotoGroupRepresentative,
            sourceCreatedAt: clip.sourceCreatedAt,
            sourcePixelSize: clip.sourcePixelSize
        )
    }

    private func sourceSignature(_ source: ClipSource) -> String {
        switch source {
        case .photoAsset(let localIdentifier):
            return "photo:\(localIdentifier)"
        case .imageFile(let url):
            return "image:\(url.standardizedFileURL.path)"
        case .videoFile(let url):
            return "video:\(url.standardizedFileURL.path)"
        case .livePhotoFiles(let imageURL, let videoURL):
            return "live:\(imageURL.standardizedFileURL.path)|\(videoURL.standardizedFileURL.path)"
        }
    }

    private func roundedSignatureValue(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private func watermarkSignature(_ settings: WatermarkSettings) -> String {
        [
            "\(settings.isEnabled)",
            "\(settings.logoEnabled)",
            settings.text,
            settings.address,
            settings.platform.rawValue,
            settings.position.rawValue,
            settings.fontName,
            settings.textColorHex,
            "\(settings.shadowEnabled)",
            "\(roundedSignatureValue(settings.shadowOpacity))",
            settings.shadowColorHex,
            settings.lineSpacing.rawValue,
            "\(roundedSignatureValue(settings.lineSpacingScale))",
            settings.fontSize.rawValue,
            settings.copyrightPosition.rawValue,
            settings.copyrightTextColorHex,
            settings.copyrightShadowColorHex,
            "\(roundedSignatureValue(settings.copyrightShadowOpacity))",
            settings.copyrightIconColorMode.rawValue,
            settings.copyrightIconColorHex,
            settings.customCopyrightIconPath
        ].joined(separator: "\u{1F}")
    }

    func refreshPendingSharedItems() {
        let records = SharedInbox.pendingRecords()
        let thumbnailRecords = Array(records.prefix(9))
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
        importSharedBrowserFavoritesIfNeeded()
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
                defaultVideoSegmentMode: defaultVideoSegmentMode,
                outputAspectRatio: outputAspectRatio,
                automaticSourceSize: automaticSourceSize,
                textOverlaySettings: textOverlaySettings,
                backgroundMusicSettings: backgroundMusicSettings,
                activeProjectID: activeProjectID
            )
            reset()
            newlySavedProjectID = savedID
            refreshPendingSharedItems()
        } catch {
            alertMessage =
                "현재 영화를 저장하지 못해 공유 파일 대기 화면으로 "
                + "이동하지 못했습니다. \(error.localizedDescription)"
        }
    }

    private func importSharedBrowserFavoritesIfNeeded() {
        let pending = SharedInbox.consumePendingRecords()
        let favoriteRecords = pending.filter {
            $0.kind == .browserFavorites
        }
        let remainingRecords = pending.filter {
            $0.kind != .browserFavorites
        }
        SharedInbox.append(remainingRecords)
        guard !favoriteRecords.isEmpty else { return }

        var importedURLs: [String] = []
        for record in favoriteRecords {
            guard let url = try? SharedInbox.fileURL(
                named: record.primaryFilename
            ), let data = try? Data(contentsOf: url),
               let archive = try? JSONDecoder().decode(
                BrowserFavoritesArchive.self,
                from: data
               )
            else { continue }
            importedURLs.append(contentsOf: archive.favorites)
            try? FileManager.default.removeItem(at: url)
        }

        let storageKey = "hanClipOnlineMusicFavorites"
        let existing = UserDefaults.standard.string(forKey: storageKey) ?? ""
        var merged: [String] = []
        var indexByAddress: [String: Int] = [:]

        for value in existing.split(separator: "\n").map(String.init) {
            let trimmed = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard let key = browserFavoriteAddressKey(trimmed) else {
                continue
            }
            if let index = indexByAddress[key] {
                merged[index] = trimmed
            } else {
                indexByAddress[key] = merged.count
                merged.append(trimmed)
            }
        }

        var addedCount = 0
        var replacedAddresses = Set<String>()
        for value in importedURLs {
            let trimmed = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard let key = browserFavoriteAddressKey(trimmed) else {
                continue
            }
            if let index = indexByAddress[key] {
                merged[index] = trimmed
                replacedAddresses.insert(key)
            } else {
                indexByAddress[key] = merged.count
                merged.append(trimmed)
                addedCount += 1
            }
        }
        UserDefaults.standard.set(
            merged.joined(separator: "\n"),
            forKey: storageKey
        )
        let replacedCount = replacedAddresses.count
        if addedCount > 0, replacedCount > 0 {
            alertMessage = "브라우저 즐겨찾기 \(addedCount)개를 추가하고 "
                + "\(replacedCount)개를 덮어썼습니다."
        } else if addedCount > 0 {
            alertMessage = "브라우저 즐겨찾기 \(addedCount)개를 추가했습니다."
        } else if replacedCount > 0 {
            alertMessage = "브라우저 즐겨찾기 \(replacedCount)개를 덮어썼습니다."
        } else {
            alertMessage = "가져올 브라우저 즐겨찾기가 없습니다."
        }
    }

    private func browserFavoriteAddressKey(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme,
              let host = components.host
        else { return trimmed.lowercased() }

        components.scheme = scheme.lowercased()
        components.host = host.lowercased()
        components.fragment = nil
        if components.path.isEmpty {
            components.path = "/"
        } else {
            while components.path.count > 1,
                  components.path.hasSuffix("/") {
                components.path.removeLast()
            }
        }
        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        return components.string ?? trimmed.lowercased()
    }

    func deletePendingSharedItems() {
        SharedInbox.clearPendingImports()
        pendingSharedItemCount = 0
        pendingSharedThumbnails = []
    }

    func queueBrowserDownloadAsSharedItem(
        _ url: URL,
        isVideo: Bool = false
    ) -> Bool {
        do {
            let filename = try Self.copyFileToSharedInbox(
                url,
                fallbackExtension: isVideo ? "mp4" : "mp3"
            )
            SharedInbox.append([
                SharedImportRecord(
                    kind: isVideo ? .video : .image,
                    primaryFilename: filename,
                    originalFilename: url.lastPathComponent.isEmpty
                        ? filename
                        : url.lastPathComponent
                )
            ])
            refreshPendingSharedItems()
            return true
        } catch {
            alertMessage =
                "브라우저에서 받은 파일을 대기 목록에 넣지 못했습니다. "
                + error.localizedDescription
            return false
        }
    }

    func loadProjectAndImportPending(id: UUID) {
        loadProject(id: id) { [weak self] didLoad in
            guard let self, didLoad,
                  isProjectOpen, pendingSharedItemCount > 0
            else { return }
            importSharedItems(destination: .existingProject)
        }
    }

    func importPendingItemsIntoNewProject() {
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
        guard !isLoadingProject else { return }
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
        progressMessage = "사진 앱으로 개봉하는 중…"

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
                    ? "사진 앱에 개봉했습니다."
                    : "\(albumName) 앨범에 개봉했습니다."
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
        guard !isImportingSharedItems else { return }
        let storedDestination = SharedInbox.consumeImportDestination()
        let requestedDestination = destination ?? storedDestination
        let records = SharedInbox.consumePendingRecords()
        guard !records.isEmpty else { return }
        pendingSharedItemCount = 0
        pendingSharedThumbnails = []
        isImportingSharedItems = true
        sharedImportProgress = 0
        sharedImportThumbnail = nil
        progressMessage =
            "공유한 파일 \(records.count)개를 불러오는 중…"

        sharedImportTask = Task {
            let preparedNewProjectBeforeImport: Bool
            if requestedDestination == .newProject {
                // Do this before decoding shared media. Otherwise a large
                // existing project and every newly decoded thumbnail coexist
                // until 100%, creating the import's highest memory spike.
                prepareNewProjectForSharedImport()
                preparedNewProjectBeforeImport = true
            } else {
                preparedNewProjectBeforeImport = false
            }

            var imported: [ClipItem] = []
            imported.reserveCapacity(records.count)
            let audioRecords = records
                .filter(Self.isSharedAudioRecord)
                .sorted(by: sharedAudioRecordSortOrder)
            let mediaRecords = records.filter {
                !Self.isSharedAudioRecord($0)
                    && $0.kind != .browserFavorites
            }
            let shouldAnalyzeSharedVideoAudio = records.count < 20
            let unresolvedLivePhotoNames = Set(
                mediaRecords.compactMap { record -> String? in
                    guard record.kind == .livePhoto,
                          record.secondaryFilename == nil else { return nil }
                    return record.originalFilename
                }
            )
            let resolvedLivePhotoAssets: [String: PHAsset]
            if !unresolvedLivePhotoNames.isEmpty,
               await PhotoLibraryService.requestReadAccess() {
                resolvedLivePhotoAssets = PhotoLibraryService.livePhotoAssets(
                    matchingOriginalFilenames: unresolvedLivePhotoNames
                )
            } else {
                resolvedLivePhotoAssets = [:]
            }
            var unresolvedLivePhotoCount = 0
            for (index, record) in mediaRecords.enumerated() {
                guard !Task.isCancelled else {
                    cancelSharedImportAndRestore(
                        records
                    )
                    return
                }
                do {
                    let primary = try SharedInbox.fileURL(
                        named: record.primaryFilename
                    )
                    switch record.kind {
                    case .image:
                        let imageInfo = await Task.detached(
                            priority: .userInitiated
                        ) {
                            Self.sharedImageInfo(at: primary)
                        }.value
                        guard let imageInfo else { continue }
                        imported.append(
                            ClipItem(
                                source: .imageFile(primary),
                                thumbnail: imageInfo.thumbnail,
                                duration: defaultDuration,
                                photoSimilarityFingerprint:
                                    imageInfo.fingerprint,
                                sourcePixelSize: imageInfo.pixelSize
                            )
                        )
                        sharedImportThumbnail = imageInfo.thumbnail

                    case .video:
                        imported.append(
                            contentsOf: try await makeVideoClips(
                                from: primary,
                                analyzeAudio: shouldAnalyzeSharedVideoAudio
                            )
                        )

                    case .livePhoto:
                        let imageInfo = await Task.detached(
                            priority: .userInitiated
                        ) {
                            Self.sharedImageInfo(at: primary)
                        }.value
                        guard let imageInfo else { continue }
                        let image = imageInfo.thumbnail
                        sharedImportThumbnail = image

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
                                    photoSimilarityFingerprint:
                                        imageInfo.fingerprint,
                                    sourcePixelSize: imageInfo.pixelSize
                                )
                            )
                        } else if let originalFilename = record.originalFilename,
                           let asset = resolvedLivePhotoAssets[
                            PhotoLibraryService.normalizedFilename(
                                originalFilename
                            )
                           ] {
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
                                    photoSimilarityFingerprint:
                                        imageInfo.fingerprint,
                                    sourceCreatedAt: asset.creationDate,
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
                                    photoSimilarityFingerprint:
                                        imageInfo.fingerprint,
                                    sourcePixelSize: imageInfo.pixelSize
                                )
                            )
                        }
                    case .browserFavorites:
                        continue
                    }
                } catch {
                    continue
                }

                let completedCount = index + 1
                sharedImportProgress =
                    Double(completedCount) / Double(max(1, records.count))
                    * 0.98
                progressMessage =
                    "공유한 파일 \(completedCount)/\(records.count)개를 "
                    + "불러오는 중…"

                // Give SwiftUI a chance to display progress between large
                // batches instead of presenting a frozen 0% screen.
                await Task.yield()
            }

            guard !Task.isCancelled else {
                cancelSharedImportAndRestore(
                    records
                )
                return
            }

            let selectedAudioURL = audioRecords.first.flatMap {
                try? SharedInbox.fileURL(named: $0.primaryFilename)
            }
            sharedImportProgress = 0.99
            progressMessage = "영화 화면을 정리하는 중…"
            await Task.yield()

            if !imported.isEmpty || selectedAudioURL != nil {
                switch requestedDestination {
                case .newProject:
                    if !preparedNewProjectBeforeImport {
                        prepareNewProjectForSharedImport()
                    }
                case .existingProject:
                    prepareExistingProjectForSharedImport()
                case nil:
                    if !isProjectOpen {
                        beginNewProject()
                    }
                }
                if !imported.isEmpty {
                    addPickedItems(
                        imported,
                        sourcesAlreadyPersisted: true
                    )
                }
                let didImportMusic: Bool
                if let selectedAudioURL {
                    didImportMusic = importBackgroundMusic([selectedAudioURL])
                } else {
                    didImportMusic = false
                }
                if unresolvedLivePhotoCount > 0 {
                    alertMessage =
                        "공유한 항목 \(imported.count)개를 가져왔습니다. "
                        + "Live Photo \(unresolvedLivePhotoCount)개는 "
                        + "사진 보관함에서 원본을 찾지 못해 사진으로 "
                        + "가져왔습니다."
                } else if didImportMusic, imported.isEmpty {
                    alertMessage = "공유한 음악 파일을 적용했습니다."
                } else if didImportMusic {
                    alertMessage =
                        "공유한 항목 \(imported.count)개와 음악 파일을 "
                        + "가져왔습니다."
                } else if selectedAudioURL != nil {
                    alertMessage = imported.isEmpty
                        ? "음악 파일을 가져올 수 없습니다."
                        : "공유한 항목 \(imported.count)개를 가져왔지만 음악 파일은 가져오지 못했습니다."
                } else {
                    alertMessage =
                        "공유한 항목 \(imported.count)개를 가져왔습니다."
                }
            } else {
                alertMessage =
                    "공유한 항목을 불러오지 못했습니다."
            }
            isImportingSharedItems = false
            progressMessage = ""
            sharedImportProgress = 0
            sharedImportThumbnail = nil
            sharedImportTask = nil
        }
    }

    func cancelSharedItemImport() {
        guard isImportingSharedItems else { return }
        progressMessage = "공유 미디어 불러오기를 취소하는 중…"
        sharedImportTask?.cancel()
    }

    private func cancelSharedImportAndRestore(
        _ records: [SharedImportRecord]
    ) {
        SharedInbox.append(records)
        isImportingSharedItems = false
        sharedImportProgress = 0
        sharedImportThumbnail = nil
        progressMessage = ""
        sharedImportTask = nil
        refreshPendingSharedItems()
        alertMessage = "공유 미디어 불러오기를 취소했습니다. 다시 시도할 수 있습니다."
    }

    nonisolated private static func sharedImageInfo(
        at url: URL,
        maxPixelSize: CGFloat = 320
    ) -> (
        thumbnail: UIImage,
        pixelSize: CGSize,
        fingerprint: [UInt8]
    )? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?
            .doubleValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?
            .doubleValue ?? 0

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }

        let thumbnail = UIImage(cgImage: image)
        let pixelSize = width > 0 && height > 0
            ? CGSize(width: width, height: height)
            : thumbnail.size
        return (
            thumbnail,
            pixelSize,
            // Shared imports can contain hundreds of items. The 16×16
            // structure fingerprint is sufficient for grouping; running a
            // Vision face request for every shared image made this path
            // several times slower and accumulated memory before the final
            // screen transition.
            PhotoSimilarityFingerprint.make(
                from: thumbnail,
                detectFaces: false
            )
        )
    }

    private func sharedAudioRecordSortOrder(
        _ lhs: SharedImportRecord,
        _ rhs: SharedImportRecord
    ) -> Bool {
        let left = lhs.originalFilename ?? lhs.primaryFilename
        let right = rhs.originalFilename ?? rhs.primaryFilename
        return left.localizedStandardCompare(right) == .orderedAscending
    }

    nonisolated private static func isSharedAudioRecord(
        _ record: SharedImportRecord
    ) -> Bool {
        return isSharedAudioFilename(record.primaryFilename)
            || isSharedAudioFilename(record.originalFilename)
    }

    nonisolated private static func isSharedAudioFilename(
        _ filename: String?
    ) -> Bool {
        guard let filename else { return false }
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return [
            "aac",
            "aif",
            "aiff",
            "caf",
            "m4a",
            "mp3",
            "wav"
        ].contains(ext)
    }

    private func prepareNewProjectForSharedImport() {
        if isProjectOpen, !clips.isEmpty {
            _ = try? ProjectStore.save(
                clips: clips,
                defaultDuration: defaultDuration,
                defaultVideoSegmentMode: defaultVideoSegmentMode,
                outputAspectRatio: outputAspectRatio,
                automaticSourceSize: automaticSourceSize,
                textOverlaySettings: textOverlaySettings,
                backgroundMusicSettings: backgroundMusicSettings,
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
            loadProjectImmediately(id: latestProject.id)
        } else {
            beginNewProject()
            alertMessage =
                "기존 영화가 없어 새 영화에 추가했습니다."
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImportingFiles = true
        progressMessage = "파일을 가져오는 중…"

        Task {
            defer {
                isImportingFiles = false
                progressMessage = ""
            }

            var imported: [ClipItem] = []
            for (index, source) in urls.enumerated() {
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
                    imported.append(contentsOf: try await makeVideoClips(from: local))
                } catch {
                    continue
                }

                progressMessage =
                    "파일 \(index + 1)/\(urls.count)개를 가져오는 중…"
            }
            addPickedItems(imported)
            if imported.isEmpty {
                alertMessage = "선택한 영상 파일을 가져올 수 없습니다."
            }
        }
    }

    func importMediaFromCalendarDates(_ dates: Set<Date>) {
        guard !dates.isEmpty else { return }
        calendarImportTask?.cancel()
        let selectedDates = Set(
            dates.map { Calendar.current.startOfDay(for: $0) }
        )
        isCalendarPickerPresented = false
        isImportingCalendarMedia = true
        calendarImportProgress = 0
        progressMessage = "선택한 날짜의 미디어를 불러오는 중…"

        calendarImportTask = Task {
            let assets = PhotoLibraryService.mediaAssets(
                on: selectedDates,
                calendar: .current
            )
            var imported: [ClipItem] = []
            imported.reserveCapacity(assets.count)

            for (index, asset) in assets.enumerated() {
                guard !Task.isCancelled else { break }
                do {
                    let thumbnail = try await PhotoLibraryService.thumbnail(
                        for: asset,
                        size: CGSize(width: 160, height: 160)
                    )
                    let items = try await makeClips(from: asset, thumbnail)
                    for item in items {
                        guard !Task.isCancelled else { break }
                        let persistedItem = try await persistCalendarImportedItem(
                            item
                        )
                        if Task.isCancelled {
                            WorkingClipSourceStore.remove(persistedItem.source)
                            break
                        }
                        imported.append(persistedItem)
                    }
                } catch {
                    continue
                }

                guard !Task.isCancelled else { break }

                calendarImportProgress = assets.isEmpty
                    ? 1
                    : Double(index + 1) / Double(assets.count) * 0.92
                progressMessage =
                    "선택한 날짜의 미디어 \(index + 1)/\(assets.count)개를 "
                    + "불러오는 중…"
            }

            guard !Task.isCancelled else {
                cancelCalendarImportAndRollback(imported)
                return
            }

            calendarImportProgress = 0.94
            progressMessage = "불러온 미디어를 정리하는 중…"
            let thumbnailRefreshTask = addPickedItems(
                imported,
                sourcesAlreadyPersisted: true
            )

            if let thumbnailRefreshTask {
                calendarImportProgress = 0.97
                progressMessage = "자영상 썸네일을 정리하는 중…"
                await withTaskCancellationHandler {
                    await thumbnailRefreshTask.value
                } onCancel: {
                    thumbnailRefreshTask.cancel()
                }
            }

            guard !Task.isCancelled else {
                cancelCalendarImportAndRollback(imported)
                return
            }

            alertMessage = imported.isEmpty
                ? "선택한 날짜에 가져올 수 있는 미디어가 없습니다."
                : "선택한 날짜의 미디어 \(imported.count)개를 가져왔습니다."
            calendarImportProgress = 1
            progressMessage = ""
            isImportingCalendarMedia = false
            calendarImportProgress = 0
            calendarImportTask = nil
        }
    }

    func cancelCalendarMediaImport() {
        guard isImportingCalendarMedia else { return }
        progressMessage = "미디어 불러오기를 취소하는 중…"
        calendarImportTask?.cancel()
    }

    private func cancelCalendarImportAndRollback(_ imported: [ClipItem]) {
        let importedIDs = Set(imported.map(\.id))
        clips.removeAll { clip in
            importedIDs.contains(clip.id)
                || clip.videoSegmentParentID.map(importedIDs.contains) == true
        }
        imported.forEach { WorkingClipSourceStore.remove($0.source) }
        progressMessage = ""
        calendarImportProgress = 0
        isImportingCalendarMedia = false
        calendarImportTask = nil
        alertMessage = "미디어 불러오기를 취소했습니다."
    }

    private func persistCalendarImportedItem(
        _ item: ClipItem
    ) async throws -> ClipItem {
        if case .photoAsset = item.source {
            return item
        }

        let originalSource = item.source
        let stableSource = try await Task.detached(priority: .userInitiated) {
            try WorkingClipSourceStore.persist(originalSource)
        }.value
        removeTemporaryImportedSource(originalSource)
        return item.replacingSource(stableSource)
    }

    private func removeTemporaryImportedSource(_ source: ClipSource) {
        let temporaryDirectory = FileManager.default.temporaryDirectory.path

        func removeIfTemporary(_ url: URL) {
            guard url.path.hasPrefix(temporaryDirectory) else { return }
            try? FileManager.default.removeItem(at: url)
        }

        switch source {
        case .photoAsset:
            break
        case .imageFile(let url), .videoFile(let url):
            removeIfTemporary(url)
        case .livePhotoFiles(let imageURL, let videoURL):
            removeIfTemporary(imageURL)
            removeIfTemporary(videoURL)
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
            max(0.1, duration)
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

    @discardableResult
    func applyVideoSegmentModeToAll(
        _ mode: VideoSegmentMode
    ) -> Task<Void, Never>? {
        let normalizedMode: VideoSegmentMode = mode == .single
            ? .single
            : .multiple
        defaultVideoSegmentMode = normalizedMode

        let parentIDs = clips.compactMap { clip -> UUID? in
            guard clip.mediaKind == .video,
                  !clip.isVideoSegmentChild
            else { return nil }
            return clip.id
        }
        guard !parentIDs.isEmpty else { return nil }

        var updatedClips = clips.filter { !$0.isVideoSegmentChild }
        for index in updatedClips.indices where
            updatedClips[index].mediaKind == .video {
            updatedClips[index].videoSegmentMode = .single
            updatedClips[index].isVideoSegmentParent = false
        }

        guard normalizedMode == .multiple else {
            clips = updatedClips
            return nil
        }

        let segmentedParentIDs = applyDefaultVideoSegmentation(
            to: parentIDs,
            in: &updatedClips
        )
        clips = updatedClips
        return segmentedParentIDs.isEmpty
            ? nil
            : refreshSegmentChildThumbnails(parentIDs: segmentedParentIDs)
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
            && clip.isVideoSegmentSelected
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
                isVideoSegmentSelected: true,
                sourcePixelSize: sourceClip.sourcePixelSize
            )
        }

        clips.insert(
            contentsOf: childClips,
            at: clips.index(after: parentIndex)
        )
        _ = refreshSegmentChildThumbnails(
            parentID: sourceClip.id,
            sourceClip: sourceClip
        )
    }

    @discardableResult
    private func refreshSegmentChildThumbnails(
        parentID: UUID,
        sourceClip: ClipItem
    ) -> Task<Void, Never>? {
        refreshSegmentChildThumbnails(
            parentSources: [(id: parentID, clip: sourceClip)]
        )
    }

    @discardableResult
    private func refreshSegmentChildThumbnails(
        parentIDs: [UUID]
    ) -> Task<Void, Never>? {
        let parentIDSet = Set(parentIDs)
        let parentSources = clips.compactMap { clip -> (id: UUID, clip: ClipItem)? in
            guard parentIDSet.contains(clip.id) else { return nil }
            return (id: clip.id, clip: clip)
        }
        return refreshSegmentChildThumbnails(parentSources: parentSources)
    }

    @discardableResult
    private func refreshSegmentChildThumbnails(
        parentSources: [(id: UUID, clip: ClipItem)]
    ) -> Task<Void, Never>? {
        let videoURLs: [UUID: URL] = Dictionary(
            uniqueKeysWithValues: parentSources.compactMap { parent in
                guard case .videoFile(let url) = parent.clip.source
                else { return nil }
                return (parent.id, url)
            }
        )
        let childTargets = clips.compactMap {
            clip -> (id: UUID, parentID: UUID, url: URL, midpoint: Double)? in
            guard let parentID = clip.videoSegmentParentID,
                  let url = videoURLs[parentID]
            else { return nil }
            return (
                id: clip.id,
                parentID: parentID,
                url: url,
                midpoint: clip.trimStart + clip.duration / 2
            )
        }
        guard !childTargets.isEmpty else { return nil }

        return Task {
            let batchSize = 8
            var batchStart = 0

            while batchStart < childTargets.count {
                guard !Task.isCancelled else { break }
                let batchEnd = min(batchStart + batchSize, childTargets.count)
                let batch = Array(childTargets[batchStart..<batchEnd])
                let updates = await withTaskGroup(
                    of: (id: UUID, parentID: UUID, image: UIImage)?.self,
                    returning: [(id: UUID, parentID: UUID, image: UIImage)].self
                ) { group in
                    for target in batch {
                        group.addTask {
                            guard !Task.isCancelled else { return nil }
                            guard let thumbnail = try? await self.videoThumbnail(
                                for: target.url,
                                at: target.midpoint,
                                maximumSize: CGSize(width: 160, height: 160)
                            ) else { return nil }
                            guard !Task.isCancelled else { return nil }
                            return (
                                id: target.id,
                                parentID: target.parentID,
                                image: thumbnail
                            )
                        }
                    }

                    var completed: [(
                        id: UUID,
                        parentID: UUID,
                        image: UIImage
                    )] = []
                    completed.reserveCapacity(batch.count)
                    for await update in group {
                        if let update {
                            completed.append(update)
                        }
                    }
                    return completed
                }

                guard !Task.isCancelled else { break }
                applySegmentThumbnailUpdates(updates)
                batchStart = batchEnd
                await Task.yield()
            }
        }
    }

    private func applySegmentThumbnailUpdates(
        _ updates: [(id: UUID, parentID: UUID, image: UIImage)]
    ) {
        let updatesByID = Dictionary(
            uniqueKeysWithValues: updates.map { ($0.id, $0) }
        )
        var updatedClips = clips
        var didUpdate = false

        for index in updatedClips.indices {
            guard let update = updatesByID[updatedClips[index].id],
                  updatedClips[index].videoSegmentParentID == update.parentID
            else { continue }
            updatedClips[index].thumbnail = update.image
            didUpdate = true
        }
        if didUpdate {
            clips = updatedClips
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
            .filter {
                $0.isLivePhoto
                    && ($0.sourceDuration == nil || $0.livePhotoDuration == nil)
            }
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

    private func makeVideoClips(
        from url: URL,
        analyzeAudio: Bool = true
    ) async throws -> [ClipItem] {
        let thumbnail = try await videoThumbnail(for: url)
        let duration = try await PhotoLibraryService.videoDuration(at: url)
        let analysis: AudioAnalysisResult?
        if analyzeAudio {
            analysis = try? await AudioAnalysisService.analyze(url: url)
        } else {
            analysis = nil
        }
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
                sourceCreatedAt: asset.creationDate,
                sourcePixelSize: CGSize(
                    width: asset.pixelWidth,
                    height: asset.pixelHeight
                )
            )
        ]
    }

    private func videoThumbnail(
        for url: URL,
        at seconds: Double = 0,
        maximumSize: CGSize = CGSize(width: 640, height: 640)
    ) async throws -> UIImage {
        try await Task.detached {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = maximumSize
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
        let audioThumbnails = Dictionary(
            uniqueKeysWithValues: records
                .filter(isSharedAudioRecord)
                .map {
                    (
                        $0.id,
                        pendingAudioThumbnail(
                            title: $0.originalFilename ?? $0.primaryFilename
                        )
                    )
                }
        )
        let task = Task.detached { () -> [UIImage] in
            records.compactMap { record in
                guard let url = try? SharedInbox.fileURL(
                    named: record.primaryFilename
                ) else { return nil }

                if isSharedAudioRecord(record) {
                    return audioThumbnails[record.id]
                }

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
                case .browserFavorites:
                    return UIImage(systemName: "bookmark.square.fill")
                }
            }
        }
        return await task.value
    }

    private static func pendingAudioThumbnail(title: String) -> UIImage {
        let size = CGSize(width: 180, height: 180)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(
                red: 0.06,
                green: 0.47,
                blue: 0.50,
                alpha: 0.24
            ).setFill()
            UIBezierPath(
                roundedRect: rect,
                cornerRadius: 26
            ).fill()

            UIColor(
                red: 0.02,
                green: 0.23,
                blue: 0.26,
                alpha: 0.86
            ).setFill()
            UIBezierPath(
                roundedRect: rect.insetBy(dx: 16, dy: 16),
                cornerRadius: 22
            ).fill()

            let symbolConfig = UIImage.SymbolConfiguration(
                pointSize: 42,
                weight: .bold
            )
            let symbol = UIImage(
                systemName: "music.note",
                withConfiguration: symbolConfig
            )?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            let symbolSize = symbol?.size ?? .zero
            symbol?.draw(
                in: CGRect(
                    x: (size.width - symbolSize.width) / 2,
                    y: 34,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
            )

            let trimmedTitle = title
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            NSString(string: trimmedTitle).draw(
                in: CGRect(x: 18, y: 100, width: 144, height: 44),
                withAttributes: attributes
            )

            let badgeAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.82),
                .paragraphStyle: paragraph
            ]
            NSString(string: "오디오").draw(
                in: CGRect(x: 18, y: 146, width: 144, height: 20),
                withAttributes: badgeAttributes
            )
        }
    }

    private static func copyFileToSharedInbox(
        _ source: URL,
        fallbackExtension: String
    ) throws -> String {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let ext = source.pathExtension.isEmpty
            ? fallbackExtension
            : source.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = try SharedInbox.fileURL(named: filename)
        try FileManager.default.copyItem(at: source, to: destination)
        return filename
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

    static func remove(_ source: ClipSource) {
        switch source {
        case .photoAsset:
            break
        case .imageFile(let url), .videoFile(let url):
            try? FileManager.default.removeItem(at: url)
        case .livePhotoFiles(let imageURL, let videoURL):
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: videoURL)
        }
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
