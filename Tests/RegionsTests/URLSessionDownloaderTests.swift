import Foundation
import Testing

@testable import Regions

/// The real downloader, against a stubbed network.
@Suite("URLSessionDownloader")
struct URLSessionDownloaderTests {
    private func downloader() -> URLSessionDownloader {
        URLSessionDownloader(userAgent: "GeoMapKitTests/1.0", configuration: { StubURLProtocol.configuration() })
    }

    private func host() -> String { "stub-\(UUID().uuidString.lowercased()).test" }

    private func part(_ bytes: Int = 0) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-part-\(UUID().uuidString)")
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    private let data = Data((0..<40_000).map { UInt8($0 % 253) })

    /// A server that honours `Range` and `If-Range` for a file with this ETag.
    private func server(etag: String = "\"v1\"") -> StubURLProtocol.Handler {
        let data = self.data
        return { request in
            var headers = ["ETag": etag, "Last-Modified": "Mon, 01 Jan 2026 00:00:00 GMT"]
            if request.httpMethod == "HEAD" {
                if request.value(forHTTPHeaderField: "If-None-Match") == etag { return StubResponse(status: 304) }
                headers["Content-Length"] = "\(data.count)"
                return StubResponse(headers: headers)
            }
            if let range = request.value(forHTTPHeaderField: "Range"), request.value(forHTTPHeaderField: "If-Range") == etag,
                let start = Int(range.dropFirst("bytes=".count).dropLast())
            {
                headers["Content-Range"] = "bytes \(start)-\(data.count - 1)/\(data.count)"
                return StubResponse(status: 206, headers: headers, body: data.subdata(in: start..<data.count))
            }
            headers["Content-Length"] = "\(data.count)"
            return StubResponse(headers: headers, body: data)
        }
    }

    @Test("A question about a file gives its size, ETag and date, names the app, and uses HEAD without compression")
    func metadata() async throws {
        let name = host()
        StubURLProtocol.register(host: name, server())
        let url = URL(string: "https://\(name)/europe/norway-latest.osm.pbf")!
        let result = try await downloader().metadata(of: url, ifNoneMatch: nil)
        #expect(result == .info(RemoteFileInfo(size: 40_000, etag: "\"v1\"", lastModified: "Mon, 01 Jan 2026 00:00:00 GMT")))
        let request = try #require(StubURLProtocol.requests(host: name).first)
        #expect(request.httpMethod == "HEAD" && request.value(forHTTPHeaderField: "User-Agent") == "GeoMapKitTests/1.0")
        #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == "identity" && request.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test("A conditional question gives 'not modified' for the same ETag; another status is an error")
    func conditional() async throws {
        let name = host()
        StubURLProtocol.register(host: name, server())
        let url = URL(string: "https://\(name)/a.osm.pbf")!
        #expect(try await downloader().metadata(of: url, ifNoneMatch: "\"v1\"") == .notModified)
        #expect(StubURLProtocol.requests(host: name).first?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        guard case .info = try await downloader().metadata(of: url, ifNoneMatch: "\"old\"") else { Issue.record("not info"); return }
        StubURLProtocol.register(host: name) { _ in StubResponse(status: 404) }
        await #expect(throws: DownloadError.httpStatus(404, url)) { try await downloader().metadata(of: url, ifNoneMatch: nil) }
    }

    @Test("A download writes the whole file as it arrives, and reports the bytes held")
    func fullDownload() async throws {
        let name = host()
        StubURLProtocol.register(host: name, server())
        let file = try part(300)
        defer { try? FileManager.default.removeItem(at: file) }
        let log = Counter()
        let info = try await downloader().download(
            from: URL(string: "https://\(name)/a.osm.pbf")!, to: file, resumeFrom: 0, ifRange: nil
        ) { log.set($0) }
        #expect(try Data(contentsOf: file) == data, "an old content of the file is replaced")
        #expect(info == RemoteFileInfo(size: 40_000, etag: "\"v1\"", lastModified: "Mon, 01 Jan 2026 00:00:00 GMT"))
        #expect(log.value == 40_000)
        let request = try #require(StubURLProtocol.requests(host: name).first)
        #expect(request.httpMethod == "GET" && request.value(forHTTPHeaderField: "Range") == nil)
    }

    @Test("A download continues after the bytes held, with Range and If-Range, and learns the full size from Content-Range")
    func resume() async throws {
        let name = host()
        StubURLProtocol.register(host: name, server())
        let file = try part()
        defer { try? FileManager.default.removeItem(at: file) }
        try data.prefix(15_000).write(to: file)
        let log = Counter()
        let info = try await downloader().download(
            from: URL(string: "https://\(name)/a.osm.pbf")!, to: file, resumeFrom: 15_000, ifRange: "\"v1\""
        ) { log.set($0) }
        #expect(try Data(contentsOf: file) == data)
        #expect(info.size == 40_000 && info.etag == "\"v1\"" && log.value == 40_000)
        let request = try #require(StubURLProtocol.requests(host: name).first)
        #expect(request.value(forHTTPHeaderField: "Range") == "bytes=15000-" && request.value(forHTTPHeaderField: "If-Range") == "\"v1\"")
    }

    @Test("If the file changed, the server sends it whole and the local file starts again")
    func changedFile() async throws {
        let name = host()
        StubURLProtocol.register(host: name, server(etag: "\"v2\""))
        let file = try part()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 9, count: 15_000).write(to: file)
        let info = try await downloader().download(
            from: URL(string: "https://\(name)/a.osm.pbf")!, to: file, resumeFrom: 15_000, ifRange: "\"v1\"") { _ in }
        #expect(try Data(contentsOf: file) == data && info.etag == "\"v2\"")
    }

