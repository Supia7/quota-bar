import Foundation

public struct AccountDisplayPreference: Codable, Equatable, Sendable {
    public var alias: String
    public var isEmailHidden: Bool

    public init(alias: String, isEmailHidden: Bool) {
        self.alias = alias
        self.isEmailHidden = isEmailHidden
    }
}

public struct JSONAccountDisplayPreferencesStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = JSONAccountDisplayPreferencesStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() throws -> [UUID: AccountDisplayPreference] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([UUID: AccountDisplayPreference].self, from: data)
    }

    public func save(_ preferences: [UUID: AccountDisplayPreference]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(preferences).write(to: fileURL, options: .atomic)
    }

    public static func defaultFileURL(
        fileManager: FileManager = .default
    ) -> URL {
        let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return supportDirectory
            .appendingPathComponent("QuotaBar", isDirectory: true)
            .appendingPathComponent("display-preferences.json")
    }
}
