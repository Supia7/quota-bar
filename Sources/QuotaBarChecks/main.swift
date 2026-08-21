import Foundation
import QuotaBarCore

@main
enum QuotaBarChecks {
    static func main() async throws {
        try check(
            QuotaWindow(
                id: "over",
                kind: .fiveHour,
                title: "5-hour window",
                remainingFraction: 1.4,
                resetAt: nil
            ).remainingFraction == 1,
            "remaining fraction must clamp its upper bound"
        )
        try check(
            QuotaWindow(
                id: "under",
                kind: .weekly,
                title: "Weekly",
                remainingFraction: -0.2,
                resetAt: nil
            ).remainingFraction == 0,
            "remaining fraction must clamp its lower bound"
        )
        try check(
            QuotaWindow(
                id: "weekly",
                kind: .weekly,
                title: "Weekly",
                remainingFraction: 0.876,
                resetAt: nil
            ).remainingPercentage == 88,
            "remaining percentage must round for display"
        )

        let account = QuotaAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            provider: .claude,
            alias: "Work Claude",
            email: "work@example.com",
            isEmailHidden: false,
            windows: [
                QuotaWindow(
                    id: "claude-five-hour",
                    kind: .fiveHour,
                    title: "5-hour window",
                    remainingFraction: 0.8,
                    resetAt: nil
                ),
                QuotaWindow(
                    id: "claude-weekly",
                    kind: .weekly,
                    title: "Weekly",
                    remainingFraction: 0.5,
                    resetAt: nil
                ),
                QuotaWindow(
                    id: "claude-fable",
                    kind: .fableWeekly,
                    title: "Fable weekly",
                    remainingFraction: 0.3,
                    resetAt: nil
                )
            ],
            isSampleData: false
        )
        try check(account.displayName == "Work Claude", "alias must be the primary label")
        try check(account.visibleEmail == "work@example.com", "email must be visible by default")
        try check(account.withEmailHidden.visibleEmail == nil, "email hiding must affect display only")

        let secondAccount = QuotaAccount(
            provider: .codex,
            alias: "Personal Codex",
            email: "personal@example.com",
            windows: [
                QuotaWindow(
                    id: "codex-weekly",
                    kind: .weekly,
                    title: "Weekly",
                    remainingFraction: 0.6,
                    resetAt: nil
                )
            ],
            isSampleData: false
        )
        let accounts = [account, secondAccount]
        let accountGroups = QuotaGrouping.groups(accounts: accounts, mode: .account)
        try check(accountGroups.count == 2, "account view must keep one group per account")
        let limitGroups = QuotaGrouping.groups(accounts: accounts, mode: .limitType)
        try check(limitGroups.count == 3, "limit view must group five-hour, weekly, and Fable rows")
        try check(
            limitGroups.first(where: { $0.kind == .weekly })?.rows.count == 2,
            "weekly limit group must contain every matching account"
        )

        let claudeFixture = try JSONSerialization.data(withJSONObject: [
            "five_hour": [
                "utilization": 33.0,
                "resets_at": "2026-08-21T12:00:00Z"
            ] as [String: Any],
            "seven_day": [
                "utilization": 44.0,
                "resets_at": "2026-08-25T12:00:00Z"
            ] as [String: Any],
            "limits": [
                [
                    "kind": "weekly_scoped",
                    "percent": 28.0,
                    "resets_at": "2026-08-24T12:00:00Z",
                    "scope": ["model": ["display_name": "Fable"] as [String: Any]] as [String: Any]
                ] as [String: Any]
            ] as [[String: Any]]
        ] as [String: Any])
        let claudeWindows = try ClaudeUsageDecoder.decode(claudeFixture)
        try check(claudeWindows.count == 3, "Claude decoder must return 5-hour, weekly, and Fable windows")
        try check(
            claudeWindows.first(where: { $0.kind == .fiveHour })?.remainingPercentage == 67,
            "Claude 5-hour usage must be converted to remaining percentage"
        )
        try check(
            claudeWindows.first(where: { $0.kind == .fableWeekly })?.remainingPercentage == 72,
            "Claude Fable usage must be converted to remaining percentage"
        )

        let codexFixture = try JSONSerialization.data(withJSONObject: [
            "plan_type": "pro",
            "rate_limit": [
                "secondary_window": [
                    "used_percent": 37,
                    "reset_at": 1780000000,
                    "limit_window_seconds": 604800
                ] as [String: Any]
            ] as [String: Any],
            "email": "codex@example.com"
        ] as [String: Any])
        let codexWindows = try CodexUsageDecoder.decode(codexFixture)
        try check(codexWindows.count == 1, "Codex decoder must expose the weekly subscription window")
        try check(
            codexWindows[0].remainingPercentage == 63,
            "Codex weekly usage must be converted to remaining percentage"
        )

