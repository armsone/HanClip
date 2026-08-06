import Foundation

struct SharedImportRecord: Codable, Identifiable {
    enum Kind: String, Codable {
        case image
        case video
        case livePhoto
        case browserFavorites
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

struct BrowserFavoritesArchive: Codable {
    static let typeIdentifier = "com.intosharp.hanclip.browser-favorites"
    static let filenameExtension = "hanclipfavorites"

    let version: Int
    let favorites: [String]

    init(favorites: [String]) {
        version = 1
        self.favorites = favorites
    }
}
