import Foundation

public enum ReleaseUpdateError: Error, Equatable {
    case invalidVersion
    case invalidJSON
    case invalidPayload
    case untrustedURL
    case invalidResponse
    case temporaryFailure
}

public struct ReleaseVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ rawValue: String) throws {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        let parts = value.split(separator: ".")
        guard (1...3).contains(parts.count) else {
            throw ReleaseUpdateError.invalidVersion
        }
        let numbers = parts.map { Int($0) }
        guard numbers.allSatisfy({ $0 != nil }) else {
            throw ReleaseUpdateError.invalidVersion
        }
        major = numbers[0] ?? 0
        minor = numbers.count > 1 ? numbers[1] ?? 0 : 0
        patch = numbers.count > 2 ? numbers[2] ?? 0 : 0
    }

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}

public struct GitHubReleaseAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL

    public init(name: String, downloadURL: URL) {
        self.name = name
        self.downloadURL = downloadURL
    }
}

public struct GitHubRelease: Equatable, Sendable {
    public let version: ReleaseVersion
    public let pageURL: URL
    public let assets: [GitHubReleaseAsset]

    public init(
        version: ReleaseVersion,
        pageURL: URL,
        assets: [GitHubReleaseAsset]
    ) {
        self.version = version
        self.pageURL = pageURL
        self.assets = assets
    }

    public func asset(named name: String) -> GitHubReleaseAsset? {
        assets.first(where: { $0.name == name })
    }
}

public enum GitHubReleaseDecoder {
    public static func decode(_ data: Data) throws -> GitHubRelease {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = root["tag_name"] as? String,
              let pageString = root["html_url"] as? String,
              let pageURL = URL(string: pageString),
              isTrustedGitHubURL(pageURL)
        else {
            throw ReleaseUpdateError.invalidPayload
        }

        let version = try ReleaseVersion(tagName)
        let assets = (root["assets"] as? [[String: Any]] ?? []).compactMap { asset -> GitHubReleaseAsset? in
            guard let name = asset["name"] as? String,
                  let downloadString = asset["browser_download_url"] as? String,
                  let downloadURL = URL(string: downloadString),
                  isTrustedGitHubURL(downloadURL)
            else {
                return nil
            }
            return GitHubReleaseAsset(name: name, downloadURL: downloadURL)
        }
        return GitHubRelease(version: version, pageURL: pageURL, assets: assets)
    }

    private static func isTrustedGitHubURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "github.com"
    }
}

public struct GitHubReleaseUpdateChecker: Sendable {
    public static let endpointURL = URL(
        string: "https://api.github.com/repos/Supia7/quota-bar/releases/latest"
    )!

    private let endpointURL: URL

    public init(endpointURL: URL = GitHubReleaseUpdateChecker.endpointURL) {
        self.endpointURL = endpointURL
    }

    public func check(currentVersion: ReleaseVersion) async throws -> GitHubRelease? {
        guard endpointURL.scheme?.lowercased() == "https",
              endpointURL.host?.lowercased() == "api.github.com",
              endpointURL.path == "/repos/Supia7/quota-bar/releases/latest"
        else {
            throw ReleaseUpdateError.untrustedURL
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("QuotaBar/0.1", forHTTPHeaderField: "User-Agent")

        let delegate = ReleaseRedirectRejectingDelegate()
        let session = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200
            else {
                throw ReleaseUpdateError.invalidResponse
            }
            let release = try GitHubReleaseDecoder.decode(data)
            return release.version > currentVersion ? release : nil
        } catch let error as ReleaseUpdateError {
            throw error
        } catch {
            throw ReleaseUpdateError.temporaryFailure
        }
    }
}

private final class ReleaseRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate {
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
