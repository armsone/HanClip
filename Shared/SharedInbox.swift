import Foundation

enum SharedImportDestination: String {
    case newProject
    case existingProject
}

enum SharedInbox {
    static let appGroup = "group.com.intosharp.hanclip"
    private static let queueKey = "pending-import-records"
    private static let destinationKey = "pending-import-destination"

    static func containerURL() throws -> URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            throw InboxError.appGroupUnavailable
        }
        let inbox = url.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(
            at: inbox,
            withIntermediateDirectories: true
        )
        return inbox
    }

    static func append(_ records: [SharedImportRecord]) {
        guard !records.isEmpty,
              let defaults = UserDefaults(suiteName: appGroup) else { return }

        var existing = pendingRecords()
        existing.append(contentsOf: records)
        if let encoded = try? JSONEncoder().encode(existing) {
            defaults.set(encoded, forKey: queueKey)
        }
    }

    static func pendingRecords() -> [SharedImportRecord] {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: queueKey),
              let records = try? JSONDecoder().decode(
                [SharedImportRecord].self,
                from: data
              ) else {
            return []
        }
        return records
    }

    static func consumePendingRecords() -> [SharedImportRecord] {
        let records = pendingRecords()
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: queueKey)
        return records
    }

    static func clearPendingImports() {
        let records = pendingRecords()
        for record in records {
            if let primary = try? fileURL(
                named: record.primaryFilename
            ) {
                try? FileManager.default.removeItem(at: primary)
            }
            if let secondaryFilename = record.secondaryFilename,
               let secondary = try? fileURL(
                named: secondaryFilename
               ) {
                try? FileManager.default.removeItem(at: secondary)
            }
        }

        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.removeObject(forKey: queueKey)
        defaults?.removeObject(forKey: destinationKey)
    }

    static func setImportDestination(
        _ destination: SharedImportDestination
    ) {
        UserDefaults(suiteName: appGroup)?.set(
            destination.rawValue,
            forKey: destinationKey
        )
    }

    static func consumeImportDestination()
        -> SharedImportDestination? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let rawValue = defaults.string(forKey: destinationKey)
        else { return nil }
        defaults.removeObject(forKey: destinationKey)
        return SharedImportDestination(rawValue: rawValue)
    }

    static func fileURL(named filename: String) throws -> URL {
        try containerURL().appendingPathComponent(filename)
    }

    enum InboxError: LocalizedError {
        case appGroupUnavailable

        var errorDescription: String? {
            "HanClip 공동 보관함을 열 수 없습니다."
        }
    }
}
