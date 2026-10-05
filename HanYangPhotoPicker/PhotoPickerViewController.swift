import UIKit
import UniformTypeIdentifiers
import Photos
import QuickLook

/// 한양(HanAI) 사진 고르기: Photos에서 여러 장을 고른 뒤 이 화면에서 원하는
/// 장수(N)를 정하면, 로컬에서만 품질을 채점해 상위 N장을 미리보기로 보여주고
/// 선택한 원본 사진의 참조를 확보한 뒤 앨범에 정리한다.
/// 기존 사진을 수정·삭제하지 않으며, 네트워크도 쓰지 않는다.
@MainActor
final class PhotoPickerViewController: UIViewController {
    var suppliedExtensionContext: NSExtensionContext?
    private var shareContext: NSExtensionContext? { suppliedExtensionContext ?? extensionContext }
    private struct Candidate {
        let index: Int
        let stagingURL: URL
        let measurement: ImageQualityMeasurement
        let suggestedFilename: String?
    }

    private let pointColor = UIColor(red: 0, green: 118 / 255, blue: 68 / 255, alpha: 1)
    private let secondaryColor = UIColor(red: 41 / 255, green: 171 / 255, blue: 135 / 255, alpha: 1)

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let explainLabel = UILabel()
    private let countStack = UIStackView()
    private let countLabel = UILabel()
    private let countStepper = UIStepper()
    private let startButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let progressLabel = UILabel()
    private let thumbnailsStack = UIStackView()
    private let retryButton = UIButton(type: .system)
    private let changeCountButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)
    private let albumButton = UIButton(type: .system)
    private var albumDestination: HanYangAlbumDestination?
    private let cancelButton = UIButton(type: .system)

    private let batchID = UUID()
    private var batchLease: HanYangBatchLease?
    private var providers: [NSItemProvider] = []
    private var candidates: [Candidate] = []
    private var previewURLs: [URL] = []
    private var previewImageViews: [UIImageView] = []
    private var failedCount = 0
    private var selectedN = 1
    private var recommendedN = 1
    private var hasCustomCount = false
    private var currentTask: Task<Void, Never>?
    private var isCommitted = false
    private var isSaving = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadAttachments()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        loadVisiblePhotoPreviews()
    }

    private func loadVisiblePhotoPreviews() {
        guard !thumbnailsStack.isHidden else { return }
        let visible = scrollView.bounds.insetBy(dx: 0, dy: -scrollView.bounds.height / 2)
        for imageView in previewImageViews {
            let position = imageView.tag
            guard previewURLs.indices.contains(position) else { continue }
            if imageView.convert(imageView.bounds, to: scrollView).intersects(visible) {
                if imageView.image == nil, let image = ImageQualityAnalyzer.downsampledCGImage(
                    at: previewURLs[position], maxPixelSize: 768
                ) { imageView.image = UIImage(cgImage: image) }
            } else { imageView.image = nil }
        }
    }

    // MARK: - Layout

    private func configureView() {
        view.backgroundColor = .systemBackground

        titleLabel.text = "한양 사진 고르기"
        titleLabel.font = .systemFont(ofSize: 24, weight: .black)
        titleLabel.textColor = pointColor

        statusLabel.text = "사진을 불러오는 중입니다."
        statusLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        statusLabel.numberOfLines = 0

        explainLabel.text =
            "선명도, 노출, 해상도를 기준으로 한 장치 내 참고 점수이며, " +
            "선택한 원본 사진을 앨범에 정리합니다. 사진을 복사하거나 삭제하지 않습니다."
        explainLabel.font = .systemFont(ofSize: 13, weight: .regular)
        explainLabel.textColor = .secondaryLabel
        explainLabel.numberOfLines = 0

        countLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        countLabel.numberOfLines = 0
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countStepper.setContentCompressionResistancePriority(.required, for: .horizontal)
        countStepper.minimumValue = 1
        countStepper.value = 1
        countStepper.addTarget(self, action: #selector(countChanged), for: .valueChanged)
        countStack.axis = .horizontal
        countStack.spacing = 12
        countStack.alignment = .center
        countStack.addArrangedSubview(countLabel)
        countStack.addArrangedSubview(countStepper)

        configureButton(
            startButton,
            title: "좋은 사진 고르기",
            background: secondaryColor,
            action: #selector(startAnalysis)
        )
        configureButton(retryButton, title: "실패한 사진 다시 분석", background: pointColor, action: #selector(retryAnalysis))
        configureButton(
            changeCountButton,
            title: "개수 바꾸기",
            background: secondaryColor.withAlphaComponent(0.55),
            action: #selector(backToCountSelection)
        )
        configureButton(
            confirmButton,
            title: "선택한 사진 앨범에 저장",
            background: pointColor,
            action: #selector(saveAlbum)
        )
        configureButton(albumButton, title: "저장할 앨범 선택", background: secondaryColor,
            action: #selector(chooseAlbum))

        cancelButton.setTitle("닫기", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        cancelButton.setTitleColor(pointColor, for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelFlow), for: .touchUpInside)

        progressView.progressTintColor = secondaryColor
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        progressLabel.textColor = secondaryColor

        thumbnailsStack.axis = .vertical
        thumbnailsStack.spacing = 8

        [
            titleLabel, statusLabel, explainLabel, countStack, startButton,
            progressLabel, progressView, thumbnailsStack,
            retryButton, changeCountButton, albumButton, confirmButton, cancelButton
        ].forEach(stack.addArrangedSubview)

        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        let widthConstraint = stack.widthAnchor.constraint(
            lessThanOrEqualToConstant: 640
        )
        widthConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.contentLayoutGuide.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor
            ),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -22),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48).withPriority(998),
            widthConstraint
        ])

        setStage(.configuring)
    }

    private func configureButton(
        _ button: UIButton,
        title: String,
        background: UIColor,
        action: Selector
    ) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = background
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        let height = button.heightAnchor.constraint(equalToConstant: 52)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private enum Stage {
        case configuring, analyzing, result, failed, resolving, saving, saved
    }

    private func setStage(_ stage: Stage) {
        if stage != .result {
            // Hidden stacks receive a zero-height constraint. Remove photo aspect
            // constraints with their views instead of fighting that hidden height.
            thumbnailsStack.arrangedSubviews.forEach {
                thumbnailsStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            previewImageViews = []
        }
        startButton.isHidden = stage != .configuring
        countStack.isHidden = stage != .configuring || candidates.isEmpty
        progressView.isHidden = stage != .analyzing && stage != .resolving
        progressLabel.isHidden = stage != .analyzing && stage != .resolving
        thumbnailsStack.isHidden = stage != .result
        changeCountButton.isHidden = stage != .result
        confirmButton.isHidden = stage != .result
        albumButton.isHidden = stage != .result
        albumButton.isEnabled = stage != .saving
        cancelButton.isEnabled = stage != .saving
        explainLabel.isHidden = stage == .failed
        retryButton.isHidden = !(failedCount > 0 && (stage == .failed || stage == .result))
    }

    // MARK: - Loading

    private func loadAttachments() {
        do {
            batchLease = try HanYangBatchLease(batchID: batchID)
            HanYangStaging.recoverAbandonedBatches(excluding: batchID)
        } catch {
            statusLabel.text = "분석용 저장소를 열지 못했습니다. 잠시 후 다시 공유해 주세요."
            setStage(.failed)
            return
        }
        providers = shareContext?
            .inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        guard !providers.isEmpty else {
            statusLabel.text = "가져올 수 있는 사진이 없습니다."
            setStage(.failed)
            return
        }

        countStepper.maximumValue = Double(providers.count)
        countStepper.value = 1
        selectedN = 1
        startButton.configuration?.title = "한양에게 추천받기"
        statusLabel.text = "\(providers.count)장을 선택했습니다. 한양이 품질을 보고 추천 장수를 정합니다."
    }

    private func updateCountLabel() {
        startButton.configuration?.title = "선택한 \(Int(countStepper.value))장 확인"
        countLabel.text = "\(Int(countStepper.value))장 뽑기 (전체 \(providers.count)장)"
    }

    @objc private func countChanged() {
        hasCustomCount = true
        selectedN = Int(countStepper.value)
        updateCountLabel()
    }

    // MARK: - Analysis

    @objc private func startAnalysis() {
        guard currentTask == nil, !isCommitted else { return }
        if !candidates.isEmpty { renderSelection(); return }
        setStage(.analyzing)
        statusLabel.text = "0/\(providers.count)장을 분석하는 중입니다."
        progressView.progress = 0
        progressLabel.text = "0%"

        currentTask = Task {
            var staged: [Candidate] = []
            var failures = 0

            for (index, provider) in providers.enumerated() {
                guard !Task.isCancelled else { return }
                if let candidate = await stageAndMeasure(provider: provider, index: index) {
                    staged.append(candidate)
                } else {
                    failures += 1
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let completed = index + 1
                    let progress = Float(completed) / Float(self.providers.count)
                    self.progressView.setProgress(progress, animated: true)
                    self.progressLabel.text = "\(Int((progress * 100).rounded()))%"
                    self.statusLabel.text = "\(completed)/\(self.providers.count)장을 분석하는 중입니다."
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.candidates = staged
                self.failedCount = failures
                self.currentTask = nil
                self.showResult()
            }
        }
    }

    @objc private func retryAnalysis() {
        guard currentTask == nil, !isCommitted else { return }
        HanYangStaging.clearStagedMedia(batchID: batchID)
        candidates = []
        failedCount = 0
        startAnalysis()
    }

    private func stageAndMeasure(
        provider: NSItemProvider,
        index: Int
    ) async -> Candidate? {
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        }) else { return nil }

        guard let sourceURL = try? await loadFileRepresentation(
            provider: provider,
            typeIdentifier: typeIdentifier
        ) else { return nil }
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        guard !Task.isCancelled else { return nil }

        let fallbackExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "jpg"
        guard let stagingURL = try? HanYangStaging.stage(
            fileAt: sourceURL,
            batchID: batchID,
            index: index,
            fallbackExtension: fallbackExtension
        ) else { return nil }

        guard !Task.isCancelled else { return nil }
        guard let measurement = await ImageQualityAnalyzer.measure(fileAt: stagingURL) else {
            try? FileManager.default.removeItem(at: stagingURL)
            return nil
        }

        guard !Task.isCancelled else { return nil }
        return Candidate(
            index: index,
            stagingURL: stagingURL,
            measurement: measurement,
            suggestedFilename: provider.suggestedName
        )
    }

    private func loadFileRepresentation(
        provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: HanYangStaging.HanYangError.decodeFailed)
                    return
                }
                do {
                    let temporary = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    try FileManager.default.copyItem(at: url, to: temporary)
                    continuation.resume(returning: temporary)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Result

    private func showResult() {
        guard !candidates.isEmpty else {
            statusLabel.text = "분석할 수 있는 사진이 없어 선택할 수 없습니다."
            setStage(.failed)
            return
        }

        let qualityCandidates = candidates.map {
            ImageQualityCandidate(index: $0.index, sharpness: $0.measurement.sharpness,
                exposureScore: $0.measurement.exposureScore, pixelCount: $0.measurement.pixelCount,
                aestheticsScore: isUsingAesthetics ? $0.measurement.aestheticsScore : nil)
        }
        recommendedN = ImageTopNSelector.recommendedCount(candidates: qualityCandidates)
        if !hasCustomCount { selectedN = recommendedN }
        countStepper.maximumValue = Double(candidates.count)
        countStepper.value = Double(selectedN)
        renderSelection()
    }

    private func renderSelection() {
        let hanAICandidates = candidates.map {
            ImageQualityCandidate(
                index: $0.index,
                sharpness: $0.measurement.sharpness,
                exposureScore: $0.measurement.exposureScore,
                pixelCount: $0.measurement.pixelCount,
                aestheticsScore: isUsingAesthetics ? $0.measurement.aestheticsScore : nil
            )
        }
        let ranking = ImageTopNSelector.selectTopN(candidates: hanAICandidates, n: selectedN)
        let selectedIndices = Set(ranking.selectedIndices)
        let selected = candidates
            .filter { selectedIndices.contains($0.index) }
            .sorted { $0.index < $1.index }

        var statusText = "전체 \(providers.count)장 중 한양은 \(recommendedN)장을 추천합니다. \(selected.count)장을 골랐습니다."
        confirmButton.isEnabled = selected.count == selectedN && albumDestination != nil
        if selected.count < selectedN { statusText += " 개수를 줄이거나 다시 분석해 주세요." }
        if failedCount > 0 {
            statusText += " (\(failedCount)장은 분석에 실패해 제외했습니다)"
        }
        if !isUsingAesthetics {
            statusText += " 선명도·노출·해상도 기준으로 골랐습니다."
        }
        if isUsingAesthetics { statusText += " 사진 품질 평가도 반영했습니다." }
        statusLabel.text = statusText

        thumbnailsStack.arrangedSubviews.forEach {
            thumbnailsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        previewURLs = selected.map { $0.stagingURL }
        previewImageViews = []
        for (position, candidate) in selected.enumerated() {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.backgroundColor = .secondarySystemBackground
            imageView.isUserInteractionEnabled = true
            imageView.tag = position
            imageView.accessibilityLabel = "고른 사진 \(position + 1) 크게 보기"
            imageView.accessibilityTraits = .button
            imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openPhotoPreview(_:))))
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 10
            if let cgImage = ImageQualityAnalyzer.downsampledCGImage(
                at: candidate.stagingURL, maxPixelSize: ImageQualityAnalyzer.thumbnailMaxPixelSize
            ) {
                imageView.heightAnchor.constraint(
                    equalTo: imageView.widthAnchor,
                    multiplier: CGFloat(cgImage.height) / CGFloat(cgImage.width)
                ).isActive = true
            } else {
                imageView.heightAnchor.constraint(equalToConstant: 160).isActive = true
            }
            thumbnailsStack.addArrangedSubview(imageView)
            previewImageViews.append(imageView)
        }

        confirmButton.configuration?.title = "선택한 \(selected.count)장 앨범에 저장"
        setStage(.result)
        view.layoutIfNeeded()
        scrollView.setContentOffset(.zero, animated: false)
    }

    private var isUsingAesthetics: Bool {
        !candidates.isEmpty && candidates.allSatisfy { $0.measurement.aestheticsScore != nil }
    }

    @objc private func backToCountSelection() {
        try? HanYangStaging.writeManifest(batchID: batchID, state: "staging", selectedFilenames: [])
        countStepper.value = Double(min(selectedN, candidates.count))
        selectedN = Int(countStepper.value)
        setStage(.configuring)
        updateCountLabel()
        statusLabel.text = "\(providers.count)장 중 뽑을 장수를 다시 정해 주세요."
        view.layoutIfNeeded()
        scrollView.setContentOffset(.zero, animated: false)
    }

    @objc private func chooseAlbum() {
        guard currentTask == nil, !isSaving, !isCommitted else { return }
        currentTask = Task {
            var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if status == .notDetermined {
                status = await withCheckedContinuation { continuation in
                    PHPhotoLibrary.requestAuthorization(for: .readWrite) { continuation.resume(returning: $0) }
                }
            }
            currentTask = nil
            guard !Task.isCancelled else { return }
            guard status == .authorized else {
                statusLabel.text = (status == .limited
                    ? HanYangAlbumSaver.SaveError.limitedAccess
                    : HanYangAlbumSaver.SaveError.denied).localizedDescription
                return
            }
            let picker = HanYangAlbumPicker { [weak self] destination in
                guard let self else { return }
                self.albumDestination = destination
                self.albumButton.configuration?.title = "앨범: " + destination.name
                self.renderSelection()
            }
            present(UINavigationController(rootViewController: picker), animated: true)
        }
    }

    // MARK: - Save album

    @objc private func saveAlbum() {
        guard !isCommitted, !isSaving, currentTask == nil else { return }
        guard let destination = albumDestination else {
            statusLabel.text = "저장할 앨범을 선택해 주세요."
            return
        }
        let inputs = candidates.map {
            ImageQualityCandidate(index: $0.index, sharpness: $0.measurement.sharpness,
                exposureScore: $0.measurement.exposureScore, pixelCount: $0.measurement.pixelCount,
                aestheticsScore: isUsingAesthetics ? $0.measurement.aestheticsScore : nil)
        }
        let indices = Set(ImageTopNSelector.selectTopN(candidates: inputs, n: selectedN).selectedIndices)
        let selected = candidates.filter { indices.contains($0.index) }.sorted { $0.index < $1.index }
        guard selected.count == selectedN, !selected.isEmpty else { return }
        progressView.progress = 0
        progressLabel.text = "원본 대조 준비 중"
        setStage(.resolving)
        statusLabel.text = "선택한 \(selected.count)장의 원본을 확인하는 중입니다."
        currentTask = Task {
            do {
                try HanYangStaging.writeManifest(batchID: batchID, state: "saving",
                    selectedFilenames: selected.map { $0.stagingURL.lastPathComponent })
                let resolver = HanYangOriginalResolver()
                var originals: [HanYangAlbumPhoto] = []
                for (index, candidate) in selected.enumerated() {
                    let identifier = try await resolver.resolve(fileURL: candidate.stagingURL,
                        suggestedFilename: candidate.suggestedFilename) { [weak self] done, total in
                            await MainActor.run {
                                self?.statusLabel.text = "원본 확인 \(index + 1)/\(selected.count)장 · 보관함 대조 \(done)/\(total)"
                                let fraction = total > 0 ? Float(done) / Float(total) : 0
                                self?.progressView.progress = fraction
                                self?.progressLabel.text = "\(Int(fraction * 100))%"
                            }
                        }
                    originals.append(HanYangAlbumPhoto(fileURL: candidate.stagingURL,
                        originalFilename: candidate.suggestedFilename, assetIdentifier: identifier))
                    statusLabel.text = "원본 확인 \(index + 1)/\(selected.count)장"
                }
                try Task.checkCancellation()
                // Only the uncancellable PhotoKit commit disables the close action.
                isSaving = true
                setStage(.saving)
                // No library mutations occur unless every selected original was resolved.
                statusLabel.text = "‘\(destination.name)’ 앨범에 원본 사진을 추가하는 중입니다."
                let result = try await HanYangAlbumSaver.save(photos: originals, destination: destination)
                // PhotoKit has committed. Later cleanup failures must not offer duplicate-saving retries.
                isCommitted = true
                isSaving = false
                currentTask = nil
                try? HanYangStaging.writeManifest(batchID: batchID, state: "saved", selectedFilenames: [])
                HanYangStaging.deleteBatch(batchID: batchID)
                setStage(.saved)
                if result.albumCount == result.savedCount {
                    statusLabel.text = "‘\(result.albumName)’ 앨범에 \(result.albumCount)장을 저장했습니다. 사진 앱의 앨범에서 확인해 주세요."
                } else {
                    statusLabel.text = "사진 \(result.savedCount)장을 저장했지만 앨범에는 \(result.albumCount)장만 연결됐습니다. 사진 앱에서 확인해 주세요."
                }
            } catch {
                isSaving = false
                currentTask = nil
                if Task.isCancelled { return }
                try? HanYangStaging.writeManifest(batchID: batchID, state: "staging", selectedFilenames: [])
                renderSelection()
                statusLabel.text = error.localizedDescription
            }
        }
    }

    @objc private func openPhotoPreview(_ gesture: UITapGestureRecognizer) {
        guard let position = gesture.view?.tag, previewURLs.indices.contains(position) else { return }
        let preview = QLPreviewController()
        preview.dataSource = self
        preview.currentPreviewItemIndex = position
        preview.modalPresentationStyle = .fullScreen
        present(preview, animated: true)
    }

    // MARK: - Cancel

    @objc private func cancelFlow() {
        guard !isSaving else { return }
        let pendingTask = currentTask
        pendingTask?.cancel()
        cancelButton.isEnabled = false
        Task {
            // Wait for any provider callback to finish before cleaning our staging folder.
            await pendingTask?.value
            currentTask = nil
            if !isCommitted {
                        HanYangStaging.deleteBatch(batchID: batchID)
            }
            completeExtension()
        }
    }

    private func completeExtension() {
        shareContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ value: Float) -> NSLayoutConstraint {
        priority = UILayoutPriority(value)
        return self
    }
}

