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
                Color(uiColor: electricCobaltSecondary)
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
            return electricCobaltSecondary
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
        red: 169.0 / 255.0,
        green: 111.0 / 255.0,
        blue: 103.0 / 255.0,
        alpha: 1
    )
    private static let dimGray = UIColor(
        red: 92.0 / 255.0,
        green: 86.0 / 255.0,
        blue: 80.0 / 255.0,
        alpha: 1
    )
    private static let electricCobalt = UIColor(
        red: 0.0 / 255.0,
        green: 71.0 / 255.0,
        blue: 255.0 / 255.0,
        alpha: 1
    )
    private static let electricCobaltSecondary = UIColor(
        red: 0.0 / 255.0,
        green: 153.0 / 255.0,
        blue: 255.0 / 255.0,
        alpha: 1
    )
    private static let electricCobaltBackground = UIColor(
        red: 240.0 / 255.0,
        green: 248.0 / 255.0,
        blue: 255.0 / 255.0,
        alpha: 1
    )
    private static let electricCobaltBackgroundWithBlack = UIColor(
        red: 222.0 / 255.0,
        green: 239.0 / 255.0,
        blue: 255.0 / 255.0,
        alpha: 1
    )
    private static let electricCobaltText = UIColor(
        red: 10.0 / 255.0,
        green: 22.0 / 255.0,
        blue: 62.0 / 255.0,
        alpha: 1
    )
    static var background: Color {
        if selectedMode == .electricCobalt {
            return Color(uiColor: electricCobaltBackground)
        }
        return themedColor(light: .white, dark: darkBackground)
    }

    static var backgroundWithBlack: Color {
        if selectedMode == .electricCobalt {
            return Color(uiColor: electricCobaltBackgroundWithBlack)
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
        if selectedMode == .electricCobalt {
            return Color(uiColor: electricCobaltText)
        }
        return themedColor(light: black90, dark: .white)
    }

    static var defaultTextBlack: Color {
        Color(uiColor: black90)
    }

    static var primaryText: Color {
        text.opacity(selectedMode == .dark ? 0.92 : 0.88)
    }

    static var secondaryText: Color {
        text.opacity(selectedMode == .dark ? 0.66 : 0.58)
    }

    static var mutedIcon: Color {
        text.opacity(selectedMode == .dark ? 0.52 : 0.46)
    }

    static var panelFill: Color {
        if selectedMode == .electricCobalt {
            return secondary.opacity(0.105)
        }
        return secondary.opacity(selectedMode == .dark ? 0.14 : 0.08)
    }

    static var panelStroke: Color {
        if selectedMode == .electricCobalt {
            return primary.opacity(0.22)
        }
        return primary.opacity(selectedMode == .dark ? 0.26 : 0.18)
    }

    static var groupFill: Color {
        if selectedMode == .electricCobalt {
            return secondary.opacity(0.18)
        }
        return secondary.opacity(selectedMode == .dark ? 0.24 : 0.16)
    }

    static var childFill: Color {
        if selectedMode == .electricCobalt {
            return secondary.opacity(0.075)
        }
        return secondary.opacity(selectedMode == .dark ? 0.11 : 0.045)
    }

    static var separator: Color {
        if selectedMode == .electricCobalt {
            return secondary.opacity(0.24)
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
    case open
    case photo
    case calendar
    case files

    init?(url: URL) {
        guard url.scheme == "hanclip" else { return nil }

        let actionName = url.host ?? url.pathComponents.dropFirst().first
        switch actionName {
        case "open":
            self = .open
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

struct HanClipGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    var fillOpacity: Double = 0.035
    var strokeOpacity: Double = 0.22
    var shadowOpacity: Double = 0.08

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(fillOpacity),
                        HanClipTheme.secondary.opacity(fillOpacity)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
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
                    _ = FontImportStore.importedFontNames
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onChange(of: scenePhase) { _, phase in
                    UIApplication.shared.isIdleTimerDisabled = phase == .active
                }
        }
    }
}
