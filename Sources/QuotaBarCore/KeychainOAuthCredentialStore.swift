import Foundation
import Security

public enum KeychainOAuthCredentialStoreError: Error, Equatable {
    case keychainFailure(OSStatus)
    case invalidPayload
}

public struct KeychainOAuthCredentialStore: Sendable {
    public static let defaultService = "com.supia.quotabar.oauth"

    public let service: String

    public init(service: String = KeychainOAuthCredentialStore.defaultService) {
        self.service = service
    }

    public func save(_ credential: OAuthCredential, for accountID: UUID) throws {
        let data = try JSONEncoder().encode(Payload(credential: credential))
        let query = baseQuery(for: accountID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainOAuthCredentialStoreError.keychainFailure(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainOAuthCredentialStoreError.keychainFailure(addStatus)
        }
    }

    public func load(for accountID: UUID) throws -> OAuthCredential? {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainOAuthCredentialStoreError.keychainFailure(status)
        }
        guard let data = result as? Data else {
            throw KeychainOAuthCredentialStoreError.invalidPayload
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw KeychainOAuthCredentialStoreError.invalidPayload
        }
        return payload.credential
    }

    public func delete(for accountID: UUID) throws {
        let status = SecItemDelete(baseQuery(for: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainOAuthCredentialStoreError.keychainFailure(status)
        }
    }

    private func baseQuery(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString
        ]
    }

    private struct Payload: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let accountID: String?
        let email: String?
        let subscriptionType: String?

        init(credential: OAuthCredential) {
            accessToken = credential.accessToken
            refreshToken = credential.refreshToken
            expiresAt = credential.expiresAt
            accountID = credential.accountID
            email = credential.email
            subscriptionType = credential.subscriptionType
        }

        var credential: OAuthCredential {
            OAuthCredential(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                accountID: accountID,
                email: email,
                subscriptionType: subscriptionType
            )
        }
    }
}
