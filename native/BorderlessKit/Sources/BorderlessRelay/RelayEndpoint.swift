import Foundation

/// A user-selected relay, never a provider endpoint or credential-bearing URL.
/// Cleartext is permitted only for the fixed simulator loopback service.
public struct RelayEndpoint: Sendable, Equatable {
    public let url: URL
    public static let simulator = RelayEndpoint(url: URL(string: "ws://127.0.0.1:8766")!)

    private init(url: URL) { self.url = url }

    public init(validating address: String) throws {
        guard address.count <= 2_048,
              let parts = URLComponents(string: address),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              let url = parts.url else { throw RelayFailure.invalidEndpoint }
        let secure = parts.scheme == "wss"
        let loopback = parts.scheme == "ws" && host == "127.0.0.1" && parts.port == 8766
            && (parts.path.isEmpty || parts.path == "/")
        guard secure || loopback else { throw RelayFailure.invalidEndpoint }
        self.url = url
    }
}

/// Never forward relay authentication to an HTTP redirect target.
final class RelaySessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
