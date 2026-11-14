import Foundation

/// The folder of downloaded source files, with a record for each.
///
/// For a region `norway` the folder holds `norway.osm.pbf` (the file), `norway.osm.pbf.json` (its ``CachedSource`` record) and,
/// while a download is unfinished, `norway.osm.pbf.part` with `norway.osm.pbf.part.json` (the `ETag` of the bytes in it, to resume
/// from). A file only appears under its real name once it is complete, so a failed download never replaces a good file.
/// Nothing is ever deleted except by ``remove(regionID:)``, and the cache has no size limit.
///
/// The clock and the free-space function are given by the caller, so the time limit and the space check can be tested.
public struct SourceCache: Sendable {
    /// The folder.
    public let directory: URL
    /// How long a file counts as current after the server was last asked about it, in seconds. 30 days by default.
    public let staleAfter: TimeInterval
    private let now: @Sendable () -> Date
    private let availableCapacity: @Sendable (URL) -> Int64?

    /// Creates a cache.
    ///
    /// - Parameters:
    ///   - directory: The folder; it is created when the first file arrives.
    ///   - staleAfter: The time limit in seconds.
    ///   - now: The clock.
    ///   - availableCapacity: The free space, in bytes, on the volume of a folder, or `nil` if unknown. The default asks the
    ///     system.
    public init(
        directory: URL, staleAfter: TimeInterval = 30 * 24 * 3600, now: @escaping @Sendable () -> Date = { Date() },
        availableCapacity: @escaping @Sendable (URL) -> Int64? = SourceCache.systemAvailableCapacity
    ) {
        self.directory = directory
        self.staleAfter = staleAfter
        self.now = now
        self.availableCapacity = availableCapacity
    }

