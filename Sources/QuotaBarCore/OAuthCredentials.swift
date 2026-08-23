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
        credentialSource: OAuthCredentialSource = .keychain,
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
        try container.encode(credentialSource, forKey: .credentialSource)
        try container.encodeIfPresent(credentialIdentity, forKey: .credentialIdentity)
    }

    public func isEquivalent(to other: OAuthAccountDescriptor) -> Bool {
        guard provider == other.provider else { return false }
        if let credentialIdentity, !credentialIdentity.isEmpty,
           let otherIdentity = other.credentialIdentity, !otherIdentity.isEmpty {
            return credentialIdentity.caseInsensitiveCompare(otherIdentity) == .orderedSame
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

    public var keychainOnly: AccountRegistry {
        AccountRegistry(accounts: accounts.filter { $0.credentialSource == .keychain })
    }
}
