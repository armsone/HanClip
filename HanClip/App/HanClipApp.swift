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
        case .light:
            return .light
        case .dark:
            return .dark
        case .automatic, .rosyBrown, .electricCobalt:
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
        case .light, .dark, .automatic:
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
        case .light, .dark, .automatic:
            return UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? golfPrimary
                    : golfSecondary
            }
        }
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
    static let background = adaptiveColor(
        light: .white,
        dark: UIColor(
            red: 55.0 / 255.0,
            green: 58.0 / 255.0,
            blue: 54.0 / 255.0,
            alpha: 1
        )
    )
    static let backgroundWithBlack = adaptiveColor(
        light: UIColor(
            red: 0.96,
            green: 0.96,
            blue: 0.96,
            alpha: 1
        ),
        dark: UIColor(
            red: (55.0 / 255.0) * 0.96,
            green: (58.0 / 255.0) * 0.96,
            blue: (54.0 / 255.0) * 0.96,
            alpha: 1
        )
    )
    static let backgroundGradient = LinearGradient(
        colors: [backgroundWithBlack, background],
        startPoint: .top,
        endPoint: .bottom
    )
    static let text = adaptiveColor(
        light: .black,
        dark: .white
    )

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

@main
struct HanClipApp: App {
    var body: some Scene {
        WindowGroup {
            EditorView()
                .tint(HanClipTheme.primary)
                .foregroundStyle(HanClipTheme.text)
                .background(HanClipTheme.backgroundGradient)
        }
    }
}
