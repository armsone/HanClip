import Foundation

struct SharedImportRecord: Codable, Identifiable {
    enum Kind: String, Codable {
        case image
        case video
        case livePhoto
    }

    let id: UUID
    let kind: Kind
    let primaryFilename: String
    let secondaryFilename: String?
    let originalFilename: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        primaryFilename: String,
        secondaryFilename: String? = nil,
        originalFilename: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.primaryFilename = primaryFilename
        self.secondaryFilename = secondaryFilename
        self.originalFilename = originalFilename
    }
}
