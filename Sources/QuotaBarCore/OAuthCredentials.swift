import Foundation

public struct OAuthCredential: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let accountID: String?
    public let email: String?
    public let subscriptionType: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        accountID: String? = nil,
        email: String? = nil,
        subscriptionType: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
        self.email = email
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

public enum OAuthCredentialSource: String, Codable, Sendable {
    case file
    case keychain
}

public struct OAuthAccountDescriptor: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let provider: QuotaProviderID
    public var alias: String
    public let email: String
    public var isEmailHidden: Bool
    public let credentialPath: String
    public let credentialSource: OAuthCredentialSource
    public let credentialIdentity: String?

    public init(
        id: UUID = UUID(),
        provider: QuotaProviderID,
        alias: String,
        email: String,
        isEmailHidden: Bool = false,
        credentialPath: String = "",
        credentialSource: OAuthCredentialSource = .file,
        credentialIdentity: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.alias = alias
        self.email = email
        self.isEmailHidden = isEmailHidden
        self.credentialPath = credentialPath
        self.credentialSource = credentialSource
        self.credentialIdentity = credentialIdentity
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case alias
        case email
        case isEmailHidden
        case credentialPath
        case credentialSource
        case credentialIdentity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        provider = try container.decode(QuotaProviderID.self, forKey: .provider)
        alias = try container.decode(String.self, forKey: .alias)
        email = try container.decode(String.self, forKey: .email)
        isEmailHidden = try container.decodeIfPresent(Bool.self, forKey: .isEmailHidden) ?? false
        credentialPath = try container.decodeIfPresent(String.self, forKey: .credentialPath) ?? ""
        credentialSource = try container.decodeIfPresent(
            OAuthCredentialSource.self,
            forKey: .credentialSource
        ) ?? .file
        credentialIdentity = try container.decodeIfPresent(String.self, forKey: .credentialIdentity)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider, forKey: .provider)
        try container.encode(alias, forKey: .alias)
        try container.encode(email, forKey: .email)
        try container.encode(isEmailHidden, forKey: .isEmailHidden)
        try container.encode(credentialPath, forKey: .credentialPath)
        try container.encode(credentialSource, forKey: .credentialSource)
        try container.encodeIfPresent(credentialIdentity, forKey: .credentialIdentity)
    }

    public func isEquivalent(to other: OAuthAccountDescriptor) -> Bool {
        guard provider == other.provider else { return false }
        if let credentialIdentity, !credentialIdentity.isEmpty,
           let otherIdentity = other.credentialIdentity, !otherIdentity.isEmpty {
            return credentialIdentity.caseInsensitiveCompare(otherIdentity) == .orderedSame
        }
        if credentialSource == .file, other.credentialSource == .file {
            let path = (credentialPath as NSString).expandingTildeInPath
            let otherPath = (other.credentialPath as NSString).expandingTildeInPath
            return !path.isEmpty && path == otherPath
        }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let otherEmail = other.email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalizedEmail.isEmpty
            && normalizedEmail.caseInsensitiveCompare(otherEmail) == .orderedSame
    }
}

public struct AccountRegistry: Codable, Equatable, Sendable {
    public var accounts: [OAuthAccountDescriptor]

    public init(accounts: [OAuthAccountDescriptor] = []) {
        self.accounts = accounts
    }

    public func containsEquivalentAccount(_ descriptor: OAuthAccountDescriptor) -> Bool {
        accounts.contains { $0.isEquivalent(to: descriptor) }
    }
}
