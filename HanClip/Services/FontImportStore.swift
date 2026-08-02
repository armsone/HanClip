import CoreText
import Foundation
import UIKit

enum FontImportStore {
    private static let folderName = "ImportedFonts"
    private static let supportedExtensions = Set(["ttf", "otf", "ttc"])
    private static let allowedBundledFontFilenames = Set([
        "NanumGothic-Regular.ttf",
        "KakaoBigSans-Regular.ttf"
    ])
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

    private static func registerFontIfNeeded(at url: URL) {
        let path = url.standardizedFileURL.path
        guard !registeredFontPaths.contains(path) else { return }

        let names = fontNames(in: url)
        if !names.isEmpty,
           names.allSatisfy({ UIFont(name: $0, size: 1) != nil }) {
            registeredFontPaths.insert(path)
            return
        }

        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(
            url as CFURL,
            .process,
            &error
        )
        registeredFontPaths.insert(path)
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
        supportedExtensions.flatMap { ext in
            Bundle.main.urls(
                forResourcesWithExtension: ext,
                subdirectory: nil
            ) ?? []
        }
        .filter {
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