    /// The default folder: `GeoMapKit/Sources` in the application support folder of the user.
    ///
    /// - Throws: ``SourceError/cacheUnusable(_:)`` if the system gives no such folder.
    public static func defaultDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SourceError.cacheUnusable("no application support folder")
        }
        return base.appendingPathComponent("GeoMapKit", isDirectory: true).appendingPathComponent("Sources", isDirectory: true)
    }

    /// The free space on the volume of a folder (the nearest folder that exists), as the system reports it for important use, or
    /// `nil` on watchOS, where nothing is downloaded.
    public static func systemAvailableCapacity(_ url: URL) -> Int64? {
        var folder = url
        while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 {
            folder = folder.deletingLastPathComponent()
        }
        #if os(watchOS)
        return nil  // The Watch never downloads source files.
        #else
        return (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        #endif
    }

    // MARK: Paths

    /// Where the file of a region is, whether or not it exists.
    public func fileURL(forRegionID id: String) -> URL { directory.appendingPathComponent("\(Self.safe(id)).osm.pbf") }

    private func recordURL(_ id: String) -> URL { directory.appendingPathComponent("\(Self.safe(id)).osm.pbf.json") }
    /// Where the unfinished download of a region is.
    func partURL(_ id: String) -> URL { directory.appendingPathComponent("\(Self.safe(id)).osm.pbf.part") }
    private func partRecordURL(_ id: String) -> URL { directory.appendingPathComponent("\(Self.safe(id)).osm.pbf.part.json") }

    /// An identifier as a file name: ASCII letters, digits and `-` stay, every other byte is written as `%XX`, so an id from an
    /// index cannot name a file outside the folder, and different ids never give the same name.
    private static func safe(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: allowedInNames) ?? "%"
    }

    private static let allowedInNames = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")

    // MARK: Reading

    /// The record of a region and whether its file can be used.
    ///
    /// - Parameter regionID: The region.
    /// - Returns: The status, and the record when there is a usable one.
    public func status(ofRegionID regionID: String) -> (status: CacheStatus, record: CachedSource?) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: recordURL(regionID).path) || manager.fileExists(atPath: fileURL(forRegionID: regionID).path) else {
            return (.missing, nil)
        }
        guard let data = try? Data(contentsOf: recordURL(regionID)) else { return (.damaged("the record is missing"), nil) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(CachedSource.self, from: data), record.regionID == regionID else {
            return (.damaged("the record cannot be read"), nil)
        }
        guard let size = Self.size(of: fileURL(forRegionID: regionID)) else { return (.damaged("the file is missing"), nil) }
        guard size == record.size else {
            return (.damaged("the file has \(size) bytes, the record says \(record.size)"), nil)
        }
        let age = now().timeIntervalSince(record.checkedAt)
        return (age > staleAfter ? .stale(checkedAt: record.checkedAt) : .current(checkedAt: record.checkedAt), record)
    }

    /// The records of all files in the cache that can be read, ordered by region.
    public func list() -> [CachedSource] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names.filter { $0.hasSuffix(".osm.pbf.json") }.sorted().compactMap { name in
            (try? Data(contentsOf: directory.appendingPathComponent(name))).flatMap { try? decoder.decode(CachedSource.self, from: $0) }
        }
    }

    /// One thing in the cache folder that takes space: a usable file, one that cannot be used, or an unfinished download.
    public struct Entry: Equatable, Sendable, Identifiable {
        /// What it is.
        public enum Kind: Equatable, Sendable {
            /// A file with a readable record whose size agrees with the file (current or stale).
            case file(CachedSource)
            /// A file or record that cannot be trusted, with the reason (see ``CacheStatus/damaged(_:)``). It is downloaded again when needed.
            case damaged(String)
            /// The bytes of a download that did not finish; a new download continues after them.
            case unfinished
        }

        /// The region.
        public let regionID: String
        /// What it is.
        public let kind: Kind
        /// The bytes it takes on disk (the file, or the part file); 0 for a record whose file is missing.
        public let bytes: Int64

        /// A region can have a file and an unfinished download at the same time, so the kind is part of the identity.
        public var id: String {
            switch kind {
            case .file: "\(regionID)#file"
            case .damaged: "\(regionID)#damaged"
            case .unfinished: "\(regionID)#unfinished"
            }
        }
    }

    /// Everything in the cache folder that takes space, ordered by region: files, files that cannot be used (also a file with no
    /// record, and a record with no file) and unfinished downloads.
    ///
    /// - Returns: The entries; empty if the folder does not exist.
    public func entries() -> [Entry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        // The name of a file is the percent-encoded region id plus a suffix, so the id can be read back from it.
        func regionID(_ name: String, suffix: String) -> String? {
            guard name.hasSuffix(suffix) else { return nil }
            return String(name.dropLast(suffix.count)).removingPercentEncoding
        }
        var found: [Entry] = []
        var seen = Set<String>()
        for name in names.sorted() {
            if let id = regionID(name, suffix: ".osm.pbf.json") {
                seen.insert(id)
                let bytes = Self.size(of: fileURL(forRegionID: id)) ?? 0
                switch status(ofRegionID: id) {
                case (.damaged(let reason), _): found.append(Entry(regionID: id, kind: .damaged(reason), bytes: bytes))
                case (_, let record?): found.append(Entry(regionID: id, kind: .file(record), bytes: bytes))
                default: break
                }
            } else if let id = regionID(name, suffix: ".osm.pbf.part") {
                found.append(Entry(regionID: id, kind: .unfinished, bytes: Self.size(of: partURL(id)) ?? 0))
            }
        }
        // A file with no record: nothing says what it is, and ``status(ofRegionID:)`` does not trust it.
        for name in names.sorted() {
            guard let id = regionID(name, suffix: ".osm.pbf"), !seen.contains(id) else { continue }
            found.append(Entry(regionID: id, kind: .damaged("the record is missing"), bytes: Self.size(of: fileURL(forRegionID: id)) ?? 0))
        }
        return found.sorted { ($0.regionID, $0.id) < ($1.regionID, $1.id) }
    }

    // MARK: Changing

    /// Records that the server was asked and the file is current.
    ///
    /// - Parameter regionID: The region. Nothing happens if it has no usable record.
    public func markChecked(regionID: String) throws {
        guard var record = status(ofRegionID: regionID).record else { return }
        record.checkedAt = now()
        try write(record)
    }

    /// Puts a finished download in place: the part file becomes the file of the region and a record is written. An older file of
    /// the region is replaced in one step, and the unfinished-download note is removed. The file and its record are two files, so
    /// a crash between the two steps leaves a file whose size is not the record's: ``status(ofRegionID:)`` then says damaged and
    /// the file is downloaded again, which is wasteful but never wrong.
    ///
    /// - Parameters:
    ///   - regionID: The region.
    ///   - url: Where the file came from.
    ///   - info: What the server said about it. `size` must be the size of the part file.
    /// - Throws: ``SourceError/incompleteDownload(region:expected:received:)`` if the server's size is known and the part file
    ///   has another, or a file error.
    public func install(regionID: String, from url: URL, info: RemoteFileInfo) throws {
        let part = partURL(regionID)
        let received = Self.size(of: part) ?? 0
        if let expected = info.size, expected != received {
            throw SourceError.incompleteDownload(region: regionID, expected: expected, received: received)
        }
        let manager = FileManager.default
        let target = fileURL(forRegionID: regionID)
        if manager.fileExists(atPath: target.path) {
            _ = try manager.replaceItemAt(target, withItemAt: part)
        } else {
            try manager.moveItem(at: part, to: target)
        }
        try write(
            CachedSource(
                regionID: regionID, url: url, size: received, downloadedAt: now(), checkedAt: now(), etag: info.etag,
                lastModified: info.lastModified))
        try? manager.removeItem(at: partRecordURL(regionID))
    }

    /// Removes the file, the record and any unfinished download of a region.
    ///
    /// - Parameter regionID: The region.
    public func remove(regionID: String) throws {
        let manager = FileManager.default
        for url in [fileURL(forRegionID: regionID), recordURL(regionID), partURL(regionID), partRecordURL(regionID)]
        where manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
    }

    /// Removes the unfinished download of a region (the part file and its note) and leaves the file of the region alone.
    ///
    /// - Parameter regionID: The region.
    public func removeUnfinished(regionID: String) throws {
        let manager = FileManager.default
        for url in [partURL(regionID), partRecordURL(regionID)] where manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
    }

    // MARK: Unfinished downloads

    /// An unfinished download that can be continued: how many bytes the part file holds and the `ETag` of the file they came from.
    public func partialDownload(regionID: String) -> (bytes: Int64, etag: String?)? {
        guard let bytes = Self.size(of: partURL(regionID)), bytes > 0 else { return nil }
        let etag = (try? Data(contentsOf: partRecordURL(regionID))).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }?["etag"]
        return (bytes, etag)
    }

    /// Prepares the part file of a region and notes which version of the file its bytes are from.
    ///
    /// - Parameters:
    ///   - regionID: The region.
    ///   - etag: The `ETag` of the file about to be downloaded, or `nil`.
    ///   - keepBytes: Whether to keep the bytes already in the part file (to resume) or empty it.
    /// - Returns: The part file.
    public func preparePart(regionID: String, etag: String?, keepBytes: Bool) throws -> URL {
        let manager = FileManager.default
        try ensureDirectory()
        let part = partURL(regionID)
        if !keepBytes || !manager.fileExists(atPath: part.path) {
            try? manager.removeItem(at: part)
            guard manager.createFile(atPath: part.path, contents: nil) else { throw SourceError.cacheUnusable("cannot create \(part.path)") }
        }
        if let etag {
            try JSONEncoder().encode(["etag": etag]).write(to: partRecordURL(regionID), options: .atomic)
        } else {
            try? manager.removeItem(at: partRecordURL(regionID))
        }
        return part
    }

    /// The free space on the volume of the cache, in bytes, or `nil` if it is not known.
    public func availableBytes() -> Int64? { availableCapacity(directory) }

    private func ensureDirectory() throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw SourceError.cacheUnusable("cannot create \(directory.path): \(error.localizedDescription)")
        }
    }

    private func write(_ record: CachedSource) throws {
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: recordURL(record.regionID), options: .atomic)
    }

    private static func size(of url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        if let size = attributes[.size] as? Int64 { return size }
        return (attributes[.size] as? Int).map(Int64.init)
    }
}
