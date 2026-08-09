import Combine
import SwiftUI
import UIKit

enum HanClipThemeMode: String, CaseIterable {
    case automatic
    case light
    case dark
    case blossomGlow
    case grayscalePlay
    case pixelPop

    static let baseModes: [HanClipThemeMode] = [
        .automatic,
        .light,
        .dark
    ]

    static let customModes: [HanClipThemeMode] = [
        .blossomGlow,
        .grayscalePlay,
        .pixelPop
    ]

    static let visibleModes: [HanClipThemeMode] = baseModes + customModes

    var colorScheme: ColorScheme? {
        switch self {
        case .light, .blossomGlow, .grayscalePlay, .pixelPop:
            return .light
        case .dark:
            return .dark
        case .automatic:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .light:
            return "Light Mode"
        case .dark:
            return "Dark Mode"
        case .automatic:
            return "Automatic Mode"
        case .blossomGlow:
            return "Blossom Glow"
        case .grayscalePlay:
            return "Grayscale Play"
        case .pixelPop:
            return "Pixel Pop"
        }
    }
}

enum HanClipTheme {
    static var primary: Color {
        Color(uiColor: primaryUIColor)
    }

    static var secondary: Color {
        Color(uiColor: secondaryUIColor)
    }

    static var onSecondary: Color {
        switch selectedMode {
        case .grayscalePlay:
            return Color(uiColor: grayscaleBackground)
        default:
            return .white
        }
    }

    static func previewColors(
        for mode: HanClipThemeMode
    ) -> (primary: Color, secondary: Color)? {
        switch mode {
        case .automatic:
            return nil
        case .light:
            return (
                Color(uiColor: readableComfortPrimary),
                Color(uiColor: readableComfortSecondary)
            )
        case .dark:
            return (
                Color(uiColor: nightSlatePrimary),
                Color(uiColor: nightSlateSecondary)
            )
        case .blossomGlow:
            return (
                Color(uiColor: blossomGlowPrimary),
                Color(uiColor: blossomGlowSecondary)
            )
        case .grayscalePlay:
            return (
                Color(uiColor: grayscalePrimary),
                Color(uiColor: grayscaleSecondary)
            )
        case .pixelPop:
            return (
                Color(uiColor: pixelPopPrimary),
                Color(uiColor: pixelPopSecondary)
            )
        }
    }

