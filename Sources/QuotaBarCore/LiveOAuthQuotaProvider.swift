import Foundation

public struct LiveOAuthQuotaProvider: QuotaProvider, Sendable {
    public let id = "oauth"

    private let accounts: [OAuthAccountDescriptor]
    private let credentialResolver: OAuthCredentialResolver
    private let httpClient: any OAuthUsageHTTPClient
    private let tokenService: OAuthTokenService

    public init(
        accounts: [OAuthAccountDescriptor],
        credentialLoader: FileOAuthCredentialLoader = FileOAuthCredentialLoader(),
        httpClient: any OAuthUsageHTTPClient = URLSessionOAuthHTTPClient(),
        tokenService: OAuthTokenService = OAuthTokenService()
    ) {
        self.accounts = accounts
        self.credentialResolver = OAuthCredentialResolver(fileLoader: credentialLoader)
        self.httpClient = httpClient
        self.tokenService = tokenService
    }

    public func snapshot(at date: Date) async throws -> [QuotaAccount] {
        var snapshots: [QuotaAccount] = []
        snapshots.reserveCapacity(accounts.count)

        for account in accounts {
            let credential = try await credential(for: account)
            let (windows, resolvedEmail) = try await fetchWithRefresh(
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

    private func credential(for account: OAuthAccountDescriptor) async throws -> OAuthCredential {
        let loaded = try credentialResolver.load(account)
        guard account.credentialSource == .keychain,
              loaded.isExpired(),
              let refreshToken = loaded.refreshToken,
              !refreshToken.isEmpty
        else {
            return loaded
        }
        let refreshed = try await tokenService.refresh(
            provider: account.provider,
            refreshToken: refreshToken
        )
        try credentialResolver.save(refreshed, for: account)
        return refreshed
    }

    private func fetchWithRefresh(
        account: OAuthAccountDescriptor,
        credential: OAuthCredential
    ) async throws -> ([QuotaWindow], String) {
        do {
            return try await fetch(account: account, credential: credential)
        } catch OAuthNetworkError.reauthenticationRequired {
            guard account.credentialSource == .keychain,
                  let refreshToken = credential.refreshToken,
                  !refreshToken.isEmpty
            else {
                throw OAuthNetworkError.reauthenticationRequired
            }
            let refreshed = try await tokenService.refresh(
                provider: account.provider,
                refreshToken: refreshToken
            )
            try credentialResolver.save(refreshed, for: account)
            return try await fetch(account: account, credential: refreshed)
        }
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
