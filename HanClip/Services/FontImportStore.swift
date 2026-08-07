import CoreText
import Foundation
import SwiftUI
import UIKit

enum CaptionFontCategory: String, CaseIterable, Codable, Identifiable {
    case basic = "기본"
    case golf = "골프"
    case title = "제목"
    case vlog = "브이로그"
    case emotional = "감성"
    case handwriting = "손글씨"

    var id: String { rawValue }
}

struct CaptionFontInfo: Identifiable, Equatable {
    let id: String
    let displayName: String
    let familyName: String
    let category: CaptionFontCategory
    let assetPath: String?
    let availableWeights: [UIFont.Weight]
    let fallbackFont: String
    let licenseFilePath: String?
    let legacyStoredValues: [String]

    var resourceFilename: String? {
        assetPath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    var isSystemFont: Bool {
        id == FontRegistry.systemFontID
    }
}

enum FontRegistry {
    static let systemFontID = "system"
    static let fallbackFontID = systemFontID

    static let fonts: [CaptionFontInfo] = [
        CaptionFontInfo(
            id: systemFontID,
            displayName: "시스템",
            familyName: "",
            category: .basic,
            assetPath: nil,
            availableWeights: [.regular, .semibold, .bold],
            fallbackFont: systemFontID,
            licenseFilePath: nil,
            legacyStoredValues: ["", "System", ".SFUI-Regular"]
        ),
        CaptionFontInfo(
            id: "nanum_gothic",
            displayName: "나눔고딕",
            familyName: "NanumGothic",
            category: .basic,
            assetPath: "Resources/Fonts/NanumGothic-Regular.ttf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/NanumGothic-OFL.txt",
            legacyStoredValues: ["NanumGothic", "NanumGothic-Regular"]
        ),
        CaptionFontInfo(
            id: "kakao",
            displayName: "카카오",
            familyName: "KakaoBigSans-Regular",
            category: .basic,
            assetPath: "Resources/Fonts/KakaoBigSans-Regular.ttf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/KakaoBigSans-OFL.txt",
            legacyStoredValues: ["KakaoBigSans-Regular", "Kakao Big Sans"]
        ),
        CaptionFontInfo(
            id: "pretendard",
            displayName: "프리텐다드",
            familyName: "Pretendard-Regular",
            category: .basic,
            assetPath: "Resources/Fonts/Pretendard-Regular.otf",
            availableWeights: [.regular, .bold],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/Pretendard-LICENSE.txt",
            legacyStoredValues: ["Pretendard", "Pretendard-Regular"]
        ),
        CaptionFontInfo(
            id: "pretendard_bold",
            displayName: "프리텐다드B",
            familyName: "Pretendard-Bold",
            category: .basic,
            assetPath: "Resources/Fonts/Pretendard-Bold.ttf",
            availableWeights: [.bold],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/Pretendard-LICENSE.txt",
            legacyStoredValues: ["Pretendard-Bold", "Pretendard Bold"]
        ),
        CaptionFontInfo(
            id: "nexon_lv1_gothic",
            displayName: "넥슨 Lv.1 고딕",
            familyName: "NEXONLv1GothicRegular",
            category: .basic,
            assetPath: "Resources/Fonts/NEXONLv1GothicRegular.ttf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/NEXONLv1Gothic-LICENSE.txt",
            legacyStoredValues: ["NEXON Lv1 Gothic", "NEXONLv1GothicRegular"]
        ),
        CaptionFontInfo(
            id: "poppins",
            displayName: "Poppins",
            familyName: "Poppins-Regular",
            category: .vlog,
            assetPath: "Resources/Fonts/Poppins-Regular.ttf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/Poppins-OFL.txt",
            legacyStoredValues: ["Poppins", "Poppins-Regular"]
        ),
        CaptionFontInfo(
            id: "puradak_gentle",
            displayName: "젠틀고딕",
            familyName: "PuradakGentleGothicR",
            category: .golf,
            assetPath: "Resources/Fonts/PuradakGentleGothic.ttf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/PuradakGentleGothic-LICENSE.txt",
            legacyStoredValues: [
                "PuradakGentleGothic",
                "Puradak Gentle Gothic"
            ]
        ),
        CaptionFontInfo(
            id: "tenada",
            displayName: "태나다",
            familyName: "Tenada",
            category: .title,
            assetPath: "Resources/Fonts/Tenada.ttf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/Tenada-LICENSE.txt",
            legacyStoredValues: ["Tenada"]
        ),
        CaptionFontInfo(
            id: "cafe24_ssurround",
            displayName: "써라운드",
            familyName: "Cafe24Ssurround",
            category: .vlog,
            assetPath: "Resources/Fonts/Cafe24Ssurround.ttf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/Cafe24Ssurround-LICENSE.txt",
            legacyStoredValues: ["Cafe24Ssurround", "Cafe24Surround"]
        ),
        CaptionFontInfo(
            id: "maruburi",
            displayName: "마루부리",
            familyName: "MaruBuri-Regular",
            category: .emotional,
            assetPath: "Resources/Fonts/MaruBuri-Regular.ttf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/MaruBuri-LICENSE.txt",
            legacyStoredValues: ["MaruBuri-Regular", "MaruBuri"]
        ),
        CaptionFontInfo(
            id: "gowun_dodum",
            displayName: "고운돋움",
            familyName: "GowunDodum-Regular",
            category: .emotional,
            assetPath: "Resources/Fonts/GowunDodum-Regular.ttf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/GowunDodum-OFL.txt",
            legacyStoredValues: ["GowunDodum-Regular", "Gowun Dodum"]
        ),
        CaptionFontInfo(
            id: "gowun_batang",
            displayName: "고운바탕",
            familyName: "GowunBatang-Regular",
            category: .emotional,
            assetPath: "Resources/Fonts/GowunBatang-Regular.ttf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/GowunBatang-OFL.txt",
            legacyStoredValues: ["GowunBatang-Regular", "Gowun Batang"]
        ),
        CaptionFontInfo(
            id: "black_han_sans",
            displayName: "검은고딕",
            familyName: "BlackHanSans-Regular",
            category: .title,
            assetPath: "Resources/Fonts/BlackHanSans-Regular.ttf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/BlackHanSans-OFL.txt",
            legacyStoredValues: ["BlackHanSans-Regular", "Black Han Sans"]
        ),
        CaptionFontInfo(
            id: "paperlogy_bold",
            displayName: "페이퍼로지 Bold",
            familyName: "Paperlogy-7Bold",
            category: .title,
            assetPath: "Resources/Fonts/Paperlogy-7Bold.ttf",
            availableWeights: [.bold],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/Paperlogy-OFL.txt",
            legacyStoredValues: ["Paperlogy", "Paperlogy-7Bold"]
        ),
        CaptionFontInfo(
            id: "do_hyeon",
            displayName: "도현",
            familyName: "DoHyeon-Regular",
            category: .vlog,
            assetPath: "Resources/Fonts/DoHyeon-Regular.ttf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/DoHyeon-OFL.txt",
            legacyStoredValues: ["DoHyeon-Regular", "Do Hyeon"]
        ),
        CaptionFontInfo(
            id: "ddulgi_mayo",
            displayName: "둘기마요",
            familyName: "Dovemayo-Medium",
            category: .handwriting,
            assetPath: "Resources/Fonts/DdulgiMayo.otf",
            availableWeights: [.regular],
            fallbackFont: systemFontID,
            licenseFilePath: "Resources/font-licenses/DdulgiMayo-LICENSE.txt",
            legacyStoredValues: ["Dovemayo-Medium", "DulgiMayo", "DdulgiMayo"]
        )
    ]

