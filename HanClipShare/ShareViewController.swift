import AVFoundation
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let pointColor = UIColor(
        red: 0,
        green: 118 / 255,
        blue: 68 / 255,
        alpha: 1
    )
    private let secondaryColor = UIColor(
        red: 41 / 255,
        green: 171 / 255,
        blue: 135 / 255,
        alpha: 1
    )
    private let logoStack = UIStackView()
    private let logoImageView = UIImageView()
    private let logoTitleLabel = UILabel()
    private let statusLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let thumbnailContainer = UIView()
    private let thumbnailView = UIImageView()
    private let progressLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let cancelButton = UIButton(type: .system)
    private var importTask: Task<Void, Never>?
    private var isImportComplete = false
    private var isOpeningHostApp = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        importSharedAttachments()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        logoImageView.image = UIImage(named: "LogoMarkV2")
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.tintColor = pointColor
        logoImageView.translatesAutoresizingMaskIntoConstraints = false

        logoTitleLabel.text = "HanClip"
        logoTitleLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        logoTitleLabel.textColor = pointColor

        logoStack.axis = .horizontal
        logoStack.alignment = .center
        logoStack.distribution = .fill
        logoStack.spacing = 6
        logoStack.isLayoutMarginsRelativeArrangement = true
        logoStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 16,
            leading: 0,
            bottom: 0,
            trailing: 0
        )
        logoStack.addArrangedSubview(logoImageView)
        logoStack.addArrangedSubview(logoTitleLabel)
        logoStack.setContentHuggingPriority(.required, for: .horizontal)
        logoStack.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        statusLabel.text = "공유 파일을 준비하는 중입니다."
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        descriptionLabel.text =
            "확인을 누른 뒤 HanClip을 열면 공유 파일을 새 프로젝트나 "
            + "기존 프로젝트에 추가할 수 있습니다."
        descriptionLabel.font = .preferredFont(forTextStyle: .footnote)
        descriptionLabel.textAlignment = .center
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0

        thumbnailContainer.backgroundColor = secondaryColor.withAlphaComponent(
            0.10
        )
        thumbnailContainer.layer.cornerRadius = 18
        thumbnailContainer.clipsToBounds = true
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailContainer.addSubview(thumbnailView)
        thumbnailView.image = UIImage(systemName: "photo.on.rectangle.angled")
        thumbnailView.tintColor = secondaryColor

        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: 35.2),
            logoImageView.heightAnchor.constraint(equalToConstant: 35.2),
            thumbnailView.centerXAnchor.constraint(
                equalTo: thumbnailContainer.centerXAnchor
            ),
            thumbnailView.centerYAnchor.constraint(
                equalTo: thumbnailContainer.centerYAnchor
            ),
            thumbnailView.widthAnchor.constraint(
                equalTo: thumbnailContainer.widthAnchor
            ),
            thumbnailView.heightAnchor.constraint(
                equalTo: thumbnailContainer.heightAnchor
            ),
            thumbnailContainer.heightAnchor.constraint(
                equalTo: thumbnailContainer.widthAnchor
            )
        ])

        progressView.progress = 0
        progressView.transform = CGAffineTransform(scaleX: 1, y: 2)
        progressView.progressTintColor = secondaryColor
        progressView.trackTintColor = secondaryColor.withAlphaComponent(0.18)

        progressLabel.text = "0%"
        progressLabel.font = .monospacedDigitSystemFont(
            ofSize: 13,
            weight: .semibold
        )
        progressLabel.textColor = secondaryColor
        progressLabel.textAlignment = .right
        progressLabel.setContentHuggingPriority(.required, for: .horizontal)
        progressLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        let progressStack = UIStackView(
            arrangedSubviews: [
                progressLabel,
                progressView
            ]
        )
        progressStack.axis = .horizontal
        progressStack.alignment = .center
        progressStack.spacing = 10

        cancelButton.setTitle("취소", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(
            ofSize: 18,
            weight: .semibold
        )
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = pointColor
        cancelButton.layer.cornerRadius = 12
        cancelButton.addTarget(
            self,
            action: #selector(cancelImport),
            for: .touchUpInside
        )

        let stack = UIStackView(
            arrangedSubviews: [
                logoStack,
                thumbnailContainer,
                progressStack,
                statusLabel,
                cancelButton,
                descriptionLabel
            ]
        )
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -60
            ),
            stack.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 24
            ),
            stack.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -24
            ),
            thumbnailContainer.widthAnchor.constraint(
                equalTo: stack.widthAnchor
            ),
            progressStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cancelButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            descriptionLabel.widthAnchor.constraint(
                equalTo: stack.widthAnchor
            ),
            cancelButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func importSharedAttachments() {
        SharedInbox.clearPendingImports()

        let providers = extensionContext?
            .inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        guard !providers.isEmpty else {
            showResult(count: 0)
            return
        }

        statusLabel.text = "0/\(providers.count)개 파일을 복사하는 중입니다."

        importTask = Task {
            var records: [SharedImportRecord] = []
            for (index, provider) in providers.enumerated() {
                guard !Task.isCancelled else { return }
                if let record = try? await importProvider(provider) {
                    records.append(record)
                    await MainActor.run {
                        self.showThumbnail(for: record)
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let completed = index + 1
                    let progress = Float(completed) / Float(providers.count)
                    self.progressView.setProgress(
                        progress,
                        animated: true
                    )
                    self.progressLabel.text =
                        "\(Int((progress * 100).rounded()))%"
                    self.statusLabel.text =
                        "\(completed)/\(providers.count)개 파일을 "
                        + "복사하는 중입니다."
                }
            }
            guard !Task.isCancelled else { return }
            SharedInbox.append(records)
            await MainActor.run {
                self.importTask = nil
                showResult(count: records.count)
            }
        }
    }

    private func importProvider(
        _ provider: NSItemProvider
    ) async throws -> SharedImportRecord {
        if supportsLivePhoto(provider),
           let liveRecord = try? await importLivePhoto(provider) {
            return liveRecord
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            let filename = try await copyRepresentation(
                from: provider,
                type: .movie,
                fallbackExtension: "mov"
            )
            return SharedImportRecord(
                kind: .video,
                primaryFilename: filename
            )
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let importedFile = try await copyRepresentationDetails(
                from: provider,
                type: .image,
                fallbackExtension: "jpg"
            )
            if supportsLivePhoto(provider) {
                return SharedImportRecord(
                    kind: .livePhoto,
                    primaryFilename: importedFile.filename,
                    originalFilename:
                        importedFile.originalFilename
                        ?? provider.suggestedName
                )
            }
            return SharedImportRecord(
                kind: .image,
                primaryFilename: importedFile.filename
            )
        }

        throw MediaShareError.unsupportedItem
    }

    private func importLivePhoto(
        _ provider: NSItemProvider
    ) async throws -> SharedImportRecord {
        for identifier in livePhotoTypeIdentifiers
        where provider.hasItemConformingToTypeIdentifier(identifier) {
            if let record = try? await importLivePhotoBundle(
                provider,
                typeIdentifier: identifier
            ) {
                return record
            }
        }

        if provider.hasItemConformingToTypeIdentifier(
            UTType.image.identifier
        ), provider.hasItemConformingToTypeIdentifier(
            UTType.movie.identifier
        ) {
            let imageName = try await copyRepresentation(
                from: provider,
                type: .image,
                fallbackExtension: "jpg"
            )
            let videoName = try await copyRepresentation(
                from: provider,
                type: .movie,
                fallbackExtension: "mov"
            )
            return SharedImportRecord(
                kind: .livePhoto,
                primaryFilename: imageName,
                secondaryFilename: videoName
            )
        }

        throw MediaShareError.livePhotoComponentsUnavailable
    }

    private func importLivePhotoBundle(
        _ provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> SharedImportRecord {
        let sourceURL = try await loadFileRepresentation(
            provider,
            typeIdentifier: typeIdentifier
        )
        let contents = recursiveContents(of: sourceURL)

        guard let image = contents.first(where: {
            ["jpg", "jpeg", "heic", "png"].contains(
                $0.pathExtension.lowercased()
            )
        }), let video = contents.first(where: {
            ["mov", "mp4"].contains($0.pathExtension.lowercased())
        }) else {
            throw MediaShareError.livePhotoComponentsUnavailable
        }

        let imageName = try copyFileToInbox(
            image,
            fallbackExtension: "jpg"
        )
        let videoName = try copyFileToInbox(
            video,
            fallbackExtension: "mov"
        )
        return SharedImportRecord(
            kind: .livePhoto,
            primaryFilename: imageName,
            secondaryFilename: videoName
        )
    }

    private var livePhotoTypeIdentifiers: [String] {
        [
            UTType.livePhoto.identifier,
            "com.apple.live-photo-bundle",
            "com.apple.private.live-photo-bundle"
        ]
    }

    private func supportsLivePhoto(_ provider: NSItemProvider) -> Bool {
        livePhotoTypeIdentifiers.contains {
            provider.hasItemConformingToTypeIdentifier($0)
        }
    }

    private func recursiveContents(of sourceURL: URL) -> [URL] {
        let isDirectory = (
            try? sourceURL.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory
        ) ?? false
        guard isDirectory else { return [sourceURL] }

        guard let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { element in
            guard let url = element as? URL,
                  (try? url.resourceValues(
                    forKeys: [.isRegularFileKey]
                  ).isRegularFile) == true
            else { return nil }
            return url
        }
    }

    private func copyRepresentation(
        from provider: NSItemProvider,
        type: UTType,
        fallbackExtension: String
    ) async throws -> String {
        try await copyRepresentationDetails(
            from: provider,
            type: type,
            fallbackExtension: fallbackExtension
        ).filename
    }

    private func copyRepresentationDetails(
        from provider: NSItemProvider,
        type: UTType,
        fallbackExtension: String
    ) async throws -> (
        filename: String,
        originalFilename: String?
    ) {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation {
            (
                continuation: CheckedContinuation<
                    (
                        filename: String,
                        originalFilename: String?
                    ),
                    Error
                >
            ) in
            provider.loadFileRepresentation(
                forTypeIdentifier: type.identifier
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(
                        throwing: MediaShareError.missingFile
                    )
                    return
                }
                do {
                    let filename = try self.copyFileToInbox(
                        url,
                        fallbackExtension: fallbackExtension
                    )
                    continuation.resume(
                        returning: (
                            filename,
                            url.lastPathComponent.isEmpty
                                ? suggestedName
                                : url.lastPathComponent
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func loadFileRepresentation(
        _ provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(
                forTypeIdentifier: typeIdentifier
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    do {
                        let temporary = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(url.pathExtension)
                        try FileManager.default.copyItem(
                            at: url,
                            to: temporary
                        )
                        continuation.resume(returning: temporary)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(
                        throwing: MediaShareError.missingFile
                    )
                }
            }
        }
    }

    private func copyFileToInbox(
        _ source: URL,
        fallbackExtension: String
    ) throws -> String {
        let ext = source.pathExtension.isEmpty
            ? fallbackExtension
            : source.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = try SharedInbox.fileURL(named: filename)
        try FileManager.default.copyItem(at: source, to: destination)
        return filename
    }

    private func showResult(count: Int) {
        if count > 0 {
            isImportComplete = true
            progressView.progress = 1
            progressLabel.text = "100%"
            statusLabel.text =
                "\(count)개 파일 복사가 완료되었습니다."
            cancelButton.setTitle("앱열기", for: .normal)
            openHostApp(completeAfterAttempt: false)
        } else {
            isImportComplete = false
            statusLabel.text = "가져올 수 있는 사진이나 영상이 없습니다."
            progressView.isHidden = true
            progressLabel.isHidden = true
            cancelButton.setTitle("확인", for: .normal)
        }
    }

    private func showThumbnail(for record: SharedImportRecord) {
        guard let url = try? SharedInbox.fileURL(
            named: record.primaryFilename
        ) else { return }

        let image: UIImage?
        switch record.kind {
        case .image, .livePhoto:
            image = UIImage(contentsOfFile: url.path)
        case .video:
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            image = (try? generator.copyCGImage(
                at: .zero,
                actualTime: nil
            )).map(UIImage.init(cgImage:))
        }

        guard let image else { return }
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.image = image
    }

    @objc private func cancelImport() {
        if let importTask {
            importTask.cancel()
            self.importTask = nil
            extensionContext?.cancelRequest(
                withError: MediaShareError.cancelled
            )
        } else if isImportComplete {
            openHostApp(completeAfterAttempt: true)
        } else {
            completeExtension()
        }
    }

    private func openHostApp(completeAfterAttempt: Bool) {
        guard !isOpeningHostApp else { return }
        guard let url = URL(string: "hanclip://shared-import") else {
            completeExtension()
            return
        }

        isOpeningHostApp = true
        cancelButton.isEnabled = false
        statusLabel.text = "HanClip을 여는 중입니다."
        extensionContext?.open(url) { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isOpeningHostApp = false
                self.cancelButton.isEnabled = true

                if completeAfterAttempt {
                    if !success {
                        _ = self.openHostAppFromResponderChain(url)
                    }
                    self.completeExtension()
                    return
                }

                if success {
                    self.statusLabel.text =
                        "앱 실행을 시도했습니다. 열리지 않으면 앱열기를 다시 눌러 주세요."
                    self.cancelButton.setTitle("앱열기", for: .normal)
                } else if self.openHostAppFromResponderChain(url) {
                    self.statusLabel.text =
                        "앱 실행을 다시 시도했습니다. 열리지 않으면 앱열기를 다시 눌러 주세요."
                    self.cancelButton.setTitle("앱열기", for: .normal)
                } else {
                    self.statusLabel.text =
                        "자동 실행에 실패했습니다. 앱열기를 눌러 HanClip을 여세요."
                    self.cancelButton.setTitle("앱열기", for: .normal)
                }
            }
        }
    }

    private func openHostAppFromResponderChain(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if currentResponder.responds(to: selector) {
                currentResponder.perform(selector, with: url)
                return true
            }
            responder = currentResponder.next
        }
        return false
    }

    private func completeExtension() {
        extensionContext?.completeRequest(
            returningItems: nil,
            completionHandler: nil
        )
    }
}

private enum MediaShareError: LocalizedError {
    case unsupportedItem
    case missingFile
    case livePhotoComponentsUnavailable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedItem:
            "지원하지 않는 공유 항목입니다."
        case .missingFile:
            "공유 파일을 읽을 수 없습니다."
        case .livePhotoComponentsUnavailable:
            "Live Photo 구성 파일을 읽을 수 없습니다."
        case .cancelled:
            "가져오기를 취소했습니다."
        }
    }
}
