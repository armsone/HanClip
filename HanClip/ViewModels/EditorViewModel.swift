import AVFoundation
import Combine
import CoreLocation
import ImageIO
import Photos
import SwiftUI

private enum PreviewSaveRequest {
    case photos(albumName: String)
    case files
}

struct EndingInfoRouteStop: Identifiable, Equatable {
    let id = UUID()
    let countryCode: String
    let label: String
    let dateText: String
}

struct EndingInfoPreviewData: Equatable {
    let dateText: String
    let stops: [EndingInfoRouteStop]
}

private struct EndingInfoPackage {
    let preview: EndingInfoPreviewData
    let sourceLocation: CLLocation
    let temporaryImageURL: URL
    let image: UIImage
}

private struct LocatedMediaSample {
    let location: CLLocation
    let date: Date?
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
    case quick
    case aiShot
    case travel
    case life
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

    var selectedMediaDateRange: ClosedRange<Date>? {
        let dates = renderableClips.compactMap(\.sourceCreatedAt)
        guard let firstDate = dates.min(), let lastDate = dates.max() else {
            return nil
        }
        return firstDate...lastDate
    }

    var selectedSourceMediaCount: Int {
        clips.filter { !$0.isVideoSegmentChild }.count
    }

    var hasEndingInfoData: Bool {
        selectedMediaDateRange != nil
            && orderedPhotoLocations(in: renderableClips).isEmpty == false
    }

