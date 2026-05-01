import Foundation

private enum PreviewTemporaryStorageError: LocalizedError, CustomNSError {
    case missingCachesDirectory

    static var errorDomain: String {
        "EPSQuickLook.Storage"
    }

    var errorCode: Int {
        switch self {
        case .missingCachesDirectory:
            return 1
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingCachesDirectory:
            return "The caches directory is unavailable."
        }
    }
}

enum TemporaryCleanupIntervalOption: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case twelveHours = "12h"
    case oneDay = "1d"
    case threeDays = "3d"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour:
            return "1 hour"
        case .twelveHours:
            return "12 hours"
        case .oneDay:
            return "1 day"
        case .threeDays:
            return "3 days"
        }
    }

    var retentionInterval: TimeInterval {
        switch self {
        case .oneHour:
            return 60 * 60
        case .twelveHours:
            return 12 * 60 * 60
        case .oneDay:
            return 24 * 60 * 60
        case .threeDays:
            return 3 * 24 * 60 * 60
        }
    }

    static let defaultOption: TemporaryCleanupIntervalOption = .threeDays
}

enum PreviewTemporaryStorage {
    static let appGroupIdentifier = "group.com.flew.eps-quick-look"
    static let temporaryCleanupIntervalDefaultsKey = "temporaryCleanupInterval"

    private static let managedTemporaryDirectoryName = "EPSQuickLook"
    private static let temporaryDirectoryName = "Temporary"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private static var configuredCleanupIntervalOption: TemporaryCleanupIntervalOption {
        guard let rawValue = sharedDefaults?.string(forKey: temporaryCleanupIntervalDefaultsKey),
              let option = TemporaryCleanupIntervalOption(rawValue: rawValue) else {
            return .defaultOption
        }
        return option
    }

    static func registerDefaults() {
        sharedDefaults?.register(defaults: [
            temporaryCleanupIntervalDefaultsKey: TemporaryCleanupIntervalOption.defaultOption.rawValue
        ])
    }

    static func makeManagedTemporaryDirectory(prefix: String) throws -> URL {
        guard let cachesDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw PreviewTemporaryStorageError.missingCachesDirectory
        }

        let temporaryRootURL = cachesDirectoryURL
            .appendingPathComponent(managedTemporaryDirectoryName, isDirectory: true)
            .appendingPathComponent(temporaryDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRootURL, withIntermediateDirectories: true)
        cleanupManagedTemporaryDirectories(in: temporaryRootURL)

        let temporaryDirectory = temporaryRootURL
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        return temporaryDirectory
    }

    private static func cleanupManagedTemporaryDirectories(in temporaryRootURL: URL) {
        let fileManager = FileManager.default
        let cutoffDate = Date().addingTimeInterval(-configuredCleanupIntervalOption.retentionInterval)
        let resourceKeys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]

        guard let itemURLs = try? fileManager.contentsOfDirectory(
            at: temporaryRootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for itemURL in itemURLs {
            guard let resourceValues = try? itemURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }

            let referenceDate = resourceValues.contentModificationDate ?? resourceValues.creationDate ?? .distantFuture
            guard referenceDate < cutoffDate else {
                continue
            }

            try? fileManager.removeItem(at: itemURL)
        }
    }
}