    static var availableFonts: [CaptionFontInfo] {
        fonts.filter { $0.isSystemFont || bundledFontURL(for: $0) != nil }
    }

    static var bundledFontFilenames: Set<String> {
        Set(fonts.compactMap(\.resourceFilename))
    }

    static func font(for id: String) -> CaptionFontInfo {
        fonts.first { $0.id == normalizedID(forStoredValue: id) }
            ?? fonts[0]
    }

    static func normalizedID(forStoredValue value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return systemFontID }
        if fonts.contains(where: { $0.id == trimmed }) {
            return trimmed
        }
        return fonts.first { font in
            font.legacyStoredValues.contains(trimmed)
        }?.id ?? systemFontID
    }

    static func resolvedUIFont(
        for id: String,
        size: CGFloat,
        weight: UIFont.Weight = .semibold
    ) -> UIFont {
        let font = self.font(for: id)
        guard !font.isSystemFont else {
            return .systemFont(ofSize: size, weight: weight)
        }
        register(font)
        return UIFont(name: font.familyName, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: weight)
    }

    static func resolvedSwiftUIFont(
        for id: String,
        size: CGFloat,
        weight: Font.Weight = .semibold
    ) -> Font {
        let font = self.font(for: id)
        guard !font.isSystemFont else {
            return .system(size: size, weight: weight)
        }
        register(font)
        guard UIFont(name: font.familyName, size: size) != nil else {
            return .system(size: size, weight: weight)
        }
        return .custom(font.familyName, size: size)
    }

