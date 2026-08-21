import Foundation

public enum OAuthCredentialPathDiscovery {
    public static func defaultPath(
        for provider: QuotaProviderID,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let relativePath: String
        switch provider {
        case .claude:
            relativePath = ".claude/.credentials.json"
        case .codex:
            relativePath = ".codex/auth.json"
        }
        return homeDirectory.appendingPathComponent(relativePath).path
    }

    public static func existingPath(
        for provider: QuotaProviderID,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        let path = defaultPath(for: provider, homeDirectory: homeDirectory)
        guard fileManager.isReadableFile(atPath: path) else { return nil }
        return path
    }
}
