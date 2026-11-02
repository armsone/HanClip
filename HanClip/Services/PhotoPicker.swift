import AVFoundation
import AVKit
import HanAIApple
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private final class PhotoPickerGradientView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.insertSublayer(gradientLayer, at: 0)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    private func updateColors() {
        gradientLayer.colors = [
            UIColor(HanClipTheme.backgroundWithBlack).cgColor,
            UIColor(HanClipTheme.background).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.12, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.88, y: 1)
    }
}

private final class PhotoPickerGlassButton: UIButton {
    private let blurView = UIVisualEffectView()
    private let tintView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.tintColor = HanClipTheme.secondaryUIColor
                .withAlphaComponent(0.12)
            glassEffect.isInteractive = true
            blurView.effect = glassEffect
            tintView.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        } else {
            blurView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            tintView.backgroundColor = UIColor.white.withAlphaComponent(0.20)
        }
        blurView.isUserInteractionEnabled = false
        blurView.clipsToBounds = true
        blurView.layer.cornerRadius = 20
        blurView.layer.cornerCurve = .continuous
        blurView.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(blurView, at: 0)
        tintView.isUserInteractionEnabled = false
        tintView.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(tintView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tintView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private enum PhotoDurationFilterComparison {
    case atLeast
    case atMost

    var title: String {
        switch self {
        case .atLeast: "이상"
        case .atMost: "이하"
        }
    }
}

private struct PhotoDurationFilterEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Int
    @State private var seconds: Int
    @State private var comparison: PhotoDurationFilterComparison

    private let maximumMinutes: Int
    let onApply: (TimeInterval, PhotoDurationFilterComparison) -> Void
    let onClear: () -> Void

    init(
        currentSeconds: TimeInterval?,
        currentComparison: PhotoDurationFilterComparison,
        onApply: @escaping (
            TimeInterval,
            PhotoDurationFilterComparison
        ) -> Void,
        onClear: @escaping () -> Void
    ) {
        let initialSeconds = max(Int((currentSeconds ?? 180).rounded()), 0)
        _minutes = State(initialValue: initialSeconds / 60)
        _seconds = State(initialValue: initialSeconds % 60)
        _comparison = State(initialValue: currentComparison)
        maximumMinutes = max(180, initialSeconds / 60 + 30)
        self.onApply = onApply
        self.onClear = onClear
    }

    private var totalSeconds: Int {
        minutes * 60 + seconds
    }

    private var resultText: String {
        "\(formattedDuration(totalSeconds)) \(comparison.title)인 영상만 표시"
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 10) {
                Text("빠른 선택")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HanClipTheme.text.opacity(0.72))

                HStack(spacing: 8) {
                    presetButton("1분", seconds: 60)
                    presetButton("3분", seconds: 180)
                    presetButton("5분", seconds: 300)
                    presetButton("10분", seconds: 600)
                }
            }

            VStack(spacing: 12) {
                Picker("시간 조건", selection: $comparison) {
                    Text("이상").tag(PhotoDurationFilterComparison.atLeast)
                    Text("이하").tag(PhotoDurationFilterComparison.atMost)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    timePicker(
                        title: "분",
                        selection: $minutes,
                        values: 0...maximumMinutes
                    )
                    timePicker(
                        title: "초",
                        selection: $seconds,
                        values: 0...59
                    )
                }

                Label(resultText, systemImage: "video.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HanClipTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        HanClipTheme.primary.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .padding(14)
            .background(
                HanClipTheme.panelFill,
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(HanClipTheme.secondary.opacity(0.22))
            }

            HStack(spacing: 10) {
                Button {
                    onClear()
                    dismiss()
                } label: {
                    Text("필터 해제")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(HanClipTheme.text.opacity(0.76))
                .padding(.vertical, 14)
                .background(
                    HanClipTheme.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16)
                )

                Button {
                    onApply(TimeInterval(totalSeconds), comparison)
                    dismiss()
                } label: {
                    Text("\(comparison.title) 영상 보기")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(HanClipTheme.onSecondary)
                .padding(.vertical, 14)
                .background(
                    HanClipTheme.primary,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .disabled(totalSeconds == 0)
                .opacity(totalSeconds == 0 ? 0.38 : 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(HanClipTheme.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(HanClipTheme.primary)
                .frame(width: 42, height: 42)
                .background(
                    HanClipTheme.primary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("영상 시간 필터")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(HanClipTheme.text)
                Text("설정한 시간 이상인 영상만 찾습니다.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HanClipTheme.text.opacity(0.62))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HanClipTheme.text)
                    .frame(width: 38, height: 38)
                    .background(
                        HanClipTheme.secondary.opacity(0.12),
                        in: Circle()
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
    }

    private func presetButton(
        _ title: String,
        seconds presetSeconds: Int
    ) -> some View {
        let isSelected = totalSeconds == presetSeconds
        return Button {
            minutes = presetSeconds / 60
            seconds = presetSeconds % 60
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(
                    isSelected ? HanClipTheme.onSecondary : HanClipTheme.text
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    isSelected
                        ? HanClipTheme.primary
                        : HanClipTheme.secondary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 13)
                )
        }
        .buttonStyle(.plain)
    }

    private func timePicker(
        title: String,
        selection: Binding<Int>,
        values: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 4) {
            Picker(title, selection: selection) {
                ForEach(Array(values), id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.menu)
            .tint(HanClipTheme.primary)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HanClipTheme.text.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            HanClipTheme.background.opacity(0.78),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func formattedDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0, seconds > 0 {
            return "\(minutes)분 \(seconds)초"
        }
        if minutes > 0 {
            return "\(minutes)분"
        }
        return "\(seconds)초"
    }
}

struct PhotoPicker: UIViewControllerRepresentable {
    let initialSelectionIdentifiers: [String]
    let excludedImportIdentifiers: Set<String>
    let videoOnly: Bool
    let onSelectionIdentifiers: (([String]) -> Void)?
    let onComplete: ([ClipItem], [String]) -> Void
    let onStart: () -> Void
    let onProgress: (Double, String) -> Void
    let onRegisterCancellation: (@escaping () -> Void) -> Void
    let onCancel: () -> Void
    let onDismiss: () -> Void
    let onShowCalendar: ([String]) -> Void

    init(
        initialSelectionIdentifiers: [String],
        excludedImportIdentifiers: Set<String>,
        videoOnly: Bool = false,
        onSelectionIdentifiers: (([String]) -> Void)? = nil,
        onComplete: @escaping ([ClipItem], [String]) -> Void,
        onStart: @escaping () -> Void,
        onProgress: @escaping (Double, String) -> Void,
        onRegisterCancellation: @escaping (@escaping () -> Void) -> Void,
        onCancel: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onShowCalendar: @escaping ([String]) -> Void
    ) {
        self.initialSelectionIdentifiers = initialSelectionIdentifiers
        self.excludedImportIdentifiers = excludedImportIdentifiers
        self.videoOnly = videoOnly
        self.onSelectionIdentifiers = onSelectionIdentifiers
        self.onComplete = onComplete
        self.onStart = onStart
        self.onProgress = onProgress
        self.onRegisterCancellation = onRegisterCancellation
        self.onCancel = onCancel
        self.onDismiss = onDismiss
        self.onShowCalendar = onShowCalendar
    }

    func makeUIViewController(
        context: Context
    ) -> DragSelectionPhotoPickerViewController {
        let container = DragSelectionPhotoPickerViewController(
            initialSelectionIdentifiers: initialSelectionIdentifiers,
            videoOnly: videoOnly,
            onCancel: {
                context.coordinator.cancelPicking()
            },
            onShowCalendar: onShowCalendar,
            onDone: { assetIdentifiers in
                context.coordinator.finishPicking(
                    assetIdentifiers: assetIdentifiers
                )
            }
        )
        return container
    }

    func updateUIViewController(
        _ uiViewController: DragSelectionPhotoPickerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            excludedImportIdentifiers: excludedImportIdentifiers,
            onSelectionIdentifiers: onSelectionIdentifiers,
            onStart: onStart,
            onProgress: onProgress,
            onRegisterCancellation: onRegisterCancellation,
            onComplete: onComplete,
            onCancel: onCancel,
            onDismiss: onDismiss
        )
    }

    final class DragSelectionPhotoPickerViewController: UIViewController,
        UICollectionViewDataSource,
        UICollectionViewDelegate,
        UICollectionViewDelegateFlowLayout,
        UIGestureRecognizerDelegate {
        private let onCancel: () -> Void
        private let onShowCalendar: ([String]) -> Void
        private let onDone: ([String]) -> Void
        private let videoOnly: Bool
        private let imageManager = PHCachingImageManager()
        private var assets: PHFetchResult<PHAsset>?
        private var assetSections: [AssetDaySection] = []
        private var selectedMediaFilters: Set<MediaFilter> = [
            .photo,
            .livePhoto,
            .video
        ]
        private var durationFilterSeconds: TimeInterval?
        private var durationFilterComparison: PhotoDurationFilterComparison = .atLeast
        private var mediaFiltersBeforeDurationFilter: Set<MediaFilter>?
        private var mediaSortMode: MediaSortMode = .captureDate
        private var isMediaSortAscending = true
        private var selectedIdentifiers: [String] = []
        private var selectedIdentifierSet: Set<String> = []
        private var dragShouldSelect = true
        private var lastDragIndexPath: IndexPath?
        private var suppressNextTap = false
        private var columnCount = 5
        private var dragLocationInView: CGPoint?
        private var autoScrollDisplayLink: CADisplayLink?
        private var lastAutoScrollTimestamp: CFTimeInterval?
        private let filterButton = UIButton(type: .system)
        private let clearSelectionButton = UIButton(type: .system)
        private let doneButton = UIButton(type: .system)
        private let headerDoneButton = PhotoPickerGlassButton(type: .system)
        private let previousDayButton = UIButton(type: .system)
        private let todayButton = UIButton(type: .system)
        private var isTodayButtonArmedForSelection = false
        private let collectionView: UICollectionView

        private enum MediaFilter: Int {
            case photo = 0
            case livePhoto = 1
            case video = 2

            var title: String {
                switch self {
                case .photo: "사진"
                case .livePhoto: "라이브"
                case .video: "영상"
                }
            }

            var symbolName: String {
                switch self {
                case .photo: "photo"
                case .livePhoto: "livephoto"
                case .video: "video.fill"
                }
            }
        }

        private enum MediaSortMode: Int {
            case captureDate
            case addedDate

            var title: String {
                switch self {
                case .captureDate: "날짜순"
                case .addedDate: "추가순"
                }
            }

            var symbolName: String {
                switch self {
                case .captureDate: "calendar"
                case .addedDate: "tray.and.arrow.down"
                }
            }
        }

        private struct AssetDaySection {
            let date: Date
            let assets: [PHAsset]
        }

        init(
            initialSelectionIdentifiers: [String],
            videoOnly: Bool,
            onCancel: @escaping () -> Void,
            onShowCalendar: @escaping ([String]) -> Void,
            onDone: @escaping ([String]) -> Void
        ) {
            self.onCancel = onCancel
            self.onShowCalendar = onShowCalendar
            self.onDone = onDone
            self.videoOnly = videoOnly
            if videoOnly {
                selectedMediaFilters = [.video]
            }
            selectedIdentifiers = initialSelectionIdentifiers
            selectedIdentifierSet = Set(initialSelectionIdentifiers)
            let layout = UICollectionViewFlowLayout()
            layout.minimumLineSpacing = 2
            layout.minimumInteritemSpacing = 2
            collectionView = UICollectionView(
                frame: .zero,
                collectionViewLayout: layout
            )
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = UIColor(HanClipTheme.background)
            let background = PhotoPickerGradientView()
            background.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(background)
            NSLayoutConstraint.activate([
                background.topAnchor.constraint(equalTo: view.topAnchor),
                background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                background.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            configureHeader()
            configureCollectionView()
            configureToolbar()
            configureDayNavigationButtons()
            requestAccessAndLoadAssets()
        }

        private func configureHeader() {
            let header = UIView()
            header.backgroundColor = .clear
            header.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(header)

            let titleButton = PhotoPickerGlassButton(type: .system)
            titleButton.setTitle("사진", for: .normal)
            titleButton.setTitleColor(UIColor(HanClipTheme.text), for: .normal)
            titleButton.titleLabel?.font = UIFontMetrics(
                forTextStyle: .headline
            ).scaledFont(
                for: .systemFont(ofSize: 17, weight: .semibold),
                maximumPointSize: 24
            )
            titleButton.titleLabel?.adjustsFontForContentSizeCategory = true
            titleButton.accessibilityHint = "달력 선택 화면으로 전환합니다."
            titleButton.backgroundColor = .clear
            titleButton.layer.cornerRadius = 20
            titleButton.layer.cornerCurve = .continuous
            titleButton.layer.borderWidth = 1
            titleButton.layer.borderColor = UIColor.white
                .withAlphaComponent(0.52).cgColor
            titleButton.layer.shadowColor = HanClipTheme.secondaryUIColor.cgColor
            titleButton.layer.shadowOpacity = 0.08
            titleButton.layer.shadowRadius = 8
            titleButton.layer.shadowOffset = CGSize(width: 0, height: 4)
            titleButton.addTarget(
                self,
                action: #selector(showCalendarTapped),
                for: .touchUpInside
            )
            titleButton.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(titleButton)

            let cancelButton = PhotoPickerGlassButton(type: .system)
            configureCompactButton(
                cancelButton,
                title: "취소",
                symbolName: nil,
                fontSize: 16,
                foregroundColor: UIColor(HanClipTheme.text)
                    .withAlphaComponent(0.72),
                backgroundColor: UIColor.white.withAlphaComponent(0.14),
                borderColor: UIColor.white.withAlphaComponent(0.52)
            )
            cancelButton.addTarget(
                self,
                action: #selector(cancelTapped),
                for: .touchUpInside
            )
            cancelButton.backgroundColor = .clear
            cancelButton.layer.shadowColor = HanClipTheme.secondaryUIColor.cgColor
            cancelButton.layer.shadowOpacity = 0.08
            cancelButton.layer.shadowRadius = 8
            cancelButton.layer.shadowOffset = CGSize(width: 0, height: 4)

            configureCompactButton(
                headerDoneButton,
                title: "0개 추가",
                symbolName: nil,
                fontSize: 16,
                foregroundColor: UIColor(HanClipTheme.text)
                    .withAlphaComponent(0.72),
                backgroundColor: UIColor.white.withAlphaComponent(0.14),
                borderColor: UIColor.white.withAlphaComponent(0.52)
            )
            headerDoneButton.setTitleColor(
                UIColor(HanClipTheme.text).withAlphaComponent(0.72),
                for: .disabled
            )
            headerDoneButton.isEnabled = false
            headerDoneButton.addTarget(
                self,
                action: #selector(doneTapped),
                for: .touchUpInside
            )
            headerDoneButton.backgroundColor = .clear
            headerDoneButton.layer.shadowColor =
                HanClipTheme.secondaryUIColor.cgColor
            headerDoneButton.layer.shadowOpacity = 0.08
            headerDoneButton.layer.shadowRadius = 8
            headerDoneButton.layer.shadowOffset = CGSize(width: 0, height: 4)

            cancelButton.translatesAutoresizingMaskIntoConstraints = false
            headerDoneButton.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(cancelButton)
            header.addSubview(headerDoneButton)

            NSLayoutConstraint.activate([
                header.topAnchor.constraint(equalTo: view.topAnchor),
                header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                header.bottomAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.topAnchor,
                    constant: 68
                ),
                cancelButton.leadingAnchor.constraint(
                    equalTo: header.leadingAnchor,
                    constant: 18
                ),
                cancelButton.topAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.topAnchor,
                    constant: 14
                ),
                cancelButton.widthAnchor.constraint(equalToConstant: 88),
                cancelButton.heightAnchor.constraint(equalToConstant: 40),
                headerDoneButton.trailingAnchor.constraint(
                    equalTo: header.trailingAnchor,
                    constant: -18
                ),
                headerDoneButton.topAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.topAnchor,
                    constant: 14
                ),
                headerDoneButton.widthAnchor.constraint(equalToConstant: 88),
                headerDoneButton.heightAnchor.constraint(equalToConstant: 40),
                titleButton.centerXAnchor.constraint(equalTo: header.centerXAnchor),
                titleButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
                titleButton.widthAnchor.constraint(equalToConstant: 88),
                titleButton.heightAnchor.constraint(equalToConstant: 40),
                titleButton.leadingAnchor.constraint(
                    greaterThanOrEqualTo: cancelButton.trailingAnchor,
                    constant: 8
                ),
                titleButton.trailingAnchor.constraint(
                    lessThanOrEqualTo: headerDoneButton.leadingAnchor,
                    constant: -8
                )
            ])
            header.tag = 101
        }

        @objc private func showCalendarTapped() {
            onShowCalendar(selectedIdentifiers)
        }

        private func configureCompactButton(
            _ button: UIButton,
            title: String,
            symbolName: String?,
            fontSize: CGFloat,
            foregroundColor: UIColor,
            backgroundColor: UIColor,
            borderColor: UIColor
        ) {
            button.configuration = nil
            button.setTitle(title, for: .normal)
            button.setImage(
                symbolName.flatMap { UIImage(systemName: $0) },
                for: .normal
            )
            button.tintColor = foregroundColor
            button.setTitleColor(foregroundColor, for: .normal)
            button.titleLabel?.font = UIFontMetrics(
                forTextStyle: .headline
            ).scaledFont(
                for: .systemFont(ofSize: fontSize, weight: .semibold),
                maximumPointSize: 24
            )
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.adjustsFontSizeToFitWidth = false
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(
                    pointSize: fontSize,
                    weight: .semibold
                ),
                forImageIn: .normal
            )
            button.semanticContentAttribute = .forceLeftToRight
            button.contentHorizontalAlignment = .center
            button.backgroundColor = backgroundColor
            button.layer.cornerRadius = fontSize >= 14 ? 20 : 18
            button.layer.cornerCurve = .continuous
            button.layer.borderWidth = 1
            button.layer.borderColor = borderColor.cgColor
            if symbolName != nil {
                button.imageEdgeInsets = UIEdgeInsets(
                    top: 0,
                    left: -3,
                    bottom: 0,
                    right: 3
                )
                button.titleEdgeInsets = UIEdgeInsets(
                    top: 0,
                    left: 3,
                    bottom: 0,
                    right: -3
                )
            } else {
                button.imageEdgeInsets = .zero
                button.titleEdgeInsets = .zero
            }
        }

        private func configureCollectionView() {
            collectionView.backgroundColor = .clear
            collectionView.alwaysBounceVertical = true
            collectionView.contentInset.bottom = 92
            collectionView.verticalScrollIndicatorInsets.bottom = 92
            collectionView.isDirectionalLockEnabled = true
            collectionView.allowsMultipleSelection = true
            collectionView.dataSource = self
            collectionView.delegate = self
            collectionView.register(
                DragSelectionPhotoCell.self,
                forCellWithReuseIdentifier: DragSelectionPhotoCell.reuseID
            )
            collectionView.register(
                PhotoPickerDateHeader.self,
                forSupplementaryViewOfKind:
                    UICollectionView.elementKindSectionHeader,
                withReuseIdentifier: PhotoPickerDateHeader.reuseID
            )
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(collectionView)

            let pan = UIPanGestureRecognizer(
                target: self,
                action: #selector(handleSelectionPan(_:))
            )
            pan.delegate = self
            pan.cancelsTouchesInView = true
            collectionView.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(
                target: self,
                action: #selector(handleGridPinch(_:))
            )
            pinch.delegate = self
            collectionView.addGestureRecognizer(pinch)

            let previewLongPress = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleMediaPreviewLongPress(_:))
            )
            previewLongPress.minimumPressDuration = 0.45
            previewLongPress.delegate = self
            collectionView.addGestureRecognizer(previewLongPress)
        }

        private func configureToolbar() {
            guard let header = view.viewWithTag(101) else { return }
            NSLayoutConstraint.activate([
                collectionView.topAnchor.constraint(
                    equalTo: header.bottomAnchor
                ),
                collectionView.leadingAnchor.constraint(
                    equalTo: view.leadingAnchor,
                    constant: 14
                ),
                collectionView.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor,
                    constant: -14
                ),
                collectionView.bottomAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.bottomAnchor
                )
            ])
        }

        private func configureDayNavigationButtons() {
            configureFloatingDayButton(
                filterButton,
                title: "필터",
                accessibilityHint: "표시할 미디어 종류를 선택합니다."
            )
            filterButton.showsMenuAsPrimaryAction = true
            updateFilterMenu()

            configureFloatingDayButton(
                previousDayButton,
                title: "전날",
                accessibilityHint: "선택이 없으면 어제와 가까운 날짜를 선택하고, 선택이 있으면 선택된 날짜의 전날을 선택합니다."
            )
            previousDayButton.addTarget(
                self,
                action: #selector(previousDayTapped),
                for: .touchUpInside
            )

            configureFloatingDayButton(
                todayButton,
                title: "오늘",
                accessibilityHint: "한 번 누르면 오늘로 이동하고, 다시 누르면 오늘의 미디어를 선택합니다."
            )
            todayButton.addTarget(
                self,
                action: #selector(todayTapped),
                for: .touchUpInside
            )

            configureFloatingDayButton(
                clearSelectionButton,
                title: "해제",
                accessibilityHint: "현재 선택한 미디어를 모두 선택 해제합니다."
            )
            clearSelectionButton.accessibilityLabel = "선택 해제"
            clearSelectionButton.isEnabled = false
            clearSelectionButton.alpha = 0.34
            clearSelectionButton.addTarget(
                self,
                action: #selector(clearSelectionTapped),
                for: .touchUpInside
            )

            configureFloatingDayButton(
                doneButton,
                title: "추가",
                accessibilityHint: "선택한 미디어를 영화에 추가합니다."
            )
            doneButton.isEnabled = false
            doneButton.alpha = 0.34
            doneButton.addTarget(
                self,
                action: #selector(doneTapped),
                for: .touchUpInside
            )

            let buttonStack = UIStackView(arrangedSubviews: [
                filterButton,
                previousDayButton,
                todayButton,
                clearSelectionButton,
                doneButton
            ])
            buttonStack.axis = .horizontal
            buttonStack.alignment = .center
            buttonStack.distribution = .equalSpacing
            buttonStack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(buttonStack)
            NSLayoutConstraint.activate([
                buttonStack.leadingAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                    constant: 18
                ),
                buttonStack.trailingAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                    constant: -18
                ),
                buttonStack.bottomAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                    constant: -16
                ),
                filterButton.widthAnchor.constraint(equalToConstant: 54),
                filterButton.heightAnchor.constraint(equalToConstant: 54),
                previousDayButton.widthAnchor.constraint(equalToConstant: 54),
                previousDayButton.heightAnchor.constraint(equalToConstant: 54),
                todayButton.widthAnchor.constraint(equalToConstant: 54),
                todayButton.heightAnchor.constraint(equalToConstant: 54),
                clearSelectionButton.widthAnchor.constraint(equalToConstant: 54),
                clearSelectionButton.heightAnchor.constraint(equalToConstant: 54),
                doneButton.widthAnchor.constraint(equalToConstant: 54),
                doneButton.heightAnchor.constraint(equalToConstant: 54)
            ])
        }

        private func configureFloatingDayButton(
            _ button: UIButton,
            title: String,
            accessibilityHint: String
        ) {
            button.configuration = nil
            button.setTitle(title, for: .normal)
            button.setTitleColor(HanClipTheme.primaryUIColor, for: .normal)
            button.titleLabel?.font = UIFontMetrics(
                forTextStyle: .footnote
            ).scaledFont(
                for: .systemFont(ofSize: 13, weight: .semibold),
                maximumPointSize: 18
            )
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.adjustsFontSizeToFitWidth = false
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.backgroundColor = UIColor(HanClipTheme.background)
                .withAlphaComponent(0.86)
            button.layer.cornerRadius = 29
            button.layer.cornerCurve = .continuous
            button.layer.borderWidth = 1.25
            button.layer.borderColor = HanClipTheme.secondaryUIColor
                .withAlphaComponent(0.34).cgColor
            button.layer.shadowColor = HanClipTheme.secondaryUIColor.cgColor
            button.layer.shadowOpacity = 0.18
            button.layer.shadowRadius = 10
            button.layer.shadowOffset = CGSize(width: 0, height: 5)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.accessibilityLabel = title
            button.accessibilityHint = accessibilityHint
        }

        private func requestAccessAndLoadAssets() {
            Task { @MainActor in
                guard await PhotoLibraryService.requestReadAccess() else {
                    updateDoneButtonTitle("권한 필요")
                    return
                }
                let options = PHFetchOptions()
                options.sortDescriptors = [
                    // Match the iPhone Photos library: older items above and
                    // the newest items at the bottom.
                    NSSortDescriptor(key: "creationDate", ascending: true)
                ]
                if videoOnly {
                    options.predicate = NSPredicate(
                        format: "mediaType == %d",
                        PHAssetMediaType.video.rawValue
                    )
                } else {
                    options.predicate = NSPredicate(
                        format: "mediaType == %d OR mediaType == %d",
                        PHAssetMediaType.image.rawValue,
                        PHAssetMediaType.video.rawValue
                    )
                }
                assets = PHAsset.fetchAssets(with: options)
                rebuildAssetSections()
                updateSelectionCount()
                collectionView.reloadData()
                collectionView.layoutIfNeeded()
                scrollToInitialMediaPosition(animated: false)
            }
        }

        private func toggleMediaFilter(_ filter: MediaFilter) {
            if selectedMediaFilters.contains(filter) {
                guard selectedMediaFilters.count > 1 else { return }
                selectedMediaFilters.remove(filter)
            } else {
                selectedMediaFilters.insert(filter)
            }
            applyMediaFilters()
        }

        private func updateFilterMenu() {
            let allAction = UIAction(
                title: videoOnly ? "전체 영상" : "전체",
                image: UIImage(systemName: "square.grid.2x2.fill"),
                state: (videoOnly
                    ? selectedMediaFilters == [.video]
                    : selectedMediaFilters.count == 3)
                    && durationFilterSeconds == nil ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                selectedMediaFilters = videoOnly
                    ? [.video]
                    : [.photo, .livePhoto, .video]
                durationFilterSeconds = nil
                mediaFiltersBeforeDurationFilter = nil
                applyMediaFilters()
            }
            let actions: [UIMenuElement]
            if videoOnly || durationFilterSeconds != nil {
                actions = [
                    UIAction(
                        title: "영상만",
                        image: UIImage(systemName: "video.fill"),
                        attributes: [.disabled],
                        state: .on
                    ) { _ in }
                ]
            } else {
                actions = [
                    MediaFilter.photo,
                    MediaFilter.livePhoto,
                    MediaFilter.video
                ].map { filter in
                    UIAction(
                        title: filter.title,
                        image: UIImage(systemName: filter.symbolName),
                        state: selectedMediaFilters.contains(filter) ? .on : .off
                    ) { [weak self] _ in
                        self?.toggleMediaFilter(filter)
                    }
                }
            }
            let durationAction = UIAction(
                title: durationFilterMenuTitle,
                image: UIImage(systemName: "clock.badge.checkmark"),
                state: durationFilterSeconds == nil ? .off : .on
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.presentDurationFilterEditor()
                }
            }
            let sortActions: [UIMenuElement] = [
                MediaSortMode.captureDate,
                MediaSortMode.addedDate
            ].map { mode in
                let isSelected = mediaSortMode == mode
                let arrow = isSelected && !isMediaSortAscending ? "↓" : "↑"
                return UIAction(
                    title: "\(mode.title) \(arrow)",
                    image: UIImage(systemName: mode.symbolName),
                    state: isSelected ? .on : .off
                ) { [weak self] _ in
                    self?.selectMediaSort(mode)
                }
            }
            filterButton.menu = UIMenu(
                title: "필터",
                options: .displayInline,
                children: [
                    allAction,
                    UIMenu(options: .displayInline, children: actions),
                    UIMenu(options: .displayInline, children: [durationAction]),
                    UIMenu(
                        title: "정렬",
                        options: .displayInline,
                        children: sortActions
                    )
                ]
            )
            var accessibilityValue = selectedMediaFilters
                .sorted { $0.rawValue < $1.rawValue }
                .map(\.title)
                .joined(separator: ", ")
            if durationFilterSeconds != nil {
                accessibilityValue += ", \(durationFilterMenuTitle)"
            }
            accessibilityValue += ", \(mediaSortMode.title) "
                + (isMediaSortAscending ? "오름차순" : "내림차순")
            filterButton.accessibilityValue = accessibilityValue
        }

        private func selectMediaSort(_ mode: MediaSortMode) {
            if mediaSortMode == mode {
                isMediaSortAscending.toggle()
            } else {
                mediaSortMode = mode
            }
            applyMediaFilters()
        }

        private var durationFilterMenuTitle: String {
            guard let seconds = durationFilterSeconds else {
                return "시간 제한 없음"
            }
            let totalSeconds = max(Int(seconds.rounded()), 0)
            let minutes = totalSeconds / 60
            let remainingSeconds = totalSeconds % 60
            let timeText: String
            if minutes > 0, remainingSeconds > 0 {
                timeText = "\(minutes)분 \(remainingSeconds)초"
            } else if minutes > 0 {
                timeText = "\(minutes)분"
            } else {
                timeText = "\(remainingSeconds)초"
            }
            return "\(timeText) 이상 영상"
        }

        private func presentDurationFilterEditor() {
            let editor = PhotoDurationFilterEditor(
                currentSeconds: durationFilterSeconds,
                currentComparison: durationFilterComparison,
                onApply: { [weak self] seconds, comparison in
                    self?.activateDurationFilter(
                        seconds: seconds,
                        comparison: comparison
                    )
                },
                onClear: { [weak self] in
                    self?.clearDurationFilter()
                }
            )
            let controller = UIHostingController(rootView: editor)
            controller.modalPresentationStyle = .pageSheet
            if let sheet = controller.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
                sheet.prefersGrabberVisible = false
                sheet.preferredCornerRadius = 28
            }
            present(controller, animated: true)
        }

        private func activateDurationFilter(
            seconds: TimeInterval,
            comparison: PhotoDurationFilterComparison
        ) {
            if durationFilterSeconds == nil {
                mediaFiltersBeforeDurationFilter = selectedMediaFilters
            }
            durationFilterSeconds = max(seconds, 1)
            durationFilterComparison = comparison
            selectedMediaFilters = [.video]
            applyMediaFilters()
        }

        private func clearDurationFilter() {
            durationFilterSeconds = nil
            durationFilterComparison = .atLeast
            selectedMediaFilters = mediaFiltersBeforeDurationFilter
                ?? (videoOnly ? [.video] : [.photo, .livePhoto, .video])
            mediaFiltersBeforeDurationFilter = nil
            applyMediaFilters()
        }

        private func applyMediaFilters() {
            resetTodayButtonState()
            updateFilterMenu()
            rebuildAssetSections()
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            scrollToInitialMediaPosition(animated: false)
        }

        private func rebuildAssetSections() {
            guard let assets else {
                assetSections = []
                return
            }
            let calendar = Calendar.current
            var filteredAssets: [PHAsset] = []
            assets.enumerateObjects { asset, _, _ in
                guard self.includesAsset(asset) else { return }
                filteredAssets.append(asset)
            }
            filteredAssets.sort { lhs, rhs in
                let leftDate = sortingDate(for: lhs)
                let rightDate = sortingDate(for: rhs)
                if leftDate == rightDate {
                    return isMediaSortAscending
                        ? lhs.localIdentifier < rhs.localIdentifier
                        : lhs.localIdentifier > rhs.localIdentifier
                }
                return isMediaSortAscending
                    ? leftDate < rightDate
                    : leftDate > rightDate
            }

            var dates: [Date] = []
            var grouped: [Date: [PHAsset]] = [:]
            for asset in filteredAssets {
                let day = calendar.startOfDay(for: sortingDate(for: asset))
                if grouped[day] == nil {
                    dates.append(day)
                    grouped[day] = []
                }
                grouped[day]?.append(asset)
            }
            assetSections = dates.compactMap { date in
                guard let dayAssets = grouped[date], !dayAssets.isEmpty else {
                    return nil
                }
                return AssetDaySection(date: date, assets: dayAssets)
            }
        }

        private func sortingDate(for asset: PHAsset) -> Date {
            switch mediaSortMode {
            case .captureDate:
                return asset.creationDate
                    ?? asset.modificationDate
                    ?? .distantPast
            case .addedDate:
                return asset.modificationDate
                    ?? asset.creationDate
                    ?? .distantPast
            }
        }

        private func scrollToInitialMediaPosition(animated: Bool) {
            guard !assetSections.isEmpty else { return }
            if isMediaSortAscending,
               let lastSection = assetSections.indices.last,
               let lastItem = assetSections[lastSection].assets.indices.last {
                collectionView.scrollToItem(
                    at: IndexPath(item: lastItem, section: lastSection),
                    at: .bottom,
                    animated: animated
                )
                return
            }
            guard let firstItem = assetSections[0].assets.indices.first else {
                return
            }
            collectionView.scrollToItem(
                at: IndexPath(item: firstItem, section: 0),
                at: .top,
                animated: animated
            )
        }

        private func includesAsset(_ asset: PHAsset) -> Bool {
            if asset.mediaType == .video {
                guard selectedMediaFilters.contains(.video) else { return false }
                guard let durationFilterSeconds else { return true }
                switch durationFilterComparison {
                case .atLeast:
                    return asset.duration >= durationFilterSeconds
                case .atMost:
                    return asset.duration <= durationFilterSeconds
                }
            }
            if asset.mediaType == .image,
               asset.mediaSubtypes.contains(.photoLive) {
                return selectedMediaFilters.contains(.livePhoto)
            }
            return selectedMediaFilters.contains(.photo)
        }

        private func asset(at indexPath: IndexPath) -> PHAsset? {
            guard assetSections.indices.contains(indexPath.section),
                  assetSections[indexPath.section].assets.indices.contains(
                    indexPath.item
                  ) else { return nil }
            return assetSections[indexPath.section].assets[indexPath.item]
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            assetSections.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            guard assetSections.indices.contains(section) else { return 0 }
            return assetSections[section].assets.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: DragSelectionPhotoCell.reuseID,
                for: indexPath
            ) as? DragSelectionPhotoCell,
                  let asset = asset(at: indexPath)
            else { return UICollectionViewCell() }

            let mediaKind: DragSelectionPhotoCell.MediaKind =
                asset.mediaType == .video
                    ? .video
                    : asset.mediaSubtypes.contains(.photoLive)
                        ? .livePhoto
                        : .photo
            let selectionOrder = selectedIdentifiers.firstIndex(
                of: asset.localIdentifier
            ).map { $0 + 1 }
            cell.representedAssetIdentifier = asset.localIdentifier
            cell.updateSelection(selectionOrder != nil)
            cell.updateMediaKind(mediaKind)
            cell.updateAccessibility(
                mediaKind: mediaKind,
                creationDate: asset.creationDate,
                selectionOrder: selectionOrder
            )
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 240, height: 240),
                contentMode: .aspectFill,
                options: nil
            ) { image, _ in
                guard cell.representedAssetIdentifier
                    == asset.localIdentifier else { return }
                cell.imageView.image = image
            }
            return cell
        }

        func collectionView(
            _ collectionView: UICollectionView,
            viewForSupplementaryElementOfKind kind: String,
            at indexPath: IndexPath
        ) -> UICollectionReusableView {
            guard kind == UICollectionView.elementKindSectionHeader,
                  let header = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: PhotoPickerDateHeader.reuseID,
                    for: indexPath
                  ) as? PhotoPickerDateHeader,
                  assetSections.indices.contains(indexPath.section)
            else { return UICollectionReusableView() }
            header.configure(date: assetSections[indexPath.section].date)
            return header
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            referenceSizeForHeaderInSection section: Int
        ) -> CGSize {
            let font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
                for: .systemFont(ofSize: 13, weight: .semibold),
                maximumPointSize: 18
            )
            return CGSize(
                width: collectionView.bounds.width,
                height: max(42, font.lineHeight + 22)
            )
        }

        func collectionView(
            _ collectionView: UICollectionView,
            didSelectItemAt indexPath: IndexPath
        ) {
            guard !suppressNextTap else { return }
            collectionView.deselectItem(at: indexPath, animated: false)
            toggleAsset(at: indexPath)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            let spacing = CGFloat(max(0, columnCount - 1)) * 2
            let width = floor(
                (collectionView.bounds.width - spacing) / CGFloat(columnCount)
            )
            return CGSize(width: width, height: width)
        }

        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
                return true
            }
            let velocity = pan.velocity(in: collectionView)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer:
                UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer
                || otherGestureRecognizer is UIPinchGestureRecognizer
        }

        @objc private func handleSelectionPan(_ gesture: UIPanGestureRecognizer) {
            dragLocationInView = gesture.location(in: view)
            let point = gesture.location(in: collectionView)
            switch gesture.state {
            case .began:
                guard let indexPath = collectionView.indexPathForItem(
                    at: point
                ), let asset = asset(at: indexPath) else { return }
                dragShouldSelect = !selectedIdentifierSet.contains(
                    asset.localIdentifier
                )
                lastDragIndexPath = indexPath
                suppressNextTap = true
                setAsset(at: indexPath, selected: dragShouldSelect)
                startAutoScroll()

            case .changed:
                continueDragSelection(at: point)

            case .ended, .cancelled, .failed:
                stopAutoScroll()
                dragLocationInView = nil
                lastDragIndexPath = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    self.suppressNextTap = false
                }

            default:
                break
            }
        }

        private func continueDragSelection(at point: CGPoint) {
            guard let indexPath = collectionView.indexPathForItem(at: point),
                  indexPath != lastDragIndexPath else { return }
            applyDragSelection(from: lastDragIndexPath, to: indexPath)
            lastDragIndexPath = indexPath
        }

        private func startAutoScroll() {
            guard autoScrollDisplayLink == nil else { return }
            let link = CADisplayLink(
                target: self,
                selector: #selector(handleAutoScrollFrame(_:))
            )
            link.add(to: .main, forMode: .common)
            autoScrollDisplayLink = link
        }

        private func stopAutoScroll() {
            autoScrollDisplayLink?.invalidate()
            autoScrollDisplayLink = nil
            lastAutoScrollTimestamp = nil
        }

        @objc private func handleAutoScrollFrame(_ link: CADisplayLink) {
            guard let location = dragLocationInView else { return }
            let edgeZone: CGFloat = 105
            let topEdge = collectionView.frame.minY + edgeZone
            let bottomEdge = collectionView.frame.maxY - edgeZone
            let direction: CGFloat
            let edgeProgress: CGFloat

            if location.y < topEdge {
                direction = -1
                edgeProgress = min(1, (topEdge - location.y) / edgeZone)
            } else if location.y > bottomEdge {
                direction = 1
                edgeProgress = min(1, (location.y - bottomEdge) / edgeZone)
            } else {
                lastAutoScrollTimestamp = link.timestamp
                return
            }

            let previousTimestamp = lastAutoScrollTimestamp ?? link.timestamp
            lastAutoScrollTimestamp = link.timestamp
            let elapsed = min(1.0 / 20.0, link.timestamp - previousTimestamp)
            let pointsPerSecond = 120 + 1_180 * pow(edgeProgress, 2)
            let proposedY = collectionView.contentOffset.y
                + direction * pointsPerSecond * elapsed
            let minimumY = -collectionView.adjustedContentInset.top
            let maximumY = max(
                minimumY,
                collectionView.contentSize.height
                    - collectionView.bounds.height
                    + collectionView.adjustedContentInset.bottom
            )
            let clampedY = min(maximumY, max(minimumY, proposedY))
            guard abs(clampedY - collectionView.contentOffset.y) > 0.01
            else { return }

            collectionView.contentOffset.y = clampedY
            collectionView.layoutIfNeeded()

            var collectionPoint = collectionView.convert(location, from: view)
            collectionPoint.x = min(
                collectionView.bounds.maxX - 1,
                max(collectionView.bounds.minX + 1, collectionPoint.x)
            )
            collectionPoint.y = direction < 0
                ? collectionView.bounds.minY + 2
                : collectionView.bounds.maxY - 2
            continueDragSelection(at: collectionPoint)
        }

        @objc private func handleGridPinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed else { return }
            if gesture.scale > 1.18 {
                changeColumnCount(towardLargerItems: true)
                gesture.scale = 1
            } else if gesture.scale < 0.82 {
                changeColumnCount(towardLargerItems: false)
                gesture.scale = 1
            }
        }

        @objc private func handleMediaPreviewLongPress(
            _ gesture: UILongPressGestureRecognizer
        ) {
            guard gesture.state == .began,
                  presentedViewController == nil else { return }
            let point = gesture.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: point),
                  let asset = asset(at: indexPath) else { return }
            let sourcePoint = collectionView.convert(point, to: nil)
            let isSelected = selectedIdentifierSet.contains(asset.localIdentifier)

            let imageAssets = assetSections.flatMap(\.assets).filter { $0.mediaType == .image }
            let preview = MediaAssetPreviewViewController(
                asset: asset,
                imageAssets: imageAssets,
                startSelectedIdentifier: asset.localIdentifier,
                imageManager: imageManager,
                showsCloseButton: false,
                sourcePoint: sourcePoint,
                onDeleteAssetIdentifier: isSelected
                    ? { [weak self] currentID in
                        self?.deselectAsset(identifier: currentID)
                    }
                    : nil
            )
            preview.modalPresentationStyle = .overFullScreen
            preview.modalTransitionStyle = .crossDissolve
            present(preview, animated: true)
        }

        private func deselectAsset(identifier: String) {
            selectedIdentifierSet.remove(identifier)
            selectedIdentifiers.removeAll { $0 == identifier }
            for case let cell as DragSelectionPhotoCell
                in collectionView.visibleCells
            where cell.representedAssetIdentifier == identifier {
                cell.updateSelection(false)
            }
            updateSelectionCount()
        }

        private func changeColumnCount(towardLargerItems: Bool) {
            let stops = [1, 3, 5, 8]
            guard let currentIndex = stops.firstIndex(of: columnCount) else {
                columnCount = 5
                return
            }
            let nextIndex = towardLargerItems
                ? max(0, currentIndex - 1)
                : min(stops.count - 1, currentIndex + 1)
            guard nextIndex != currentIndex else { return }

            let centerPoint = CGPoint(
                x: collectionView.bounds.midX,
                y: collectionView.bounds.midY
            )
            let anchor = collectionView.indexPathForItem(at: centerPoint)
            columnCount = stops[nextIndex]
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            if let anchor {
                collectionView.scrollToItem(
                    at: anchor,
                    at: .centeredVertically,
                    animated: false
                )
            }
        }

        private func applyDragSelection(
            from previous: IndexPath?,
            to current: IndexPath
        ) {
            let startIndexPath = previous ?? current
            guard let start = linearIndex(for: startIndexPath),
                  let end = linearIndex(for: current) else { return }
            let lower = min(start, end)
            let upper = max(start, end)
            for index in lower...upper {
                guard let indexPath = indexPath(forLinearIndex: index) else {
                    continue
                }
                setAsset(at: indexPath, selected: dragShouldSelect)
            }
        }

        private func linearIndex(for indexPath: IndexPath) -> Int? {
            guard assetSections.indices.contains(indexPath.section),
                  assetSections[indexPath.section].assets.indices.contains(
                    indexPath.item
                  ) else { return nil }
            let precedingCount = assetSections.prefix(indexPath.section)
                .reduce(0) { $0 + $1.assets.count }
            return precedingCount + indexPath.item
        }

        private func indexPath(forLinearIndex target: Int) -> IndexPath? {
            guard target >= 0 else { return nil }
            var offset = target
            for (section, daySection) in assetSections.enumerated() {
                if offset < daySection.assets.count {
                    return IndexPath(item: offset, section: section)
                }
                offset -= daySection.assets.count
            }
            return nil
        }

        private func toggleAsset(at indexPath: IndexPath) {
            guard let asset = asset(at: indexPath) else { return }
            setAsset(
                at: indexPath,
                selected: !selectedIdentifierSet.contains(asset.localIdentifier)
            )
        }

        private func setAsset(at indexPath: IndexPath, selected: Bool) {
            guard let asset = asset(at: indexPath) else { return }
            let identifier = asset.localIdentifier
            if selected {
                guard selectedIdentifierSet.insert(identifier).inserted else {
                    return
                }
                selectedIdentifiers.append(identifier)
            } else {
                guard selectedIdentifierSet.remove(identifier) != nil else {
                    return
                }
                selectedIdentifiers.removeAll { $0 == identifier }
            }
            (collectionView.cellForItem(at: indexPath)
                as? DragSelectionPhotoCell)?.updateSelection(selected)
            updateVisibleCellAccessibility()
            updateSelectionCount()
        }

        private func updateVisibleCellAccessibility() {
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let asset = asset(at: indexPath),
                      let cell = collectionView.cellForItem(at: indexPath)
                        as? DragSelectionPhotoCell
                else { continue }
                let mediaKind: DragSelectionPhotoCell.MediaKind =
                    asset.mediaType == .video
                        ? .video
                        : asset.mediaSubtypes.contains(.photoLive)
                            ? .livePhoto
                            : .photo
                cell.updateAccessibility(
                    mediaKind: mediaKind,
                    creationDate: asset.creationDate,
                    selectionOrder: selectedIdentifiers.firstIndex(
                        of: asset.localIdentifier
                    ).map { $0 + 1 }
                )
            }
        }

        private func updateSelectionCount() {
            let count = selectedIdentifiers.count
            updateDoneButtonTitle("추가")
            doneButton.isEnabled = count > 0
            doneButton.alpha = count > 0 ? 1 : 0.34
            doneButton.accessibilityValue = "\(count)개 선택"
            doneButton.setTitleColor(
                count > 0
                    ? HanClipTheme.primaryUIColor
                    : UIColor(HanClipTheme.text).withAlphaComponent(0.35),
                for: .normal
            )
            headerDoneButton.setTitle("\(count)개 추가", for: .normal)
            headerDoneButton.isEnabled = count > 0
            headerDoneButton.setTitleColor(
                UIColor(HanClipTheme.text).withAlphaComponent(0.72),
                for: .normal
            )
            clearSelectionButton.isEnabled = count > 0
            clearSelectionButton.alpha = count > 0 ? 1 : 0.34
        }

        private func updateDoneButtonTitle(_ title: String) {
            doneButton.setTitle(title, for: .normal)
            headerDoneButton.setTitle(title, for: .normal)
        }

        @objc private func todayTapped() {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            guard let section = assetSections.firstIndex(where: {
                calendar.isDate($0.date, inSameDayAs: today)
            }) else {
                resetTodayButtonState()
                if let latestSection = assetSections.indices.last {
                    scrollToSection(latestSection, animated: true)
                }
                return
            }

            if isTodayButtonArmedForSelection {
                selectAllAssets(in: section)
                resetTodayButtonState()
            } else {
                scrollToSection(section, animated: true)
                isTodayButtonArmedForSelection = true
                updateTodayButtonAppearance()
            }
        }

        @objc private func previousDayTapped() {
            resetTodayButtonState()
            guard let section = previousDayTargetSection() else { return }
            scrollToSection(section, animated: true)
            selectAllAssets(in: section)
        }

        private func previousDayTargetSection() -> Int? {
            let calendar = Calendar.current
            if selectedIdentifiers.isEmpty {
                let yesterday = calendar.date(
                    byAdding: .day,
                    value: -1,
                    to: calendar.startOfDay(for: Date())
                ) ?? Date()
                return assetSections.indices.min { left, right in
                    abs(assetSections[left].date.timeIntervalSince(yesterday))
                        < abs(
                            assetSections[right].date.timeIntervalSince(yesterday)
                        )
                }
            }

            let selectedAssets = PHAsset.fetchAssets(
                withLocalIdentifiers: selectedIdentifiers,
                options: nil
            )
            var earliestSelectedDate: Date?
            selectedAssets.enumerateObjects { asset, _, _ in
                guard let creationDate = asset.creationDate else { return }
                if earliestSelectedDate == nil
                    || creationDate < earliestSelectedDate! {
                    earliestSelectedDate = creationDate
                }
            }
            guard let earliestSelectedDate else { return nil }
            let baseDay = calendar.startOfDay(for: earliestSelectedDate)
            return assetSections.indices.last(where: {
                assetSections[$0].date < baseDay
            })
        }

        private func scrollToSection(_ section: Int, animated: Bool) {
            guard assetSections.indices.contains(section) else { return }
            collectionView.layoutIfNeeded()
            let indexPath = IndexPath(item: 0, section: section)
            if let attributes = collectionView.collectionViewLayout
                .layoutAttributesForSupplementaryView(
                    ofKind: UICollectionView.elementKindSectionHeader,
                    at: indexPath
                ) {
                let minimumY = -collectionView.adjustedContentInset.top
                let maximumY = max(
                    minimumY,
                    collectionView.contentSize.height
                        - collectionView.bounds.height
                        + collectionView.adjustedContentInset.bottom
                )
                let targetY = min(
                    maximumY,
                    max(
                        minimumY,
                        attributes.frame.minY
                            - collectionView.adjustedContentInset.top
                    )
                )
                collectionView.setContentOffset(
                    CGPoint(x: 0, y: targetY),
                    animated: animated
                )
            } else {
                collectionView.scrollToItem(
                    at: indexPath,
                    at: .top,
                    animated: animated
                )
            }
        }

        private func selectAllAssets(in section: Int) {
            guard assetSections.indices.contains(section) else { return }
            for asset in assetSections[section].assets {
                let identifier = asset.localIdentifier
                guard selectedIdentifierSet.insert(identifier).inserted else {
                    continue
                }
                selectedIdentifiers.append(identifier)
            }
            for case let cell as DragSelectionPhotoCell
                in collectionView.visibleCells {
                guard let identifier = cell.representedAssetIdentifier else {
                    continue
                }
                cell.updateSelection(selectedIdentifierSet.contains(identifier))
            }
            updateVisibleCellAccessibility()
            updateSelectionCount()
        }

        private func resetTodayButtonState() {
            guard isTodayButtonArmedForSelection else { return }
            isTodayButtonArmedForSelection = false
            updateTodayButtonAppearance()
        }

        private func updateTodayButtonAppearance() {
            if isTodayButtonArmedForSelection {
                todayButton.backgroundColor = HanClipTheme.primaryUIColor
                    .withAlphaComponent(0.18)
                todayButton.layer.borderColor = HanClipTheme.primaryUIColor
                    .withAlphaComponent(0.50).cgColor
                todayButton.accessibilityValue = "오늘 미디어 선택 준비"
            } else {
                todayButton.backgroundColor = UIColor(HanClipTheme.background)
                    .withAlphaComponent(0.86)
                todayButton.layer.borderColor = HanClipTheme.secondaryUIColor
                    .withAlphaComponent(0.34).cgColor
                todayButton.accessibilityValue = nil
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            resetTodayButtonState()
        }

        @objc private func cancelTapped() {
            onCancel()
        }

        @objc private func clearSelectionTapped() {
            guard !selectedIdentifiers.isEmpty else { return }
            selectedIdentifiers.removeAll(keepingCapacity: true)
            selectedIdentifierSet.removeAll(keepingCapacity: true)
            for case let cell as DragSelectionPhotoCell
                in collectionView.visibleCells {
                cell.updateSelection(false)
            }
            updateVisibleCellAccessibility()
            updateSelectionCount()
        }

        @objc private func doneTapped() {
            guard !selectedIdentifiers.isEmpty else { return }
            onDone(selectedIdentifiers)
        }

        deinit {
            autoScrollDisplayLink?.invalidate()
        }
    }

    final class PhotoPickerDateHeader: UICollectionReusableView {
        static let reuseID = "PhotoPickerDateHeader"
        private let dateLabel = UILabel()
        private static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "yyyy년 M월 d일 EEEE"
            return formatter
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = UIColor(HanClipTheme.background)
            dateLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
                for: .systemFont(ofSize: 13, weight: .semibold),
                maximumPointSize: 18
            )
            dateLabel.adjustsFontForContentSizeCategory = true
            dateLabel.textColor = UIColor(HanClipTheme.text).withAlphaComponent(0.84)
            dateLabel.backgroundColor = HanClipTheme.secondaryUIColor
                .withAlphaComponent(0.12)
            dateLabel.layer.cornerRadius = 8
            dateLabel.clipsToBounds = true
            dateLabel.textAlignment = .center
            dateLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(dateLabel)
            NSLayoutConstraint.activate([
                dateLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                dateLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
                dateLabel.bottomAnchor.constraint(
                    equalTo: bottomAnchor,
                    constant: -5
                ),
                dateLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 165)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(date: Date) {
            dateLabel.text = "  \(Self.formatter.string(from: date))  "
        }
    }

    private final class MediaPreviewIconButton: UIButton {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            let touchArea = bounds.insetBy(
                dx: min(0, (bounds.width - 48) / 2),
                dy: min(0, (bounds.height - 48) / 2)
            )
            return touchArea.contains(point)
        }
    }

    final class MediaAssetPreviewViewController: UIViewController,
        UIScrollViewDelegate,
        UIGestureRecognizerDelegate {
        private let imageAssets: [PHAsset]
        private var currentImageIndex: Int = 0
        private var currentAsset: PHAsset {
            if !imageAssets.isEmpty, currentImageIndex >= 0, currentImageIndex < imageAssets.count {
                return imageAssets[currentImageIndex]
            }
            return asset
        }
        private let asset: PHAsset
        private let imageManager: PHImageManager
        private let showsCloseButton: Bool
        private let sourcePoint: CGPoint?
        private let onDelete: (() -> Void)?
        private let onDeleteAssetIdentifier: ((String) -> Void)?
        private let onDismiss: (() -> Void)?

        private let previewSurfaceView = UIView()
        private let scrollView = UIScrollView()
        private let imageView = UIImageView()
        private let livePhotoView = PHLivePhotoView()
        private var videoHostingController: UIViewController?
        private var videoPlayer: AVPlayer?

        private let loadingIndicator = UIActivityIndicatorView(style: .large)
        private let errorContainerView = UIView()
        private let errorMessageLabel = UILabel()
        private let retryButton = UIButton(type: .system)

        private let topBarView = UIView()
        private var topCloseButton: MediaPreviewIconButton!
        private let titleLabel = UILabel()
        private var topShareButton: MediaPreviewIconButton!
        private let topDeleteButton = UIButton(type: .system)

        private let bottomBarView = UIView()
        private var previousButton: MediaPreviewIconButton!
        private var imagePlayPauseButton: MediaPreviewIconButton!
        private var nextButton: MediaPreviewIconButton!
        private var settingsButton: MediaPreviewIconButton!

        private var livePhotoPlayButton: MediaPreviewIconButton?
        private let livePhotoProgressView = UIProgressView(progressViewStyle: .bar)
        private var livePhotoProgressTimer: Timer?
        private var livePhotoPlaybackStartedAt: Date?
        private var isLivePhotoPlaying = false

        private var isSlidePlaying: Bool = false
        private var slideTimer: Timer?
        private var controlsHideTimer: Timer?
        private var areControlsVisible: Bool = true
        private var currentImageRequestID: PHImageRequestID?
        private var panIsVerticalDismiss: Bool = false
        private var isImageLoading: Bool = true

        init(
            asset: PHAsset,
            imageAssets: [PHAsset]? = nil,
            startSelectedIdentifier: String? = nil,
            imageManager: PHImageManager,
            showsCloseButton: Bool = false,
            sourcePoint: CGPoint? = nil,
            onDelete: (() -> Void)? = nil,
            onDeleteAssetIdentifier: ((String) -> Void)? = nil,
            onDismiss: (() -> Void)? = nil
        ) {
            self.asset = asset
            self.imageManager = imageManager
            self.showsCloseButton = showsCloseButton
            self.sourcePoint = sourcePoint
            self.onDelete = onDelete
            self.onDeleteAssetIdentifier = onDeleteAssetIdentifier
            self.onDismiss = onDismiss

            let resolvedAssets: [PHAsset]
            if asset.mediaType == .video {
                resolvedAssets = []
            } else if let imageAssets, !imageAssets.isEmpty {
                resolvedAssets = imageAssets.filter { $0.mediaType == .image }
            } else if asset.mediaType == .image {
                resolvedAssets = [asset]
            } else {
                resolvedAssets = []
            }
            self.imageAssets = resolvedAssets

            let targetID = startSelectedIdentifier ?? asset.localIdentifier
            if let foundIndex = resolvedAssets.firstIndex(where: { $0.localIdentifier == targetID }) {
                self.currentImageIndex = foundIndex
            } else if let foundAssetIndex = resolvedAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
                self.currentImageIndex = foundAssetIndex
            } else {
                self.currentImageIndex = 0
            }

            super.init(nibName: nil, bundle: nil)
            modalPresentationStyle = .fullScreen
        }

        convenience init(
            asset: PHAsset,
            imageManager: PHImageManager,
            showsCloseButton: Bool = false,
            sourcePoint: CGPoint? = nil,
            onDelete: (() -> Void)? = nil,
            onDismiss: (() -> Void)? = nil
        ) {
            self.init(
                asset: asset,
                imageAssets: nil,
                startSelectedIdentifier: nil,
                imageManager: imageManager,
                showsCloseButton: showsCloseButton,
                sourcePoint: sourcePoint,
                onDelete: onDelete,
                onDeleteAssetIdentifier: nil,
                onDismiss: onDismiss
            )
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
        }

        override var shouldAutorotate: Bool {
            true
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configurePreviewSurface()

            if asset.mediaType == .video {
                configureVideoPreview()
            } else if asset.mediaSubtypes.contains(.photoLive) {
                configureLivePhotoPreview()
            } else {
                configureStillPhotoPreview()
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppWillResignActive),
                name: UIApplication.willResignActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            stopSlideShow()
            controlsHideTimer?.invalidate()
            controlsHideTimer = nil
            livePhotoView.stopPlayback()
            stopLivePhotoProgress()
            videoPlayer?.pause()
        }

        deinit {
            slideTimer?.invalidate()
            controlsHideTimer?.invalidate()
            livePhotoProgressTimer?.invalidate()
            if let currentImageRequestID {
                imageManager.cancelImageRequest(currentImageRequestID)
            }
            NotificationCenter.default.removeObserver(self)
        }

        private func configurePreviewSurface() {
            previewSurfaceView.backgroundColor = .black
            previewSurfaceView.clipsToBounds = true
            previewSurfaceView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(previewSurfaceView)
            NSLayoutConstraint.activate([
                previewSurfaceView.topAnchor.constraint(equalTo: view.topAnchor),
                previewSurfaceView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                previewSurfaceView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                previewSurfaceView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])

            loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
            loadingIndicator.color = .white
            loadingIndicator.hidesWhenStopped = true
            view.addSubview(loadingIndicator)
            NSLayoutConstraint.activate([
                loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])

            configureErrorView()
        }

        private func configureErrorView() {
            errorContainerView.translatesAutoresizingMaskIntoConstraints = false
            errorContainerView.backgroundColor = UIColor.black.withAlphaComponent(0.75)
            errorContainerView.layer.cornerRadius = 16
            errorContainerView.layer.borderWidth = 1
            errorContainerView.layer.borderColor = UIColor.white.withAlphaComponent(0.20).cgColor
            errorContainerView.isHidden = true
            view.addSubview(errorContainerView)

            errorMessageLabel.font = .systemFont(ofSize: 14, weight: .medium)
            errorMessageLabel.textColor = .white
            errorMessageLabel.textAlignment = .center
            errorMessageLabel.numberOfLines = 2
            errorMessageLabel.translatesAutoresizingMaskIntoConstraints = false

            retryButton.setTitle("다시 시도", for: .normal)
            retryButton.setTitleColor(.white, for: .normal)
            retryButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
            retryButton.backgroundColor = HanClipTheme.primaryUIColor
            retryButton.layer.cornerRadius = 14
            retryButton.translatesAutoresizingMaskIntoConstraints = false

            let errorCloseButton = UIButton(type: .system)
            errorCloseButton.setTitle("닫기", for: .normal)
            errorCloseButton.setTitleColor(.white, for: .normal)
            errorCloseButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            errorCloseButton.backgroundColor = UIColor.white.withAlphaComponent(0.18)
            errorCloseButton.layer.cornerRadius = 14
            errorCloseButton.addTarget(self, action: #selector(closePreview), for: .touchUpInside)
            errorCloseButton.translatesAutoresizingMaskIntoConstraints = false

            let buttonStack = UIStackView(arrangedSubviews: [retryButton, errorCloseButton])
            buttonStack.axis = .horizontal
            buttonStack.spacing = 10
            buttonStack.distribution = .fillEqually
            buttonStack.translatesAutoresizingMaskIntoConstraints = false

            let contentStack = UIStackView(arrangedSubviews: [errorMessageLabel, buttonStack])
            contentStack.axis = .vertical
            contentStack.spacing = 14
            contentStack.translatesAutoresizingMaskIntoConstraints = false
            errorContainerView.addSubview(contentStack)

            NSLayoutConstraint.activate([
                errorContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                errorContainerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                errorContainerView.widthAnchor.constraint(lessThanOrEqualToConstant: 280),

                contentStack.topAnchor.constraint(equalTo: errorContainerView.topAnchor, constant: 18),
                contentStack.bottomAnchor.constraint(equalTo: errorContainerView.bottomAnchor, constant: -18),
                contentStack.leadingAnchor.constraint(equalTo: errorContainerView.leadingAnchor, constant: 18),
                contentStack.trailingAnchor.constraint(equalTo: errorContainerView.trailingAnchor, constant: -18),
                retryButton.heightAnchor.constraint(equalToConstant: 40),
                errorCloseButton.heightAnchor.constraint(equalToConstant: 40)
            ])
        }

        private let retryActionIdentifier = UIAction.Identifier("hanclip.preview.retry")

        private func showError(message: String, retryAction: @escaping () -> Void) {
            errorMessageLabel.text = message
            retryButton.removeAction(identifiedBy: retryActionIdentifier, for: .touchUpInside)
            retryButton.addAction(UIAction(identifier: retryActionIdentifier) { [weak self] _ in
                self?.errorContainerView.isHidden = true
                retryAction()
            }, for: .touchUpInside)
            errorContainerView.isHidden = false
        }

        private func makeCircleButton(
            systemName: String,
            accessibilityLabel: String
        ) -> MediaPreviewIconButton {
            let button = MediaPreviewIconButton(type: .system)
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
            button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
            button.layer.cornerRadius = 22
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
            button.clipsToBounds = true
            button.accessibilityLabel = accessibilityLabel
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 44),
                button.heightAnchor.constraint(equalToConstant: 44)
            ])
            return button
        }

        private func configureTopBar() {
            guard topBarView.superview == nil else {
                updateTitle()
                return
            }
            topBarView.translatesAutoresizingMaskIntoConstraints = false
            topBarView.backgroundColor = .clear
            view.addSubview(topBarView)

            topCloseButton = makeCircleButton(systemName: "xmark", accessibilityLabel: "닫기")
            topCloseButton.addTarget(self, action: #selector(closePreview), for: .touchUpInside)
            topBarView.addSubview(topCloseButton)

            titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
            titleLabel.textColor = .white
            titleLabel.textAlignment = .center
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            topBarView.addSubview(titleLabel)

            topShareButton = makeCircleButton(systemName: "square.and.arrow.up", accessibilityLabel: "공유")
            topShareButton.addTarget(self, action: #selector(handleShareTapped), for: .touchUpInside)
            topBarView.addSubview(topShareButton)

            let hasDeleteHandler = onDelete != nil || onDeleteAssetIdentifier != nil
            if hasDeleteHandler {
                topDeleteButton.setTitle("선택 해제", for: .normal)
                topDeleteButton.setTitleColor(UIColor(HanClipTheme.onSecondary), for: .normal)
                topDeleteButton.titleLabel?.font = HanClipTypography.uiFont(textStyle: .footnote, weight: .semibold)
                topDeleteButton.backgroundColor = HanClipTheme.secondaryUIColor.withAlphaComponent(0.86)
                topDeleteButton.layer.cornerRadius = 18
                topDeleteButton.layer.cornerCurve = .continuous
                topDeleteButton.accessibilityLabel = "선택에서 제거"
                topDeleteButton.addTarget(self, action: #selector(deletePreviewItem), for: .touchUpInside)
                topDeleteButton.translatesAutoresizingMaskIntoConstraints = false
                topBarView.addSubview(topDeleteButton)

                NSLayoutConstraint.activate([
                    topDeleteButton.trailingAnchor.constraint(equalTo: topShareButton.leadingAnchor, constant: -10),
                    topDeleteButton.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
                    topDeleteButton.heightAnchor.constraint(equalToConstant: 44),
                    topDeleteButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
                ])
            }

            NSLayoutConstraint.activate([
                topBarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
                topBarView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
                topBarView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
                topBarView.heightAnchor.constraint(equalToConstant: 44),

                topCloseButton.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor),
                topCloseButton.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),

                titleLabel.centerXAnchor.constraint(equalTo: topBarView.centerXAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
                titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: topCloseButton.trailingAnchor, constant: 8),

                topShareButton.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor),
                topShareButton.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor)
            ])

            updateTitle()
        }

        private func configureBottomBar() {
            bottomBarView.translatesAutoresizingMaskIntoConstraints = false
            bottomBarView.backgroundColor = .clear
            view.addSubview(bottomBarView)

            previousButton = makeCircleButton(systemName: "chevron.left", accessibilityLabel: "이전")
            previousButton.addTarget(self, action: #selector(advancePreviousImage), for: .touchUpInside)

            imagePlayPauseButton = makeCircleButton(systemName: "play.fill", accessibilityLabel: "재생")
            imagePlayPauseButton.addTarget(self, action: #selector(toggleImageSlidePlayback), for: .touchUpInside)

            nextButton = makeCircleButton(systemName: "chevron.right", accessibilityLabel: "다음")
            nextButton.addTarget(self, action: #selector(advanceNextImage), for: .touchUpInside)

            settingsButton = makeCircleButton(systemName: "slider.horizontal.3", accessibilityLabel: "설정")
            configureSettingsMenu()

            let stack = UIStackView(arrangedSubviews: [
                previousButton,
                imagePlayPauseButton,
                nextButton,
                settingsButton
            ])
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = 16
            stack.translatesAutoresizingMaskIntoConstraints = false
            bottomBarView.addSubview(stack)

            NSLayoutConstraint.activate([
                bottomBarView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
                bottomBarView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                bottomBarView.heightAnchor.constraint(equalToConstant: 48),

                stack.topAnchor.constraint(equalTo: bottomBarView.topAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomBarView.bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor)
            ])

            updateImagePlayPauseButton()
        }

        private func configureSettingsMenu() {
            let currentInterval = HanClipCommonPlayerPreferences.imageInterval
            let currentMode = HanClipCommonPlayerPreferences.imageRepeatMode

            let intervalActions = HanClipCommonPlayerPreferences.imageIntervalOptions.map { seconds in
                UIAction(
                    title: "\(Int(seconds))초",
                    state: abs(currentInterval - seconds) < 0.01 ? .on : .off
                ) { [weak self] _ in
                    HanClipCommonPlayerPreferences.imageInterval = seconds
                    self?.configureSettingsMenu()
                    if self?.isSlidePlaying == true {
                        self?.restartSlideTimer()
                    }
                }
            }
            let intervalMenu = UIMenu(
                title: "재생 간격",
                options: .displayInline,
                children: intervalActions
            )

            let modeActions = HanClipImageRepeatMode.allCases.map { mode in
                UIAction(
                    title: mode.title,
                    state: currentMode == mode ? .on : .off
                ) { [weak self] _ in
                    HanClipCommonPlayerPreferences.imageRepeatMode = mode
                    self?.configureSettingsMenu()
                }
            }
            let modeMenu = UIMenu(
                title: "반복 모드",
                options: .displayInline,
                children: modeActions
            )

            settingsButton.menu = UIMenu(
                title: "슬라이드쇼 설정",
                children: [intervalMenu, modeMenu]
            )
            settingsButton.showsMenuAsPrimaryAction = true
        }

        private func configureStillPhotoPreview() {
            scrollView.delegate = self
            scrollView.minimumZoomScale = 1.0
            scrollView.maximumZoomScale = 6.0
            scrollView.backgroundColor = .black
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            previewSurfaceView.addSubview(scrollView)

            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(imageView)

            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: previewSurfaceView.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: previewSurfaceView.bottomAnchor),
                scrollView.leadingAnchor.constraint(equalTo: previewSurfaceView.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: previewSurfaceView.trailingAnchor),

                imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
                imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
            ])

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleImageDoubleTap))
            doubleTap.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(doubleTap)

            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleImageSingleTap))
            singleTap.numberOfTapsRequired = 1
            singleTap.require(toFail: doubleTap)
            scrollView.addGestureRecognizer(singleTap)

            configureTopBar()
            configureBottomBar()
            configurePanGesture()

            loadCurrentImage()
        }

        private func configureVideoPreview() {
            configureTopBar()
            topShareButton.isHidden = true
            bottomBarView.isHidden = true
            loadingIndicator.startAnimating()

            if let videoHostingController {
                videoHostingController.willMove(toParent: nil)
                videoHostingController.view.removeFromSuperview()
                videoHostingController.removeFromParent()
                self.videoHostingController = nil
            }
            videoPlayer?.pause()
            videoPlayer = nil

            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.version = .current
            options.isNetworkAccessAllowed = true

            imageManager.requestPlayerItem(
                forVideo: asset,
                options: options
            ) { [weak self] playerItem, info in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.loadingIndicator.stopAnimating()
                    if let playerItem {
                        self.embedFullscreenVideoPlayer(with: playerItem)
                    } else {
                        let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                        if !isDegraded {
                            self.showError(message: "동영상을 불러올 수 없습니다.") { [weak self] in
                                self?.configureVideoPreview()
                            }
                        }
                    }
                }
            }
        }

        private func embedFullscreenVideoPlayer(with playerItem: AVPlayerItem) {
            let player = AVPlayer(playerItem: playerItem)
            self.videoPlayer = player

            let shareURL = (playerItem.asset as? AVURLAsset)?.url.isFileURL == true ? (playerItem.asset as? AVURLAsset)?.url : nil
            let config = HanClipFullscreenPlayerConfiguration(
                title: assetTitle(for: asset),
                shareURL: shareURL,
                autoplay: true,
                loop: HanClipCommonPlayerPreferences.isVideoLooping,
                showsLoopControl: true,
                allowsAspectModeToggle: true
            )

            let playerView = HanClipFullscreenVideoPlayer(
                player: player,
                configuration: config,
                onClose: { [weak self] in
                    self?.closePreview()
                }
            )

            let hostingController = UIHostingController(rootView: playerView)
            self.videoHostingController = hostingController
            addChild(hostingController)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.backgroundColor = .black
            previewSurfaceView.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: previewSurfaceView.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: previewSurfaceView.bottomAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: previewSurfaceView.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: previewSurfaceView.trailingAnchor)
            ])
            hostingController.didMove(toParent: self)

            topBarView.isHidden = true
        }

        private func configureLivePhotoPreview() {
            configureTopBar()
            configureLivePhotoControls()
            configurePanGesture()

            loadingIndicator.startAnimating()
            if livePhotoView.superview == nil {
                livePhotoView.contentMode = .scaleAspectFit
                livePhotoView.translatesAutoresizingMaskIntoConstraints = false
                previewSurfaceView.addSubview(livePhotoView)
                NSLayoutConstraint.activate([
                    livePhotoView.topAnchor.constraint(equalTo: previewSurfaceView.topAnchor),
                    livePhotoView.bottomAnchor.constraint(equalTo: previewSurfaceView.bottomAnchor),
                    livePhotoView.leadingAnchor.constraint(equalTo: previewSurfaceView.leadingAnchor),
                    livePhotoView.trailingAnchor.constraint(equalTo: previewSurfaceView.trailingAnchor)
                ])
            }

            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            imageManager.requestLivePhoto(
                for: asset,
                targetSize: CGSize(width: 1_800, height: 1_800),
                contentMode: .aspectFit,
                options: options
            ) { [weak self] livePhoto, info in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.loadingIndicator.stopAnimating()
                    if let livePhoto {
                        self.livePhotoView.livePhoto = livePhoto
                        self.startLivePhotoPlayback()
                    } else {
                        let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                        if !isDegraded {
                            self.showError(message: "라이브 포토를 불러올 수 없습니다.") { [weak self] in
                                self?.configureLivePhotoPreview()
                            }
                        }
                    }
                }
            }
        }

        private func configureLivePhotoControls() {
            bottomBarView.isHidden = true
            guard livePhotoPlayButton == nil else { return }

            let liveControls = UIStackView()
            liveControls.axis = .horizontal
            liveControls.alignment = .center
            liveControls.spacing = 12
            liveControls.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(liveControls)

            let playButton = makeCircleButton(systemName: "play.fill", accessibilityLabel: "라이브 포토 재생")
            playButton.addTarget(self, action: #selector(toggleLivePhotoPlayback), for: .touchUpInside)
            self.livePhotoPlayButton = playButton

            livePhotoProgressView.progressTintColor = UIColor(HanClipTheme.primary)
            livePhotoProgressView.trackTintColor = UIColor.white.withAlphaComponent(0.24)
            livePhotoProgressView.translatesAutoresizingMaskIntoConstraints = false

            liveControls.addArrangedSubview(playButton)
            liveControls.addArrangedSubview(livePhotoProgressView)

            NSLayoutConstraint.activate([
                liveControls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
                liveControls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
                liveControls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
                liveControls.heightAnchor.constraint(equalToConstant: 48),
                livePhotoProgressView.heightAnchor.constraint(equalToConstant: 4)
            ])
        }

        private func configurePanGesture() {
            if let recognizers = view.gestureRecognizers, recognizers.contains(where: { $0 is UIPanGestureRecognizer }) {
                return
            }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            pan.delegate = self
            view.addGestureRecognizer(pan)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if scrollView.zoomScale > 1.01 {
                return false
            }
            return true
        }

        @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
            if scrollView.zoomScale > 1.01 { return }

            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .began:
                panIsVerticalDismiss = false
            case .changed:
                if !panIsVerticalDismiss {
                    if translation.y > 12 && abs(translation.y) > abs(translation.x) {
                        panIsVerticalDismiss = true
                    }
                }
                if panIsVerticalDismiss {
                    let offsetY = max(translation.y, 0)
                    previewSurfaceView.transform = CGAffineTransform(translationX: 0, y: offsetY)
                    let height = view.bounds.height > 0 ? view.bounds.height : 600
                    let opacity = max(0.4, 1.0 - (offsetY / height) * 0.9)
                    view.backgroundColor = UIColor.black.withAlphaComponent(opacity)
                }
            case .ended, .cancelled:
                if panIsVerticalDismiss {
                    if translation.y > 120 {
                        closePreview()
                    } else {
                        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                            self.previewSurfaceView.transform = .identity
                            self.view.backgroundColor = .black
                        }
                    }
                    panIsVerticalDismiss = false
                } else if !asset.mediaSubtypes.contains(.photoLive) {
                    if translation.x < -60 {
                        advanceNextImage()
                    } else if translation.x > 60 {
                        advancePreviousImage()
                    }
                }
            default:
                break
            }
        }

        @objc private func handleImageSingleTap() {
            revealControls()
        }

        @objc private func handleImageDoubleTap() {
            let isDefaultScale = abs(scrollView.zoomScale - scrollView.minimumZoomScale) < 0.01
            let isDefaultCenter = abs(scrollView.contentOffset.x) <= 0.01 && abs(scrollView.contentOffset.y) <= 0.01

            if !isDefaultScale || !isDefaultCenter {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                scrollView.setContentOffset(.zero, animated: true)
            } else {
                toggleImageSlidePlayback()
            }
        }

        private func revealControls() {
            setControlsVisible(true, animated: true)
        }

        private func setControlsVisible(_ visible: Bool, animated: Bool) {
            areControlsVisible = visible
            controlsHideTimer?.invalidate()
            controlsHideTimer = nil

            let updates = {
                self.topBarView.alpha = visible ? 1.0 : 0.0
                self.bottomBarView.alpha = visible ? 1.0 : 0.0
                self.topBarView.isUserInteractionEnabled = visible
                self.bottomBarView.isUserInteractionEnabled = visible
            }

            if animated {
                UIView.animate(withDuration: 0.20, animations: updates)
            } else {
                updates()
            }

            if visible && isSlidePlaying {
                scheduleControlsHide()
            }
        }

        private func scheduleControlsHide() {
            controlsHideTimer?.invalidate()
            guard isSlidePlaying, !UIAccessibility.isVoiceOverRunning, !isImageLoading, imageView.image != nil, errorContainerView.isHidden, !scrollView.isZooming, !scrollView.isZoomBouncing, !scrollView.isDragging, !scrollView.isDecelerating else { return }
            controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
                guard let self, self.isSlidePlaying, !UIAccessibility.isVoiceOverRunning, !self.isImageLoading, self.imageView.image != nil, self.errorContainerView.isHidden, !self.scrollView.isZooming, !self.scrollView.isZoomBouncing, !self.scrollView.isDragging, !self.scrollView.isDecelerating else { return }
                self.setControlsVisible(false, animated: true)
            }
        }

        @objc private func handleShareTapped() {
            guard let currentImage = imageView.image else { return }
            let activityVC = UIActivityViewController(
                activityItems: [currentImage],
                applicationActivities: nil
            )
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topShareButton
                popover.sourceRect = topShareButton.bounds
            }
            present(activityVC, animated: true)
        }

        @objc private func closePreview() {
            stopSlideShow()
            controlsHideTimer?.invalidate()
            controlsHideTimer = nil
            videoPlayer?.pause()
            videoPlayer = nil
            if let videoHostingController {
                videoHostingController.willMove(toParent: nil)
                videoHostingController.view.removeFromSuperview()
                videoHostingController.removeFromParent()
                self.videoHostingController = nil
            }
            if let onDismiss {
                onDismiss()
            } else {
                dismiss(animated: true)
            }
        }

        @objc private func deletePreviewItem() {
            stopSlideShow()
            let currentID = currentAsset.localIdentifier
            if let onDeleteAssetIdentifier {
                onDeleteAssetIdentifier(currentID)
                if onDismiss == nil {
                    dismiss(animated: true)
                }
            } else if let onDelete {
                onDelete()
                if onDismiss == nil {
                    dismiss(animated: true)
                }
            } else {
                closePreview()
            }
        }

        @objc private func toggleLivePhotoPlayback() {
            if isLivePhotoPlaying {
                livePhotoView.stopPlayback()
                stopLivePhotoProgress()
            } else {
                startLivePhotoPlayback()
            }
        }

        private func startLivePhotoPlayback() {
            guard livePhotoView.livePhoto != nil else { return }
            livePhotoView.startPlayback(with: .full)
            isLivePhotoPlaying = true
            livePhotoProgressView.progress = 0
            livePhotoPlaybackStartedAt = Date()
            livePhotoProgressTimer?.invalidate()
            livePhotoProgressTimer = Timer.scheduledTimer(
                withTimeInterval: 0.05,
                repeats: true
            ) { [weak self] _ in
                guard let self, let startedAt = self.livePhotoPlaybackStartedAt
                else { return }
                let duration = self.asset.duration > 0
                    ? self.asset.duration
                    : 3
                let progress = Date().timeIntervalSince(startedAt) / duration
                self.livePhotoProgressView.progress = Float(min(1, progress))
                if progress >= 1 {
                    self.stopLivePhotoProgress()
                }
            }
            updateLivePhotoPlayButton()
        }

        private func stopLivePhotoProgress() {
            livePhotoProgressTimer?.invalidate()
            livePhotoProgressTimer = nil
            livePhotoPlaybackStartedAt = nil
            isLivePhotoPlaying = false
            updateLivePhotoPlayButton()
        }

        private func updateLivePhotoPlayButton() {
            let symbol = isLivePhotoPlaying ? "pause.fill" : "play.fill"
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
            livePhotoPlayButton?.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
            livePhotoPlayButton?.accessibilityLabel = isLivePhotoPlaying ? "라이브 포토 일시정지" : "라이브 포토 재생"
        }

        @objc private func toggleImageSlidePlayback() {
            if isSlidePlaying {
                stopSlideShow()
            } else {
                startSlideShow()
            }
        }

        private func startSlideShow() {
            guard imageAssets.count >= 2, !isImageLoading, imageView.image != nil, errorContainerView.isHidden else { return }
            isSlidePlaying = true
            updateImagePlayPauseButton()
            scheduleControlsHide()
            restartSlideTimer()
        }

        private func restartSlideTimer() {
            slideTimer?.invalidate()
            guard isSlidePlaying, imageAssets.count >= 2, !isImageLoading, imageView.image != nil, errorContainerView.isHidden else { return }
            let interval = HanClipCommonPlayerPreferences.imageInterval
            slideTimer = Timer.scheduledTimer(
                withTimeInterval: interval,
                repeats: true
            ) { [weak self] _ in
                guard let self, !self.isImageLoading else { return }
                self.advanceSlide()
            }
        }

        private func stopSlideShow() {
            isSlidePlaying = false
            slideTimer?.invalidate()
            slideTimer = nil
            updateImagePlayPauseButton()
            revealControls()
        }

        private func advanceSlide() {
            guard imageAssets.count > 0 else { return }
            let mode = HanClipCommonPlayerPreferences.imageRepeatMode

            switch mode {
            case .oneRepeat:
                return
            case .once:
                if currentImageIndex >= imageAssets.count - 1 {
                    stopSlideShow()
                    return
                }
                currentImageIndex += 1
                loadCurrentImage()
            case .shuffle:
                if imageAssets.count > 1 {
                    var nextIndex = currentImageIndex
                    while nextIndex == currentImageIndex {
                        nextIndex = Int.random(in: 0..<imageAssets.count)
                    }
                    currentImageIndex = nextIndex
                }
                loadCurrentImage()
            case .allRepeat:
                currentImageIndex = (currentImageIndex + 1) % imageAssets.count
                loadCurrentImage()
            }
        }

        @objc private func advancePreviousImage() {
            guard imageAssets.count > 1 else { return }
            currentImageIndex = (currentImageIndex - 1 + imageAssets.count) % imageAssets.count
            loadCurrentImage()
            revealControls()
        }

        @objc private func advanceNextImage() {
            guard imageAssets.count > 1 else { return }
            currentImageIndex = (currentImageIndex + 1) % imageAssets.count
            loadCurrentImage()
            revealControls()
        }

        private func resetZoomAndPan() {
            scrollView.zoomScale = scrollView.minimumZoomScale
            scrollView.contentOffset = .zero
        }

        private func loadCurrentImage() {
            guard !imageAssets.isEmpty else { return }
            resetZoomAndPan()
            updateTitle()

            slideTimer?.invalidate()
            slideTimer = nil
            isImageLoading = true
            imageView.image = nil

            if let currentImageRequestID {
                imageManager.cancelImageRequest(currentImageRequestID)
                self.currentImageRequestID = nil
            }

            let assetToLoad = currentAsset
            let expectedID = assetToLoad.localIdentifier

            loadingIndicator.startAnimating()
            errorContainerView.isHidden = true

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            let requestID = imageManager.requestImage(
                for: assetToLoad,
                targetSize: CGSize(width: 1_800, height: 1_800),
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                guard let self else { return }
                DispatchQueue.main.async {
                    guard self.currentAsset.localIdentifier == expectedID else { return }
                    let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    if isCancelled { return }
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if let image {
                        self.imageView.image = image
                        self.errorContainerView.isHidden = true
                        if !isDegraded {
                            self.loadingIndicator.stopAnimating()
                            self.isImageLoading = false
                            if self.isSlidePlaying {
                                self.restartSlideTimer()
                            }
                        }
                    } else if !isDegraded {
                        self.loadingIndicator.stopAnimating()
                        self.isImageLoading = false
                        self.stopSlideShow()
                        self.showError(message: "사진을 불러올 수 없습니다.") { [weak self] in
                            self?.loadCurrentImage()
                        }
                    }
                }
            }
            self.currentImageRequestID = requestID
        }

        private func updateTitle() {
            if !imageAssets.isEmpty {
                titleLabel.text = "\(currentImageIndex + 1) / \(imageAssets.count)"
            } else if let title = assetTitle(for: currentAsset) {
                titleLabel.text = title
            } else {
                titleLabel.text = ""
            }
        }

        private func assetTitle(for asset: PHAsset) -> String? {
            if let date = asset.creationDate {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "ko_KR")
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                return formatter.string(from: date)
            }
            return nil
        }

        private func updateImagePlayPauseButton() {
            guard let imagePlayPauseButton, let previousButton, let nextButton else { return }
            let symbol = isSlidePlaying ? "pause.fill" : "play.fill"
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
            imagePlayPauseButton.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
            imagePlayPauseButton.accessibilityLabel = isSlidePlaying ? "일시정지" : "재생"
            imagePlayPauseButton.isEnabled = imageAssets.count > 1
            imagePlayPauseButton.alpha = imageAssets.count > 1 ? 1.0 : 0.4
            previousButton.isEnabled = imageAssets.count > 1
            previousButton.alpha = imageAssets.count > 1 ? 1.0 : 0.4
            nextButton.isEnabled = imageAssets.count > 1
            nextButton.alpha = imageAssets.count > 1 ? 1.0 : 0.4
        }

        @objc private func handleAppWillResignActive() {
            if isSlidePlaying {
                slideTimer?.invalidate()
                slideTimer = nil
            }
            videoPlayer?.pause()
            livePhotoView.stopPlayback()
            stopLivePhotoProgress()
        }

        @objc private func handleAppDidBecomeActive() {
            if isSlidePlaying {
                restartSlideTimer()
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let subView = imageView
            let offsetX = max((scrollView.bounds.size.width - scrollView.contentSize.width) * 0.5, 0.0)
            let offsetY = max((scrollView.bounds.size.height - scrollView.contentSize.height) * 0.5, 0.0)
            subView.center = CGPoint(
                x: scrollView.contentSize.width * 0.5 + offsetX,
                y: scrollView.contentSize.height * 0.5 + offsetY
            )
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            controlsHideTimer?.invalidate()
            revealControls()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            scheduleControlsHide()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            controlsHideTimer?.invalidate()
            revealControls()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                scheduleControlsHide()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            scheduleControlsHide()
        }
    }
    final class DragSelectionPhotoCell: UICollectionViewCell {
        enum MediaKind {
            case photo
            case livePhoto
            case video

            var symbolName: String {
                switch self {
                case .photo: "photo.fill"
                case .livePhoto: "livephoto"
                case .video: "video.fill"
                }
            }

            var accessibilityTitle: String {
                switch self {
                case .photo: "사진"
                case .livePhoto: "라이브 포토"
                case .video: "영상"
                }
            }
        }

        static let reuseID = "DragSelectionPhotoCell"
        let imageView = UIImageView()
        var representedAssetIdentifier: String?
        private let selectionOverlay = UIView()
        private let checkLabel = UILabel()
        private let mediaKindBadge = UIImageView(
            image: UIImage(systemName: "photo.fill")
        )

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.layer.cornerRadius = 8
            contentView.layer.cornerCurve = .continuous
            contentView.clipsToBounds = true
            isAccessibilityElement = true
            accessibilityTraits = [.button]
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(imageView)

            selectionOverlay.backgroundColor = HanClipTheme.secondaryUIColor
                .withAlphaComponent(0.18)
            selectionOverlay.layer.borderColor = HanClipTheme.secondaryUIColor.cgColor
            selectionOverlay.layer.borderWidth = 2.4
            selectionOverlay.layer.cornerRadius = 9
            selectionOverlay.layer.cornerCurve = .continuous
            selectionOverlay.isHidden = true
            selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(selectionOverlay)

            checkLabel.text = "✓"
            checkLabel.textAlignment = .center
            checkLabel.font = .systemFont(ofSize: 12, weight: .black)
            checkLabel.textColor = UIColor(HanClipTheme.onSecondary)
            checkLabel.backgroundColor = HanClipTheme.secondaryUIColor
            checkLabel.layer.cornerRadius = 9
            checkLabel.clipsToBounds = true
            checkLabel.isHidden = true
            checkLabel.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(checkLabel)

            mediaKindBadge.tintColor = UIColor(HanClipTheme.background)
                .withAlphaComponent(0.80)
            mediaKindBadge.backgroundColor = UIColor(HanClipTheme.text)
                .withAlphaComponent(0.32)
            mediaKindBadge.layer.cornerRadius = 7
            mediaKindBadge.contentMode = .center
            mediaKindBadge.preferredSymbolConfiguration =
                UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            mediaKindBadge.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(mediaKindBadge)

            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                selectionOverlay.topAnchor.constraint(equalTo: contentView.topAnchor),
                selectionOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                selectionOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                selectionOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                checkLabel.bottomAnchor.constraint(
                    equalTo: contentView.bottomAnchor,
                    constant: -5
                ),
                checkLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
                checkLabel.widthAnchor.constraint(equalToConstant: 18),
                checkLabel.heightAnchor.constraint(equalToConstant: 18),
                mediaKindBadge.leadingAnchor.constraint(
                    equalTo: contentView.leadingAnchor,
                    constant: 5
                ),
                mediaKindBadge.bottomAnchor.constraint(
                    equalTo: contentView.bottomAnchor,
                    constant: -5
                ),
                mediaKindBadge.widthAnchor.constraint(equalToConstant: 20),
                mediaKindBadge.heightAnchor.constraint(equalToConstant: 18)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            representedAssetIdentifier = nil
            imageView.image = nil
            updateSelection(false)
            accessibilityLabel = nil
            accessibilityValue = nil
        }

        func updateSelection(_ isSelected: Bool) {
            selectionOverlay.isHidden = !isSelected
            checkLabel.isHidden = !isSelected
            let scale: CGFloat = isSelected ? 0.86 : 1
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            imageView.transform = transform
            selectionOverlay.transform = transform
            imageView.layer.cornerRadius = isSelected ? 9 : 0
            contentView.backgroundColor = isSelected
                ? HanClipTheme.secondaryUIColor.withAlphaComponent(0.16)
                : .clear
        }

        func updateMediaKind(_ mediaKind: MediaKind) {
            mediaKindBadge.image = UIImage(systemName: mediaKind.symbolName)
            mediaKindBadge.isHidden = false
        }

        func updateAccessibility(
            mediaKind: MediaKind,
            creationDate: Date?,
            selectionOrder: Int?
        ) {
            let dateText = creationDate.map {
                Self.accessibilityDateFormatter.string(from: $0)
            }
            accessibilityLabel = [dateText, mediaKind.accessibilityTitle]
                .compactMap { $0 }
                .joined(separator: ", ")
            if let selectionOrder {
                accessibilityValue = "선택됨, \(selectionOrder)번째"
                accessibilityTraits.insert(.selected)
            } else {
                accessibilityValue = "선택 안 됨"
                accessibilityTraits.remove(.selected)
            }
            accessibilityHint = "두 번 탭하여 선택하거나 선택 해제합니다."
        }

        private static let accessibilityDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }()
    }

    final class PhotoPickerContainerViewController: UIViewController {
        private let picker: PHPickerViewController
        private let onCancel: () -> Void
        private let onDone: () -> Void
        private let selectionLabel = UILabel()
        private let doneButton = UIButton(type: .system)

        init(
            picker: PHPickerViewController,
            onCancel: @escaping () -> Void,
            onDone: @escaping () -> Void
        ) {
            self.picker = picker
            self.onCancel = onCancel
            self.onDone = onDone
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground

            addChild(picker)
            picker.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(picker.view)
            picker.didMove(toParent: self)

            let toolbar = UIView()
            toolbar.backgroundColor = .secondarySystemBackground
            toolbar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(toolbar)

            let cancelButton = UIButton(type: .system)
            cancelButton.setTitle("취소", for: .normal)
            cancelButton.titleLabel?.font = HanClipTypography.uiFont(
                textStyle: .headline,
                weight: .semibold
            )
            cancelButton.titleLabel?.adjustsFontForContentSizeCategory = true
            cancelButton.addTarget(
                self,
                action: #selector(cancelTapped),
                for: .touchUpInside
            )
            cancelButton.translatesAutoresizingMaskIntoConstraints = false

            selectionLabel.text = "사진을 누른 채 드래그 · 0개 선택"
            selectionLabel.font = HanClipTypography.uiFont(
                textStyle: .subheadline,
                weight: .semibold
            )
            selectionLabel.textColor = .secondaryLabel
            selectionLabel.textAlignment = .center
            selectionLabel.adjustsFontForContentSizeCategory = true
            selectionLabel.adjustsFontSizeToFitWidth = false
            selectionLabel.lineBreakMode = .byTruncatingTail
            selectionLabel.translatesAutoresizingMaskIntoConstraints = false

            doneButton.setTitle("추가", for: .normal)
            doneButton.titleLabel?.font = HanClipTypography.uiFont(
                textStyle: .headline,
                weight: .semibold
            )
            doneButton.titleLabel?.adjustsFontForContentSizeCategory = true
            doneButton.isEnabled = false
            doneButton.addTarget(
                self,
                action: #selector(doneTapped),
                for: .touchUpInside
            )
            doneButton.translatesAutoresizingMaskIntoConstraints = false

            toolbar.addSubview(cancelButton)
            toolbar.addSubview(selectionLabel)
            toolbar.addSubview(doneButton)

            NSLayoutConstraint.activate([
                toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                toolbar.topAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                    constant: -58
                ),
                picker.view.topAnchor.constraint(equalTo: view.topAnchor),
                picker.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                picker.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                picker.view.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
                cancelButton.leadingAnchor.constraint(
                    equalTo: toolbar.safeAreaLayoutGuide.leadingAnchor,
                    constant: 18
                ),
                cancelButton.centerYAnchor.constraint(
                    equalTo: toolbar.topAnchor,
                    constant: 29
                ),
                doneButton.trailingAnchor.constraint(
                    equalTo: toolbar.safeAreaLayoutGuide.trailingAnchor,
                    constant: -18
                ),
                doneButton.centerYAnchor.constraint(
                    equalTo: toolbar.topAnchor,
                    constant: 29
                ),
                selectionLabel.leadingAnchor.constraint(
                    equalTo: cancelButton.trailingAnchor,
                    constant: 8
                ),
                selectionLabel.trailingAnchor.constraint(
                    equalTo: doneButton.leadingAnchor,
                    constant: -8
                ),
                selectionLabel.centerYAnchor.constraint(
                    equalTo: toolbar.topAnchor,
                    constant: 29
                )
            ])
        }

        func updateSelectionCount(_ count: Int) {
            selectionLabel.text = "사진을 누른 채 드래그 · \(count)개 선택"
            doneButton.setTitle(count > 0 ? "추가 \(count)" : "추가", for: .normal)
            doneButton.isEnabled = count > 0
        }

        @objc private func cancelTapped() {
            onCancel()
        }

        @objc private func doneTapped() {
            onDone()
        }
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let excludedImportIdentifiers: Set<String>
        private let onStart: () -> Void
        private let onProgress: (Double, String) -> Void
        private let onRegisterCancellation: (@escaping () -> Void) -> Void
        private let onSelectionIdentifiers: (([String]) -> Void)?
        private let onComplete: ([ClipItem], [String]) -> Void
        private let onCancel: () -> Void
        private let onDismiss: () -> Void
        private var selectedResults: [PHPickerResult] = []
        private var importTask: Task<Void, Never>?
        weak var container: PhotoPickerContainerViewController?

        init(
            excludedImportIdentifiers: Set<String>,
            onSelectionIdentifiers: (([String]) -> Void)?,
            onStart: @escaping () -> Void,
            onProgress: @escaping (Double, String) -> Void,
            onRegisterCancellation: @escaping (
                @escaping () -> Void
            ) -> Void,
            onComplete: @escaping ([ClipItem], [String]) -> Void,
            onCancel: @escaping () -> Void,
            onDismiss: @escaping () -> Void
        ) {
            self.excludedImportIdentifiers = excludedImportIdentifiers
            self.onSelectionIdentifiers = onSelectionIdentifiers
            self.onStart = onStart
            self.onProgress = onProgress
            self.onRegisterCancellation = onRegisterCancellation
            self.onComplete = onComplete
            self.onCancel = onCancel
            self.onDismiss = onDismiss
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            selectedResults = results
            container?.updateSelectionCount(results.count)
        }

        func cancelPicking() {
            selectedResults = []
            onCancel()
        }

        func finishPicking(assetIdentifiers: [String]) {
            let identifiersToImport = assetIdentifiers.filter {
                !excludedImportIdentifiers.contains($0)
            }
            onDismiss()
            if let onSelectionIdentifiers {
                onSelectionIdentifiers(identifiersToImport)
                return
            }
            guard !identifiersToImport.isEmpty else {
                onComplete([], assetIdentifiers)
                return
            }
            onStart()

            importTask?.cancel()
            importTask = Task { @MainActor [weak self] in
                guard let self else { return }
                var items: [ClipItem] = []
                items.reserveCapacity(identifiersToImport.count)
                for (index, identifier) in identifiersToImport.enumerated() {
                    guard !Task.isCancelled else { return }
                    defer {
                        let completed = index + 1
                        onProgress(
                            Double(completed) / Double(identifiersToImport.count),
                            "미디어 \(completed)/\(identifiersToImport.count)개를 불러오는 중…"
                        )
                    }
                    guard let asset = PhotoLibraryService.asset(
                        localIdentifier: identifier
                    ), let thumbnail = try? await PhotoLibraryService.thumbnail(
                        for: asset
                    ) else { continue }

                    if asset.mediaType == .video,
                       let videoItems = try? await Self.makeVideoItems(
                        asset: asset,
                        thumbnail: thumbnail
                       ) {
                        items.append(contentsOf: videoItems)
                        continue
                    }

                    let isLive = asset.mediaSubtypes.contains(.photoLive)
                    let duration = isLive
                        ? (try? await PhotoLibraryService
                            .livePhotoVideoDuration(for: asset)) ?? 4
                        : 4
                    items.append(
                        ClipItem(
                            source: .photoAsset(
                                localIdentifier: identifier
                            ),
                            thumbnail: thumbnail,
                            duration: duration,
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
                    )
                }
                guard !Task.isCancelled else { return }
                onComplete(items, assetIdentifiers)
                importTask = nil
            }
            onRegisterCancellation { [weak self] in
                self?.importTask?.cancel()
            }
        }

        func finishPicking() {
            let results = selectedResults
            guard !results.isEmpty else { return }
            selectedResults = []
            onDismiss()
            onStart()

            importTask?.cancel()
            importTask = Task { @MainActor [weak self] in
                guard let self else { return }
                var items: [ClipItem] = []
                for (index, result) in results.enumerated() {
                    guard !Task.isCancelled else { return }
                    defer {
                        let completed = index + 1
                        onProgress(
                            Double(completed) / Double(results.count),
                            "미디어 \(completed)/\(results.count)개를 불러오는 중…"
                        )
                    }
                    if let identifier = result.assetIdentifier,
                       let asset = PhotoLibraryService.asset(
                        localIdentifier: identifier
                       ),
                       let thumbnail = try? await PhotoLibraryService.thumbnail(
                        for: asset
                       ) {
                        if asset.mediaType == .video,
                           let videoItems = try? await Self.makeVideoItems(
                            asset: asset,
                            thumbnail: thumbnail
                           ) {
                            items.append(contentsOf: videoItems)
                            continue
                        }
                        let isLive = asset.mediaSubtypes.contains(.photoLive)
                        let duration = isLive
                            ? (try? await PhotoLibraryService
                                .livePhotoVideoDuration(for: asset)) ?? 4
                            : 4
                        items.append(
                            ClipItem(
                                source: .photoAsset(
                                    localIdentifier: identifier
                                ),
                                thumbnail: thumbnail,
                                duration: duration,
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
                        )
                    } else if let fallbackItems = await Self.loadFallback(
                        result
                    ) {
                        items.append(contentsOf: fallbackItems)
                    }
                }
                guard !Task.isCancelled else { return }
                onComplete(
                    items,
                    results.compactMap(\.assetIdentifier)
                )
                importTask = nil
            }
            onRegisterCancellation { [weak self] in
                self?.importTask?.cancel()
            }
        }

        @MainActor
        private static func loadFallback(
            _ result: PHPickerResult
        ) async -> [ClipItem]? {
            if result.itemProvider.hasItemConformingToTypeIdentifier(
                UTType.movie.identifier
            ), let items = try? await loadFallbackVideo(
                result.itemProvider
            ) {
                return items
            }
            guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else {
                return nil
            }

            return await withCheckedContinuation { continuation in
                result.itemProvider.loadObject(ofClass: UIImage.self) {
                    object,
                    _ in
                    guard let image = object as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.95)
                    else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("jpg")
                    do {
                        try data.write(to: url)
                        continuation.resume(
                            returning: [
                                ClipItem(
                                    source: .imageFile(url),
                                    thumbnail: image,
                                    sourcePixelSize: image.size
                                )
                            ]
                        )
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        private static func makeVideoItems(
            asset: PHAsset,
            thumbnail: UIImage
        ) async throws -> [ClipItem] {
            let url = try await PhotoLibraryService.exportVideo(for: asset)
            let duration = try await PhotoLibraryService.videoDuration(at: url)
            let analysis = try? await AudioAnalysisService.analyze(url: url)
            return VideoClipSegmenter.makeClips(
                source: .videoFile(url),
                photoLibraryAssetIdentifier: asset.localIdentifier,
                thumbnail: thumbnail,
                sourceDuration: duration,
                selectedDuration: min(4, duration),
                segmentCount: 1,
                analysis: analysis,
                sourcePixelSize: CGSize(
                    width: asset.pixelWidth,
                    height: asset.pixelHeight
                )
            )
        }

        private static func loadFallbackVideo(
            _ provider: NSItemProvider
        ) async throws -> [ClipItem] {
            let url = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<URL, Error>) in
                provider.loadFileRepresentation(
                    forTypeIdentifier: UTType.movie.identifier
                ) { source, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let source else {
                        continuation.resume(
                            throwing: MediaError.videoTrackUnavailable
                        )
                        return
                    }
                    do {
                        let target = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(
                                source.pathExtension.isEmpty
                                    ? "mov"
                                    : source.pathExtension
                            )
                        try FileManager.default.copyItem(
                            at: source,
                            to: target
                        )
                        continuation.resume(returning: target)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            let asset = AVURLAsset(url: url)
            let duration = try await PhotoLibraryService.videoDuration(at: url)
            let sourcePixelSize = try await Self.naturalVideoPixelSize(
                asset: asset
            )
            let cgImage = try await RepresentativeVideoFrame.extract(
                asset: asset,
                anchor: 0,
                appliesPreferredTrackTransform: true,
                maximumSize: CGSize(width: 640, height: 640)
            )
            let thumbnail = UIImage(cgImage: cgImage)
            let analysis = try? await AudioAnalysisService.analyze(url: url)
            return VideoClipSegmenter.makeClips(
                source: .videoFile(url),
                thumbnail: thumbnail,
                sourceDuration: duration,
                selectedDuration: min(4, duration),
                segmentCount: 1,
                analysis: analysis,
                sourcePixelSize: sourcePixelSize
            )
        }

        /// `RepresentativeVideoFrame.extract`의 `maximumSize` bound로 인해
        /// 썸네일 크기가 원본 치수보다 작아질 수 있어, `sourcePixelSize`
        /// 메타데이터는 썸네일 크기가 아닌 track의 실제(회전 반영) 크기에서
        /// 구한다.
        private static func naturalVideoPixelSize(
            asset: AVURLAsset
        ) async throws -> CGSize {
            guard let track = try await asset.loadTracks(
                withMediaType: .video
            ).first else {
                throw MediaError.videoTrackUnavailable
            }
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformedSize = naturalSize.applying(transform)
            return CGSize(
                width: abs(transformedSize.width),
                height: abs(transformedSize.height)
            )
        }
    }
}