    static var primaryUIColor: UIColor {
        switch selectedMode {
        case .blossomGlow:
            return blossomGlowPrimary
        case .grayscalePlay:
            return grayscalePrimary
        case .pixelPop:
            return pixelPopPrimary
        case .light:
            return readableComfortPrimary
        case .dark:
            return nightSlatePrimary
        case .automatic:
            return UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? nightSlatePrimary
                    : signalClearPrimary
            }
        }
    }

    static var secondaryUIColor: UIColor {
        switch selectedMode {
        case .blossomGlow:
            return blossomGlowSecondary
        case .grayscalePlay:
            return grayscaleSecondary
        case .pixelPop:
            return pixelPopSecondary
        case .light:
            return readableComfortSecondary
        case .dark:
            return nightSlateSecondary
        case .automatic:
            return UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? nightSlateSecondary
                    : signalClearSecondary
            }
        }
    }

    static var lightSecondary: Color {
        Color(uiColor: signalClearSecondary)
    }

    private static var selectedMode: HanClipThemeMode {
        let rawValue = UserDefaults.standard.string(
            forKey: "hanClipThemeMode"
        )
        if rawValue == "readableComfort" {
            return .light
        }
        if rawValue == "rosyBrown" || rawValue == "electricCobalt" {
            return .automatic
        }
        return HanClipThemeMode(rawValue: rawValue ?? "")
            ?? .automatic
    }

    private static let golfPrimary = UIColor(
        red: 0.0 / 255.0,
        green: 118.0 / 255.0,
        blue: 68.0 / 255.0,
        alpha: 1
    )
    private static let golfSecondary = UIColor(
        red: 41.0 / 255.0,
        green: 171.0 / 255.0,
        blue: 135.0 / 255.0,
        alpha: 1
    )
    private static let signalClearPrimary = UIColor(
        red: 7.0 / 255.0,
        green: 41.0 / 255.0,
        blue: 49.0 / 255.0,
        alpha: 1
    )
    private static let signalClearSecondary = UIColor(
        red: 0.0 / 255.0,
        green: 126.0 / 255.0,
        blue: 129.0 / 255.0,
        alpha: 1
    )
    private static let signalClearBackground = UIColor(
        red: 248.0 / 255.0,
        green: 251.0 / 255.0,
        blue: 250.0 / 255.0,
        alpha: 1
    )
    private static let signalClearBackgroundWithBlack = UIColor(
        red: 231.0 / 255.0,
        green: 240.0 / 255.0,
        blue: 238.0 / 255.0,
        alpha: 1
    )
    private static let signalClearText = UIColor(
        red: 15.0 / 255.0,
        green: 23.0 / 255.0,
        blue: 42.0 / 255.0,
        alpha: 1
    )
    private static let nightSlatePrimary = UIColor(
        red: 103.0 / 255.0,
        green: 232.0 / 255.0,
        blue: 249.0 / 255.0,
        alpha: 1
    )
    private static let nightSlateSecondary = UIColor(
        red: 82.0 / 255.0,
        green: 115.0 / 255.0,
        blue: 135.0 / 255.0,
        alpha: 1
    )
    private static let nightSlateBackground = UIColor(
        red: 10.0 / 255.0,
        green: 14.0 / 255.0,
        blue: 18.0 / 255.0,
        alpha: 1
    )
    private static let nightSlateBackgroundWithBlack = UIColor(
        red: 17.0 / 255.0,
        green: 24.0 / 255.0,
        blue: 31.0 / 255.0,
        alpha: 1
    )
    private static let nightSlateText = UIColor(
        red: 232.0 / 255.0,
        green: 238.0 / 255.0,
        blue: 242.0 / 255.0,
        alpha: 1
    )
    private static let blossomGlowPrimary = UIColor(
        red: 214.0 / 255.0,
        green: 94.0 / 255.0,
        blue: 122.0 / 255.0,
        alpha: 1
    )
    private static let blossomGlowSecondary = UIColor(
        red: 139.0 / 255.0,
        green: 104.0 / 255.0,
        blue: 151.0 / 255.0,
        alpha: 1
    )
    private static let blossomGlowBackground = UIColor(
        red: 255.0 / 255.0,
        green: 248.0 / 255.0,
        blue: 250.0 / 255.0,
        alpha: 1
    )
    private static let blossomGlowBackgroundWithBlack = UIColor(
        red: 247.0 / 255.0,
        green: 235.0 / 255.0,
        blue: 241.0 / 255.0,
        alpha: 1
    )
    private static let blossomGlowText = UIColor(
        red: 45.0 / 255.0,
        green: 31.0 / 255.0,
        blue: 40.0 / 255.0,
        alpha: 1
    )
    private static let readableComfortPrimary = UIColor(
        red: 0.0 / 255.0,
        green: 34.0 / 255.0,
        blue: 40.0 / 255.0,
        alpha: 1
    )
    private static let readableComfortSecondary = UIColor(
        red: 0.0 / 255.0,
        green: 92.0 / 255.0,
        blue: 96.0 / 255.0,
        alpha: 1
    )
    private static let readableComfortBackground = UIColor(
        red: 250.0 / 255.0,
        green: 254.0 / 255.0,
        blue: 253.0 / 255.0,
        alpha: 1
    )
    private static let readableComfortBackgroundWithBlack = UIColor(
        red: 210.0 / 255.0,
        green: 231.0 / 255.0,
        blue: 229.0 / 255.0,
        alpha: 1
    )
    private static let readableComfortText = UIColor(
        red: 0.0 / 255.0,
        green: 7.0 / 255.0,
        blue: 12.0 / 255.0,
        alpha: 1
    )
    private static let grayscalePrimary = UIColor(
        red: 28.0 / 255.0,
        green: 28.0 / 255.0,
        blue: 30.0 / 255.0,
        alpha: 1
    )
    private static let grayscaleSecondary = UIColor(
        red: 120.0 / 255.0,
        green: 120.0 / 255.0,
        blue: 128.0 / 255.0,
        alpha: 1
    )
    private static let grayscaleBackground = UIColor(
        red: 247.0 / 255.0,
        green: 247.0 / 255.0,
        blue: 248.0 / 255.0,
        alpha: 1
    )
    private static let grayscaleBackgroundWithBlack = UIColor(
        red: 226.0 / 255.0,
        green: 226.0 / 255.0,
        blue: 229.0 / 255.0,
        alpha: 1
    )
    private static let grayscaleText = UIColor(
        red: 18.0 / 255.0,
        green: 18.0 / 255.0,
        blue: 20.0 / 255.0,
        alpha: 1
    )
    private static let pixelPopPrimary = UIColor(
        red: 38.0 / 255.0,
        green: 82.0 / 255.0,
        blue: 255.0 / 255.0,
        alpha: 1
    )
    private static let pixelPopSecondary = UIColor(
        red: 220.0 / 255.0,
        green: 47.0 / 255.0,
        blue: 101.0 / 255.0,
        alpha: 1
    )
    private static let pixelPopBackground = UIColor(
        red: 249.0 / 255.0,
        green: 251.0 / 255.0,
        blue: 255.0 / 255.0,
        alpha: 1
    )
    private static let pixelPopBackgroundWithBlack = UIColor(
        red: 232.0 / 255.0,
        green: 239.0 / 255.0,
        blue: 255.0 / 255.0,
        alpha: 1
    )
    private static let pixelPopText = UIColor(
        red: 15.0 / 255.0,
        green: 22.0 / 255.0,
        blue: 48.0 / 255.0,
        alpha: 1
    )
    static var background: Color {
        if selectedMode == .light {
            return Color(uiColor: readableComfortBackground)
        }
        if selectedMode == .dark {
            return Color(uiColor: nightSlateBackground)
        }
        if selectedMode == .blossomGlow {
            return Color(uiColor: blossomGlowBackground)
        }
        if selectedMode == .grayscalePlay {
            return Color(uiColor: grayscaleBackground)
        }
        if selectedMode == .pixelPop {
            return Color(uiColor: pixelPopBackground)
        }
        return themedColor(light: .white, dark: darkBackground)
    }

    static var backgroundWithBlack: Color {
        if selectedMode == .light {
            return Color(uiColor: readableComfortBackgroundWithBlack)
        }
        if selectedMode == .dark {
            return Color(uiColor: nightSlateBackgroundWithBlack)
        }
        if selectedMode == .blossomGlow {
            return Color(uiColor: blossomGlowBackgroundWithBlack)
        }
        if selectedMode == .grayscalePlay {
            return Color(uiColor: grayscaleBackgroundWithBlack)
        }
        if selectedMode == .pixelPop {
            return Color(uiColor: pixelPopBackgroundWithBlack)
        }
        return themedColor(light: lightBackgroundWithBlack, dark: darkBackgroundWithBlack)
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundWithBlack, background],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var text: Color {
        if selectedMode == .light {
            return Color(uiColor: readableComfortText)
        }
        if selectedMode == .dark {
            return Color(uiColor: nightSlateText)
        }
        if selectedMode == .blossomGlow {
            return Color(uiColor: blossomGlowText)
        }
        if selectedMode == .grayscalePlay {
            return Color(uiColor: grayscaleText)
        }
        if selectedMode == .pixelPop {
            return Color(uiColor: pixelPopText)
        }
        return themedColor(light: black90, dark: .white)
    }

    static var defaultTextBlack: Color {
        Color(uiColor: black90)
    }

    static var primaryText: Color {
        text.opacity(
            selectedMode == .dark
                ? 0.92
                : 0.88
        )
    }

    static var secondaryText: Color {
        text.opacity(
            selectedMode == .dark
                ? 0.66
                : 0.58
        )
    }

    static var mutedIcon: Color {
        text.opacity(
            selectedMode == .dark
                ? 0.52
                : 0.46
        )
    }

    static var panelFill: Color {
        if selectedMode == .light {
            return secondary.opacity(0.18)
        }
        if selectedMode == .dark {
            return Color.white.opacity(0.06)
        }
        if selectedMode == .blossomGlow {
            return secondary.opacity(0.10)
        }
        if selectedMode == .grayscalePlay {
            return secondary.opacity(0.12)
        }
        if selectedMode == .pixelPop {
            return secondary.opacity(0.085)
        }
        return secondary.opacity(selectedMode == .dark ? 0.14 : 0.08)
    }

    static var browserDownloadPanelFill: Color {
        if selectedMode == .light {
            return secondary.opacity(0.36)
        }
        if selectedMode == .dark {
            return Color.white.opacity(0.12)
        }
        if selectedMode == .blossomGlow {
            return secondary.opacity(0.20)
        }
        if selectedMode == .grayscalePlay {
            return secondary.opacity(0.24)
        }
        if selectedMode == .pixelPop {
            return secondary.opacity(0.17)
        }
        return secondary.opacity(selectedMode == .dark ? 0.28 : 0.16)
    }

    static var panelStroke: Color {
        if selectedMode == .light {
            return primary.opacity(0.36)
        }
        if selectedMode == .dark {
            return primary.opacity(0.30)
        }
        if selectedMode == .blossomGlow {
            return primary.opacity(0.20)
        }
        if selectedMode == .grayscalePlay {
            return primary.opacity(0.24)
        }
        if selectedMode == .pixelPop {
            return primary.opacity(0.24)
        }
        return primary.opacity(selectedMode == .dark ? 0.26 : 0.18)
    }

    static var groupFill: Color {
        if selectedMode == .light {
            return secondary.opacity(0.28)
        }
        if selectedMode == .dark {
            return Color.white.opacity(0.08)
        }
        if selectedMode == .blossomGlow {
            return secondary.opacity(0.18)
        }
        if selectedMode == .grayscalePlay {
            return secondary.opacity(0.18)
        }
        if selectedMode == .pixelPop {
            return secondary.opacity(0.15)
        }
        return secondary.opacity(selectedMode == .dark ? 0.24 : 0.16)
    }

    static var childFill: Color {
        if selectedMode == .light {
            return secondary.opacity(0.12)
        }
        if selectedMode == .dark {
            return Color.white.opacity(0.045)
        }
        if selectedMode == .blossomGlow {
            return secondary.opacity(0.065)
        }
        if selectedMode == .grayscalePlay {
            return secondary.opacity(0.075)
        }
        if selectedMode == .pixelPop {
            return primary.opacity(0.055)
        }
        return secondary.opacity(selectedMode == .dark ? 0.11 : 0.045)
    }

    static var separator: Color {
        if selectedMode == .light {
            return primary.opacity(0.34)
        }
        if selectedMode == .dark {
            return primary.opacity(0.22)
        }
        if selectedMode == .blossomGlow {
            return primary.opacity(0.16)
        }
        if selectedMode == .grayscalePlay {
            return primary.opacity(0.20)
        }
        if selectedMode == .pixelPop {
            return primary.opacity(0.18)
        }
        return secondary.opacity(selectedMode == .dark ? 0.22 : 0.14)
    }

    private static let darkBackground = UIColor(
        red: 55.0 / 255.0,
        green: 58.0 / 255.0,
        blue: 54.0 / 255.0,
        alpha: 1
    )
    private static let lightBackgroundWithBlack = UIColor(
        red: 0.96,
        green: 0.96,
        blue: 0.96,
        alpha: 1
    )
    private static let darkBackgroundWithBlack = UIColor(
        red: (55.0 / 255.0) * 0.96,
        green: (58.0 / 255.0) * 0.96,
        blue: (54.0 / 255.0) * 0.96,
        alpha: 1
    )
    private static let black90 = UIColor(
        red: 26.0 / 255.0,
        green: 26.0 / 255.0,
        blue: 26.0 / 255.0,
        alpha: 1
    )

    private static func themedColor(light: UIColor, dark: UIColor) -> Color {
        switch selectedMode {
        case .light, .blossomGlow, .grayscalePlay, .pixelPop:
            return Color(uiColor: light)
        case .dark:
            return Color(uiColor: dark)
        case .automatic:
            return adaptiveColor(light: light, dark: dark)
        }
    }

    private static func adaptiveColor(
        light: UIColor,
        dark: UIColor
    ) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}

