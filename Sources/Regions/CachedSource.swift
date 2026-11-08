import Foundation

/// What is known about a source file in the cache. It is kept next to the file as a small JSON file.
public struct CachedSource: Codable, Equatable, Sendable {
    /// The region the file is for.
    public var regionID: String
    /// Where the file came from.
    public var url: URL
    /// The size of the file in bytes, which is checked against the file on disk.
    public var size: Int64
    /// When the file was downloaded.
    public var downloadedAt: Date
    /// When the server was last asked whether the file is current (the download itself counts).
    public var checkedAt: Date
    /// The `ETag` the server gave, or `nil`.
    public var etag: String?
    /// The `Last-Modified` the server gave, or `nil`.
    public var lastModified: String?

    /// Creates a record.
    public init(
        regionID: String, url: URL, size: Int64, downloadedAt: Date, checkedAt: Date, etag: String? = nil, lastModified: String? = nil
    ) {
        self.regionID = regionID
        self.url = url
        self.size = size
        self.downloadedAt = downloadedAt
        self.checkedAt = checkedAt
        self.etag = etag
        self.lastModified = lastModified
    }
}

/// Whether a cached source file can be used.
public enum CacheStatus: Equatable, Sendable {
    /// There is no file for the region.
    case missing
    /// The file is there and was checked with the server within the time limit.
    case current(checkedAt: Date)
    /// The file is there but was last checked longer ago than the time limit; the server should be asked.
    case stale(checkedAt: Date)
    /// The record and the file do not agree (the file is gone or has another size) or the record cannot be read. The file
    /// cannot be trusted.
    case damaged(String)
}