    @Test("Bytes are not continued without an ETag: no Range is sent and the file starts again")
    func noEtagNoRange() async throws {
        let name = host()
        StubURLProtocol.register(host: name, server())
        let file = try part()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 9, count: 5_000).write(to: file)
        _ = try await downloader().download(from: URL(string: "https://\(name)/a.osm.pbf")!, to: file, resumeFrom: 5_000, ifRange: nil) { _ in }
        #expect(try Data(contentsOf: file) == data)
        #expect(StubURLProtocol.requests(host: name).first?.value(forHTTPHeaderField: "Range") == nil)
    }

    @Test("A partial answer that starts elsewhere than asked is refused")
    func wrongRange() async throws {
        let name = host()
        StubURLProtocol.register(host: name) { _ in
            StubResponse(status: 206, headers: ["Content-Range": "bytes 0-99/100"], body: Data(repeating: 1, count: 100))
        }
        let file = try part(10)
        defer { try? FileManager.default.removeItem(at: file) }
        await #expect(throws: DownloadError.unexpectedRange("bytes 0-99/100")) {
            try await downloader().download(from: URL(string: "https://\(name)/a")!, to: file, resumeFrom: 10, ifRange: "\"v1\"") { _ in }
        }
    }

    @Test("A status that is not success is an error and writes nothing")
    func errors() async throws {
        let name = host()
        StubURLProtocol.register(host: name) { _ in StubResponse(status: 503, body: Data("busy".utf8)) }
        let file = try part()
        defer { try? FileManager.default.removeItem(at: file) }
        let url = URL(string: "https://\(name)/a")!
        await #expect(throws: DownloadError.httpStatus(503, url)) {
            try await downloader().download(from: url, to: file, resumeFrom: 0, ifRange: nil) { _ in }
        }
        #expect(try Data(contentsOf: file).isEmpty)
    }

    @Test("A redirect from https to http is refused, a redirect to https is followed")
    func redirects() async throws {
        let target = host(), source = host(), weak = host()
        StubURLProtocol.register(host: target, server())
        StubURLProtocol.register(host: source) { _ in StubResponse(redirect: URL(string: "https://\(target)/real.osm.pbf")!) }
        StubURLProtocol.register(host: weak) { _ in StubResponse(redirect: URL(string: "http://\(target)/real.osm.pbf")!) }
        let file = try part()
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try await downloader().download(from: URL(string: "https://\(source)/a")!, to: file, resumeFrom: 0, ifRange: nil) { _ in }
        #expect(try Data(contentsOf: file) == data)
        await #expect(throws: DownloadError.insecureRedirect(URL(string: "http://\(target)/real.osm.pbf")!)) {
            try await downloader().download(from: URL(string: "https://\(weak)/a")!, to: file, resumeFrom: 0, ifRange: nil) { _ in }
        }
        await #expect(throws: DownloadError.self) { try await downloader().metadata(of: URL(string: "https://\(weak)/a")!, ifNoneMatch: nil) }
    }

    @Test("A file of several megabytes arrives complete")
    func large() async throws {
        let name = host()
        let big = Data((0..<4_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        StubURLProtocol.register(host: name) { _ in StubResponse(headers: ["Content-Length": "\(big.count)", "ETag": "\"big\""], body: big) }
        let file = try part()
        defer { try? FileManager.default.removeItem(at: file) }
        let info = try await downloader().download(from: URL(string: "https://\(name)/big")!, to: file, resumeFrom: 0, ifRange: nil) { _ in }
        #expect(info.size == 4_000_000)
        #expect(try Data(contentsOf: file) == big)
    }

    @Test("A task that is cancelled before the request starts ends and does not hang", .timeLimit(.minutes(1)))
    func cancelledBeforeStart() async throws {
        let name = host()
        StubURLProtocol.register(host: name, server())
        let file = try part()
        defer { try? FileManager.default.removeItem(at: file) }
        let client = downloader()
        let url = URL(string: "https://\(name)/a")!
        for _ in 0..<20 {
            let task = Task { try await client.download(from: url, to: file, resumeFrom: 0, ifRange: nil) { _ in } }
            task.cancel()
            // Either it was cancelled in time or it had already finished: both end, neither hangs.
            _ = try? await task.value
        }
    }

    @Test("A response without Content-Length gives an unknown size, for a question and for a download")
    func unknownLength() async throws {
        let name = host()
        StubURLProtocol.register(host: name) { request in
            StubResponse(headers: ["ETag": "\"n\""], body: request.httpMethod == "HEAD" ? Data() : Data(repeating: 4, count: 3_000))
        }
        let url = URL(string: "https://\(name)/a")!
        let result = try await downloader().metadata(of: url, ifNoneMatch: nil)
        guard case .info(let info) = result else { Issue.record("not info"); return }
        #expect(info.size == nil && info.etag == "\"n\"")
        let file = try part()
        defer { try? FileManager.default.removeItem(at: file) }
        let received = try await downloader().download(from: url, to: file, resumeFrom: 0, ifRange: nil) { _ in }
        let stored = try Data(contentsOf: file)
        #expect(received.size == nil && stored.count == 3_000)
    }

    @Test("Cancelling the task stops a download that hangs")
    func cancelling() async throws {
        let name = host()
        StubURLProtocol.register(host: name) { _ in
            StubResponse(headers: ["Content-Length": "1000000"], body: Data(repeating: 3, count: 100_000), hangs: true)
        }
        let file = try part()
        defer { try? FileManager.default.removeItem(at: file) }
        let client = downloader()
        let url = URL(string: "https://\(name)/a")!
        let task = Task { try await client.download(from: url, to: file, resumeFrom: 0, ifRange: nil) { _ in } }
        // Wait until the request has reached the server, then cancel.
        while StubURLProtocol.requests(host: name).isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Int64 = 0
    func set(_ value: Int64) { lock.lock(); current = value; lock.unlock() }
    var value: Int64 { lock.lock(); defer { lock.unlock() }; return current }
}
