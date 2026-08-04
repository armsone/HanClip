import Foundation

enum WatermarkPosition: String, CaseIterable, Codable, Identifiable {
    case topLeading
    case topQuarterLeading
    case topCenter
    case topQuarterTrailing
    case topTrailing
    case upperLeading
    case upperQuarterLeading
    case upperCenter
    case upperQuarterTrailing
    case upperTrailing
    case middleLeading
    case middleQuarterLeading
    case center
    case middleQuarterTrailing
    case middleTrailing
    case lowerLeading
    case lowerQuarterLeading
    case lowerCenter
    case lowerQuarterTrailing
    case lowerTrailing
    case bottomLeading
    case bottomQuarterLeading
    case bottomCenter
    case bottomQuarterTrailing
    case bottomTrailing

    var id: String { rawValue }

    var gridColumn: Int {
        switch self {
        case .topLeading, .upperLeading, .middleLeading,
             .lowerLeading, .bottomLeading:
            return 0
        case .topQuarterLeading, .upperQuarterLeading,
             .middleQuarterLeading, .lowerQuarterLeading,
             .bottomQuarterLeading:
            return 1
        case .topCenter, .upperCenter, .center,
             .lowerCenter, .bottomCenter:
            return 2
        case .topQuarterTrailing, .upperQuarterTrailing,
             .middleQuarterTrailing, .lowerQuarterTrailing,
             .bottomQuarterTrailing:
            return 3
        case .topTrailing, .upperTrailing, .middleTrailing,
             .lowerTrailing, .bottomTrailing:
            return 4
        }
    }

    var gridRow: Int {
        switch self {
        case .topLeading, .topQuarterLeading, .topCenter,
             .topQuarterTrailing, .topTrailing:
            return 0
        case .upperLeading, .upperQuarterLeading, .upperCenter,
             .upperQuarterTrailing, .upperTrailing:
            return 1
        case .middleLeading, .middleQuarterLeading, .center,
             .middleQuarterTrailing, .middleTrailing:
            return 2
        case .lowerLeading, .lowerQuarterLeading, .lowerCenter,
             .lowerQuarterTrailing, .lowerTrailing:
            return 3
        case .bottomLeading, .bottomQuarterLeading, .bottomCenter,
             .bottomQuarterTrailing, .bottomTrailing:
            return 4
        }
    }

    var horizontalFraction: Double {
        Double(gridColumn) / 4.0
    }

    var verticalFractionFromTop: Double {
        Double(gridRow) / 4.0
    }

    var title: String {
        "가로 \(gridColumn + 1), 세로 \(gridRow + 1)"
    }
}

enum WatermarkLineSpacing: String, CaseIterable, Codable, Identifiable {
    case wide
    case normal
    case tight

    static let displayOrder: [WatermarkLineSpacing] = [
        .tight,
        .normal,
        .wide
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wide:
            return "넓게"
        case .normal:
            return "보통"
        case .tight:
            return "좁게"
        }
    }

    var multiplier: Double {
        Self.defaultMultiplier
    }

    static let defaultMultiplier = 1.0
    static let step = 0.20
    static let minimumMultiplier = 0.5
    static let maximumMultiplier = 2.0
}

enum WatermarkFontSize: String, CaseIterable, Codable, Identifiable {
    case small
    case normal
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small:
            return "작게"
        case .normal:
            return "기본"
        case .large:
            return "크게"
        case .extraLarge:
            return "더크게"
        }
    }

    var multiplier: Double {
        switch self {
        case .small:
            return 0.8
        case .normal:
            return 1.0
        case .large:
            return 1.5
        case .extraLarge:
            return 26.0 / 14.0
        }
    }

    var pointSize: Int {
        switch self {
        case .small:
            return 11
        case .normal:
            return 14
        case .large:
            return 21
        case .extraLarge:
            return 26
        }
    }
}

enum CopyrightIconColorMode: String, CaseIterable, Codable, Identifiable {
    case original
    case gray
    case tint

