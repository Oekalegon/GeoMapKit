import Foundation

/// The Geofabrik region index, kept in a folder and renewed with the same rules as the source files.
///
/// The index is downloaded once and then used as it is for 30 days (``staleAfter``). After that the server is asked with the
/// `ETag` of the copy that is held: "not modified" renews the check date, a changed index is downloaded, read and, only if it
/// is valid, put in place. If the server cannot be reached, the copy that is held is used. Without a copy the error is raised.
/// Nothing large is downloaded: the index is a few megabytes.
public struct GeofabrikCatalog: RegionCatalog {
    /// Where Geofabrik publishes the index.
    public static let indexURL = URL(string: "https://download.geofabrik.de/index-v1.json")!

    /// The folder the copy is kept in.
    public let directory: URL
    /// How long a copy is used without asking the server, in seconds.
    public let staleAfter: TimeInterval
    private let url: URL
    private let downloader: any Downloader
    private let now: @Sendable () -> Date

    /// Creates a catalog.
    ///
    /// - Parameters:
    ///   - directory: The folder for the copy of the index (it is created when needed).
    ///   - downloader: The network.
    ///   - url: Where the index is, `indexURL` by default.
    ///   - staleAfter: The time limit in seconds, 30 days by default.
    ///   - now: The clock.
    public init(
        directory: URL, downloader: any Downloader, url: URL = GeofabrikCatalog.indexURL, staleAfter: TimeInterval = 30 * 24 * 3600,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.downloader = downloader
        self.url = url
        self.staleAfter = staleAfter
        self.now = now
    }

    private struct Note: Codable {
        var etag: String?
        var checkedAt: Date
    }

    private var indexFile: URL { directory.appendingPathComponent("geofabrik-index-v1.json") }
    private var noteFile: URL { directory.appendingPathComponent("geofabrik-index-v1.json.note") }

    public func index() async throws -> RegionIndex {
        let cached = readCached()
        if let cached, now().timeIntervalSince(cached.note.checkedAt) <= staleAfter { return cached.index }
        do {
            switch try await downloader.metadata(of: url, ifNoneMatch: cached?.note.etag) {
            case .notModified:
                if let cached {
                    try write(Note(etag: cached.note.etag, checkedAt: now()))
                    return cached.index
                }
                throw DownloadError.httpStatus(304, url)
            case .info(let info):
                return try await download(info)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // No network, or a bad answer: the copy that is held is better than none.
            if let cached { return cached.index }
            throw error
        }
    }

    private func readCached() -> (index: RegionIndex, note: Note)? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: indexFile), let noteData = try? Data(contentsOf: noteFile),
            let note = try? decoder.decode(Note.self, from: noteData), let index = try? RegionIndex(geoJSON: data)
        else { return nil }
        return (index, note)
    }

    private func download(_ info: RemoteFileInfo) async throws -> RegionIndex {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let part = directory.appendingPathComponent("geofabrik-index-v1.json.part")
        try? FileManager.default.removeItem(at: part)
        guard FileManager.default.createFile(atPath: part.path, contents: nil) else {
            throw SourceError.cacheUnusable("cannot create \(part.path)")
        }
        defer { try? FileManager.default.removeItem(at: part) }
        let received = try await downloader.download(from: url, to: part, resumeFrom: 0, ifRange: nil) { _ in }
        let data = try Data(contentsOf: part)
        if let expected = received.size ?? info.size, expected != Int64(data.count) {
            throw SourceError.incompleteDownload(region: "index", expected: expected, received: Int64(data.count))
        }
        // Read it before it is put in place: a bad index never replaces a good one.
        let index = try RegionIndex(geoJSON: data)
        try data.write(to: indexFile, options: .atomic)
        try write(Note(etag: received.etag ?? info.etag, checkedAt: now()))
        return index
    }

    private func write(_ note: Note) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(note).write(to: noteFile, options: .atomic)
    }
}
