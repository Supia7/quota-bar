import Foundation
import QuotaBarCore

@main
enum QuotaBarChecks {
    static func main() async throws {
        let emptyAccounts = try await EmptyQuotaProvider().snapshot(at: Date())
        try check(emptyAccounts.isEmpty, "a fresh install must not expose sample quota accounts")

        let mixedRegistry = AccountRegistry(accounts: [
            OAuthAccountDescriptor(
                provider: .claude,
                alias: "Legacy file account",
                email: "legacy@example.com",
                credentialPath: "~/.claude/.credentials.json",
                credentialSource: .file
            ),
            OAuthAccountDescriptor(
                provider: .codex,
                alias: "Keychain account",
                email: "keychain@example.com",
                credentialSource: .keychain,
                credentialIdentity: "acct-keychain"
            )
        ])
        try check(
            mixedRegistry.keychainOnly.accounts.count == 1
                && mixedRegistry.keychainOnly.accounts[0].credentialSource == OAuthCredentialSource.keychain,
            "legacy file-backed accounts must be excluded from the active registry"
        )

        try check(QuotaWindowKind.fiveHour.compactLabel == "5h", "five-hour limits need a compact label")
        try check(QuotaWindowKind.weekly.compactLabel == "W", "weekly limits need a compact label")
        try check(QuotaWindowKind.fableWeekly.compactLabel == "F", "Fable limits need a compact label")

        let invalidGrant = Data(#"{"error":"invalid_grant"}"#.utf8)
        try check(
            OAuthTokenExchangeReason.decode(invalidGrant) == .invalidGrant,
            "invalid_grant must be surfaced as an actionable OAuth reason"
        )
        let redirectMismatch = Data(#"{"error":"invalid_request","error_description":"redirect_uri mismatch"}"#.utf8)
        try check(
            OAuthTokenExchangeReason.decode(redirectMismatch) == .redirectMismatch,
            "redirect mismatch must be surfaced as an actionable OAuth reason"
        )

        do {
            _ = try OAuthCallbackParser.parse(
                "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ0ZXN0In0.c2lnbmF0dXJl",
                expectedState: "state"
            )
            throw CheckFailure("access tokens must not be accepted as callback codes")
        } catch OAuthLoginError.accessTokenNotAccepted {
            // expected
        }

        let claudeManualCode = try OAuthCallbackParser.parse(
            "claude-code-fixture#display-fragment-fixture",
            expectedState: "state"
        )
        try check(
            claudeManualCode.code == "claude-code-fixture",
            "Claude manual authorization codes must drop the display fragment"
        )
        do {
            _ = try OAuthCallbackParser.parse(
                "https://platform.claude.com/oauth/code/callback?code=missing-state-code",
                expectedState: "state"
            )
            throw CheckFailure("OAuth callback URLs must not accept a missing state")
        } catch OAuthLoginError.stateMismatch {
            // expected
        }

        let loopbackCapture = LoopbackCapture()
        let loopbackServer = OAuthLoopbackCallbackServer(port: 41455)
        try loopbackServer.start(
            onReady: { port in
                Task { await loopbackCapture.ready(port) }
            },
            onCallback: { callbackURL in
                Task { await loopbackCapture.callback(callbackURL) }
            },
            onFailure: {
                Task { await loopbackCapture.failed() }
            }
        )
        let loopbackPort = try await loopbackCapture.waitForPort()
        let loopbackURL = URL(string: "http://127.0.0.1:\(loopbackPort)/auth/callback?code=auto-code&state=auto-state")!
        let (_, loopbackResponse) = try await URLSession(configuration: .ephemeral).data(from: loopbackURL)
        try check(
            (loopbackResponse as? HTTPURLResponse)?.statusCode == 200,
            "loopback OAuth callback must return an HTTP success response"
        )
        let receivedCallback = try await loopbackCapture.waitForCallback()
        _ = try OAuthCallbackParser.parse(receivedCallback, expectedState: "auto-state")
        loopbackServer.stop()

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

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let usageNow = Date(timeIntervalSince1970: 1_780_000_000)
        let usageFormatter = ISO8601DateFormatter()
        usageFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainUsageFormatter = ISO8601DateFormatter()
        plainUsageFormatter.formatOptions = [.withInternetDateTime]
        let claudeUsageFixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-claude-usage-\(UUID().uuidString).jsonl")
        let claudeUsageRecords: [[String: Any]] = [
            [
                "type": "assistant",
                "timestamp": usageFormatter.string(from: usageNow.addingTimeInterval(60)),
                "sessionId": "claude-session",
                "message": [
                    "model": "claude-sonnet-4",
                    "usage": [
                        "input_tokens": 100,
                        "output_tokens": 50,
                        "cache_read_input_tokens": 20,
                        "cache_creation_input_tokens": 10
                    ] as [String: Int]
                ] as [String: Any]
            ],
            [
                "type": "assistant",
                "timestamp": plainUsageFormatter.string(from: usageNow.addingTimeInterval(120)),
                "sessionId": "claude-session",
                "message": [
                    "model": "claude-sonnet-4",
                    "usage": [
                        "input_tokens": 200,
                        "output_tokens": 100,
                        "cache_read_input_tokens": 30,
                        "cache_creation_input_tokens": 5
                    ] as [String: Int]
                ] as [String: Any]
            ]
        ]
        let claudeUsageFixture = "{malformed-json-line}\n" + (try claudeUsageRecords.map { record in
            String(data: try JSONSerialization.data(withJSONObject: record), encoding: .utf8)!
        }.joined(separator: "\n") + "\n")
        try Data(claudeUsageFixture.utf8).write(to: claudeUsageFixtureURL)

        let codexUsageFixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-codex-usage-\(UUID().uuidString).jsonl")
        let codexUsageRecord: [String: Any] = [
            "type": "event_msg",
            "timestamp": usageFormatter.string(from: usageNow.addingTimeInterval(180)),
            "payload": [
                "type": "token_count",
                "session_id": "codex-session",
                "info": [
                    "model": "gpt-5.3-codex",
                    "last_token_usage": [
                        "input_tokens": 100,
                        "cached_input_tokens": 40,
                        "output_tokens": 25,
                        "reasoning_output_tokens": 5
                    ] as [String: Int]
                ] as [String: Any]
            ] as [String: Any]
        ]
        let codexUsageFixture = String(
            data: try JSONSerialization.data(withJSONObject: codexUsageRecord),
            encoding: .utf8
        )! + "\n"
        try Data(codexUsageFixture.utf8).write(to: codexUsageFixtureURL)

        let localUsageScanner = LocalUsageScanner()
        let claudeUsage = try localUsageScanner.scan(
            files: [claudeUsageFixtureURL],
            provider: .claude,
            now: usageNow,
            calendar: utcCalendar
        )
        let codexUsage = try localUsageScanner.scan(
            files: [codexUsageFixtureURL],
            provider: .codex,
            now: usageNow,
            calendar: utcCalendar
        )
        try check(
            claudeUsage.inputTokens == 300
                && claudeUsage.outputTokens == 150
                && claudeUsage.cacheReadTokens == 50
                && claudeUsage.cacheWriteTokens == 15
                && claudeUsage.requestCount == 2
                && claudeUsage.sessionCount == 1
                && claudeUsage.totalTokens == 515,
            "Claude local session usage must aggregate today's token and cache fields"
        )
        try check(
            codexUsage.inputTokens == 100
                && codexUsage.outputTokens == 25
                && codexUsage.cacheReadTokens == 40
                && codexUsage.requestCount == 1
                && codexUsage.sessionCount == 1,
            "Codex local session usage must read last_token_usage without double-counting events"
        )
        try? FileManager.default.removeItem(at: claudeUsageFixtureURL)
        try? FileManager.default.removeItem(at: codexUsageFixtureURL)

        let discoveryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-local-usage-home-\(UUID().uuidString)")
        let discoveryClaudeDirectory = discoveryHome
            .appendingPathComponent(".claude/projects/sample", isDirectory: true)
        try FileManager.default.createDirectory(
            at: discoveryClaudeDirectory,
            withIntermediateDirectories: true
        )
        let discoveryClaudeURL = discoveryClaudeDirectory.appendingPathComponent("session.jsonl")
        let discoveryNow = Date()
        let discoveryRecord: [String: Any] = [
            "type": "assistant",
            "timestamp": ISO8601DateFormatter().string(from: discoveryNow),
            "sessionId": "discovered-session",
            "message": [
                "usage": ["input_tokens": 10, "output_tokens": 5] as [String: Int]
            ] as [String: Any]
        ]
        try String(
            data: JSONSerialization.data(withJSONObject: discoveryRecord),
            encoding: .utf8
        )!.appending("\n").write(to: discoveryClaudeURL, atomically: true, encoding: .utf8)
        let discoveredUsage = LocalUsageScanner(homeDirectory: discoveryHome).scanToday(at: discoveryNow)
        try check(
            discoveredUsage[.claude]?.requestCount == 1
                && discoveredUsage[.claude]?.totalTokens == 15,
            "local usage discovery must find today's Claude JSONL under the user's config directory"
        )
        try? FileManager.default.removeItem(at: discoveryHome)

        let liveLocalUsage = LocalUsageScanner().scanToday()
        try check(
            liveLocalUsage.values.allSatisfy {
                $0.requestCount >= 0
                    && $0.sessionCount >= 0
                    && $0.totalTokens >= 0
            },
            "live local usage scanning must return bounded non-negative summaries"
        )

        let resetAccountID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let previousCodex = QuotaAccount(
            id: resetAccountID,
            provider: .codex,
            alias: "Reset Codex",
            email: "reset-codex@example.com",
            windows: [
                QuotaWindow(
                    id: "codex-weekly",
                    kind: .weekly,
                    title: "Weekly",
                    remainingFraction: 0.31,
                    resetAt: Date(timeIntervalSince1970: 1_780_000_000)
                )
            ],
            isSampleData: false
        )
        let currentCodex = QuotaAccount(
            id: resetAccountID,
            provider: .codex,
            alias: "Reset Codex",
            email: "reset-codex@example.com",
            windows: [
                QuotaWindow(
                    id: "codex-weekly",
                    kind: .weekly,
                    title: "Weekly",
                    remainingFraction: 1,
                    resetAt: Date(timeIntervalSince1970: 1_780_001_000)
                )
            ],
            isSampleData: false
        )
        let resetEvents = QuotaResetDetector.detect(
            previous: QuotaResetDetector.observations(from: [previousCodex]),
            current: [currentCodex],
            at: Date(timeIntervalSince1970: 1_780_001_100)
        )
        try check(
            resetEvents.count == 1
                && resetEvents[0].provider == .codex
                && resetEvents[0].currentRemainingPercentage == 100,
            "Codex recovery to full quota must emit one reset event"
        )
        try check(
            QuotaResetDetector.detect(previous: [], current: [currentCodex]).isEmpty,
            "the first quota observation must establish a baseline without notifying"
        )
        let observationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-reset-observations-\(UUID().uuidString).json")
        let observationStore = JSONQuotaResetObservationStore(fileURL: observationURL)
        let observations = QuotaResetDetector.observations(from: [currentCodex])
        try observationStore.save(observations)
        let loadedObservations = try observationStore.load()
        try check(
            loadedObservations == observations,
            "reset observations must round-trip without credentials"
        )
        try? FileManager.default.removeItem(at: observationURL)

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

        let registry = AccountRegistry(accounts: [
            OAuthAccountDescriptor(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                provider: .claude,
                alias: "Work Claude",
                email: "work@example.com",
                isEmailHidden: false,
                credentialSource: .keychain,
                credentialIdentity: "acct-work"
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
        let duplicateDescriptor = OAuthAccountDescriptor(
            provider: .claude,
            alias: "Duplicate",
            email: "other@example.com",
            credentialSource: .keychain,
            credentialIdentity: "acct-work"
        )
        try check(
            registry.containsEquivalentAccount(duplicateDescriptor),
            "account registry must reject duplicate provider identities"
        )
        try? FileManager.default.removeItem(at: registryURL)

        let preferenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-preferences-\(UUID().uuidString).json")
        let preferenceStore = JSONAccountDisplayPreferencesStore(fileURL: preferenceURL)
        let preference = AccountDisplayPreference(alias: "Renamed", isEmailHidden: true)
        try preferenceStore.save([account.id: preference])
        let loadedPreferences = try preferenceStore.load()
        try check(loadedPreferences[account.id] == preference, "display preferences must round-trip to disk")
        try? FileManager.default.removeItem(at: preferenceURL)

        let liveClaudeID = UUID()
        let liveCodexID = UUID()
        let liveCredential = OAuthCredential(
            accessToken: "live-access-fixture",
            refreshToken: nil
        )
        let liveKeychainStore = KeychainOAuthCredentialStore()
        try liveKeychainStore.save(liveCredential, for: liveClaudeID)
        try liveKeychainStore.save(liveCredential, for: liveCodexID)
        let liveProvider = LiveOAuthQuotaProvider(
            accounts: [
                OAuthAccountDescriptor(
                    id: liveClaudeID,
                    provider: .claude,
                    alias: "Live Claude",
                    email: "live-claude@example.com",
                    credentialSource: .keychain,
                    credentialIdentity: "live-claude"
                ),
                OAuthAccountDescriptor(
                    id: liveCodexID,
                    provider: .codex,
                    alias: "Live Codex",
                    email: "live-codex@example.com",
                    credentialSource: .keychain,
                    credentialIdentity: "live-codex"
                )
            ],
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
        try liveKeychainStore.delete(for: liveClaudeID)
        try liveKeychainStore.delete(for: liveCodexID)

        let samples = try await SampleQuotaProvider().snapshot(
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try check(samples.count == 2, "sample provider must return Claude and Codex only")
        try check(samples.allSatisfy(\.isSampleData), "sample accounts must be explicitly marked")
        try check(samples.map(\.provider) == [.claude, .codex], "sample providers must be stable")
        try check(samples.allSatisfy { !$0.windows.isEmpty }, "sample accounts must contain quota windows")

        let codexLogin = try OAuthAuthorizationConfiguration.makeRequest(for: .codex)
        try check(
            codexLogin.url.host == "auth.openai.com"
                && codexLogin.redirectURI == "http://localhost:1455/auth/callback",
            "Codex login must use the official PKCE authorization host and callback"
        )
        try check(
            codexLogin.url.absoluteString.contains("client_id=app_EMoamEEZ73f0CkXaXp7hrann")
                && codexLogin.url.absoluteString.contains("code_challenge_method=S256"),
            "Codex login URL must contain the registered client and S256 PKCE"
        )
        let claudeLogin = try OAuthAuthorizationConfiguration.makeRequest(for: .claude)
        try check(
            claudeLogin.url.host == "claude.com"
                && claudeLogin.redirectURI == "https://platform.claude.com/oauth/code/callback",
            "Claude login must use the official authorization host and fixed callback"
        )
        try check(
            claudeLogin.url.absoluteString.contains("client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e")
                && claudeLogin.url.absoluteString.contains("code_challenge_method=S256"),
            "Claude login URL must contain the registered client and S256 PKCE"
        )
        let tokenFixture = try JSONSerialization.data(withJSONObject: [
            "access_token": "access-fixture",
            "refresh_token": "refresh-fixture",
            "expires_in": 3600,
            "account_id": "account-fixture"
        ] as [String: Any])
        let tokenCredential = try OAuthTokenResponseDecoder.decode(
            tokenFixture,
            provider: .codex,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try check(
            tokenCredential.accessToken == "access-fixture"
                && tokenCredential.refreshToken == "refresh-fixture"
                && tokenCredential.accountID == "account-fixture",
            "OAuth token response must decode into an in-memory credential"
        )
        let claudeNestedAccountFixture = try JSONSerialization.data(withJSONObject: [
            "access_token": "claude-access-fixture",
            "refresh_token": "claude-refresh-fixture",
            "expires_in": 28800,
            "account": [
                "uuid": "claude-account-fixture",
                "email_address": "claude@example.com"
            ] as [String: String]
        ] as [String: Any])
        let claudeNestedCredential = try OAuthTokenResponseDecoder.decode(
            claudeNestedAccountFixture,
            provider: .claude
        )
        try check(
            claudeNestedCredential.accountID == "claude-account-fixture"
                && claudeNestedCredential.email == "claude@example.com",
            "Claude token response must decode nested account identity"
        )
        let claimIdentityFixture = try JSONSerialization.data(withJSONObject: [
            "access_token": "eyJhbGciOiJub25lIn0.eyJzdWIiOiJzdGFibGUtc3ViIn0.c2ln",
            "refresh_token": "refresh-claim-fixture"
        ] as [String: Any])
        let claimIdentityCredential = try OAuthTokenResponseDecoder.decode(
            claimIdentityFixture,
            provider: .codex
        )
        try check(
            claimIdentityCredential.accountID == "stable-sub",
            "OAuth JWT subject must become a stable account identity"
        )
        let missingIdentityFixture = try JSONSerialization.data(withJSONObject: [
            "access_token": "opaque-access-fixture",
            "refresh_token": "opaque-refresh-fixture"
        ] as [String: Any])
        do {
            _ = try OAuthTokenResponseDecoder.decode(missingIdentityFixture, provider: .codex)
            throw CheckFailure("OAuth token without a stable identity must be rejected")
        } catch OAuthLoginError.missingAccountIdentity {
            // expected
        }
        let keychainStore = KeychainOAuthCredentialStore()
        let keychainID = UUID()
        try keychainStore.save(tokenCredential, for: keychainID)
        let keychainCredential = try keychainStore.load(for: keychainID)
        try check(
            keychainCredential == tokenCredential,
            "Keychain OAuth credentials must round-trip without using the registry"
        )
        try keychainStore.delete(for: keychainID)
        let deletedCredential = try keychainStore.load(for: keychainID)
        try check(
            deletedCredential == nil,
            "Deleted Keychain OAuth credentials must not remain available"
        )

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

private actor LoopbackCapture {
    private var port: UInt16?
    private var callbackURL: String?
    private var didFail = false

    func ready(_ port: UInt16) {
        self.port = port
    }

    func callback(_ callbackURL: String) {
        self.callbackURL = callbackURL
    }

    func failed() {
        didFail = true
    }

    func waitForPort() async throws -> UInt16 {
        for _ in 0..<100 {
            if didFail {
                throw CheckFailure("loopback callback server failed to start")
            }
            if let port {
                return port
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CheckFailure("loopback callback server did not become ready")
    }

    func waitForCallback() async throws -> String {
        for _ in 0..<100 {
            if let callbackURL {
                return callbackURL
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CheckFailure("loopback callback server did not receive a callback")
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
