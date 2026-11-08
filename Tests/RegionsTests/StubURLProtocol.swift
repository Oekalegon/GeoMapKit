import Foundation

/// What a stubbed server answers.
struct StubResponse: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()
    /// If set, the answer is a redirect to this URL (the status is 301).
    var redirect: URL?
    /// If set, the answer is cut off and the connection hangs: the body so far arrives and then nothing.
    var hangs = false
}

/// A `URLProtocol` that answers requests from handlers registered by host name, so `URLSession` can be tested without a network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> StubResponse
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var seen: [String: [URLRequest]] = [:]

    /// Registers a handler for a host and returns a configuration whose sessions use it.
    static func register(host: String, _ handler: @escaping Handler) {
        lock.lock(); handlers[host] = handler; seen[host] = []; lock.unlock()
    }

    static func requests(host: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return seen[host] ?? []
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.lock.lock()
        let handler = Self.handlers[host]
        Self.seen[host, default: []].append(request)
        Self.lock.unlock()
        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let answer = handler(request)
        if let target = answer.redirect {
            let response = HTTPURLResponse(url: url, statusCode: 301, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // The body in pieces, as a network delivers it.
        var position = 0
        let half = answer.hangs ? answer.body.count / 2 : answer.body.count
        while position < half {
            let end = min(position + 16_384, half)
            client?.urlProtocol(self, didLoad: answer.body.subdata(in: position..<end))
            position = end
        }
        if !answer.hangs { client?.urlProtocolDidFinishLoading(self) }
    }

    override func stopLoading() {}
}