        let codexPrimaryFixture = try JSONSerialization.data(withJSONObject: [
            "rate_limit": [
                "primary_window": [
                    "used_percent": 58,
                    "reset_at": 1_787_803_166,
                    "limit_window_seconds": 604_800
                ] as [String: Any],
                "secondary_window": NSNull()
            ] as [String: Any]
        ] as [String: Any])
        let codexPrimaryWindows = try CodexUsageDecoder.decode(codexPrimaryFixture)
        try check(
            codexPrimaryWindows.count == 1 && codexPrimaryWindows[0].remainingPercentage == 42,
            "Codex decoder must fall back to primary weekly window when secondary is null"
        )

        try check(
            OAuthEndpointPolicy.claudeUsage.allows(URL(string: "https://api.anthropic.com/api/oauth/usage")!),
            "Claude usage host must be allowed"
        )
        try check(
            !OAuthEndpointPolicy.claudeUsage.allows(URL(string: "https://evil.example/api/oauth/usage")!),
            "Claude usage host must reject an untrusted host"
        )
        try check(
            OAuthEndpointPolicy.codexUsage.allows(URL(string: "https://chatgpt.com/backend-api/wham/usage")!),
            "Codex usage host must be allowed"
        )

        let currentVersion = try ReleaseVersion("0.1.2")
        let newerVersion = try ReleaseVersion("v0.1.3")
        try check(newerVersion > currentVersion, "new release versions must compare correctly")
        let equalVersion = try ReleaseVersion("0.1.2")
        try check(
            !(equalVersion > currentVersion),
            "equal release versions must not be treated as updates"
        )
        let releaseFixture = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v0.1.3",
            "html_url": "https://github.com/Supia7/quota-bar/releases/tag/v0.1.3",
            "assets": [
                [
                    "name": "QuotaBar-macos-arm64.dmg",
                    "browser_download_url": "https://github.com/Supia7/quota-bar/releases/download/v0.1.3/QuotaBar-macos-arm64.dmg"
                ] as [String: String],
                [
                    "name": "SHA256SUMS",
                    "browser_download_url": "https://github.com/Supia7/quota-bar/releases/download/v0.1.3/SHA256SUMS"
                ] as [String: String]
            ] as [[String: String]]
        ] as [String: Any])
        let release = try GitHubReleaseDecoder.decode(releaseFixture)
        try check(release.version == newerVersion, "GitHub release tag must decode to a version")
        try check(
            release.asset(named: "QuotaBar-macos-arm64.dmg") != nil,
            "GitHub release assets must expose the architecture DMG"
        )

        let claudeCredentialData = try JSONSerialization.data(withJSONObject: [
            "claudeAiOauth": [
                "accessToken": "claude-access-token-fixture",
                "refreshToken": "claude-refresh-token-fixture",
                "expiresAt": 1_800_000_000_000,
                "subscriptionType": "max"
            ] as [String: Any]
        ] as [String: Any])
        let claudeCredential = try OAuthCredentialFileDecoder.claude(claudeCredentialData)
        try check(
            claudeCredential.accessToken == "claude-access-token-fixture",
            "Claude OAuth access token must decode from provider credentials"
        )
        try check(
            claudeCredential.refreshToken == "claude-refresh-token-fixture",
            "Claude OAuth refresh token must decode from provider credentials"
        )

        let codexCredentialData = try JSONSerialization.data(withJSONObject: [
            "tokens": [
                "access_token": "codex-access-token-fixture",
                "refresh_token": "codex-refresh-token-fixture",
                "account_id": "acct_fixture"
            ] as [String: Any]
        ] as [String: Any])
        let codexCredential = try OAuthCredentialFileDecoder.codex(codexCredentialData)
        try check(
            codexCredential.accessToken == "codex-access-token-fixture" && codexCredential.accountID == "acct_fixture",
            "Codex OAuth credentials must decode from provider auth.json"
        )

        let discoveryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: discoveryHome, withIntermediateDirectories: true)
        let discoveredCodexPath = discoveryHome.appendingPathComponent(".codex/auth.json")
        try FileManager.default.createDirectory(
            at: discoveredCodexPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try codexCredentialData.write(to: discoveredCodexPath, options: .atomic)
        try check(
            OAuthCredentialPathDiscovery.defaultPath(for: .codex, homeDirectory: discoveryHome)
                == discoveredCodexPath.path,
            "Codex default credential path must be discovered"
        )
        try check(
            OAuthCredentialPathDiscovery.existingPath(
                for: .codex,
                homeDirectory: discoveryHome
            ) == discoveredCodexPath.path,
            "Existing Codex credentials must be detected automatically"
        )
        try? FileManager.default.removeItem(at: discoveryHome)

        let registry = AccountRegistry(accounts: [
            OAuthAccountDescriptor(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                provider: .claude,
                alias: "Work Claude",
                email: "work@example.com",
                isEmailHidden: false,
                credentialPath: "~/.claude/.credentials.json"
            )
        ])
        let registryData = try JSONEncoder().encode(registry)
        let registryText = String(decoding: registryData, as: UTF8.self)
        try check(
            !registryText.contains("access-token-fixture") && !registryText.contains("refresh-token-fixture"),
            "account registry must never persist OAuth token values"
        )

        let registryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-registry-\(UUID().uuidString).json")
        let registryStore = JSONAccountRegistryStore(fileURL: registryURL)
        try registryStore.save(registry)
        let loadedRegistry = try registryStore.load()
        try check(loadedRegistry == registry, "account registry must round-trip to disk")
        try? FileManager.default.removeItem(at: registryURL)

        let preferenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-preferences-\(UUID().uuidString).json")
        let preferenceStore = JSONAccountDisplayPreferencesStore(fileURL: preferenceURL)
        let preference = AccountDisplayPreference(alias: "Renamed", isEmailHidden: true)
        try preferenceStore.save([account.id: preference])
        let loadedPreferences = try preferenceStore.load()
        try check(loadedPreferences[account.id] == preference, "display preferences must round-trip to disk")
        try? FileManager.default.removeItem(at: preferenceURL)

        let claudeCredentialPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-claude-\(UUID().uuidString).json")
        let codexCredentialPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-codex-\(UUID().uuidString).json")
        try claudeCredentialData.write(to: claudeCredentialPath, options: .atomic)
        try codexCredentialData.write(to: codexCredentialPath, options: .atomic)
        let liveProvider = LiveOAuthQuotaProvider(
            accounts: [
                OAuthAccountDescriptor(
                    provider: .claude,
                    alias: "Live Claude",
                    email: "live-claude@example.com",
                    credentialPath: claudeCredentialPath.path
                ),
                OAuthAccountDescriptor(
                    provider: .codex,
                    alias: "Live Codex",
                    email: "live-codex@example.com",
                    credentialPath: codexCredentialPath.path
                )
            ],
            credentialLoader: FileOAuthCredentialLoader(),
            httpClient: FixtureOAuthHTTPClient(
                responses: [
                    OAuthEndpointPolicy.claudeUsage.pathPrefix: claudeFixture,
                    OAuthEndpointPolicy.codexUsage.pathPrefix: codexFixture
                ]
            )
        )
        let liveAccounts = try await liveProvider.snapshot(
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try check(liveAccounts.count == 2, "live provider must support multiple accounts without a cap")
        try check(liveAccounts.allSatisfy { !$0.isSampleData }, "live accounts must not be marked as sample data")
        try? FileManager.default.removeItem(at: claudeCredentialPath)
        try? FileManager.default.removeItem(at: codexCredentialPath)

        let samples = try await SampleQuotaProvider().snapshot(
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try check(samples.count == 2, "sample provider must return Claude and Codex only")
        try check(samples.allSatisfy(\.isSampleData), "sample accounts must be explicitly marked")
        try check(samples.map(\.provider) == [.claude, .codex], "sample providers must be stable")
        try check(samples.allSatisfy { !$0.windows.isEmpty }, "sample accounts must contain quota windows")

        print("QuotaBarChecks: all checks passed")
    }

    private static func check(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw CheckFailure(message)
        }
    }
}

private struct FixtureOAuthHTTPClient: OAuthUsageHTTPClient {
    let responses: [String: Data]

    func get(
        url: URL,
        credential _: OAuthCredential,
        headers _: [String: String],
        policy _: OAuthEndpointPolicy
    ) async throws -> Data {
        guard let data = responses[url.path] else {
            throw FixtureError.missingResponse(url.path)
        }
        return data
    }
}

private enum FixtureError: Error {
    case missingResponse(String)
}

private struct CheckFailure: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String {
        "QuotaBarChecks failed: \(message)"
    }
}
