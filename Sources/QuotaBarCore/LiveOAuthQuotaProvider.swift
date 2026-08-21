import Foundation

public struct LiveOAuthQuotaProvider: QuotaProvider, Sendable {
    public let id = "oauth"

    private let accounts: [OAuthAccountDescriptor]
    private let credentialLoader: FileOAuthCredentialLoader
    private let httpClient: any OAuthUsageHTTPClient

    public init(
        accounts: [OAuthAccountDescriptor],
        credentialLoader: FileOAuthCredentialLoader = FileOAuthCredentialLoader(),
        httpClient: any OAuthUsageHTTPClient = URLSessionOAuthHTTPClient()
    ) {
        self.accounts = accounts
        self.credentialLoader = credentialLoader
        self.httpClient = httpClient
    }

    public func snapshot(at date: Date) async throws -> [QuotaAccount] {
        var snapshots: [QuotaAccount] = []
        snapshots.reserveCapacity(accounts.count)

        for account in accounts {
            let credential = try credentialLoader.load(account)
            let (windows, resolvedEmail) = try await fetch(
                account: account,
                credential: credential
            )
            snapshots.append(
                QuotaAccount(
                    id: account.id,
                    provider: account.provider,
                    alias: account.alias,
                    email: resolvedEmail,
                    isEmailHidden: account.isEmailHidden,
                    windows: windows,
                    isSampleData: false
                )
            )
        }
        return snapshots
    }

    private func fetch(
        account: OAuthAccountDescriptor,
        credential: OAuthCredential
    ) async throws -> ([QuotaWindow], String) {
        switch account.provider {
        case .claude:
            let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
            let data = try await httpClient.get(
                url: url,
                credential: credential,
                headers: [
                    "anthropic-beta": "oauth-2025-04-20",
                    "User-Agent": "claude-code/2.1.80"
                ],
                policy: .claudeUsage
            )
            return (try ClaudeUsageDecoder.decode(data), account.email)

        case .codex:
            let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
            var headers: [String: String] = [:]
            if let accountID = credential.accountID, !accountID.isEmpty {
                headers["ChatGPT-Account-Id"] = accountID
            }
            let data = try await httpClient.get(
                url: url,
                credential: credential,
                headers: headers,
                policy: .codexUsage
            )
            return (try CodexUsageDecoder.decode(data), account.email)
        }
    }
}
