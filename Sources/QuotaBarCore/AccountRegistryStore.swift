import Foundation

public enum AccountRegistryStoreError: Error, Equatable {
    case invalidDirectory
}

public struct JSONAccountRegistryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = JSONAccountRegistryStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() throws -> AccountRegistry {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AccountRegistry()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AccountRegistry.self, from: data)
    }

    public func save(_ registry: AccountRegistry) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.pretty.encode(registry)
        try data.write(to: fileURL, options: .atomic)
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
            .appendingPathComponent("accounts.json")
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
