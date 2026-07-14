import Foundation

/// A fake network for `KitchenSyncClient`.
///
/// The client is deliberately a thin transport over `URLSession`, so the honest
/// way to test anything above it is to stub at the `URLProtocol` layer and let
/// the real client — real URL building, real form encoding, real status checking
/// — run against it. Mocking `KitchenSyncClient` itself would test nothing:
/// it would assert that our fake calls our fake.
///
/// Every request the app makes lands in `requests`, so a test can assert on the
/// exact route, method, and body the device would have received.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var status: Int = 200
        var body: Data = Data()
    }

    /// Route ("METHOD /path") → response. Query strings are not part of the key;
    /// assert on them via `requests` instead.
    nonisolated(unsafe) static var routes: [String: Response] = [:]
    /// Every request seen, in order. Bodies included.
    nonisolated(unsafe) static var requests: [(method: String, url: URL, body: Data)] = []

    static func reset() {
        routes = [:]
        requests = []
    }

    /// A `URLSession` that talks only to this stub.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let method = request.httpMethod ?? "GET"
        Self.requests.append((method, url, Self.body(of: request)))

        let key = "\(method) \(url.path)"
        let stub = Self.routes[key] ?? Response(status: 404, body: Data())

        let response = HTTPURLResponse(url: url, statusCode: stub.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
