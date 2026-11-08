import Foundation

@testable import Regions

/// A server in memory that the tests can change, cut off, and count the requests of.
actor FakeServer {
    struct File {
        var data: Data
        var etag: String?
        var lastModified: String?
        /// Whether the server says how large the file is (`Content-Length`).
        var sizeKnown = true
    }
    enum Failure: Error { case offline, connectionLost }

    private(set) var files: [URL: File] = [:]
    /// What was asked, for example `HEAD https://… if-none-match "v1"` or `GET https://… from 500`.
    private(set) var log: [String] = []
    var offline = false
    var supportsRange = true
    /// If set, the next download stops after this many bytes and fails.
    private var cutAfter: Int?

    func put(
        _ url: URL, _ data: Data, etag: String? = "\"v1\"", lastModified: String? = "Mon, 01 Jan 2026 00:00:00 GMT",
        sizeKnown: Bool = true
    ) {
        files[url] = File(data: data, etag: etag, lastModified: lastModified, sizeKnown: sizeKnown)
    }

    func data(_ url: URL) -> Data? { files[url]?.data }
    func setOffline(_ value: Bool) { offline = value }
    func setSupportsRange(_ value: Bool) { supportsRange = value }
    func cutNextDownload(after bytes: Int) { cutAfter = bytes }
    func requests(containing text: String) -> [String] { log.filter { $0.contains(text) } }

    func head(_ url: URL, ifNoneMatch: String?) throws -> RemoteMetadata {
        log.append("HEAD \(url)" + (ifNoneMatch.map { " if-none-match \($0)" } ?? ""))
        guard !offline else { throw Failure.offline }
        guard let file = files[url] else { throw URLError(.fileDoesNotExist) }
        if let ifNoneMatch, ifNoneMatch == file.etag { return .notModified }
        return .info(RemoteFileInfo(size: file.sizeKnown ? Int64(file.data.count) : nil, etag: file.etag, lastModified: file.lastModified))
    }

    /// What the server sends for a request: the bytes, where they start in the file, and the file's description.
    func get(_ url: URL, from offset: Int, ifRange: String?) throws -> (bytes: Data, start: Int, info: RemoteFileInfo, cut: Int?) {
        log.append("GET \(url) from \(offset)" + (ifRange.map { " if-range \($0)" } ?? ""))
        guard !offline else { throw Failure.offline }
        guard let file = files[url] else { throw URLError(.fileDoesNotExist) }
        let info = RemoteFileInfo(size: file.sizeKnown ? Int64(file.data.count) : nil, etag: file.etag, lastModified: file.lastModified)
        // A range is honoured only if the server supports it and the file is the one the bytes came from.
        let start = (supportsRange && offset > 0 && (ifRange == nil || ifRange == file.etag)) ? offset : 0
        let cut = cutAfter
        cutAfter = nil
        return (file.data.subdata(in: start..<file.data.count), start, info, cut)
    }
}

/// A ``Downloader`` that talks to a ``FakeServer``.
struct FakeDownloader: Downloader {
    let server: FakeServer

    func metadata(of url: URL, ifNoneMatch etag: String?) async throws -> RemoteMetadata {
        try await server.head(url, ifNoneMatch: etag)
    }

    func download(
        from url: URL, to file: URL, resumeFrom offset: Int64, ifRange etag: String?, progress: @Sendable (Int64) -> Void
    ) async throws -> RemoteFileInfo {
        let answer = try await server.get(url, from: Int(offset), ifRange: etag)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        if answer.start == 0 { try handle.truncate(atOffset: 0) } else { try handle.seekToEnd() }
        var written = Int64(answer.start)
        var position = 0
        while position < answer.bytes.count {
            if let cut = answer.cut, position >= cut { throw FakeServer.Failure.connectionLost }
            let end = min(position + 700, answer.bytes.count, answer.cut ?? .max)
            try handle.write(contentsOf: answer.bytes.subdata(in: position..<end))
            written += Int64(end - position)
            position = end
            progress(written)
            if let cut = answer.cut, position >= cut, position < answer.bytes.count { throw FakeServer.Failure.connectionLost }
        }
        return answer.info
    }
}

/// A clock the tests move by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = date }
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(days: Double) { lock.lock(); current = current.addingTimeInterval(days * 86_400); lock.unlock() }
}