enum HanClipQuickAction: Equatable {
    case open
    case aiShot
    case photo
    case quick
    case calendar
    case files
    case search

    init?(url: URL) {
        guard url.scheme == "hanclip" else { return nil }

        let actionName = url.host ?? url.pathComponents.dropFirst().first
        switch actionName {
        case "open":
            self = .open
        case "aishot":
            self = .aiShot
        case "photo":
            self = .photo
        case "quick":
            self = .quick
        case "calendar":
            self = .calendar
        case "files":
            self = .files
        case "search":
            self = .search
        default:
            return nil
        }
    }

    init?(shortcutItem: UIApplicationShortcutItem) {
        switch shortcutItem.type {
        case "com.intosharp.hanclip.aishot":
            self = .aiShot
        case "com.intosharp.hanclip.photo":
            self = .photo
        case "com.intosharp.hanclip.quick":
            self = .quick
        case "com.intosharp.hanclip.calendar":
            self = .calendar
        case "com.intosharp.hanclip.files":
            self = .files
        case "com.intosharp.hanclip.search":
            self = .search
        default:
            return nil
        }
    }
}

struct HanClipGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    var fillOpacity: Double = 0.035
    var strokeOpacity: Double = 0.22
    var shadowOpacity: Double = 0.08

    func body(content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(fillOpacity),
                        HanClipTheme.secondary.opacity(fillOpacity)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.48),
                            HanClipTheme.primary.opacity(strokeOpacity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(
                color: HanClipTheme.secondary.opacity(shadowOpacity),
                radius: 12,
                y: 6
            )
    }
}

