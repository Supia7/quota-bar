import Foundation
import Network

public final class OAuthLoopbackCallbackServer: @unchecked Sendable {
    public let requestedPort: UInt16

    private let queue = DispatchQueue(label: "com.supia.quotabar.oauth-loopback")
    private var listener: NWListener?
    private var onReady: (@Sendable (UInt16) -> Void)?
    private var onCallback: (@Sendable (String) -> Void)?
    private var onFailure: (@Sendable () -> Void)?

    public init(port: UInt16 = 1455) {
        requestedPort = port
    }

    public func start(
        onReady: @escaping @Sendable (UInt16) -> Void,
        onCallback: @escaping @Sendable (String) -> Void,
        onFailure: @escaping @Sendable () -> Void
    ) throws {
        stop()

        let parameters = NWParameters.tcp
        guard let port = NWEndpoint.Port(rawValue: requestedPort) else {
            throw OAuthLoopbackCallbackServerError.invalidPort
        }
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: port
        )

        let listener = try NWListener(using: parameters)
        self.listener = listener
        self.onReady = onReady
        self.onCallback = onCallback
        self.onFailure = onFailure

        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else { return }
            switch state {
            case .ready:
                guard let boundPort = listener.port?.rawValue else {
                    onFailure()
                    return
                }
                onReady(boundPort)
            case .failed:
                onFailure()
                self.stop()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        onReady = nil
        onCallback = nil
        onFailure = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.receiveRequest(on: connection)
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16 * 1024
        ) { [weak self, weak connection] data, _, _, _ in
            guard let self, let connection else { return }
            guard let data,
                  let target = Self.requestTarget(from: data),
                  let callbackURL = Self.callbackURL(from: target)
            else {
                self.sendResponse(
                    status: "400 Bad Request",
                    body: "The OAuth callback request was invalid.",
                    on: connection
                )
                return
            }

            self.sendResponse(
                status: "200 OK",
                body: "You can return to QuotaBar. This browser window can be closed.",
                on: connection
            )
            self.onCallback?(callbackURL.absoluteString)
        }
    }

    private func sendResponse(
        status: String,
        body: String,
        on connection: NWConnection
    ) {
        let bodyData = Data(body.utf8)
        let response = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(bodyData.count)\r\n"
            + "Connection: close\r\n\r\n"
        var responseData = Data(response.utf8)
        responseData.append(bodyData)
        connection.send(
            content: responseData,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    private static func requestTarget(from data: Data) -> String? {
        guard let request = String(data: data, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first
        else {
            return nil
        }
        let parts = firstLine.split(separator: " ", maxSplits: 2)
        guard parts.count == 3, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }

    private static func callbackURL(from target: String) -> URL? {
        guard let components = URLComponents(
            string: "http://127.0.0.1\(target)"
        ), components.path == "/auth/callback",
        components.queryItems?.contains(where: { $0.name == "code" }) == true
        else {
            return nil
        }
        return components.url
    }
}

public enum OAuthLoopbackCallbackServerError: Error, Equatable, Sendable {
    case invalidPort
}