    static var allCases: [CopyrightIconColorMode] {
        [.original]
    }

    init?(rawValue: String) {
        switch rawValue {
        case "original":
            self = .original
        case "gray":
            self = .gray
        case "tint", "overlay":
            self = .tint
        default:
            return nil
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original:
            return "원색"
        case .gray:
            return "회색"
        case .tint:
            return "틴트"
        }
    }
}

struct WatermarkSettings: Codable {
    static let logoEnabledStorageKey = "hanClipLogoWatermarkEnabled"
    static let enabledStorageKey = "hanClipWatermarkEnabled"
    static let textStorageKey = "hanClipWatermarkText"
    static let addressStorageKey = "hanClipWatermarkAddress"
    static let platformStorageKey = "hanClipWatermarkPlatform"
    static let positionStorageKey = "hanClipWatermarkPosition"
    static let fontNameStorageKey = "hanClipWatermarkFontName"
    static let textColorStorageKey = "hanClipWatermarkTextColor"
    static let shadowEnabledStorageKey = "hanClipWatermarkShadowEnabled"
    static let shadowOpacityStorageKey = "hanClipWatermarkShadowOpacity"
    static let shadowColorStorageKey = "hanClipWatermarkShadowColor"
    static let lineSpacingStorageKey = "hanClipWatermarkLineSpacing"
    static let lineSpacingScaleStorageKey =
        "hanClipWatermarkLineSpacingScale"
    static let fontSizeStorageKey = "hanClipWatermarkFontSize"
    static let copyrightPositionStorageKey =
        "hanClipCopyrightWatermarkPosition"
    static let copyrightTextColorStorageKey =
        "hanClipCopyrightWatermarkTextColor"
    static let copyrightShadowColorStorageKey =
        "hanClipCopyrightWatermarkShadowColor"
    static let copyrightShadowOpacityStorageKey =
        "hanClipCopyrightWatermarkShadowOpacity"
    static let copyrightIconColorModeStorageKey =
        "hanClipCopyrightIconColorMode"
    static let copyrightIconColorStorageKey =
        "hanClipCopyrightIconColor"
    static let customCopyrightIconPathStorageKey =
        "hanClipCustomCopyrightIconPath"
    static let defaultIsEnabled = true
    static let defaultTextIsEnabled = false
    static let legacyDefaultText = "여기에 글을 넣으세요."
    static let defaultText = """
    여기에 글을 넣으세요
    I Love you ♡
    +82 10-0000-0000
    """
    static let defaultAddress = ""
    static let defaultPlatform = WatermarkPlatform.hanclip
    static let defaultPosition = WatermarkPosition.topLeading
    static let defaultFontName = "pretendard"
    static let defaultTextColor = "#FFFFFF"
    static let defaultShadowEnabled = true
    static let defaultShadowOpacity = 0.2
    static let defaultShadowColor = "#000000"
    static let defaultLineSpacing = WatermarkLineSpacing.normal
    static let defaultLineSpacingScale =
        WatermarkLineSpacing.defaultMultiplier
    static let defaultFontSize = WatermarkFontSize.large
    static let defaultCopyrightPosition = WatermarkPosition.bottomTrailing
    static let defaultCopyrightTextColor = "#007644"
    static let defaultCopyrightShadowColor = "#29AB87"
    static let defaultCopyrightShadowOpacity = 0.2
    static let defaultCopyrightIconColorMode = CopyrightIconColorMode.original
    static let defaultCopyrightIconColor = "#007644"
    static let defaultCustomCopyrightIconPath = ""