extension View {
    func hanClipGlassPanel(
        cornerRadius: CGFloat,
        fillOpacity: Double = 0.035,
        strokeOpacity: Double = 0.22,
        shadowOpacity: Double = 0.08
    ) -> some View {
        modifier(
            HanClipGlassPanelModifier(
                cornerRadius: cornerRadius,
                fillOpacity: fillOpacity,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity
            )
        )
    }
}

@MainActor
final class HanClipQuickActionRouter: ObservableObject {
    static let shared = HanClipQuickActionRouter()

    @Published var pendingAction: HanClipQuickAction?

    func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = HanClipQuickAction(shortcutItem: shortcutItem)
        else { return false }

        pendingAction = action
        return true
    }

    func handle(_ url: URL) -> Bool {
        guard let action = HanClipQuickAction(url: url) else { return false }

        pendingAction = action
        return true
    }

    func clear(_ action: HanClipQuickAction) {
        if pendingAction == action {
            pendingAction = nil
        }
    }
}

final class HanClipAppDelegate: NSObject, UIApplicationDelegate {
    let quickActionRouter = HanClipQuickActionRouter.shared
    var supportedOrientationMask: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        supportedOrientationMask
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]?
    ) -> Bool {
        if let shortcutItem = launchOptions?[.shortcutItem]
            as? UIApplicationShortcutItem {
            return !quickActionRouter.handle(shortcutItem)
        }

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let url = options.urlContexts.first?.url {
            _ = quickActionRouter.handle(url)
        }

        if let shortcutItem = options.shortcutItem {
            _ = quickActionRouter.handle(shortcutItem)
        }

        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = HanClipSceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(quickActionRouter.handle(shortcutItem))
    }
}

final class HanClipSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let url = connectionOptions.urlContexts.first?.url {
            _ = HanClipQuickActionRouter.shared.handle(url)
        }
    }

    func scene(
        _ scene: UIScene,
        openURLContexts URLContexts: Set<UIOpenURLContext>
    ) {
        guard let url = URLContexts.first?.url else { return }
        _ = HanClipQuickActionRouter.shared.handle(url)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(
            HanClipQuickActionRouter.shared.handle(shortcutItem)
        )
    }
}

@main
struct HanClipApp: App {
    @UIApplicationDelegateAdaptor(HanClipAppDelegate.self)
    private var appDelegate
    @StateObject private var purchaseManager =
        CopyrightPurchaseManager.shared

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environmentObject(appDelegate.quickActionRouter)
                .environmentObject(purchaseManager)
                .tint(HanClipTheme.primary)
                .foregroundStyle(HanClipTheme.text)
                .background(HanClipTheme.backgroundGradient)
        }
    }
}
