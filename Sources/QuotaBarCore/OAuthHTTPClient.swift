import Foundation

public protocol OAuthUsageHTTPClient: Sendable {
    func get(
        url: URL,
        credential: OAuthCredential,
        headers: [String: String],
        policy: OAuthEndpointPolicy
    ) async throws -> Data
}

public enum OAuthNetworkError: Error, Equatable {
    case untrustedEndpoint
    case redirectRejected
    case invalidResponse
    case reauthenticationRequired
    case rateLimited
    case temporaryFailure
}

public struct FileOAuthCredentialLoader: Sendable {
    public init() {}

    public func load(_ descriptor: OAuthAccountDescriptor) throws -> OAuthCredential {
        let expandedPath = (descriptor.credentialPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        let data = try Data(contentsOf: url)
        switch descriptor.provider {
        case .claude:
            return try OAuthCredentialFileDecoder.claude(data)
        case .codex:
            return try OAuthCredentialFileDecoder.codex(data)
        }
    }
}

public struct URLSessionOAuthHTTPClient: OAuthUsageHTTPClient {
    public init() {}

    public func get(
        url: URL,
        credential: OAuthCredential,
        headers: [String: String],
        policy: OAuthEndpointPolicy
    ) async throws -> Data {
        guard policy.allows(url) else {
            throw OAuthNetworkError.untrustedEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let delegate = RedirectRejectingDelegate()
        let session = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw OAuthNetworkError.invalidResponse
            }
            switch response.statusCode {
            case 200 ... 299:
                return data
            case 401, 403:
                throw OAuthNetworkError.reauthenticationRequired
            case 429:
                throw OAuthNetworkError.rateLimited
            default:
                throw OAuthNetworkError.temporaryFailure
            }
        } catch let error as OAuthNetworkError {
            throw error
        } catch {
            throw OAuthNetworkError.temporaryFailure
        }
    }
}

private final class RedirectRejectingDelegate: NSObject, URLSessionTaskDelegate {
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
