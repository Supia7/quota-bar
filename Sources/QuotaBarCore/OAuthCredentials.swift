import Foundation

public struct OAuthCredential: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let accountID: String?
    public let subscriptionType: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        accountID: String? = nil,
        subscriptionType: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
        self.subscriptionType = subscriptionType
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date.addingTimeInterval(60)
    }
}

public enum OAuthCredentialFileDecoder {
    public static func claude(_ data: Data) throws -> OAuthCredential {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let accessToken = oauth["accessToken"] as? String,
            !accessToken.isEmpty
        else {
            throw UsageDecoderError.invalidPayload
        }

        return OAuthCredential(
            accessToken: accessToken,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAt: date(milliseconds: oauth["expiresAt"]),
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }

    public static func codex(_ data: Data) throws -> OAuthCredential {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String,
            !accessToken.isEmpty
        else {
            throw UsageDecoderError.invalidPayload
        }

        return OAuthCredential(
            accessToken: accessToken,
            refreshToken: tokens["refresh_token"] as? String,
            accountID: tokens["account_id"] as? String
        )
    }

    private static func date(milliseconds value: Any?) -> Date? {
        guard let value = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: value.doubleValue / 1_000)
    }
}

public struct OAuthAccountDescriptor: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let provider: QuotaProviderID
    public var alias: String
    public let email: String
    public var isEmailHidden: Bool
    public let credentialPath: String

    public init(
        id: UUID = UUID(),
        provider: QuotaProviderID,
        alias: String,
        email: String,
        isEmailHidden: Bool = false,
        credentialPath: String
    ) {
        self.id = id
        self.provider = provider
        self.alias = alias
        self.email = email
        self.isEmailHidden = isEmailHidden
        self.credentialPath = credentialPath
    }
}

public struct AccountRegistry: Codable, Equatable, Sendable {
    public var accounts: [OAuthAccountDescriptor]

    public init(accounts: [OAuthAccountDescriptor] = []) {
        self.accounts = accounts
    }
}
