import CryptoKit
import Foundation

public struct OAuthPKCE: Equatable, Sendable {
    public let verifier: String
    public let challenge: String
    public let state: String

    public init() {
        verifier = Self.randomURLSafeString()
        challenge = Self.base64URL(SHA256.hash(data: Data(verifier.utf8)))
        state = Self.randomURLSafeString()
    }

    private static func randomURLSafeString() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0 ... 255) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URL(_ digest: SHA256.Digest) -> String {
        Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct OAuthAuthorizationRequest: Equatable, Sendable {
    public let provider: QuotaProviderID
    public let url: URL
    public let redirectURI: String
    public let verifier: String
    public let state: String
}

public enum OAuthAuthorizationConfiguration {
    public static func makeRequest(for provider: QuotaProviderID) throws -> OAuthAuthorizationRequest {
        let pkce = OAuthPKCE()
        let redirectURI: String
        let authorizeURL: String
        var queryItems: [URLQueryItem]

        switch provider {
        case .claude:
            authorizeURL = "https://claude.com/cai/oauth/authorize"
            redirectURI = "https://platform.claude.com/oauth/code/callback"
            queryItems = [
                URLQueryItem(name: "code", value: "true"),
                URLQueryItem(name: "client_id", value: "9d1c250a-e61b-44d9-88ed-5944d1962f5e"),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(
                    name: "scope",
                    value: "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
                ),
                URLQueryItem(name: "code_challenge", value: pkce.challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: pkce.state)
            ]
        case .codex:
            authorizeURL = "https://auth.openai.com/oauth/authorize"
            redirectURI = "http://localhost:1455/auth/callback"
            queryItems = [
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "client_id", value: "app_EMoamEEZ73f0CkXaXp7hrann"),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(
                    name: "scope",
                    value: "openid profile email offline_access api.connectors.read api.connectors.invoke"
                ),
                URLQueryItem(name: "code_challenge", value: pkce.challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "id_token_add_organizations", value: "true"),
                URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
                URLQueryItem(name: "state", value: pkce.state),
                URLQueryItem(name: "originator", value: "codex_cli_rs")
            ]
        }

        var components = URLComponents(string: authorizeURL)
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw OAuthLoginError.invalidAuthorizationURL
        }
        return OAuthAuthorizationRequest(
            provider: provider,
            url: url,
            redirectURI: redirectURI,
            verifier: pkce.verifier,
            state: pkce.state
        )
    }
}

public enum OAuthLoginError: Error, Equatable {
    case invalidAuthorizationURL
    case invalidCallback
    case accessTokenNotAccepted
    case stateMismatch
    case tokenExchangeFailed
    case tokenExchangeRejected(OAuthTokenExchangeReason)
    case invalidTokenResponse
    case missingAccountIdentity
    case unsupportedProvider
}

public enum OAuthTokenExchangeReason: Equatable, Sendable {
    case invalidGrant
    case invalidRequest
    case redirectMismatch
    case providerRejected
    case unknown

    public static func decode(_ data: Data) -> OAuthTokenExchangeReason {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }
        let error = (object["error"] as? String)?.lowercased() ?? ""
        let description = (object["error_description"] as? String)?.lowercased() ?? ""
        if description.contains("redirect") || description.contains("redirect_uri") {
            return .redirectMismatch
        }
        switch error {
        case "invalid_grant":
            return .invalidGrant
        case "invalid_request":
            return .invalidRequest
        case "invalid_client", "unauthorized_client":
            return .providerRejected
        default:
            return .unknown
        }
    }
}

public struct OAuthCallback: Equatable, Sendable {
    public let code: String
    public let state: String
}

public enum OAuthCallbackParser {
    public static func parse(_ input: String, expectedState: String) throws -> OAuthCallback {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OAuthLoginError.invalidCallback }
        if !trimmed.contains("://"), Self.looksLikeJWT(trimmed) {
            throw OAuthLoginError.accessTokenNotAccepted
        }

        let code: String
        let state: String
        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw OAuthLoginError.invalidCallback
            }
            let items = components.queryItems ?? []
            guard let parsedCode = items.first(where: { $0.name == "code" })?.value else {
                throw OAuthLoginError.invalidCallback
            }
            code = parsedCode
            state = items.first(where: { $0.name == "state" })?.value ?? expectedState
        } else {
            code = trimmed
            state = expectedState
        }

        guard !code.isEmpty else { throw OAuthLoginError.invalidCallback }
        guard state == expectedState else { throw OAuthLoginError.stateMismatch }
        return OAuthCallback(code: code, state: state)
    }

    private static func looksLikeJWT(_ input: String) -> Bool {
        let parts = input.split(separator: ".")
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        return parts.allSatisfy { part in
            var encoded = String(part)
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            return Data(base64Encoded: encoded) != nil
        }
    }
}

public enum OAuthTokenResponseDecoder {
    public static func decode(
        _ data: Data,
        provider: QuotaProviderID,
        now: Date = Date(),
        fallbackRefreshToken: String? = nil
    ) throws -> OAuthCredential {
        struct Response: Decodable {
            let accessToken: String?
            let refreshToken: String?
            let expiresIn: TimeInterval?
            let accountID: String?
            let idToken: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
                case accountID = "account_id"
                case idToken = "id_token"
            }
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let accessToken = response.accessToken,
              !accessToken.isEmpty
        else {
            throw OAuthLoginError.invalidTokenResponse
        }

        let claims = response.idToken.flatMap(Self.jwtClaims)
        let accessClaims = Self.jwtClaims(accessToken)
        let responseAccountID = response.accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountID = (responseAccountID?.isEmpty == false ? responseAccountID : nil)
            ?? (claims?["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_account_id"] as? String
            ?? Self.stableIdentity(from: claims)
            ?? Self.stableIdentity(from: accessClaims)
        let email = (claims?["email"] as? String)
            ?? (accessClaims?["email"] as? String)
        guard accountID != nil || !(email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
            throw OAuthLoginError.missingAccountIdentity
        }
        let expiresAt = response.expiresIn.map {
            now.addingTimeInterval(max(0, $0 - 300))
        } ?? Self.jwtExpiry(accessToken)

        switch provider {
        case .claude, .codex:
            return OAuthCredential(
                accessToken: accessToken,
                refreshToken: response.refreshToken ?? fallbackRefreshToken,
                expiresAt: expiresAt,
                accountID: accountID,
                email: email,
                subscriptionType: nil
            )
        }
    }

    private static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func stableIdentity(from claims: [String: Any]?) -> String? {
        guard let claims else { return nil }
        for key in ["sub", "user_id", "userId", "account_id", "accountId", "oid"] {
            if let value = claims[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func jwtExpiry(_ token: String) -> Date? {
        guard let exp = jwtClaims(token)?["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue - 300)
    }
}
