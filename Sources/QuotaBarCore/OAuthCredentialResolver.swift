import Foundation

public struct OAuthCredentialResolver: Sendable {
    public let keychainStore: KeychainOAuthCredentialStore

    public init(
        keychainStore: KeychainOAuthCredentialStore = KeychainOAuthCredentialStore()
    ) {
        self.keychainStore = keychainStore
    }

    public func load(_ descriptor: OAuthAccountDescriptor) throws -> OAuthCredential {
        guard descriptor.credentialSource == .keychain else {
            throw OAuthNetworkError.reauthenticationRequired
        }
        guard let credential = try keychainStore.load(for: descriptor.id) else {
            throw OAuthNetworkError.reauthenticationRequired
        }
        return credential
    }

    public func save(_ credential: OAuthCredential, for descriptor: OAuthAccountDescriptor) throws {
        guard descriptor.credentialSource == .keychain else { return }
        try keychainStore.save(credential, for: descriptor.id)
    }

    public func delete(_ descriptor: OAuthAccountDescriptor) throws {
        guard descriptor.credentialSource == .keychain else { return }
        try keychainStore.delete(for: descriptor.id)
    }
}
