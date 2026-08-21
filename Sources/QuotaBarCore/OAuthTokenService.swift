import Foundation

public struct OAuthTokenService: Sendable {
    public init() {}

    public func exchange(
        request: OAuthAuthorizationRequest,
        callback: OAuthCallback
    ) async throws -> OAuthCredential {
        let configuration = configuration(for: request.provider)
        var fields = [
            "grant_type": "authorization_code",
            "code": callback.code,
            "redirect_uri": request.redirectURI,
            "client_id": configuration.clientID,
            "code_verifier": request.verifier
        ]
        if request.provider == .claude {
            fields["state"] = callback.state
        }
        let data = try await post(
            fields,
            url: configuration.tokenURL,
            policy: configuration.policy,
            usesJSON: configuration.usesJSON
        )
        return try OAuthTokenResponseDecoder.decode(
            data,
            provider: request.provider
        )
    }

    public func refresh(
        provider: QuotaProviderID,
        refreshToken: String,
        now: Date = Date()
    ) async throws -> OAuthCredential {
        let configuration = configuration(for: provider)
        var fields = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": configuration.clientID
        ]
        if provider == .claude {
            fields["scope"] = "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
        }
        let data = try await post(
            fields,
            url: configuration.tokenURL,
            policy: configuration.policy,
            usesJSON: configuration.usesJSON
        )
        return try OAuthTokenResponseDecoder.decode(
            data,
            provider: provider,
            now: now,
            fallbackRefreshToken: refreshToken
        )
    }

    private func configuration(for provider: QuotaProviderID) -> Configuration {
        switch provider {
        case .claude:
            Configuration(
                clientID: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
                tokenURL: URL(string: "https://platform.claude.com/v1/oauth/token")!,
                policy: .claudeToken,
                usesJSON: true
            )
        case .codex:
            Configuration(
                clientID: "app_EMoamEEZ73f0CkXaXp7hrann",
                tokenURL: URL(string: "https://auth.openai.com/oauth/token")!,
                policy: .codexToken,
                usesJSON: false
            )
        }
    }

    private func post(
        _ fields: [String: String],
        url: URL,
        policy: OAuthEndpointPolicy,
        usesJSON: Bool
    ) async throws -> Data {
        guard policy.allows(url) else {
            throw OAuthNetworkError.untrustedEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(
            usesJSON ? "application/json" : "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if usesJSON {
            request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        } else {
            var components = URLComponents()
            components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        }

        let session = URLSession(
            configuration: .ephemeral,
            delegate: RedirectRejectingTokenDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw OAuthNetworkError.invalidResponse
            }
            guard (200 ... 299).contains(response.statusCode) else {
                if response.statusCode == 429 {
                    throw OAuthNetworkError.rateLimited
                }
                if response.statusCode == 401 || response.statusCode == 403 {
                    throw OAuthNetworkError.reauthenticationRequired
                }
                throw OAuthLoginError.tokenExchangeFailed
            }
            return data
        } catch let error as OAuthNetworkError {
            throw error
        } catch let error as OAuthLoginError {
            throw error
        } catch {
            throw OAuthNetworkError.temporaryFailure
        }
    }

    private struct Configuration {
        let clientID: String
        let tokenURL: URL
        let policy: OAuthEndpointPolicy
        let usesJSON: Bool
    }
}

private final class RedirectRejectingTokenDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