    var quickRecommendedDuration: Double {
        let sourceMediaCount = max(
            1,
            clips.filter { !$0.isVideoSegmentChild }.count
        )
        return Double(sourceMediaCount)
    }
    @Published var isPickerPresented = false
    @Published var isCalendarPickerPresented = false
    @Published var mediaPickerSelectionIdentifiers: [String] = []
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
    @Published var photoLibraryImportProgress = 0.0
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
    @Published private(set) var isQuickModeProject = false
    @Published private(set) var activeMoviePreset: MoviePreset?
    @Published var isQuickDurationPickerPresented = false
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
        let clipDuration = clips.reduce(0) { total, clip in
            clip.isRenderableClip ? total + clip.duration : total
        }
        return clipDuration
            + (textOverlaySettings.includesEndingInfoCard
                && hasEndingInfoData
                ? textOverlaySettings.endingInfoCardDuration
                : 0)
    }

    func endingInfoPreviewData() async -> EndingInfoPreviewData? {
        await makeEndingInfoPreview(
            for: renderableClips,
            shootingRange: selectedMediaDateRange
        )
    }

    func endingInfoPreviewImage(
        _ data: EndingInfoPreviewData,
        theme: EndingInfoCardTheme
    ) -> UIImage {
        var settings = textOverlaySettings
        settings.endingInfoCardTheme = theme
        return Self.renderEndingInfoCard(
            data,
            backgroundImage: renderableClips.first?.thumbnail,
            size: outputRenderSize,
            settings: settings
        )
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
                isCalendarPickerPresented = false
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
        if preset == .travel || preset == .life {
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
                isPickerPresented = true
            } else {
                alertMessage = "사진 보관함 접근을 허용해 주세요."
            }
        }
    }

    func switchPhotoPickerToCalendar(selectionIdentifiers: [String]) {
        mediaPickerSelectionIdentifiers = selectionIdentifiers
        Task {
            await prepareCalendarPicker()
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.11)) {
                isCalendarPickerPresented = true
            }
        }
    }

    func switchCalendarPickerToPhotos(selectionIdentifiers: [String]) {
        mediaPickerSelectionIdentifiers = selectionIdentifiers
        withAnimation(.easeInOut(duration: 0.11)) {
            isCalendarPickerPresented = false
        }
    }

    func closeMediaPicker() {
        isPickerPresented = false
        isCalendarPickerPresented = false
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
        activeMoviePreset = preset
        isQuickModeProject = preset == .quick

        switch preset {
        case .newMovie:
            defaultDuration = 2
            defaultVideoSegmentMode = .multiple
            overlay = .dateCaptionPreset(text: Self.movieDateCaptionText())
            musicTrackID = nil
        case .quick:
            defaultDuration = 1
            defaultVideoSegmentMode = .multiple
            overlay = .dateCaptionPreset(text: "")
            overlay.isEnabled = true
            musicTrackID = "daily-loop"
        case .aiShot:
            defaultDuration = 4
            defaultVideoSegmentMode = .multiple
            overlay = .greenGolfPreset(text: Self.movieDateCaptionText())
            musicTrackID = nil
        case .golf:
            defaultDuration = 4
            defaultVideoSegmentMode = .multiple
            overlay = .dateCaptionPreset(text: Self.movieDateCaptionText())
            musicTrackID = "golf-lets-go"
        case .travel:
            defaultDuration = 1
            defaultVideoSegmentMode = .multiple
            setSimilarPhotoRepresentativeInterval(6)
            overlay = .travelPreset(text: Self.movieDateCaptionText())
            overlay.includesEndingInfoCard = true
            overlay.endingInfoCardTheme = .treasureMap
            musicTrackID = "travel-joy"
        case .life:
            defaultDuration = 2
            defaultVideoSegmentMode = .multiple
            setSimilarPhotoRepresentativeInterval(3)
            overlay = .dateCaptionPreset(text: Self.movieDateCaptionText())
            musicTrackID = nil
        }

        textOverlaySettings = overlay
        backgroundMusicSettings = musicTrackID.flatMap { trackID in
            BackgroundMusicSettings.sampleTracks
                .first { $0.id == trackID }?
                .settings
        } ?? .empty
    }

    func startQuickMovieIfNeeded() {
        guard isQuickModeProject,
              !renderableClips.isEmpty,
              !isExporting
        else { return }
        isQuickDurationPickerPresented = true
    }

    func confirmQuickMovieDuration(_ targetDuration: Double?) {
        guard isQuickModeProject,
              !renderableClips.isEmpty,
              !isExporting
        else { return }
        isQuickDurationPickerPresented = false
        if let targetDuration {
            let sourceMediaCount = max(
                1,
                clips.filter { !$0.isVideoSegmentChild }.count
            )
            defaultDuration = max(
                0.1,
                targetDuration / Double(sourceMediaCount)
            )
            applyDefaultDurationToAll()
        }
        isQuickModeProject = false
        saveProjectAndOpenPreview()
    }

    func cancelQuickMovieDurationSelection() {
        isQuickDurationPickerPresented = false
        isQuickModeProject = false
        reset()
    }

    func refreshPresetCaptionAfterMediaImport() async {
        guard activeMoviePreset == .travel else { return }

        let dateText: String
        if selectedSourceMediaCount <= 1 {
            dateText = WatermarkSettings.dateRangeCaptionText(
                from: Date(),
                to: Date()
            )
        } else if let range = selectedMediaDateRange {
            dateText = WatermarkSettings.dateRangeCaptionText(
                from: range.lowerBound,
                to: range.upperBound
            )
        } else {
            dateText = WatermarkSettings.dateRangeCaptionText(
                from: Date(),
                to: Date()
            )
        }

        struct LocationCluster {
            let location: CLLocation
            var count: Int
            let order: Int
        }
        var clusters: [LocationCluster] = []
        for (order, sample) in allPhotoLocationSamples(
            in: renderableClips
        ).enumerated() {
            if let index = clusters.firstIndex(where: {
                $0.location.distance(from: sample.location) < 10_000
            }) {
                clusters[index].count += 1
            } else {
                clusters.append(
                    LocationCluster(
                        location: sample.location,
                        count: 1,
                        order: order
                    )
                )
            }
        }

        var cityCounts: [String: (count: Int, order: Int)] = [:]
        for cluster in clusters.sorted(by: {
            $0.count == $1.count
                ? $0.order < $1.order
                : $0.count > $1.count
        }).prefix(12) {
            guard let place = await MovieCollectionStore.shared
                .resolvedPlace(for: cluster.location)
            else { continue }
            let city = place.cityName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !city.isEmpty else { continue }
            let current = cityCounts[city]
            cityCounts[city] = (
                (current?.count ?? 0) + cluster.count,
                min(current?.order ?? cluster.order, cluster.order)
            )
        }

        let mainCities = cityCounts.sorted {
            $0.value.count == $1.value.count
                ? $0.value.order < $1.value.order
                : $0.value.count > $1.value.count
        }
        .prefix(2)
        .map(\.key)

        guard activeMoviePreset == .travel else { return }
        textOverlaySettings.text = mainCities.isEmpty
            ? dateText
            : dateText + "\n" + mainCities.joined(separator: " · ")
        textOverlaySettings.isEnabled = true
    }

    private static func movieDateCaptionText(for date: Date = Date()) -> String {
        WatermarkSettings.dateCaptionText(for: date)
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
        if activeMoviePreset == .travel || activeMoviePreset == .life {
            let newIDSet = Set(newClipIDs)
            for index in updatedClips.indices
                where newIDSet.contains(updatedClips[index].id)
                    && updatedClips[index].isLivePhoto {
                let sourceDuration = updatedClips[index].sourceDuration
                    ?? updatedClips[index].livePhotoDuration
                    ?? updatedClips[index].duration
                let selectedDuration = min(defaultDuration, sourceDuration)
                updatedClips[index].livePhotoMode = .motion
                updatedClips[index].sourceDuration = sourceDuration
                updatedClips[index].livePhotoDuration = sourceDuration
                updatedClips[index].duration = selectedDuration
                updatedClips[index].photoDuration = selectedDuration
                updatedClips[index].trimStart = max(
                    0,
                    (sourceDuration - selectedDuration) / 2
                )
            }
        }
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
        isPickerPresented = false
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

                var compositionItems = savedProject.clips.filter(
                    \.isRenderableClip
                )
                let shootingRange = selectedMediaDateRange
                let endingInfoPackage = textOverlaySettings
                    .includesEndingInfoCard
                    ? await makeEndingInfoPackage(
                        for: compositionItems,
                        shootingRange: shootingRange,
                        renderSize: outputRenderSize,
                        settings: textOverlaySettings
                    )
                    : nil
                if let endingInfoPackage {
                    compositionItems.append(
                        ClipItem(
                            source: .imageFile(
                                endingInfoPackage.temporaryImageURL
                            ),
                            thumbnail: endingInfoPackage.image,
                            duration: textOverlaySettings
                                .endingInfoCardDuration,
                            photoDuration: textOverlaySettings
                                .endingInfoCardDuration,
                            mediaKind: .photo,
                            sourceCreatedAt: shootingRange?.upperBound,
                            sourcePixelSize: outputRenderSize
                        )
                    )
                }
                defer {
                    if let endingInfoPackage {
                        try? FileManager.default.removeItem(
                            at: endingInfoPackage.temporaryImageURL
                        )
                    }
                }
                let sourceLocation = endingInfoPackage?.sourceLocation
                    ?? firstPhotoLocation(in: compositionItems)
                let routeLocationNames = endingInfoPackage?.preview.stops
                    .map(\.label)
                let sourceLocationName: String?
                if let routeLocationNames, !routeLocationNames.isEmpty {
                    sourceLocationName = routeLocationNames.joined(
                        separator: " → "
                    )
                } else {
                    sourceLocationName = await MovieCollectionStore.shared
                        .resolvedLocationName(for: sourceLocation)
                }
                let movieMetadata = HanClipMovieMetadata(
                    shootingStartAt: shootingRange?.lowerBound,
                    shootingEndAt: shootingRange?.upperBound,
                    latitude: sourceLocation?.coordinate.latitude,
                    longitude: sourceLocation?.coordinate.longitude,
                    locationName: sourceLocationName,
                    routeLocationNames: routeLocationNames
                )
                var renderWatermarkSettings = textOverlaySettings
                renderWatermarkSettings.includesEndingInfoCard =
                    endingInfoPackage != nil
                previewProgress = 0.10
                progressMessage = "시사회 영화를 준비하는 중…"
                let output = try await VideoComposer().compose(
                    items: compositionItems,
                    renderSize: outputRenderSize,
                    watermarkSettings: renderWatermarkSettings
                        .withCopyrightSettings(
                            CopyrightPurchaseManager.shared.isPurchased
                                ? WatermarkSettings.stored()
                                : WatermarkSettings.stored()
                                    .withLogoEnabled(false)
                    ),
                    backgroundMusicSettings: backgroundMusicSettings,
                    movieMetadata: movieMetadata
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
                let collectionTitle = savedProjects.first {
                    $0.id == savedID
                }?.memo.trimmingCharacters(in: .whitespacesAndNewlines)
                let automaticCollectionTitle = collectionTitle?.isEmpty == false
                    ? collectionTitle
                    : nil
                releaseEditingMemory()
                isProjectOpen = false
                previewProgress = 1
                progressMessage = ""
                isExporting = false
                isPreviewRendering = false
                previewThumbnail = nil
                previewTask = nil
                showPreview = true
                Task { @MainActor in
                    try? await MovieCollectionStore.shared.importMovie(
                        from: storedOutput,
                        title: automaticCollectionTitle,
                        madeAt: Date(),
                        shootingRange: shootingRange,
                        location: sourceLocation,
                        locationName: sourceLocationName
                    )
                }
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

    private func firstPhotoLocation(in items: [ClipItem]) -> CLLocation? {
        orderedPhotoLocations(in: items).first
    }

    private func orderedPhotoLocations(in items: [ClipItem]) -> [CLLocation] {
        orderedPhotoLocationSamples(in: items).map(\.location)
    }

    private func orderedPhotoLocationSamples(
        in items: [ClipItem]
    ) -> [LocatedMediaSample] {
        var result: [LocatedMediaSample] = []
        for sample in allPhotoLocationSamples(in: items) {
            if let previous = result.last,
               previous.location.distance(from: sample.location) < 5_000,
               Self.isSameEndingInfoDay(previous.date, sample.date) {
                continue
            }
            result.append(sample)
        }
        return result
    }

    private func allPhotoLocationSamples(
        in items: [ClipItem]
    ) -> [LocatedMediaSample] {
        let identifiers = items.compactMap { item -> String? in
            guard case .photoAsset(let identifier) = item.source else {
                return nil
            }
            return identifier
        }
        var locationsByIdentifier: [String: CLLocation] = [:]
        if !identifiers.isEmpty {
            let assets = PHAsset.fetchAssets(
                withLocalIdentifiers: Array(Set(identifiers)),
                options: nil
            )
            assets.enumerateObjects { asset, _, _ in
                if let location = asset.location {
                    locationsByIdentifier[asset.localIdentifier] = location
                }
            }
        }

        var result: [LocatedMediaSample] = []
        for item in items {
            let location: CLLocation?
            switch item.source {
            case .photoAsset(let identifier):
                location = locationsByIdentifier[identifier]
            case .imageFile(let url):
                location = Self.imageLocation(at: url)
            case .livePhotoFiles(let imageURL, _):
                location = Self.imageLocation(at: imageURL)
            case .videoFile:
                location = nil
            }
            guard let location else { continue }
            let sample = LocatedMediaSample(
                location: location,
                date: item.sourceCreatedAt
            )
            result.append(sample)
        }
        return result
    }

    private static func isSameEndingInfoDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            Calendar.current.isDate(lhs, inSameDayAs: rhs)
        case (nil, nil):
            true
        default:
            false
        }
    }

    private static func imageLocation(at url: URL) -> CLLocation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
              ) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary]
                as? [CFString: Any],
              let latitudeNumber = gps[kCGImagePropertyGPSLatitude]
                as? NSNumber,
              let longitudeNumber = gps[kCGImagePropertyGPSLongitude]
                as? NSNumber
        else { return nil }
        let rawLatitude = latitudeNumber.doubleValue
        let rawLongitude = longitudeNumber.doubleValue
        let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String
        let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
        let latitude = latitudeRef == "S" ? -rawLatitude : rawLatitude
        let longitude = longitudeRef == "W" ? -rawLongitude : rawLongitude
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    private func makeEndingInfoPreview(
        for items: [ClipItem],
        shootingRange: ClosedRange<Date>?
    ) async -> EndingInfoPreviewData? {
        guard let shootingRange else { return nil }
        let samples = orderedPhotoLocationSamples(in: items)
        guard !samples.isEmpty else { return nil }

        var stops: [EndingInfoRouteStop] = []
        var previousCountryCode: String?
        var previousCityName: String?
        var previousDate: Date?
        for sample in samples {
            try? Task.checkCancellation()
            guard let place = await MovieCollectionStore.shared
                .resolvedPlace(for: sample.location) else { continue }
            let date = sample.date ?? shootingRange.lowerBound
            if previousCountryCode == place.countryCode,
               previousCityName == place.cityName,
               Self.isSameEndingInfoDay(previousDate, date) {
                continue
            }
            let countryChanged = previousCountryCode != place.countryCode
            let label: String
            if place.countryCode == "KR" {
                label = place.cityName
            } else if countryChanged {
                label = "\(place.countryName) \(place.cityName)"
            } else {
                label = place.cityName
            }
            stops.append(
                EndingInfoRouteStop(
                    countryCode: place.countryCode,
                    label: label,
                    dateText: Self.endingInfoStopDateText(date)
                )
            )
            previousCountryCode = place.countryCode
            previousCityName = place.cityName
            previousDate = date
        }
        guard !stops.isEmpty else { return nil }
        return EndingInfoPreviewData(
            dateText: Self.endingInfoDateText(shootingRange),
            stops: stops
        )
    }

    private func makeEndingInfoPackage(
        for items: [ClipItem],
        shootingRange: ClosedRange<Date>?,
        renderSize: CGSize,
        settings: WatermarkSettings
    ) async -> EndingInfoPackage? {
        guard let preview = await makeEndingInfoPreview(
            for: items,
            shootingRange: shootingRange
        ), let sourceLocation = orderedPhotoLocations(in: items).first else {
            return nil
        }
        let image = Self.renderEndingInfoCard(
            preview,
            backgroundImage: items.first?.thumbnail,
            size: renderSize,
            settings: settings
        )
        guard let data = image.jpegData(compressionQuality: 0.94) else {
            return nil
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HanClip-EndingInfo-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        do {
            try data.write(to: url, options: .atomic)
            return EndingInfoPackage(
                preview: preview,
                sourceLocation: sourceLocation,
                temporaryImageURL: url,
                image: image
            )
        } catch {
            return nil
        }
    }

    private static func endingInfoDateText(
        _ range: ClosedRange<Date>
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy. M. d."
        if Calendar.current.isDate(
            range.lowerBound,
            inSameDayAs: range.upperBound
        ) {
            return formatter.string(from: range.lowerBound)
        }
        return "\(formatter.string(from: range.lowerBound))  –  \(formatter.string(from: range.upperBound))"
    }

    private static func endingInfoStopDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M. d."
        return formatter.string(from: date)
    }

    private static func renderEndingInfoCard(
        _ data: EndingInfoPreviewData,
        backgroundImage: UIImage?,
        size: CGSize,
        settings: WatermarkSettings
    ) -> UIImage {
        let safeSize = CGSize(width: max(2, size.width), height: max(2, size.height))
        let captionTextColor = Self.endingInfoUIColor(
            hexString: settings.textColorHex
        )
            ?? HanClipTheme.primaryUIColor
        let captionShadowColor = Self.endingInfoUIColor(
            hexString: settings.shadowColorHex
        )
            ?? HanClipTheme.secondaryUIColor
        let backgroundColors: [UIColor]
        let panelColor: UIColor
        let textColor: UIColor
        let accentColor: UIColor
        let secondaryColor: UIColor
        let showsBackgroundImage: Bool
        let titleFontName: String?
        switch settings.endingInfoCardTheme {
        case .caption:
            backgroundColors = [
                UIColor.black.withAlphaComponent(0.56),
                captionShadowColor.withAlphaComponent(0.48)
            ]
            panelColor = UIColor(HanClipTheme.background)
                .withAlphaComponent(0.38)
            textColor = captionTextColor
            accentColor = captionTextColor
            secondaryColor = captionShadowColor
            showsBackgroundImage = true
            titleFontName = settings.fontName
        case .itinerary:
            backgroundColors = [
                UIColor(red: 0.99, green: 0.96, blue: 0.94, alpha: 1),
                UIColor(red: 1.00, green: 0.99, blue: 0.98, alpha: 1)
            ]
            panelColor = UIColor.white.withAlphaComponent(0.96)
            textColor = UIColor(red: 0.22, green: 0.20, blue: 0.21, alpha: 1)
            accentColor = UIColor(red: 0.84, green: 0.28, blue: 0.38, alpha: 1)
            secondaryColor = UIColor(red: 0.94, green: 0.55, blue: 0.49, alpha: 1)
            showsBackgroundImage = false
            titleFontName = nil
        case .landmark:
            backgroundColors = [
                UIColor(red: 0.96, green: 0.90, blue: 0.87, alpha: 1),
                UIColor(red: 1.00, green: 0.98, blue: 0.94, alpha: 1)
            ]
            panelColor = UIColor(red: 1.00, green: 0.97, blue: 0.92, alpha: 0.97)
            textColor = UIColor(red: 0.27, green: 0.19, blue: 0.17, alpha: 1)
            accentColor = UIColor(red: 0.56, green: 0.29, blue: 0.28, alpha: 1)
            secondaryColor = UIColor(red: 0.69, green: 0.48, blue: 0.42, alpha: 1)
            showsBackgroundImage = false
            titleFontName = "maruburi"
        case .office:
            backgroundColors = [
                UIColor(red: 0.95, green: 0.95, blue: 0.92, alpha: 1),
                .white
            ]
            panelColor = UIColor.white.withAlphaComponent(0.90)
            textColor = UIColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1)
            accentColor = UIColor(red: 0.13, green: 0.24, blue: 0.40, alpha: 1)
            secondaryColor = UIColor(red: 0.43, green: 0.48, blue: 0.54, alpha: 1)
            showsBackgroundImage = false
            titleFontName = nil
        case .treasureMap:
            backgroundColors = [
                UIColor(red: 0.48, green: 0.29, blue: 0.12, alpha: 1),
                UIColor(red: 0.91, green: 0.76, blue: 0.48, alpha: 1)
            ]
            panelColor = UIColor(red: 0.95, green: 0.84, blue: 0.61, alpha: 0.92)
            textColor = UIColor(red: 0.24, green: 0.12, blue: 0.055, alpha: 1)
            accentColor = UIColor(red: 0.48, green: 0.18, blue: 0.06, alpha: 1)
            secondaryColor = UIColor(red: 0.38, green: 0.25, blue: 0.12, alpha: 1)
            showsBackgroundImage = false
            titleFontName = "gowun_batang"
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: safeSize, format: format).image {
            context in
            let bounds = CGRect(origin: .zero, size: safeSize)
            let cg = context.cgContext
            backgroundColors[0].setFill()
            cg.fill(bounds)

            if showsBackgroundImage, let backgroundImage {
                let sourceRatio = backgroundImage.size.width
                    / max(1, backgroundImage.size.height)
                let targetRatio = safeSize.width / safeSize.height
                let drawSize: CGSize
                if sourceRatio > targetRatio {
                    drawSize = CGSize(
                        width: safeSize.height * sourceRatio,
                        height: safeSize.height
                    )
                } else {
                    drawSize = CGSize(
                        width: safeSize.width,
                        height: safeSize.width / sourceRatio
                    )
                }
                backgroundImage.draw(
                    in: CGRect(
                        x: (safeSize.width - drawSize.width) / 2,
                        y: (safeSize.height - drawSize.height) / 2,
                        width: drawSize.width,
                        height: drawSize.height
                    ),
                    blendMode: .normal,
                    alpha: settings.endingInfoCardTheme == .caption ? 0.46 : 0.16
                )
            }

            let colors = backgroundColors.map(\.cgColor) as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: safeSize.width, y: safeSize.height),
                    options: []
                )
            }

            let scale = min(safeSize.width, safeSize.height) / 390
            let panelInset = 30 * scale
            let panel = bounds.insetBy(dx: panelInset, dy: panelInset * 1.25)
            let panelPath = UIBezierPath(
                roundedRect: panel,
                cornerRadius: 26 * scale
            )
            panelColor.setFill()
            panelPath.fill()
            secondaryColor.withAlphaComponent(0.62).setStroke()
            panelPath.lineWidth = max(1, 1.2 * scale)
            panelPath.stroke()

            if settings.endingInfoCardTheme == .treasureMap {
                cg.saveGState()
                cg.setStrokeColor(accentColor.withAlphaComponent(0.55).cgColor)
                cg.setLineWidth(max(1, 1.4 * scale))
                cg.setLineDash(phase: 0, lengths: [6 * scale, 5 * scale])
                cg.stroke(panel.insetBy(dx: 12 * scale, dy: 12 * scale))
                cg.restoreGState()
                UIImage(systemName: "safari.fill")?
                    .withTintColor(accentColor, renderingMode: .alwaysOriginal)
                    .draw(
                        in: CGRect(
                            x: panel.maxX - 54 * scale,
                            y: panel.minY + 22 * scale,
                            width: 28 * scale,
                            height: 28 * scale
                        )
                    )
            } else if settings.endingInfoCardTheme == .office {
                cg.setFillColor(accentColor.cgColor)
                cg.fill(
                    CGRect(
                        x: panel.minX,
                        y: panel.minY,
                        width: 7 * scale,
                        height: panel.height
                    )
                )
            }

            if settings.endingInfoCardTheme == .itinerary {
                Self.drawTravelItinerary(
                    data,
                    in: panel,
                    scale: scale,
                    textColor: textColor,
                    accentColor: accentColor,
                    secondaryColor: secondaryColor,
                    context: cg
                )
                return
            }
            if settings.endingInfoCardTheme == .landmark {
                Self.drawLandmarkJourney(
                    data,
                    in: panel,
                    scale: scale,
                    textColor: textColor,
                    accentColor: accentColor,
                    secondaryColor: secondaryColor,
                    context: cg
                )
                return
            }
            if settings.endingInfoCardTheme == .office {
                Self.drawOfficeReport(
                    data,
                    in: panel,
                    scale: scale,
                    textColor: textColor,
                    accentColor: accentColor,
                    secondaryColor: secondaryColor,
                    context: cg
                )
                return
            }

            let captionShadow: NSShadow? = {
                guard settings.endingInfoCardTheme == .caption else {
                    return nil
                }
                let shadow = NSShadow()
                shadow.shadowColor = captionShadowColor.withAlphaComponent(
                    CGFloat(settings.shadowOpacity)
                )
                shadow.shadowBlurRadius = 6 * scale
                shadow.shadowOffset = CGSize(width: 1.5 * scale, height: 2 * scale)
                return shadow
            }()

            let titleFont = titleFontName.map {
                FontRegistry.resolvedUIFont(for: $0, size: 17 * scale)
            } ?? UIFont.systemFont(ofSize: 17 * scale, weight: .semibold)
            let title = "여행 기록" as NSString
            title.draw(
                at: CGPoint(x: panel.minX + 24 * scale, y: panel.minY + 25 * scale),
                withAttributes: [
                    .font: titleFont,
                    .foregroundColor: settings.endingInfoCardTheme == .caption
                        ? accentColor
                        : secondaryColor.withAlphaComponent(0.82),
                    .shadow: captionShadow ?? NSShadow()
                ]
            )

            let dateParagraph = NSMutableParagraphStyle()
            dateParagraph.alignment = .center
            (data.dateText as NSString).draw(
                in: CGRect(
                    x: panel.minX + 24 * scale,
                    y: panel.minY
                        + (settings.endingInfoCardTheme == .office ? 88 : 65)
                        * scale,
                    width: panel.width - 48 * scale,
                    height: 48 * scale
                ),
                withAttributes: [
                    .font: titleFontName.map {
                        FontRegistry.resolvedUIFont(for: $0, size: 24 * scale)
                    } ?? UIFont.systemFont(ofSize: 24 * scale, weight: .bold),
                    .foregroundColor: accentColor,
                    .paragraphStyle: dateParagraph,
                    .shadow: captionShadow ?? NSShadow()
                ]
            )

            let routeRect = CGRect(
                x: panel.minX + 32 * scale,
                y: panel.minY
                    + (settings.endingInfoCardTheme == .office ? 154 : 126)
                    * scale,
                width: panel.width - 64 * scale,
                height: panel.height
                    - (settings.endingInfoCardTheme == .office ? 190 : 170)
                    * scale
            )
            if settings.endingInfoCardTheme == .treasureMap {
                Self.drawTreasureMapRoute(
                    data.stops,
                    in: routeRect,
                    scale: scale,
                    variation: settings.endingInfoCardVariation,
                    textColor: textColor,
                    accentColor: accentColor,
                    secondaryColor: secondaryColor,
                    context: cg
                )
                return
            }
            let route = NSMutableAttributedString()
            for (index, stop) in data.stops.enumerated() {
                if index > 0 {
                    let previous = data.stops[index - 1]
                    let symbolName = previous.countryCode == stop.countryCode
                        ? "car.fill"
                        : "airplane"
                    let attachment = NSTextAttachment()
                    attachment.image = UIImage(systemName: symbolName)?
                        .withTintColor(
                            secondaryColor,
                            renderingMode: .alwaysOriginal
                        )
                    attachment.bounds = CGRect(
                        x: 0,
                        y: -3 * scale,
                        width: 18 * scale,
                        height: 18 * scale
                    )
                    route.append(NSAttributedString(string: "  "))
                    route.append(NSAttributedString(attachment: attachment))
                    route.append(
                        NSAttributedString(
                            string: "\u{2060}\u{00A0}\u{2060}"
                        )
                    )
                }
                route.append(
                    NSAttributedString(
                        string: Self.unbreakableEndingInfoLabel(stop.label)
                    )
                )
            }

            var routeFontSize = 23 * scale
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = 12 * scale
            while routeFontSize > 5 * scale {
                let routeFont = settings.endingInfoCardTheme == .caption
                    ? FontRegistry.resolvedUIFont(
                        for: settings.fontName,
                        size: routeFontSize
                    )
                    : UIFont.systemFont(
                        ofSize: routeFontSize,
                        weight: .semibold
                    )
                route.addAttributes(
                    [
                        .font: routeFont,
                        .foregroundColor: textColor,
                        .paragraphStyle: paragraph,
                        .shadow: captionShadow ?? NSShadow()
                    ],
                    range: NSRange(location: 0, length: route.length)
                )
                let measured = route.boundingRect(
                    with: routeRect.size,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                let widestLabel = data.stops.enumerated().map { index, stop in
                    let labelWidth = (
                        Self.unbreakableEndingInfoLabel(stop.label) as NSString
                    )
                        .size(withAttributes: [.font: routeFont])
                        .width
                    return labelWidth + (index == 0 ? 0 : 24 * scale)
                }.max() ?? 0
                if measured.height <= routeRect.height,
                   widestLabel <= routeRect.width {
                    break
                }
                routeFontSize -= 1.5 * scale
            }
            route.draw(
                with: routeRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
    }

    private static func endingInfoUIColor(hexString: String) -> UIColor? {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return nil
        }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func unbreakableEndingInfoLabel(_ label: String) -> String {
        let nonBreaking = label.replacingOccurrences(of: " ", with: "\u{00A0}")
        return nonBreaking.map(String.init).joined(separator: "\u{2060}")
    }

    private static func drawOfficeReport(
        _ data: EndingInfoPreviewData,
        in panel: CGRect,
        scale: CGFloat,
        textColor: UIColor,
        accentColor: UIColor,
        secondaryColor: UIColor,
        context: CGContext
    ) {
        let content = panel.insetBy(dx: 24 * scale, dy: 20 * scale)
        context.setFillColor(accentColor.cgColor)
        context.fill(
            CGRect(x: content.minX, y: content.minY, width: 5 * scale, height: 48 * scale)
        )
        Self.drawSingleLineText(
            "여행 기록 보고서",
            in: CGRect(
                x: content.minX + 14 * scale,
                y: content.minY,
                width: content.width * 0.62,
                height: 26 * scale
            ),
            fontSize: 19 * scale,
            minimumFontSize: 10 * scale,
            weight: .bold,
            color: accentColor,
            alignment: .left
        )
        Self.drawSingleLineText(
            "HANCLIP TRAVEL REPORT",
            in: CGRect(
                x: content.minX + 14 * scale,
                y: content.minY + 26 * scale,
                width: content.width * 0.62,
                height: 14 * scale
            ),
            fontSize: 7.5 * scale,
            minimumFontSize: 5 * scale,
            weight: .semibold,
            color: secondaryColor,
            alignment: .left
        )
        let documentNumber = String(
            abs(data.dateText.hashValue) % 100_000
        )
        Self.drawSingleLineText(
            "DOCUMENT  #\(documentNumber)",
            in: CGRect(
                x: content.midX,
                y: content.minY + 4 * scale,
                width: content.width / 2,
                height: 16 * scale
            ),
            fontSize: 7.5 * scale,
            minimumFontSize: 5 * scale,
            weight: .semibold,
            color: secondaryColor,
            alignment: .right
        )
        Self.drawSingleLineText(
            "PERIOD  \(data.dateText)",
            in: CGRect(
                x: content.midX,
                y: content.minY + 23 * scale,
                width: content.width / 2,
                height: 16 * scale
            ),
            fontSize: 8 * scale,
            minimumFontSize: 5 * scale,
            weight: .bold,
            color: textColor,
            alignment: .right
        )

        let summaryY = content.minY + 58 * scale
        context.setFillColor(accentColor.withAlphaComponent(0.08).cgColor)
        context.fill(
            CGRect(x: content.minX, y: summaryY, width: content.width, height: 30 * scale)
        )
        Self.drawSingleLineText(
            "방문 지역  \(data.stops.count)곳",
            in: CGRect(
                x: content.minX + 10 * scale,
                y: summaryY + 7 * scale,
                width: content.width * 0.45,
                height: 16 * scale
            ),
            fontSize: 9 * scale,
            minimumFontSize: 6 * scale,
            weight: .bold,
            color: accentColor,
            alignment: .left
        )
        Self.drawSingleLineText(
            "작성  HANCLIP",
            in: CGRect(
                x: content.midX,
                y: summaryY + 7 * scale,
                width: content.width / 2 - 10 * scale,
                height: 16 * scale
            ),
            fontSize: 8 * scale,
            minimumFontSize: 5 * scale,
            weight: .medium,
            color: secondaryColor,
            alignment: .right
        )

        let tableY = summaryY + 42 * scale
        let tableHeight = max(40 * scale, content.maxY - tableY)
        let headerHeight = min(22 * scale, tableHeight * 0.13)
        let numberWidth = content.width * 0.10
        let dateWidth = content.width * 0.22
        let transferWidth = content.width * 0.18
        let columns = [
            content.minX,
            content.minX + numberWidth,
            content.minX + numberWidth + dateWidth,
            content.maxX - transferWidth,
            content.maxX
        ]
        context.setFillColor(accentColor.cgColor)
        context.fill(
            CGRect(x: content.minX, y: tableY, width: content.width, height: headerHeight)
        )
        let headers = ["NO.", "DATE", "REGION", "MOVE"]
        for index in headers.indices {
            Self.drawSingleLineText(
                headers[index],
                in: CGRect(
                    x: columns[index] + 3 * scale,
                    y: tableY + 4 * scale,
                    width: columns[index + 1] - columns[index] - 6 * scale,
                    height: headerHeight - 6 * scale
                ),
                fontSize: 7.5 * scale,
                minimumFontSize: 5 * scale,
                weight: .bold,
                color: .white,
                alignment: index == 2 ? .left : .center
            )
        }

        let stops = data.stops
        let rowHeight = (tableHeight - headerHeight) / CGFloat(max(1, stops.count))
        for (index, stop) in stops.enumerated() {
            let y = tableY + headerHeight + CGFloat(index) * rowHeight
            if index.isMultiple(of: 2) {
                context.setFillColor(secondaryColor.withAlphaComponent(0.07).cgColor)
                context.fill(CGRect(x: content.minX, y: y, width: content.width, height: rowHeight))
            }
            context.setStrokeColor(secondaryColor.withAlphaComponent(0.22).cgColor)
            context.setLineWidth(max(0.5, 0.7 * scale))
            context.stroke(
                CGRect(x: content.minX, y: y, width: content.width, height: rowHeight)
            )
            let values = [
                String(format: "%02d", index + 1),
                stop.dateText,
                stop.label,
                index == 0
                    ? "시작"
                    : (stops[index - 1].countryCode == stop.countryCode ? "차량" : "항공")
            ]
            for column in values.indices {
                Self.drawSingleLineText(
                    values[column],
                    in: CGRect(
                        x: columns[column] + 4 * scale,
                        y: y + rowHeight * 0.28,
                        width: columns[column + 1] - columns[column] - 8 * scale,
                        height: rowHeight * 0.50
                    ),
                    fontSize: min(9.5 * scale, rowHeight * 0.32),
                    minimumFontSize: min(4.8 * scale, rowHeight * 0.22),
                    weight: column == 2 ? .semibold : .medium,
                    color: column == 2 ? textColor : secondaryColor,
                    alignment: column == 2 ? .left : .center
                )
            }
        }
    }

    private static func drawTravelItinerary(
        _ data: EndingInfoPreviewData,
        in panel: CGRect,
        scale: CGFloat,
        textColor: UIColor,
        accentColor: UIColor,
        secondaryColor: UIColor,
        context: CGContext
    ) {
        let headerHeight = min(panel.height * 0.23, 92 * scale)
        let headerRect = CGRect(
            x: panel.minX,
            y: panel.minY,
            width: panel.width,
            height: headerHeight
        )
        context.setFillColor(
            UIColor(red: 0.99, green: 0.91, blue: 0.90, alpha: 1).cgColor
        )
        context.fill(headerRect)

        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineBreakMode = .byClipping
        ("여행 일정표" as NSString).draw(
            in: CGRect(
                x: panel.minX + 16 * scale,
                y: panel.minY + 14 * scale,
                width: panel.width - 32 * scale,
                height: 32 * scale
            ),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 23 * scale, weight: .bold),
                .foregroundColor: accentColor,
                .paragraphStyle: centered
            ]
        )
        ("TRAVEL SCHEDULE" as NSString).draw(
            in: CGRect(
                x: panel.minX + 16 * scale,
                y: panel.minY + 42 * scale,
                width: panel.width - 32 * scale,
                height: 16 * scale
            ),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 7.5 * scale, weight: .semibold),
                .foregroundColor: secondaryColor,
                .kern: 2.2 * scale,
                .paragraphStyle: centered
            ]
        )
        Self.drawSingleLineText(
            data.dateText,
            in: CGRect(
                x: panel.minX + 18 * scale,
                y: panel.minY + 61 * scale,
                width: panel.width - 36 * scale,
                height: 20 * scale
            ),
            fontSize: 10.5 * scale,
            minimumFontSize: 6.5 * scale,
            weight: .medium,
            color: textColor.withAlphaComponent(0.72),
            alignment: .center
        )

        let stops = data.stops
        guard !stops.isEmpty else { return }
        let routeRect = CGRect(
            x: panel.minX + 28 * scale,
            y: headerRect.maxY + 18 * scale,
            width: panel.width - 56 * scale,
            height: panel.maxY - headerRect.maxY - 40 * scale
        )
        let wide = routeRect.width > routeRect.height * 1.15
        let columnCount = min(stops.count, wide ? 5 : 3)
        let rowCount = Int(ceil(Double(stops.count) / Double(max(1, columnCount))))
        let columnWidth = routeRect.width / CGFloat(max(1, columnCount))
        let rowHeight = routeRect.height / CGFloat(max(1, rowCount))

        let points: [CGPoint] = stops.indices.map { index in
            let row = index / columnCount
            let position = index % columnCount
            let column = row.isMultiple(of: 2)
                ? position
                : columnCount - position - 1
            return CGPoint(
                x: routeRect.minX + columnWidth * (CGFloat(column) + 0.5),
                y: routeRect.minY + rowHeight * (CGFloat(row) + 0.45)
            )
        }

        if points.count > 1 {
            context.saveGState()
            context.setStrokeColor(secondaryColor.withAlphaComponent(0.82).cgColor)
            context.setLineWidth(max(5 * scale, min(12 * scale, rowHeight * 0.15)))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let path = UIBezierPath()
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            path.stroke()
            context.restoreGState()
        }

        let badgeWidth = min(38 * scale, columnWidth * 0.62)
        let badgeHeight = min(16 * scale, rowHeight * 0.23)
        let labelHeight = min(25 * scale, rowHeight * 0.32)
        let iconNames = [
            "mappin.and.ellipse", "building.2.fill", "beach.umbrella.fill",
            "fork.knife", "camera.fill", "airplane.departure"
        ]
        for (index, stop) in stops.enumerated() {
            let point = points[index]
            let badge = CGRect(
                x: point.x - badgeWidth / 2,
                y: point.y - badgeHeight / 2,
                width: badgeWidth,
                height: badgeHeight
            )
            let badgePath = UIBezierPath(
                roundedRect: badge,
                cornerRadius: badgeHeight / 2
            )
            accentColor.setFill()
            badgePath.fill()
            Self.drawSingleLineText(
                stop.dateText,
                in: badge,
                fontSize: min(7.5 * scale, badgeHeight * 0.48),
                minimumFontSize: 5 * scale,
                weight: .bold,
                color: .white,
                alignment: .center
            )

            let iconSide = min(18 * scale, rowHeight * 0.23)
            UIImage(systemName: iconNames[index % iconNames.count])?
                .withTintColor(textColor.withAlphaComponent(0.78), renderingMode: .alwaysOriginal)
                .draw(
                    in: CGRect(
                        x: point.x - iconSide / 2,
                        y: badge.minY - iconSide - 4 * scale,
                        width: iconSide,
                        height: iconSide
                    )
                )

            Self.drawSingleLineText(
                stop.label,
                in: CGRect(
                    x: point.x - columnWidth * 0.47,
                    y: badge.maxY + 3 * scale,
                    width: columnWidth * 0.94,
                    height: labelHeight
                ),
                fontSize: min(11 * scale, labelHeight * 0.55),
                minimumFontSize: 5.5 * scale,
                weight: .semibold,
                color: textColor,
                alignment: .center
            )

            if index > 0,
               stops[index - 1].countryCode != stop.countryCode {
                let previous = points[index - 1]
                let midpoint = CGPoint(
                    x: (previous.x + point.x) / 2,
                    y: (previous.y + point.y) / 2
                )
                let side = min(14 * scale, rowHeight * 0.19)
                UIImage(systemName: "airplane")?
                    .withTintColor(accentColor, renderingMode: .alwaysOriginal)
                    .draw(
                        in: CGRect(
                            x: midpoint.x - side / 2,
                            y: midpoint.y - side / 2,
                            width: side,
                            height: side
                        )
                    )
            }
        }
    }

    private static func drawLandmarkJourney(
        _ data: EndingInfoPreviewData,
        in panel: CGRect,
        scale: CGFloat,
        textColor: UIColor,
        accentColor: UIColor,
        secondaryColor: UIColor,
        context: CGContext
    ) {
        let border = panel.insetBy(dx: 10 * scale, dy: 10 * scale)
        let borderPath = UIBezierPath(
            roundedRect: border,
            cornerRadius: 18 * scale
        )
        secondaryColor.withAlphaComponent(0.62).setStroke()
        borderPath.lineWidth = max(1, 1.4 * scale)
        borderPath.stroke()

        let stops = data.stops
        guard !stops.isEmpty else { return }
        let first = stops.first?.label ?? "여행"
        let last = stops.last?.label ?? first
        let title = first == last
            ? "\(first) 여행"
            : "\(first) · \(last) 여행"
        Self.drawSingleLineText(
            title,
            in: CGRect(
                x: panel.minX + 28 * scale,
                y: panel.minY + 18 * scale,
                width: panel.width - 56 * scale,
                height: 34 * scale
            ),
            fontSize: 23 * scale,
            minimumFontSize: 10 * scale,
            weight: .bold,
            color: accentColor,
            alignment: .center
        )
        Self.drawSingleLineText(
            data.dateText,
            in: CGRect(
                x: panel.minX + 30 * scale,
                y: panel.minY + 49 * scale,
                width: panel.width - 60 * scale,
                height: 18 * scale
            ),
            fontSize: 9.5 * scale,
            minimumFontSize: 6 * scale,
            weight: .medium,
            color: secondaryColor,
            alignment: .center
        )

        let ornamentSide = 18 * scale
        for x in [panel.minX + 24 * scale, panel.maxX - 24 * scale - ornamentSide] {
            UIImage(systemName: "light.beacon.max.fill")?
                .withTintColor(secondaryColor, renderingMode: .alwaysOriginal)
                .draw(
                    in: CGRect(
                        x: x,
                        y: panel.minY + 22 * scale,
                        width: ornamentSide,
                        height: ornamentSide
                    )
                )
        }

        let routeRect = CGRect(
            x: panel.minX + 30 * scale,
            y: panel.minY + 82 * scale,
            width: panel.width - 60 * scale,
            height: panel.height - 112 * scale
        )
        let wide = routeRect.width > routeRect.height * 1.12
        let columnCount = min(stops.count, wide ? 4 : 3)
        let rowCount = Int(ceil(Double(stops.count) / Double(max(1, columnCount))))
        let columnWidth = routeRect.width / CGFloat(max(1, columnCount))
        let rowHeight = routeRect.height / CGFloat(max(1, rowCount))
        let points: [CGPoint] = stops.indices.map { index in
            let row = index / columnCount
            let position = index % columnCount
            let column = row.isMultiple(of: 2)
                ? position
                : columnCount - position - 1
            return CGPoint(
                x: routeRect.minX + columnWidth * (CGFloat(column) + 0.5),
                y: routeRect.minY + rowHeight * (CGFloat(row) + 0.48)
            )
        }

        if points.count > 1 {
            context.saveGState()
            context.setStrokeColor(secondaryColor.withAlphaComponent(0.68).cgColor)
            context.setLineWidth(max(1.3, 2.1 * scale))
            context.setLineCap(.round)
            context.setLineDash(phase: 0, lengths: [4 * scale, 5.5 * scale])
            let path = UIBezierPath()
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            path.stroke()
            context.restoreGState()
        }

        for (index, stop) in stops.enumerated() {
            let point = points[index]
            let landmark = Self.landmarkDescriptor(for: stop.label)
            let iconSide = min(34 * scale, rowHeight * 0.38, columnWidth * 0.42)
            let iconRect = CGRect(
                x: point.x - iconSide / 2,
                y: point.y - iconSide * 0.82,
                width: iconSide,
                height: iconSide
            )
            context.setFillColor(
                UIColor(red: 1, green: 0.97, blue: 0.91, alpha: 0.96).cgColor
            )
            context.fillEllipse(in: iconRect.insetBy(dx: -5 * scale, dy: -5 * scale))
            if let emoji = landmark.emoji {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                (emoji as NSString).draw(
                    in: iconRect,
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: iconSide * 0.78),
                        .paragraphStyle: paragraph
                    ]
                )
            } else {
                UIImage(systemName: landmark.symbol)?
                    .withTintColor(accentColor, renderingMode: .alwaysOriginal)
                    .draw(in: iconRect)
            }

            let labelWidth = columnWidth * 0.92
            Self.drawSingleLineText(
                stop.label,
                in: CGRect(
                    x: point.x - labelWidth / 2,
                    y: iconRect.maxY + 4 * scale,
                    width: labelWidth,
                    height: 17 * scale
                ),
                fontSize: min(10.5 * scale, rowHeight * 0.15),
                minimumFontSize: 5.2 * scale,
                weight: .bold,
                color: textColor,
                alignment: .center
            )
            Self.drawSingleLineText(
                landmark.name,
                in: CGRect(
                    x: point.x - labelWidth / 2,
                    y: iconRect.maxY + 18 * scale,
                    width: labelWidth,
                    height: 15 * scale
                ),
                fontSize: min(7.5 * scale, rowHeight * 0.105),
                minimumFontSize: 4.5 * scale,
                weight: .medium,
                color: secondaryColor,
                alignment: .center
            )

            let markerSide = 9 * scale
            context.setFillColor(accentColor.cgColor)
            context.fillEllipse(
                in: CGRect(
                    x: point.x - markerSide / 2,
                    y: point.y - markerSide / 2,
                    width: markerSide,
                    height: markerSide
                )
            )
        }
    }

    private static func landmarkDescriptor(
        for label: String
    ) -> (symbol: String, name: String, emoji: String?) {
        let value = label.lowercased()
        let matches: [(
            keys: [String], symbol: String, name: String, emoji: String?
        )] = [
            (["서울", "seoul"], "antenna.radiowaves.left.and.right", "남산서울타워", "🗼"),
            (["제주", "jeju"], "mountain.2.fill", "한라산·성산일출봉", "🌋"),
            (["부산", "busan"], "water.waves", "광안대교·해동용궁사", "🌉"),
            (["인천", "incheon"], "airplane", "인천대교·송도", "🌉"),
            (["경주", "gyeongju"], "building.columns.fill", "불국사·첨성대", "🏯"),
            (["전주", "jeonju"], "house.lodge.fill", "전주한옥마을", "🏘️"),
            (["강릉", "gangneung"], "water.waves", "경포대", "🌊"),
            (["속초", "sokcho"], "mountain.2.fill", "설악산", "⛰️"),
            (["수원", "suwon"], "shield.lefthalf.filled", "수원화성", "🏰"),
            (["여수", "yeosu"], "water.waves", "여수해상케이블카", "🚠"),
            (["안동", "andong"], "house.lodge.fill", "하회마을", "🏘️"),
            (["대구", "daegu"], "mountain.2.fill", "팔공산", "⛰️"),
            (["대전", "daejeon"], "atom", "엑스포과학공원", "🔭"),
            (["광주", "gwangju"], "building.columns.fill", "국립아시아문화전당", "🏛️"),
            (["파리", "paris"], "building.columns.fill", "Eiffel Tower", "🗼"),
            (["런던", "london"], "clock.fill", "Big Ben·Tower Bridge", "🕰️"),
            (["뉴욕", "new york"], "person.fill", "Statue of Liberty", "🗽"),
            (["도쿄", "tokyo"], "antenna.radiowaves.left.and.right", "Tokyo Tower·Sensoji", "🗼"),
            (["교토", "kyoto"], "torii.gate", "Fushimi Inari", "⛩️"),
            (["오사카", "osaka"], "building.columns.fill", "Osaka Castle", "🏯"),
            (["나라", "nara"], "leaf.fill", "Todaiji·Nara Park", "🦌"),
            (["삿포로", "sapporo"], "snowflake", "Sapporo Clock Tower", "❄️"),
            (["후쿠오카", "fukuoka"], "building.2.fill", "Fukuoka Tower", "🗼"),
            (["오키나와", "okinawa"], "water.waves", "Shurijo·Blue Cave", "🏝️"),
            (["로마", "rome", "roma"], "building.columns.fill", "Colosseum", "🏛️"),
            (["베네치아", "venice", "venezia"], "ferry.fill", "Grand Canal", "🚤"),
            (["피렌체", "florence", "firenze"], "building.columns.fill", "Florence Cathedral", "⛪"),
            (["바르셀로나", "barcelona"], "building.columns.fill", "Sagrada Familia", "⛪"),
            (["마드리드", "madrid"], "crown.fill", "Royal Palace", "🏰"),
            (["리스본", "lisbon"], "tram.fill", "Belém Tower", "🚋"),
            (["암스테르담", "amsterdam"], "bicycle", "Canals·Windmills", "🚲"),
            (["베를린", "berlin"], "building.columns.fill", "Brandenburg Gate", "🏛️"),
            (["프라하", "prague", "praha"], "clock.fill", "Charles Bridge", "🏰"),
            (["비엔나", "vienna", "wien"], "music.note", "Schönbrunn Palace", "🎼"),
            (["아테네", "athens"], "building.columns.fill", "Acropolis", "🏛️"),
            (["이스탄불", "istanbul"], "moon.stars.fill", "Hagia Sophia", "🕌"),
            (["취리히", "zurich"], "mountain.2.fill", "Lake Zurich·Alps", "🏔️"),
            (["클락", "clark"], "airplane", "Clark International Airport", "✈️"),
            (["마닐라", "manila"], "building.columns.fill", "Intramuros", "🏰"),
            (["세부", "cebu"], "water.waves", "Magellan's Cross", "🏝️"),
            (["보라카이", "boracay"], "beach.umbrella.fill", "White Beach", "🏖️"),
            (["방콕", "bangkok"], "building.columns.fill", "Grand Palace", "🛕"),
            (["푸껫", "phuket"], "water.waves", "Phang Nga Bay", "🏝️"),
            (["치앙마이", "chiang mai"], "building.columns.fill", "Doi Suthep", "🛕"),
            (["싱가포르", "singapore"], "water.waves", "Marina Bay·Merlion", "🌆"),
            (["쿠알라룸푸르", "kuala lumpur"], "building.2.fill", "Petronas Towers", "🏙️"),
            (["발리", "bali"], "water.waves", "Uluwatu·Tanah Lot", "🏝️"),
            (["하노이", "hanoi"], "building.columns.fill", "Hoan Kiem Lake", "🏯"),
            (["호찌민", "ho chi minh", "saigon"], "building.2.fill", "Central Post Office", "🏛️"),
            (["다낭", "da nang", "danang"], "water.waves", "Dragon Bridge", "🐉"),
            (["홍콩", "hong kong"], "building.2.fill", "Victoria Harbour", "🌃"),
            (["타이베이", "taipei"], "building.2.fill", "Taipei 101", "🏙️"),
            (["시드니", "sydney"], "theatermasks.fill", "Sydney Opera House", "🎭"),
            (["멜버른", "melbourne"], "tram.fill", "Flinders Street", "🚋"),
            (["오클랜드", "auckland"], "antenna.radiowaves.left.and.right", "Sky Tower", "🗼"),
            (["로스앤젤레스", "los angeles"], "film.fill", "Hollywood Sign", "🎬"),
            (["샌프란시스코", "san francisco"], "water.waves", "Golden Gate Bridge", "🌉"),
            (["라스베이거스", "las vegas"], "sparkles", "The Strip", "🎰"),
            (["워싱턴", "washington"], "building.columns.fill", "U.S. Capitol", "🏛️"),
            (["시카고", "chicago"], "building.2.fill", "Cloud Gate", "🌆"),
            (["밴쿠버", "vancouver"], "mountain.2.fill", "Canada Place", "🏔️"),
            (["토론토", "toronto"], "antenna.radiowaves.left.and.right", "CN Tower", "🗼"),
            (["리우", "rio de janeiro", "rio"], "figure.arms.open", "Christ the Redeemer", "⛰️"),
            (["칸쿤", "cancun"], "water.waves", "Caribbean Beach", "🏖️"),
            (["두바이", "dubai"], "building.2.fill", "Burj Khalifa", "🏙️"),
            (["아부다비", "abu dhabi"], "moon.stars.fill", "Sheikh Zayed Mosque", "🕌"),
            (["카이로", "cairo"], "triangle.fill", "Pyramids of Giza", "🔺")
        ]
        if let match = matches.first(where: { item in
            item.keys.contains(where: value.contains)
        }) {
            return (match.symbol, match.name, match.emoji)
        }
        return ("building.2.fill", "Local Landmark", "📍")
    }

    private static func drawSingleLineText(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        minimumFontSize: CGFloat,
        weight: UIFont.Weight,
        color: UIColor,
        alignment: NSTextAlignment,
        fontName: String? = nil
    ) {
        let value = text.replacingOccurrences(of: " ", with: "\u{00A0}") as NSString
        var size = fontSize
        var font = fontName.map {
            FontRegistry.resolvedUIFont(for: $0, size: size, weight: weight)
        } ?? UIFont.systemFont(ofSize: size, weight: weight)
        while size > minimumFontSize,
              value.size(withAttributes: [.font: font]).width > rect.width {
            size -= max(0.5, fontSize * 0.04)
            font = fontName.map {
                FontRegistry.resolvedUIFont(for: $0, size: size, weight: weight)
            } ?? UIFont.systemFont(ofSize: size, weight: weight)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        value.draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static func drawTreasureMapRoute(
        _ stops: [EndingInfoRouteStop],
        in rect: CGRect,
        scale: CGFloat,
        variation: Int,
        textColor: UIColor,
        accentColor: UIColor,
        secondaryColor: UIColor,
        context: CGContext
    ) {
        guard !stops.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let count = stops.count
        let usableHeight = rect.height * 0.78
        let top = rect.minY + rect.height * 0.10
        let points: [CGPoint] = stops.indices.map { index in
            let progress = count == 1
                ? 0.5
                : CGFloat(index) / CGFloat(count - 1)
            let phase = CGFloat(variation % 9) * 0.42
            let direction: CGFloat = variation.isMultiple(of: 2) ? 1 : -1
            let wave = sin(progress * .pi * 2.4 - .pi / 2 + phase)
            return CGPoint(
                x: rect.midX + wave * rect.width * 0.28 * direction,
                y: top + progress * usableHeight
            )
        }

        if points.count > 1 {
            context.saveGState()
            context.setStrokeColor(secondaryColor.withAlphaComponent(0.82).cgColor)
            context.setLineWidth(max(1.4, 2.2 * scale))
            context.setLineCap(.round)
            context.setLineDash(
                phase: 0,
                lengths: [4.5 * scale, 6.5 * scale]
            )
            for index in 0..<(points.count - 1) {
                let start = points[index]
                let end = points[index + 1]
                let vertical = (end.y - start.y) * 0.50
                let path = UIBezierPath()
                path.move(to: start)
                path.addCurve(
                    to: end,
                    controlPoint1: CGPoint(x: start.x, y: start.y + vertical),
                    controlPoint2: CGPoint(x: end.x, y: end.y - vertical)
                )
                path.stroke()

                let midpoint = CGPoint(
                    x: (start.x + end.x) / 2,
                    y: (start.y + end.y) / 2
                )
                let symbolName = stops[index].countryCode
                    == stops[index + 1].countryCode
                    ? "car.fill"
                    : "airplane"
                let symbolSize = 14 * scale
                UIImage(systemName: symbolName)?
                    .withTintColor(accentColor, renderingMode: .alwaysOriginal)
                    .draw(
                        in: CGRect(
                            x: midpoint.x - symbolSize / 2,
                            y: midpoint.y - symbolSize / 2,
                            width: symbolSize,
                            height: symbolSize
                        )
                    )
            }
            context.restoreGState()
        }

        let fontSize = max(8 * scale, min(15 * scale, 34 * scale / sqrt(CGFloat(count))))
        for (index, stop) in stops.enumerated() {
            let point = points[index]
            let markerSize = index == 0 ? 18 * scale : 11 * scale
            if index == 0 {
                let xFont = UIFont.systemFont(
                    ofSize: markerSize,
                    weight: .black
                )
                ("×" as NSString).draw(
                    at: CGPoint(
                        x: point.x - markerSize * 0.36,
                        y: point.y - markerSize * 0.68
                    ),
                    withAttributes: [
                        .font: xFont,
                        .foregroundColor: accentColor
                    ]
                )
            } else {
                context.setFillColor(accentColor.cgColor)
                context.fillEllipse(
                    in: CGRect(
                        x: point.x - markerSize / 2,
                        y: point.y - markerSize / 2,
                        width: markerSize,
                        height: markerSize
                    )
                )
                context.setFillColor(panelColorForTreasureMarker.cgColor)
                context.fillEllipse(
                    in: CGRect(
                        x: point.x - markerSize * 0.20,
                        y: point.y - markerSize * 0.20,
                        width: markerSize * 0.40,
                        height: markerSize * 0.40
                    )
                )
            }

            let labelWidth = rect.width * 0.45
            let prefersRight = point.x <= rect.midX
            let labelX = prefersRight
                ? min(rect.maxX - labelWidth, point.x + 9 * scale)
                : max(rect.minX, point.x - labelWidth - 9 * scale)
            let labelRect = CGRect(
                x: labelX,
                y: point.y - 11 * scale,
                width: labelWidth,
                height: 28 * scale
            )
            Self.drawSingleLineText(
                stop.label,
                in: labelRect,
                fontSize: fontSize,
                minimumFontSize: max(4.5 * scale, fontSize * 0.55),
                weight: .semibold,
                color: textColor,
                alignment: .center,
                fontName: "maruburi"
            )
        }
    }

    private static var panelColorForTreasureMarker: UIColor {
        UIColor(red: 0.95, green: 0.84, blue: 0.61, alpha: 1)
    }

    func startPhotoLibraryImport() {
        isImportingPhotoLibraryMedia = true
        photoLibraryImportProgress = 0.02
        progressMessage = "선택한 미디어를 불러오는 중…"
    }

    func updatePhotoLibraryImportProgress(
        _ progress: Double,
        message: String
    ) {
        photoLibraryImportProgress = min(max(progress, 0), 1)
        progressMessage = message
    }

    func finishPhotoLibraryImport() {
        photoLibraryImportProgress = 1
        isImportingPhotoLibraryMedia = false
        progressMessage = ""
        photoLibraryImportProgress = 0
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
        isQuickModeProject = false
        activeMoviePreset = nil
        isQuickDurationPickerPresented = false
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
            settings.customCopyrightIconPath,
            "\(settings.includesEndingInfoCard)",
            "\(roundedSignatureValue(settings.endingInfoCardDuration))",
            settings.endingInfoCardTheme.rawValue,
            "\(settings.endingInfoCardVariation)"
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

    func importMediaFromCalendarDates(
        _ dates: Set<Date>,
        excluding excludedAssetIdentifiers: Set<String> = []
    ) {
        guard !dates.isEmpty else { return }
        calendarImportTask?.cancel()
        let selectedDates = Set(
            dates.map { Calendar.current.startOfDay(for: $0) }
        )
        isCalendarPickerPresented = false
        isPickerPresented = false
        isImportingCalendarMedia = true
        calendarImportProgress = 0
        progressMessage = "선택한 날짜의 미디어를 불러오는 중…"

        calendarImportTask = Task {
            let assets = PhotoLibraryService.mediaAssets(
                on: selectedDates,
                calendar: .current
            ).filter {
                !excludedAssetIdentifiers.contains($0.localIdentifier)
            }
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

            await refreshPresetCaptionAfterMediaImport()

            let shouldStartQuickMovie = isQuickModeProject
                && !imported.isEmpty
            if !shouldStartQuickMovie {
                alertMessage = imported.isEmpty
                    ? "선택한 날짜에 가져올 수 있는 미디어가 없습니다."
                    : "선택한 날짜의 미디어 \(imported.count)개를 가져왔습니다."
            }
            calendarImportProgress = 1
            progressMessage = ""
            isImportingCalendarMedia = false
            calendarImportProgress = 0
            calendarImportTask = nil
            if shouldStartQuickMovie {
                startQuickMovieIfNeeded()
            }
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
