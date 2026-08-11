import AVFoundation
import ImageIO
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
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let progressLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let actionButtonsStack = UIStackView()
    private let cancelButton = UIButton(type: .system)
    private var importTask: Task<Void, Never>?
    private var isImportComplete = false
    private var isOpeningHostApp = false
    private var didAttemptAutomaticOpen = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        importSharedAttachments()
    }

    private func configureView() {
        let usesAdaptivePadLayout = traitCollection.userInterfaceIdiom == .pad

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
            top: 8,
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

        statusLabel.text = "공유 파일을 HanClip으로 옮기는 중입니다."
        statusLabel.font = .systemFont(ofSize: 24, weight: .black)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        descriptionLabel.text =
            "복사가 끝나면 HanClip에서 바로 새 영화나 기존 영화에 추가할 수 있습니다."
        descriptionLabel.font = .systemFont(ofSize: 15, weight: .semibold)
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

        let thumbnailAspectRatioConstraint = thumbnailContainer.heightAnchor.constraint(
            equalTo: thumbnailContainer.widthAnchor,
            multiplier: 0.64
        )
        if usesAdaptivePadLayout {
            thumbnailAspectRatioConstraint.priority = UILayoutPriority(999)
        }

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
            thumbnailAspectRatioConstraint
        ])

        progressView.progress = 0
        progressView.transform = CGAffineTransform(scaleX: 1, y: 1.6)
        progressView.progressTintColor = secondaryColor
        progressView.trackTintColor = secondaryColor.withAlphaComponent(0.18)

        progressLabel.text = "0%"
        progressLabel.font = .monospacedDigitSystemFont(
            ofSize: 14,
            weight: .bold
        )
        progressLabel.textColor = secondaryColor
        progressLabel.textAlignment = .right
        progressLabel.adjustsFontSizeToFitWidth = true
        progressLabel.minimumScaleFactor = 0.82
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

        configureActionButtons()
        configureCancelButton()

        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        [
            logoStack,
            thumbnailContainer,
            progressStack,
            statusLabel,
            actionButtonsStack,
            descriptionLabel
        ].forEach(stack.addArrangedSubview)
        if usesAdaptivePadLayout {
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.alwaysBounceVertical = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.contentInsetAdjustmentBehavior = .never
            view.addSubview(scrollView)
            scrollView.addSubview(stack)
        } else {
            view.addSubview(stack)
        }
        view.addSubview(cancelButton)

        let stackFillWidth = stack.widthAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.widthAnchor,
            constant: -48
        )
        stackFillWidth.priority = UILayoutPriority(999)
        let stackRegularWidth = stack.widthAnchor.constraint(
            equalToConstant: 640
        )
        stackRegularWidth.priority = UILayoutPriority(998)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.centerXAnchor
            ),
            stack.widthAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor,
                constant: -48
            ),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
            stackFillWidth,
            stackRegularWidth,
            thumbnailContainer.widthAnchor.constraint(
                equalTo: stack.widthAnchor
            ),
            progressStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progressLabel.widthAnchor.constraint(equalToConstant: 54),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actionButtonsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            descriptionLabel.widthAnchor.constraint(
                equalTo: stack.widthAnchor
            ),
            cancelButton.centerXAnchor.constraint(
                equalTo: stack.centerXAnchor
            ),
            cancelButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cancelButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -12
            ),
            cancelButton.heightAnchor.constraint(equalToConstant: 54)
        ])

        if usesAdaptivePadLayout {
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.topAnchor
                ),
                scrollView.leadingAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.leadingAnchor
                ),
                scrollView.trailingAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.trailingAnchor
                ),
                scrollView.bottomAnchor.constraint(
                    equalTo: cancelButton.topAnchor,
                    constant: -12
                ),
                scrollView.contentLayoutGuide.widthAnchor.constraint(
                    equalTo: scrollView.frameLayoutGuide.widthAnchor
                ),
                stack.topAnchor.constraint(
                    equalTo: scrollView.contentLayoutGuide.topAnchor,
                    constant: 22
                ),
                stack.bottomAnchor.constraint(
                    equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                    constant: -12
                ),
                thumbnailContainer.heightAnchor.constraint(
                    lessThanOrEqualTo: view.safeAreaLayoutGuide.heightAnchor,
                    multiplier: 0.42
                ),
                thumbnailContainer.heightAnchor.constraint(
                    lessThanOrEqualToConstant: 320
                )
            ])
        } else {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.topAnchor,
                    constant: 22
                ),
                stack.bottomAnchor.constraint(
                    lessThanOrEqualTo: cancelButton.topAnchor,
                    constant: -12
                )
            ])
        }
    }

    private func configureActionButtons() {
        actionButtonsStack.axis = .vertical
        actionButtonsStack.alignment = .fill
        actionButtonsStack.distribution = .fill
        actionButtonsStack.spacing = 10
        actionButtonsStack.isHidden = true

        actionButtonsStack.addArrangedSubview(
            makeActionButton(
                title: "HanClip에서 열기",
                image: UIImage(systemName: "arrow.up.forward.app.fill"),
                action: #selector(openApp)
            )
        )
    }

    private func makeActionButton(
        title: String,
        image: UIImage?,
        action: Selector
    ) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = image
        configuration.imagePlacement = .leading
        configuration.imagePadding = 10
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 19,
            weight: .bold
        )
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = secondaryColor
            .withAlphaComponent(0.92)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: 20,
            bottom: 0,
            trailing: 20
        )

        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        button.heightAnchor.constraint(equalToConstant: 58).isActive = true
        button.layer.shadowColor = secondaryColor.withAlphaComponent(0.28).cgColor
        button.layer.shadowOpacity = 1
        button.layer.shadowRadius = 14
        button.layer.shadowOffset = CGSize(width: 0, height: 7)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func configureCancelButton() {
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("닫기", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(
            ofSize: 17,
            weight: .bold
        )
        cancelButton.setTitleColor(pointColor, for: .normal)
        cancelButton.setTitleColor(pointColor.withAlphaComponent(0.45), for: .disabled)
        cancelButton.backgroundColor = secondaryColor.withAlphaComponent(0.12)
        cancelButton.layer.cornerRadius = 16
        cancelButton.layer.borderColor = secondaryColor
            .withAlphaComponent(0.32)
            .cgColor
        cancelButton.layer.borderWidth = 1
        cancelButton.addTarget(
            self,
            action: #selector(cancelImport),
            for: .touchUpInside
        )

        cancelButton.layer.shadowColor = secondaryColor.withAlphaComponent(0.16).cgColor
        cancelButton.layer.shadowOpacity = 1
        cancelButton.layer.shadowRadius = 10
        cancelButton.layer.shadowOffset = CGSize(width: 0, height: 4)
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
                    let completed = index + 1
                    if completed == 1
                        || completed.isMultiple(of: 10)
                        || completed == providers.count {
                        await MainActor.run {
                            self.showThumbnail(for: record)
                        }
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
        // Photos also exposes the still HEIC of a Live Photo as a generic
        // file URL. Resolve the Live Photo bundle first so its paired video
        // is not silently discarded.
        if supportsLivePhoto(provider),
           let liveRecord = try? await importLivePhoto(provider) {
            return liveRecord
        }

        if let fileURLRecord = try? await importFileURL(provider) {
            return fileURLRecord
        }

        if let movieTypeIdentifier = provider.typeIdentifier(
            conformingTo: .movie
        ) {
            let filename = try await copyRepresentation(
                from: provider,
                typeIdentifier: movieTypeIdentifier,
                fallbackExtension: "mov"
            )
            return SharedImportRecord(
                kind: .video,
                primaryFilename: filename
            )
        }

        if let imageTypeIdentifier = provider.typeIdentifier(
            conformingTo: .image
        ) {
            let importedFile = try await copyRepresentationDetails(
                from: provider,
                typeIdentifier: imageTypeIdentifier,
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

    private func importFileURL(
        _ provider: NSItemProvider
    ) async throws -> SharedImportRecord {
        let typeIdentifier = provider.typeIdentifier(conformingTo: .fileURL)
            ?? provider.typeIdentifier(conformingTo: .url)
            ?? "public.file-url"
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else {
            throw MediaShareError.unsupportedItem
        }

        return try await copyURLItemToInbox(
            from: provider,
            typeIdentifier: typeIdentifier
        )
    }

    private static func mediaKind(for url: URL) -> SharedImportRecord.Kind {
        if url.pathExtension.lowercased()
            == BrowserFavoritesArchive.filenameExtension {
            return .browserFavorites
        }

        if let contentType = try? url.resourceValues(
            forKeys: [.contentTypeKey]
        ).contentType {
            if contentType.conforms(to: .movie) {
                return .video
            }
            if contentType.conforms(to: .image) {
                return .image
            }
        }

        let ext = url.pathExtension.lowercased()
        if ext == BrowserFavoritesArchive.filenameExtension {
            return .browserFavorites
        }
        if ["mov", "mp4", "m4v"].contains(ext) {
            return .video
        }
        return .image
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
            let imageTypeIdentifier = provider.typeIdentifier(
                conformingTo: .image
            ) ?? UTType.image.identifier
            let movieTypeIdentifier = provider.typeIdentifier(
                conformingTo: .movie
            ) ?? UTType.movie.identifier
            let imageName = try await copyRepresentation(
                from: provider,
                typeIdentifier: imageTypeIdentifier,
                fallbackExtension: "jpg"
            )
            let videoName = try await copyRepresentation(
                from: provider,
                typeIdentifier: movieTypeIdentifier,
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

    nonisolated private func recursiveContents(of sourceURL: URL) -> [URL] {
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
        typeIdentifier: String,
        fallbackExtension: String
    ) async throws -> String {
        try await copyRepresentationDetails(
            from: provider,
            typeIdentifier: typeIdentifier,
            fallbackExtension: fallbackExtension
        ).filename
    }

    private func copyRepresentationDetails(
        from provider: NSItemProvider,
        typeIdentifier: String,
        fallbackExtension: String
    ) async throws -> (
        filename: String,
        originalFilename: String?
    ) {
        let suggestedName = provider.suggestedName
        let resolvedFallbackExtension = UTType(typeIdentifier)?
            .preferredFilenameExtension
            ?? fallbackExtension
        if let importedFile = try? await copyFileRepresentationToInbox(
            from: provider,
            typeIdentifier: typeIdentifier,
            fallbackExtension: resolvedFallbackExtension
        ) {
            return importedFile
        }

        let filename = try await copyLoadedItemToInbox(
            from: provider,
            typeIdentifier: typeIdentifier,
            fallbackExtension: resolvedFallbackExtension
        )
        return (filename, suggestedName)
    }

    private func copyFileRepresentationToInbox(
        from provider: NSItemProvider,
        typeIdentifier: String,
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
                forTypeIdentifier: typeIdentifier
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

    private func copyURLItemToInbox(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> SharedImportRecord {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: typeIdentifier,
                options: nil
            ) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let sourceURL: URL?
                switch item {
                case let url as URL:
                    sourceURL = url
                case let nsURL as NSURL:
                    sourceURL = nsURL as URL
                case let string as String:
                    sourceURL = URL(string: string)
                default:
                    sourceURL = nil
                }

                guard let sourceURL else {
                    continuation.resume(
                        throwing: MediaShareError.missingFile
                    )
                    return
                }

                do {
                    let mediaKind = Self.mediaKind(for: sourceURL)
                    let fallbackExtension: String
                    switch mediaKind {
                    case .video:
                        fallbackExtension = "mov"
                    case .browserFavorites:
                        fallbackExtension =
                            BrowserFavoritesArchive.filenameExtension
                    case .image, .livePhoto:
                        fallbackExtension = "jpg"
                    }
                    let filename = try self.copyFileToInbox(
                        sourceURL,
                        fallbackExtension: fallbackExtension
                    )
                    continuation.resume(
                        returning: SharedImportRecord(
                            kind: mediaKind,
                            primaryFilename: filename,
                            originalFilename: sourceURL.lastPathComponent
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func copyLoadedItemToInbox(
        from provider: NSItemProvider,
        typeIdentifier: String,
        fallbackExtension: String
    ) async throws -> String {
        if let filename = try? await copyInPlaceRepresentation(
            from: provider,
            typeIdentifier: typeIdentifier,
            fallbackExtension: fallbackExtension
        ) {
            return filename
        }

        if let filename = try? await copyDataRepresentation(
            from: provider,
            typeIdentifier: typeIdentifier,
            fallbackExtension: fallbackExtension
        ) {
            return filename
        }

        return try await copyItemRepresentation(
            from: provider,
            typeIdentifier: typeIdentifier,
            fallbackExtension: fallbackExtension
        )
    }

    private func copyInPlaceRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String,
        fallbackExtension: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadInPlaceFileRepresentation(
                forTypeIdentifier: typeIdentifier
            ) { url, _, error in
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
                    continuation.resume(returning: filename)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func copyDataRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String,
        fallbackExtension: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(
                forTypeIdentifier: typeIdentifier
            ) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(
                        throwing: MediaShareError.missingFile
                    )
                    return
                }
                do {
                    let filename = try self.writeDataToInbox(
                        data,
                        fallbackExtension: fallbackExtension
                    )
                    continuation.resume(returning: filename)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func copyItemRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String,
        fallbackExtension: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: typeIdentifier,
                options: nil
            ) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                do {
                    switch item {
                    case let url as URL:
                        let filename = try self.copyFileToInbox(
                            url,
                            fallbackExtension: fallbackExtension
                        )
                        continuation.resume(returning: filename)
                    case let data as Data:
                        let filename = try self.writeDataToInbox(
                            data,
                            fallbackExtension: fallbackExtension
                        )
                        continuation.resume(returning: filename)
                    case let image as UIImage:
                        guard let data = image.jpegData(
                            compressionQuality: 0.96
                        ) else {
                            throw MediaShareError.missingFile
                        }
                        let filename = try self.writeDataToInbox(
                            data,
                            fallbackExtension: "jpg"
                        )
                        continuation.resume(returning: filename)
                    default:
                        continuation.resume(
                            throwing: MediaShareError.missingFile
                        )
                    }
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

    nonisolated private func copyFileToInbox(
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

    nonisolated private func writeDataToInbox(
        _ data: Data,
        fallbackExtension: String
    ) throws -> String {
        let filename = "\(UUID().uuidString).\(fallbackExtension)"
        let destination = try SharedInbox.fileURL(named: filename)
        try data.write(to: destination, options: .atomic)
        return filename
    }

    private func showResult(count: Int) {
        if count > 0 {
            isImportComplete = true
            progressView.progress = 1
            progressLabel.text = "100%"
            statusLabel.text =
                "\(count)개 파일을 준비했습니다"
            descriptionLabel.text =
                "잠시 후 HanClip으로 이동합니다. 이동하지 않으면 아래 버튼을 눌러 주세요."
            actionButtonsStack.isHidden = true
            openHostAppAutomaticallyIfNeeded()
        } else {
            isImportComplete = false
            statusLabel.text = "가져올 수 있는 사진이나 영상이 없습니다"
            progressView.isHidden = true
            progressLabel.isHidden = true
            actionButtonsStack.isHidden = true
        }
    }

    private func showThumbnail(for record: SharedImportRecord) {
        guard let url = try? SharedInbox.fileURL(
            named: record.primaryFilename
        ) else { return }

        let image: UIImage?
        switch record.kind {
        case .image, .livePhoto:
            image = downsampledImage(at: url, maximumPixelSize: 640)
        case .video:
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            image = (try? generator.copyCGImage(
                at: .zero,
                actualTime: nil
            )).map(UIImage.init(cgImage:))
        case .browserFavorites:
            image = UIImage(systemName: "bookmark.square.fill")
        }

        guard let image else { return }
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.image = image
    }

    private func downsampledImage(
        at url: URL,
        maximumPixelSize: CGFloat
    ) -> UIImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            sourceOptions
        ) else { return nil }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    @objc private func cancelImport() {
        if let importTask {
            importTask.cancel()
            self.importTask = nil
            extensionContext?.cancelRequest(
                withError: MediaShareError.cancelled
            )
        } else {
            completeExtension()
        }
    }

    @objc private func openPhoto() {
        openHostApp(path: "photo")
    }

    @objc private func openCalendar() {
        openHostApp(path: "calendar")
    }

    @objc private func openFiles() {
        openHostApp(path: "files")
    }

    @objc private func openApp() {
        openHostApp(path: "open")
    }

    private func openHostAppAutomaticallyIfNeeded() {
        guard !didAttemptAutomaticOpen else { return }
        didAttemptAutomaticOpen = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self,
                  self.isImportComplete,
                  !self.isOpeningHostApp
            else { return }
            self.openHostApp(path: "open", isAutomatic: true)
        }
    }

    private func openHostApp(path: String, isAutomatic: Bool = false) {
        guard !isOpeningHostApp else { return }
        guard let url = URL(string: "hanclip://\(path)") else {
            completeExtension()
            return
        }

        isOpeningHostApp = true
        setActionButtonsEnabled(false)
        cancelButton.isEnabled = true
        statusLabel.text = isAutomatic
            ? "HanClip으로 이동합니다"
            : "HanClip을 여는 중입니다"
        extensionContext?.open(url) { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }

                if success {
                    self.finishOpeningHostApp(success: true)
                    return
                }

                self.openHostAppFromResponderChain(url) { [weak self] success in
                    self?.finishOpeningHostApp(
                        success: success,
                        wasAutomatic: isAutomatic
                    )
                }
            }
        }
    }

    private func finishOpeningHostApp(
        success: Bool,
        wasAutomatic: Bool = false
    ) {
        isOpeningHostApp = false
        setActionButtonsEnabled(true)
        cancelButton.isEnabled = true

        if success {
            completeExtension()
        } else {
            actionButtonsStack.isHidden = false
            statusLabel.text =
                wasAutomatic
                    ? "자동으로 열리지 않았습니다"
                    : "앱 실행에 실패했습니다. 아이콘을 다시 눌러 주세요."
            descriptionLabel.text =
                "아래 버튼으로 HanClip을 열어 공유 파일을 새 영화나 기존 영화에 추가할 수 있습니다."
        }
    }

    private func setActionButtonsEnabled(_ isEnabled: Bool) {
        actionButtonsStack.arrangedSubviews.forEach { view in
            guard let button = view as? UIButton else { return }
            button.isEnabled = isEnabled
            button.alpha = isEnabled ? 1 : 0.55
        }
    }

    private func openHostAppFromResponderChain(
        _ url: URL,
        completion: @escaping (Bool) -> Void
    ) {
        let selector = NSSelectorFromString(
            "openURL:options:completionHandler:"
        )
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if let application = currentResponder as? UIApplication,
               currentResponder.responds(to: selector) {
                application.open(
                    url,
                    options: [:]
                ) { success in
                    DispatchQueue.main.async {
                        completion(success)
                    }
                }
                return
            }

            if let scene = currentResponder as? UIScene,
               currentResponder.responds(to: selector) {
                scene.open(url, options: nil) { success in
                    DispatchQueue.main.async {
                        completion(success)
                    }
                }
                return
            }

            responder = currentResponder.next
        }

        completion(false)
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

private extension NSItemProvider {
    func typeIdentifier(conformingTo type: UTType) -> String? {
        registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: type) == true
        }
    }
}
