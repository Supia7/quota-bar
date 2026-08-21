import Foundation

public struct OAuthEndpointPolicy: Equatable, Sendable {
    public let host: String
    public let pathPrefix: String

    public init(host: String, pathPrefix: String) {
        self.host = host
        self.pathPrefix = pathPrefix
    }

    public func allows(_ url: URL) -> Bool {
        guard
            url.scheme?.lowercased() == "https",
            url.host?.lowercased() == host.lowercased()
        else {
            return false
        }
        return url.path.hasPrefix(pathPrefix)
    }

    public static let claudeUsage = OAuthEndpointPolicy(
        host: "api.anthropic.com",
        pathPrefix: "/api/oauth/usage"
    )

    public static let codexUsage = OAuthEndpointPolicy(
        host: "chatgpt.com",
        pathPrefix: "/backend-api/wham/usage"
    )
}