    @discardableResult
    static func register(_ font: CaptionFontInfo) -> Bool {
        guard !font.isSystemFont,
              let url = bundledFontURL(for: font)
        else { return font.isSystemFont }
        return FontImportStore.registerFontIfNeeded(at: url)
    }

    @discardableResult
    static func registerBundledCaptionFonts() -> [String] {
        fonts
            .filter { !$0.isSystemFont }
            .compactMap { font in
                register(font) ? font.familyName : nil
            }
    }

    static func bundledFontURL(for font: CaptionFontInfo) -> URL? {
        guard let filename = font.resourceFilename else { return nil }
        let sourceURL = URL(fileURLWithPath: filename)
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        return Bundle.main.url(forResource: baseName, withExtension: ext)
            ?? Bundle.main.url(
                forResource: baseName,
                withExtension: ext,
                subdirectory: "Resources/Fonts"
            )
    }
}

enum FontImportStore {
    private static let folderName = "ImportedFonts"
    private static let supportedExtensions = Set(["ttf", "otf", "ttc"])
    private static let allowedBundledFontFilenames = Set([
        "NanumGothic-Regular.ttf",
        "KakaoBigSans-Regular.ttf",
        "Pretendard-Bold.ttf"
    ]).union(FontRegistry.bundledFontFilenames)
    private static var registeredFontPaths = Set<String>()

    static var importedFontNames: [String] {
        bundledFontNames
    }

    static var bundledFontNames: [String] {
        Array(Set(registerBundledFonts())).sorted()
    }

    static var userFontNames: [String] {
        Array(Set(registerPersistedFonts())).sorted()
    }

    @discardableResult
    static func registerBundledFonts() -> [String] {
        bundledFontFileURLs().flatMap { url in
            fontNames(in: url)
        }
    }

    @discardableResult
    static func registerPersistedFonts() -> [String] {
        fontFileURLs().flatMap { url in
            registerFontIfNeeded(at: url)
            return fontNames(in: url)
        }
    }

    static func importFonts(from urls: [URL]) throws -> [String] {
        let folder = try fontsFolder()
        var importedNames: [String] = []

        for sourceURL in urls {
            guard supportedExtensions.contains(
                sourceURL.pathExtension.lowercased()
            ) else {
                continue
            }

            let canAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let destination = uniqueDestination(
                for: sourceURL.lastPathComponent,
                in: folder
            )
            try FileManager.default.copyItem(
                at: sourceURL,
                to: destination
            )
            registerFontIfNeeded(at: destination)
            importedNames.append(contentsOf: fontNames(in: destination))
        }

        return Array(Set(importedNames)).sorted()
    }

    @discardableResult
    static func registerFontIfNeeded(at url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard !registeredFontPaths.contains(path) else { return true }

        let names = fontNames(in: url)
        if !names.isEmpty,
           names.allSatisfy({ UIFont(name: $0, size: 1) != nil }) {
            registeredFontPaths.insert(path)
            return true
        }

        var error: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(
            url as CFURL,
            .process,
            &error
        )
        registeredFontPaths.insert(path)
        return didRegister || error == nil
    }

    private static func fontNames(in url: URL) -> [String] {
        guard let descriptors =
            CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                as? [CTFontDescriptor]
        else {
            return []
        }

        return descriptors.compactMap { descriptor in
            CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontNameAttribute
            ) as? String
        }
    }

    private static func fontFileURLs() -> [URL] {
        guard let folder = try? fontsFolder(),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil
              )
        else {
            return []
        }

        return contents.filter {
            supportedExtensions.contains($0.pathExtension.lowercased())
        }
    }

    private static func bundledFontFileURLs() -> [URL] {
        let registryURLs = FontRegistry.fonts.compactMap {
            FontRegistry.bundledFontURL(for: $0)
        }
        return (supportedExtensions.flatMap { ext in
            Bundle.main.urls(
                forResourcesWithExtension: ext,
                subdirectory: nil
            ) ?? []
        } + registryURLs).filter {
            allowedBundledFontFilenames.contains($0.lastPathComponent)
        }
    }

    private static func fontsFolder() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = support.appendingPathComponent(
            folderName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder
    }

    private static func uniqueDestination(
        for filename: String,
        in folder: URL
    ) -> URL {
        let source = URL(fileURLWithPath: filename)
        let baseName = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var candidate = folder.appendingPathComponent(filename)
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(
                "\(baseName)-\(suffix).\(ext)"
            )
            suffix += 1
        }

        return candidate
    }
}