    var isEnabled: Bool
    var logoEnabled: Bool
    var text: String
    var address: String
    var platform: WatermarkPlatform
    var position: WatermarkPosition
    var fontName: String
    var textColorHex: String
    var shadowEnabled: Bool
    var shadowOpacity: Double
    var shadowColorHex: String
    var lineSpacing: WatermarkLineSpacing
    var lineSpacingScale: Double
    var fontSize: WatermarkFontSize
    var copyrightPosition: WatermarkPosition
    var copyrightTextColorHex: String
    var copyrightShadowColorHex: String
    var copyrightShadowOpacity: Double
    var copyrightIconColorMode: CopyrightIconColorMode
    var copyrightIconColorHex: String
    var customCopyrightIconPath: String

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case logoEnabled
        case text
        case address
        case platform
        case position
        case fontName
        case textColorHex
        case shadowEnabled
        case shadowOpacity
        case shadowColorHex
        case lineSpacing
        case lineSpacingScale
        case fontSize
        case copyrightPosition
        case copyrightTextColorHex
        case copyrightShadowColorHex
        case copyrightShadowOpacity
        case copyrightIconColorMode
        case copyrightIconColorHex
        case customCopyrightIconPath
    }

    init(
        isEnabled: Bool,
        logoEnabled: Bool,
        text: String,
        address: String,
        platform: WatermarkPlatform,
        position: WatermarkPosition,
        fontName: String,
        textColorHex: String,
        shadowEnabled: Bool,
        shadowOpacity: Double = Self.defaultShadowOpacity,
        shadowColorHex: String,
        lineSpacing: WatermarkLineSpacing,
        lineSpacingScale: Double,
        fontSize: WatermarkFontSize,
        copyrightPosition: WatermarkPosition,
        copyrightTextColorHex: String,
        copyrightShadowColorHex: String,
        copyrightShadowOpacity: Double = Self.defaultCopyrightShadowOpacity,
        copyrightIconColorMode: CopyrightIconColorMode,
        copyrightIconColorHex: String,
        customCopyrightIconPath: String = Self.defaultCustomCopyrightIconPath
    ) {
        self.isEnabled = isEnabled
        self.logoEnabled = logoEnabled
        self.text = text
        self.address = address
        self.platform = platform
        self.position = position
        self.fontName = fontName
        self.textColorHex = textColorHex
        self.shadowOpacity = Self.normalizedShadowOpacity(shadowOpacity)
        self.shadowEnabled = shadowEnabled && self.shadowOpacity > 0
        self.shadowColorHex = shadowColorHex
        self.lineSpacing = lineSpacing
        self.lineSpacingScale = Self.normalizedLineSpacingScale(
            lineSpacingScale
        )
        self.fontSize = fontSize
        self.copyrightPosition = copyrightPosition
        self.copyrightTextColorHex = copyrightTextColorHex
        self.copyrightShadowColorHex = copyrightShadowColorHex
        self.copyrightShadowOpacity = Self.normalizedShadowOpacity(
            copyrightShadowOpacity
        )
        self.copyrightIconColorMode = copyrightIconColorMode
        self.copyrightIconColorHex = copyrightIconColorHex
        self.customCopyrightIconPath = customCopyrightIconPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isEnabled
        ) ?? Self.defaultTextIsEnabled
        logoEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .logoEnabled
        ) ?? false
        text = try container.decodeIfPresent(String.self, forKey: .text)
            ?? Self.defaultText
        address = try container.decodeIfPresent(String.self, forKey: .address)
            ?? Self.defaultAddress
        let rawPlatform = try container.decodeIfPresent(
            String.self,
            forKey: .platform
        )
        platform = rawPlatform.flatMap(WatermarkPlatform.init(rawValue:))
            ?? Self.defaultPlatform
        position = try container.decodeIfPresent(
            WatermarkPosition.self,
            forKey: .position
        ) ?? Self.defaultPosition
        fontName = FontRegistry.normalizedID(
            forStoredValue: try container.decodeIfPresent(
                String.self,
                forKey: .fontName
            ) ?? Self.defaultFontName
        )
        textColorHex = try container.decodeIfPresent(
            String.self,
            forKey: .textColorHex
        ) ?? Self.defaultTextColor
        shadowEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .shadowEnabled
        ) ?? Self.defaultShadowEnabled
        shadowOpacity = Self.normalizedShadowOpacity(
            try container.decodeIfPresent(Double.self, forKey: .shadowOpacity)
                ?? (shadowEnabled ? Self.defaultShadowOpacity : 0)
        )
        shadowEnabled = shadowOpacity > 0
        shadowColorHex = try container.decodeIfPresent(
            String.self,
            forKey: .shadowColorHex
        ) ?? Self.defaultShadowColor
        lineSpacing = try container.decodeIfPresent(
            WatermarkLineSpacing.self,
            forKey: .lineSpacing
        ) ?? Self.defaultLineSpacing
        lineSpacingScale = Self.normalizedLineSpacingScale(
            try container.decodeIfPresent(
                Double.self,
                forKey: .lineSpacingScale
            ) ?? lineSpacing.multiplier
        )
        fontSize = try container.decodeIfPresent(
            WatermarkFontSize.self,
            forKey: .fontSize
        ) ?? Self.defaultFontSize
        copyrightPosition = try container.decodeIfPresent(
            WatermarkPosition.self,
            forKey: .copyrightPosition
        ) ?? Self.defaultCopyrightPosition
        copyrightTextColorHex = try container.decodeIfPresent(
            String.self,
            forKey: .copyrightTextColorHex
        ) ?? Self.defaultCopyrightTextColor
        copyrightShadowColorHex = try container.decodeIfPresent(
            String.self,
            forKey: .copyrightShadowColorHex
        ) ?? Self.defaultCopyrightShadowColor
        copyrightShadowOpacity = Self.normalizedShadowOpacity(
            try container.decodeIfPresent(
                Double.self,
                forKey: .copyrightShadowOpacity
            ) ?? Self.defaultCopyrightShadowOpacity
        )
        copyrightIconColorMode = try container.decodeIfPresent(
            CopyrightIconColorMode.self,
            forKey: .copyrightIconColorMode
        ) ?? Self.defaultCopyrightIconColorMode
        copyrightIconColorHex = try container.decodeIfPresent(
            String.self,
            forKey: .copyrightIconColorHex
        ) ?? Self.defaultCopyrightIconColor
        customCopyrightIconPath = try container.decodeIfPresent(
            String.self,
            forKey: .customCopyrightIconPath
        ) ?? Self.defaultCustomCopyrightIconPath
    }

    var displayText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var shouldRender: Bool {
        logoEnabled || (isEnabled && !displayText.isEmpty)
    }

    var shouldRenderText: Bool {
        isEnabled && !displayText.isEmpty
    }

    static func stored() -> WatermarkSettings {
        let defaults = UserDefaults.standard
        let rawPosition = defaults.string(forKey: positionStorageKey)
            ?? defaultPosition.rawValue
        let position = WatermarkPosition(rawValue: rawPosition)
            ?? defaultPosition
        let rawCopyrightPosition = defaults.string(
            forKey: copyrightPositionStorageKey
        ) ?? rawPosition
        let copyrightPosition = WatermarkPosition(rawValue: rawCopyrightPosition)
            ?? defaultCopyrightPosition
        let rawPlatform = defaults.string(forKey: platformStorageKey)
            ?? defaultPlatform.rawValue
        let platform = WatermarkPlatform(rawValue: rawPlatform)
            ?? defaultPlatform
        let address = defaults.string(
            forKey: addressStorageKey(for: platform)
        ) ?? defaults.string(forKey: addressStorageKey) ?? defaultAddress
        let isEnabled: Bool
        if defaults.object(forKey: enabledStorageKey) == nil {
            isEnabled = defaultTextIsEnabled
        } else {
            isEnabled = defaults.bool(forKey: enabledStorageKey)
        }
        let logoEnabled: Bool
        if defaults.object(forKey: logoEnabledStorageKey) == nil {
            logoEnabled = defaultIsEnabled
        } else {
            logoEnabled = defaults.bool(forKey: logoEnabledStorageKey)
        }
        let shadowEnabled: Bool
        if defaults.object(forKey: shadowEnabledStorageKey) == nil {
            shadowEnabled = defaultShadowEnabled
        } else {
            shadowEnabled = defaults.bool(forKey: shadowEnabledStorageKey)
        }
        let shadowOpacity: Double
        if defaults.object(forKey: shadowOpacityStorageKey) == nil {
            shadowOpacity = shadowEnabled ? defaultShadowOpacity : 0
        } else {
            shadowOpacity = normalizedShadowOpacity(
                defaults.double(forKey: shadowOpacityStorageKey)
            )
        }

        return WatermarkSettings(
            isEnabled: isEnabled,
            logoEnabled: logoEnabled,
            text: defaults.string(forKey: textStorageKey) ?? defaultText,
            address: address,
            platform: platform,
            position: position,
            fontName: FontRegistry.normalizedID(
                forStoredValue: defaults.string(forKey: fontNameStorageKey)
                    ?? defaultFontName
            ),
            textColorHex: defaults.string(forKey: textColorStorageKey)
                ?? defaultTextColor,
            shadowEnabled: shadowOpacity > 0,
            shadowOpacity: shadowOpacity,
            shadowColorHex: defaults.string(forKey: shadowColorStorageKey)
                ?? defaultShadowColor,
            lineSpacing: defaults.string(forKey: lineSpacingStorageKey)
                .flatMap(WatermarkLineSpacing.init(rawValue:))
                ?? defaultLineSpacing,
            lineSpacingScale: defaults.object(
                forKey: lineSpacingScaleStorageKey
            ) == nil
                ? defaultLineSpacingScale
                : defaults.double(forKey: lineSpacingScaleStorageKey),
            fontSize: defaults.string(forKey: fontSizeStorageKey)
                .flatMap(WatermarkFontSize.init(rawValue:))
                ?? defaultFontSize,
            copyrightPosition: copyrightPosition,
            copyrightTextColorHex: defaults.string(
                forKey: copyrightTextColorStorageKey
            ) ?? defaults.string(forKey: textColorStorageKey)
                ?? defaultCopyrightTextColor,
            copyrightShadowColorHex: defaults.string(
                forKey: copyrightShadowColorStorageKey
            ) ?? defaults.string(forKey: shadowColorStorageKey)
                ?? defaultCopyrightShadowColor,
            copyrightShadowOpacity: defaults.object(
                forKey: copyrightShadowOpacityStorageKey
            ) == nil
                ? defaultCopyrightShadowOpacity
                : normalizedShadowOpacity(
                    defaults.double(forKey: copyrightShadowOpacityStorageKey)
                ),
            copyrightIconColorMode: defaults.string(
                forKey: copyrightIconColorModeStorageKey
            ).flatMap(CopyrightIconColorMode.init(rawValue:))
                ?? defaultCopyrightIconColorMode,
            copyrightIconColorHex: defaults.string(
                forKey: copyrightIconColorStorageKey
            ) ?? defaults.string(forKey: copyrightTextColorStorageKey)
                ?? defaultCopyrightIconColor,
            customCopyrightIconPath: defaults.string(
                forKey: customCopyrightIconPathStorageKey
            ) ?? defaultCustomCopyrightIconPath
        )
    }

    static func projectDefault() -> WatermarkSettings {
        WatermarkSettings(
            isEnabled: defaultTextIsEnabled,
            logoEnabled: false,
            text: defaultText,
            address: defaultAddress,
            platform: defaultPlatform,
            position: defaultPosition,
            fontName: defaultFontName,
            textColorHex: defaultTextColor,
            shadowEnabled: defaultShadowEnabled,
            shadowOpacity: defaultShadowOpacity,
            shadowColorHex: defaultShadowColor,
            lineSpacing: defaultLineSpacing,
            lineSpacingScale: defaultLineSpacingScale,
            fontSize: defaultFontSize,
            copyrightPosition: defaultCopyrightPosition,
            copyrightTextColorHex: defaultCopyrightTextColor,
            copyrightShadowColorHex: defaultCopyrightShadowColor,
            copyrightShadowOpacity: defaultCopyrightShadowOpacity,
            copyrightIconColorMode: defaultCopyrightIconColorMode,
            copyrightIconColorHex: defaultCopyrightIconColor,
            customCopyrightIconPath: defaultCustomCopyrightIconPath
        )
    }

    func withLogoEnabled(_ logoEnabled: Bool) -> WatermarkSettings {
        WatermarkSettings(
            isEnabled: isEnabled,
            logoEnabled: logoEnabled,
            text: text,
            address: address,
            platform: platform,
            position: position,
            fontName: fontName,
            textColorHex: textColorHex,
            shadowEnabled: shadowEnabled,
            shadowOpacity: shadowOpacity,
            shadowColorHex: shadowColorHex,
            lineSpacing: lineSpacing,
            lineSpacingScale: lineSpacingScale,
            fontSize: fontSize,
            copyrightPosition: copyrightPosition,
            copyrightTextColorHex: copyrightTextColorHex,
            copyrightShadowColorHex: copyrightShadowColorHex,
            copyrightShadowOpacity: copyrightShadowOpacity,
            copyrightIconColorMode: copyrightIconColorMode,
            copyrightIconColorHex: copyrightIconColorHex,
            customCopyrightIconPath: customCopyrightIconPath
        )
    }

    func withCopyrightSettings(_ copyright: WatermarkSettings) -> WatermarkSettings {
        WatermarkSettings(
            isEnabled: isEnabled,
            logoEnabled: copyright.logoEnabled,
            text: text,
            address: copyright.address,
            platform: copyright.platform,
            position: position,
            fontName: fontName,
            textColorHex: textColorHex,
            shadowEnabled: shadowEnabled,
            shadowOpacity: shadowOpacity,
            shadowColorHex: shadowColorHex,
            lineSpacing: lineSpacing,
            lineSpacingScale: lineSpacingScale,
            fontSize: fontSize,
            copyrightPosition: copyright.copyrightPosition,
            copyrightTextColorHex: copyright.copyrightTextColorHex,
            copyrightShadowColorHex: copyright.copyrightShadowColorHex,
            copyrightShadowOpacity: copyright.copyrightShadowOpacity,
            copyrightIconColorMode: copyright.copyrightIconColorMode,
            copyrightIconColorHex: copyright.copyrightIconColorHex,
            customCopyrightIconPath: copyright.customCopyrightIconPath
        )
    }

    static func addressStorageKey(for platform: WatermarkPlatform) -> String {
        "\(addressStorageKey).\(platform.rawValue)"
    }

    static func normalizedLineSpacingScale(_ value: Double) -> Double {
        min(
            max(value, WatermarkLineSpacing.minimumMultiplier),
            WatermarkLineSpacing.maximumMultiplier
        )
    }

    static func normalizedShadowOpacity(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

enum WatermarkPlatform: String, CaseIterable, Codable, Identifiable {
    case hanclip
    case instagram
    case facebook
    case youtube
    case blog
    case kakaoTalk
    case x
    case phone
    case homepage
    case custom

    var id: String { rawValue }

    init?(rawValue: String) {
        switch rawValue {
        case "other":
            self = .custom
        case "hanclip":
            self = .hanclip
        case "instagram":
            self = .instagram
        case "facebook":
            self = .facebook
        case "youtube":
            self = .youtube
        case "blog":
            self = .blog
        case "kakaoTalk":
            self = .kakaoTalk
        case "x":
            self = .x
        case "phone":
            self = .phone
        case "homepage":
            self = .homepage
        case "custom":
            self = .custom
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .hanclip:
            return "한클립"
        case .instagram:
            return "인스타그램"
        case .facebook:
            return "페이스북"
        case .youtube:
            return "유튜브"
        case .blog:
            return "블로그"
        case .kakaoTalk:
            return "카카오톡"
        case .x:
            return "엑스"
        case .phone:
            return "전화번호"
        case .homepage:
            return "홈페이지"
        case .custom:
            return "직접입력"
        }
    }
}
