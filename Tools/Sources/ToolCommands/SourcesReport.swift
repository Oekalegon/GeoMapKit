import Foundation
import GeoCore
import Regions
import ToolSupport

/// What the source files for an area are and, after a fetch, what was done about them.
public struct SourcesReport: Sendable {
    /// The area the regions were chosen for (the box that the build cuts, widened to whole cells).
    public let area: BoundingBox
    /// The folder of the cache.
    public let cacheDirectory: URL
    /// The plan: one item per region.
    public let plan: DownloadPlan
    /// Whether the files in the plan were downloaded by this command.
    public let downloaded: Bool
    /// How long the download took, if there was one.
    public let downloadTime: Duration?

    /// Creates a report.
    public init(area: BoundingBox, cacheDirectory: URL, plan: DownloadPlan, downloaded: Bool = false, downloadTime: Duration? = nil) {
        self.area = area
        self.cacheDirectory = cacheDirectory
        self.plan = plan
        self.downloaded = downloaded
        self.downloadTime = downloadTime
    }
}

/// The cached source files for an area, ready to be cut.
public struct CachedSources: Sendable {
    /// The files, the one that covers most of the area first (the order for the cutter).
    public let files: [URL]
    /// The record of each file, in the same order.
    public let records: [CachedSource]
    /// The share of the area the regions' outlines cover.
    public let coveredShare: Double
    /// Things to tell before the build: a file that could not be checked, or one that is older than the server's.
    public let warnings: [String]
}

/// What a build was made from, written next to the store file as `name.gmk.sources.json`, so that "this area is out of date" is a
/// comparison of dates and `ETag`s with the cache.
public struct BuildSources: Codable, Equatable, Sendable {
    /// When the store was built.
    public var builtAt: Date
    /// The area that was cut: south, west, north and east edges in degrees.
    public var area: BoundingBox
    /// The source files, the one that covers most first.
    public var sources: [CachedSource]

    /// Creates the record.
    public init(builtAt: Date, area: BoundingBox, sources: [CachedSource]) {
        self.builtAt = builtAt
        self.area = area
        self.sources = sources
    }

    /// Where the record of a store file is: the file's path with `.sources.json` added.
    ///
    /// - Parameter store: The store file.
    public static func url(forStore store: URL) -> URL {
        store.deletingLastPathComponent().appendingPathComponent(store.lastPathComponent + ".sources.json")
    }

    /// Writes the record next to a store file, atomically.
    ///
    /// - Parameter store: The store file.
    /// - Throws: ``ToolError`` if the record cannot be written.
    public func write(besides store: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(self).write(to: Self.url(forStore: store), options: .atomic)
        } catch {
            throw ToolError("Cannot write \(Self.url(forStore: store).path): \(error.localizedDescription)")
        }
    }
}
