import Foundation

public struct OAuthCredentialResolver: Sendable {
    public let fileLoader: FileOAuthCredentialLoader
    public let keychainStore: KeychainOAuthCredentialStore

    public init(
        fileLoader: FileOAuthCredentialLoader = FileOAuthCredentialLoader(),
        keychainStore: KeychainOAuthCredentialStore = KeychainOAuthCredentialStore()
    ) {
        self.fileLoader = fileLoader
        self.keychainStore = keychainStore
    }

    public func load(_ descriptor: OAuthAccountDescriptor) throws -> OAuthCredential {
        switch descriptor.credentialSource {
        case .file:
            return try fileLoader.load(descriptor)
        case .keychain:
            guard let credential = try keychainStore.load(for: descriptor.id) else {
                throw OAuthNetworkError.reauthenticationRequired
            }
            return credential
        }
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
