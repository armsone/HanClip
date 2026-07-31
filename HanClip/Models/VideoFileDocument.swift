import SwiftUI
import UniformTypeIdentifiers

struct VideoFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.mpeg4Movie] }

    let sourceURL: URL

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HanClip-Imported-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        try data.write(to: url)
        sourceURL = url
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: sourceURL, options: .immediate)
    }
}
