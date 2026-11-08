import Foundation
import GeoCore

/// The list of block files that make one map, written as `manifest.json` next to the files.
///
/// A big area is stored as blocks, one store file for each tile of a coarse grid (the block zoom, for example 8). A block holds
/// all the cells of its tile and no cell belongs to two blocks. The manifest says which blocks there are, what format they have
/// (they must all agree), and which source files each was built from, so that "this block is out of date" is a comparison.
public struct StoreManifest: Codable, Equatable, Sendable {
    /// The version of this manifest format.
    public static let currentVersion = 1
    /// The largest manifest that is read, in bytes. A manifest of 100,000 blocks is under 40 MB; this bound only keeps a wrong file
    /// from being read whole.
    public static let maximumSize = 64 * 1024 * 1024

    /// A source file a block was built from.
    public struct Source: Codable, Equatable, Sendable {
        /// The region the file is for.
        public var regionID: String
        /// Where the file came from.
        public var url: String
        /// The size of the file in bytes.
        public var size: Int64
        /// When the file was downloaded.
        public var downloadedAt: Date
        /// The `ETag` of the file, if the server gave one.
        public var etag: String?
        /// The `Last-Modified` of the file, if the server gave one.
        public var lastModified: String?

        /// Creates a source record.
        public init(regionID: String, url: String, size: Int64, downloadedAt: Date, etag: String? = nil, lastModified: String? = nil) {
            self.regionID = regionID
            self.url = url
            self.size = size
            self.downloadedAt = downloadedAt
            self.etag = etag
            self.lastModified = lastModified
        }
    }

    /// One block: a tile of the block grid and the file that holds its cells.
    public struct Block: Codable, Equatable, Sendable {
        /// The column of the tile at the block zoom.
        public var x: Int
        /// The row of the tile at the block zoom.
        public var y: Int
        /// The file, relative to the manifest's folder. It stays inside the folder: no `..`, no absolute path.
        public var file: String
        /// The size of the file in bytes.
        public var bytes: Int64
        /// When the block was built.
        public var builtAt: Date
        /// The source files the block was built from, the one that covers most first.
        public var sources: [Source]

        /// Creates a block entry.
        public init(x: Int, y: Int, file: String, bytes: Int64, builtAt: Date, sources: [Source] = []) {
            self.x = x
            self.y = y
            self.file = file
            self.bytes = bytes
            self.builtAt = builtAt
            self.sources = sources
        }
    }

    /// The version of the manifest format.
    public var version: Int
    /// The format version of the block files.
    public var formatVersion: Int
    /// The rule-table version the block files were built with.
    public var classifierVersion: Int
    /// The zoom of the cells in the block files.
    public var storageZoom: Int
    /// The zoom of the block grid, at most the storage zoom.
    public var blockZoom: Int
    /// The bands the block files hold, as raw values of ``ZoomBand``.
    public var bands: [Int]
    /// The profile the blocks were built with, `full` or `watch`.
    public var profile: String
    /// The data credit that goes with the map.
    public var attribution: String
    /// The blocks.
    public var blocks: [Block]

    /// Creates a manifest.
    public init(
        formatVersion: Int, classifierVersion: Int, storageZoom: Int, blockZoom: Int, bands: [ZoomBand], profile: String,
        attribution: String, blocks: [Block]
    ) {
        version = Self.currentVersion
        self.formatVersion = formatVersion
        self.classifierVersion = classifierVersion
        self.storageZoom = storageZoom
        self.blockZoom = blockZoom
        self.bands = bands.map { Int($0.rawValue) }
        self.profile = profile
        self.attribution = attribution
        self.blocks = blocks
    }

    /// Reads a manifest from JSON and checks it.
    ///
    /// - Parameter data: The JSON.
    /// - Throws: ``StoreSetError/invalidManifest(_:)`` for malformed JSON or a manifest that does not hold together,
    ///   ``StoreSetError/unsupportedManifestVersion(_:)`` for another version.
    public init(json data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            self = try decoder.decode(StoreManifest.self, from: data)
        } catch {
            throw StoreSetError.invalidManifest("\(error)")
        }
        try validate()
    }

    /// The JSON of the manifest: sorted keys and readable, so that two runs that build the same blocks give the same text.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Checks that the manifest holds together: the version, the zooms, the bands, blocks inside the grid, no block twice, and
    /// files that stay in the folder.
    ///
    /// - Throws: ``StoreSetError/unsupportedManifestVersion(_:)`` or ``StoreSetError/invalidManifest(_:)``.
    public func validate() throws {
        guard version == Self.currentVersion else { throw StoreSetError.unsupportedManifestVersion(version) }
        guard (0...TileID.maximumZoom).contains(storageZoom), (0...storageZoom).contains(blockZoom) else {
            throw StoreSetError.invalidManifest("the block zoom \(blockZoom) must be from 0 to the storage zoom \(storageZoom), which must be from 0 to \(TileID.maximumZoom)")
        }
        guard !bands.isEmpty, bands.allSatisfy({ ZoomBand(rawValue: UInt8(clamping: $0)) != nil && $0 >= 0 }) else {
            throw StoreSetError.invalidManifest("the bands are empty or unknown")
        }
        let side = 1 << blockZoom
        var seen = Set<Int>()
        for block in blocks {
            guard (0..<side).contains(block.x), (0..<side).contains(block.y) else {
                throw StoreSetError.invalidManifest("the block \(block.x)/\(block.y) is outside the grid of zoom \(blockZoom)")
            }
            guard seen.insert(block.y * side + block.x).inserted else {
                throw StoreSetError.invalidManifest("the block \(block.x)/\(block.y) is listed twice")
            }
            guard block.bytes >= 0 else { throw StoreSetError.invalidManifest("the block \(block.x)/\(block.y) has a negative size") }
            guard Self.isInsideFolder(block.file) else {
                throw StoreSetError.invalidManifest("the file '\(block.file)' of block \(block.x)/\(block.y) is not a path inside the folder")
            }
        }
    }

    /// Whether a relative path stays inside the folder it is relative to.
    static func isInsideFolder(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0"), !path.contains("\\") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