/// Existing albums are chosen by identifier; matching titles never merge albums.
@MainActor
private final class HanYangAlbumPicker: UITableViewController {
    private var albums: [PHAssetCollection] = []
    private let completion: (HanYangAlbumDestination) -> Void
    init(completion: @escaping (HanYangAlbumDestination) -> Void) {
        self.completion = completion
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "저장할 앨범"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
            target: self, action: #selector(closePicker))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
            target: self, action: #selector(newAlbum))
        let options = PHFetchOptions()
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).enumerateObjects { album, _, _ in
            if album.canPerform(.addContent) { self.albums.append(album) }
        }
        albums.sort { ($0.localizedTitle ?? "").localizedStandardCompare($1.localizedTitle ?? "") == .orderedAscending }
        if albums.isEmpty {
            let label = UILabel()
            label.text = "추가할 수 있는 앨범이 없습니다.\n오른쪽 + 버튼으로 새 앨범을 만들 수 있습니다."
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            tableView.backgroundView = label
        }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { albums.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "album") ?? UITableViewCell(style: .default, reuseIdentifier: "album")
        var content = cell.defaultContentConfiguration()
        content.text = albums[indexPath.row].localizedTitle ?? "이름 없는 앨범"
        content.image = UIImage(systemName: "rectangle.stack")
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let album = albums[indexPath.row]
        completion(.existing(identifier: album.localIdentifier, name: album.localizedTitle ?? "이름 없는 앨범"))
        dismiss(animated: true)
    }
    @objc private func closePicker() { dismiss(animated: true) }
    @objc private func newAlbum() {
        let alert = UIAlertController(title: "새 앨범", message: "선택한 사진을 추가할 때 앨범을 만듭니다.", preferredStyle: .alert)
        alert.addTextField { field in field.placeholder = "앨범 이름"; field.text = "한양이 고른 사진" }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "선택", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
            else { return }
            self.completion(.new(name: name))
            self.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}


extension PhotoPickerViewController: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURLs.count }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        previewURLs[index] as NSURL
    }
}


extension PhotoPickerViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) { loadVisiblePhotoPreviews() }
}
