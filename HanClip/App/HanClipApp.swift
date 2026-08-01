import SwiftUI
import UIKit

enum HanClipThemeMode: String, CaseIterable {
    case automatic
    case light
    case dark
    case rosyBrown
    case electricCobalt

    var colorScheme: ColorScheme? {
        switch self {
        case .light, .rosyBrown, .electricCobalt:
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
        case .rosyBrown:
            return "Rosy Brown"
        case .electricCobalt:
            return "Electric Cobalt"
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
        selectedMode == .electricCobalt
            ? Color(uiColor: electricCobalt)
            : .white
    }

    static func previewColors(
        for mode: HanClipThemeMode
    ) -> (primary: Color, secondary: Color)? {
        switch mode {
        case .automatic:
            return nil
        case .light:
            return (
                Color(uiColor: golfPrimary),
                Color(uiColor: golfSecondary)
            )
        case .dark:
            return (
                Color(uiColor: golfSecondary),
                Color(uiColor: golfPrimary)
            )
        case .rosyBrown:
            return (
                Color(uiColor: rosyBrown),
                Color(uiColor: dimGray)
            )
        case .electricCobalt:
            return (
                Color(uiColor: electricCobalt),
                Color(uiColor: gray50)
            )
        }
    }

    static var primaryUIColor: UIColor {
        switch selectedMode {
        case .rosyBrown:
            return rosyBrown
        case .electricCobalt:
            return electricCobalt
        case .light:
            return golfPrimary
        case .dark:
            return golfSecondary
        case .automatic:
            return UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? golfSecondary
                    : golfPrimary
            }
        }
    }

    static var secondaryUIColor: UIColor {
        switch selectedMode {
        case .rosyBrown:
            return dimGray
        case .electricCobalt:
            return gray50
        case .light:
            return golfSecondary
        case .dark:
            return golfPrimary
        case .automatic:
            return UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? golfPrimary
                    : golfSecondary
            }
        }
    }

    static var rosyBrownPrimary: Color {
        Color(uiColor: rosyBrown)
    }

    static var lightSecondary: Color {
        Color(uiColor: golfSecondary)
    }

    private static var selectedMode: HanClipThemeMode {
        let rawValue = UserDefaults.standard.string(
            forKey: "hanClipThemeMode"
        )
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
    private static let rosyBrown = UIColor(
        red: 201.0 / 255.0,
        green: 132.0 / 255.0,
        blue: 122.0 / 255.0,
        alpha: 1
    )
    private static let dimGray = UIColor(
        red: 74.0 / 255.0,
        green: 85.0 / 255.0,
        blue: 104.0 / 255.0,
        alpha: 1
    )
    private static let electricCobalt = UIColor(
        red: 0.0 / 255.0,
        green: 71.0 / 255.0,
        blue: 255.0 / 255.0,
        alpha: 1
    )
    private static let gray50 = UIColor(
        red: 128.0 / 255.0,
        green: 128.0 / 255.0,
        blue: 128.0 / 255.0,
        alpha: 1
    )
    static var background: Color {
        themedColor(light: .white, dark: darkBackground)
    }

    static var backgroundWithBlack: Color {
        themedColor(light: lightBackgroundWithBlack, dark: darkBackgroundWithBlack)
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundWithBlack, background],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var text: Color {
        themedColor(light: black90, dark: .white)
    }

    static var defaultTextBlack: Color {
        Color(uiColor: black90)
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
        case .light, .rosyBrown, .electricCobalt:
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
    case photo
    case calendar
    case files

    init?(url: URL) {
        guard url.scheme == "hanclip" else { return nil }

        let actionName = url.host ?? url.pathComponents.dropFirst().first
        switch actionName {
        case "photo":
            self = .photo
        case "calendar":
            self = .calendar
        case "files":
            self = .files
        default:
            return nil
        }
    }

    init?(shortcutItem: UIApplicationShortcutItem) {
        switch shortcutItem.type {
        case "com.intosharp.hanclip.photo":
            self = .photo
        case "com.intosharp.hanclip.calendar":
            self = .calendar
        case "com.intosharp.hanclip.files":
            self = .files
        default:
            return nil
        }
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
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environmentObject(appDelegate.quickActionRouter)
                .tint(HanClipTheme.primary)
                .foregroundStyle(HanClipTheme.text)
                .background(HanClipTheme.backgroundGradient)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onChange(of: scenePhase) { _, phase in
                    UIApplication.shared.isIdleTimerDisabled = phase == .active
                }
        }
    }
}
