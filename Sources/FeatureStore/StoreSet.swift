import Foundation
import GeoCore

/// A map made of block files: it reads the manifest and hands out the file that holds a cell, opening block files when they are
/// first needed.
///
/// The files are memory-mapped, so an open block costs address space, not memory, but the number of open files is kept in bounds:
/// at most ``maximumOpenBlocks`` stay open, the one least recently used is closed first. A block is checked against the manifest
/// when it is opened (storage zoom, format version, rule table, bands and size), so a block from another build is an error and not a
/// map that is wrong in places. The Watch never opens a manifest; it receives one cut store file.
public struct StoreSet: CellSource {
    /// The manifest.
    public let manifest: StoreManifest
    /// The folder of the manifest; block files are inside it.
    public let directory: URL
    /// The most block files kept open at once.
    public let maximumOpenBlocks: Int

    private let blocksByTile: [Int: StoreManifest.Block]
    private let cache: BlockCache

    /// Opens a set from its manifest file.
    ///
    /// - Parameters:
    ///   - manifestURL: The `manifest.json`.
    ///   - maximumOpenBlocks: The most block files kept open, at least 1; 16 by default.
    /// - Throws: ``StoreSetError`` for a manifest that is too large, malformed or unsupported, or the file error.
    public init(manifestURL: URL, maximumOpenBlocks: Int = 16) throws {
        let size = (try? manifestURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= StoreManifest.maximumSize else {
            throw StoreSetError.invalidManifest("the manifest is \(size) bytes, more than the limit of \(StoreManifest.maximumSize)")
        }
        try self.init(manifest: StoreManifest(json: Data(contentsOf: manifestURL)), directory: manifestURL.deletingLastPathComponent(),
            maximumOpenBlocks: maximumOpenBlocks)
    }

    /// Creates a set from a manifest that is already read.
    ///
    /// - Parameters:
    ///   - manifest: The manifest; it is checked.
    ///   - directory: The folder the block files are in.
    ///   - maximumOpenBlocks: The most block files kept open, at least 1.
    /// - Throws: ``StoreSetError`` if the manifest does not hold together.
    public init(manifest: StoreManifest, directory: URL, maximumOpenBlocks: Int = 16) throws {
        try manifest.validate()
        self.manifest = manifest
        self.directory = directory
        self.maximumOpenBlocks = max(maximumOpenBlocks, 1)
        let side = 1 << manifest.blockZoom
        blocksByTile = Dictionary(uniqueKeysWithValues: manifest.blocks.map { ($0.y * side + $0.x, $0) })
        cache = BlockCache(limit: self.maximumOpenBlocks)
    }

    // MARK: CellSource

    public var storageZoom: Int { manifest.storageZoom }
    public var bands: [ZoomBand] { manifest.bands.compactMap { ZoomBand(rawValue: UInt8($0)) } }
    public var attribution: String { manifest.attribution }

    public func file(containing cell: TileID) throws -> FeatureStoreFile? {
        guard cell.zoom == manifest.storageZoom else { return nil }
        let shift = manifest.storageZoom - manifest.blockZoom
        let side = 1 << manifest.blockZoom
        let key = (cell.y >> shift) * side + (cell.x >> shift)
        guard let block = blocksByTile[key] else { return nil }
        let file = try openBlock(block, key: key)
        return try file.containsCell(cell) ? file : nil
    }

    /// The area the blocks cover: the union of their tiles, or `nil` for a set without blocks.
    public var boundingBox: BoundingBox? {
        let tiles = manifest.blocks.compactMap { TileID(zoom: manifest.blockZoom, x: $0.x, y: $0.y) }
        guard let first = tiles.first else { return nil }
        var box = BoundingBox(
            south: first.southEast.latitude, west: first.northWest.longitude, north: first.northWest.latitude, east: first.southEast.longitude)
        for tile in tiles.dropFirst() {
            box = BoundingBox(
                south: min(box.south, tile.southEast.latitude), west: min(box.west, tile.northWest.longitude),
                north: max(box.north, tile.northWest.latitude), east: max(box.east, tile.southEast.longitude))
        }
        return box
    }

    /// All cells of all blocks, in the order of the manifest. It opens every block file in turn, so it is slow for a large set;
    /// meant for checks and tools, not for drawing.
    public func cells() throws -> [TileID] {
        let side = 1 << manifest.blockZoom
        var result: [TileID] = []
        for block in manifest.blocks {
            result += try openBlock(block, key: block.y * side + block.x).cells()
        }
        return result
    }

    /// The number of block files that are open now (for tests and measurements).
    public var openBlockCount: Int { cache.count }

    // MARK: Opening blocks

    private func openBlock(_ block: StoreManifest.Block, key: Int) throws -> FeatureStoreFile {
        if let open = cache.file(for: key) { return open }
        let url = directory.appendingPathComponent(block.file)
        // A block must be inside the folder even when a link in it points elsewhere.
        let folder = directory.standardizedFileURL.resolvingSymlinksInPath().path
        guard url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(folder + "/") else {
            throw StoreSetError.blockMismatch(file: block.file, reason: "the file is not inside the folder of the manifest")
        }
        guard FileManager.default.fileExists(atPath: url.path) else { throw StoreSetError.blockMissing(block.file) }
        let file: FeatureStoreFile
        do {
            file = try FeatureStoreFile(contentsOf: url)
        } catch {
            throw StoreSetError.blockMismatch(file: block.file, reason: "it is not a readable store file (\(error))")
        }
        guard file.storageZoom == manifest.storageZoom else {
            throw StoreSetError.blockMismatch(file: block.file, reason: "storage zoom \(file.storageZoom), the manifest says \(manifest.storageZoom)")
        }
        guard file.formatVersion == manifest.formatVersion, file.classifierVersion == manifest.classifierVersion else {
            throw StoreSetError.blockMismatch(
                file: block.file,
                reason: "format \(file.formatVersion) and rule table \(file.classifierVersion), the manifest says \(manifest.formatVersion) and \(manifest.classifierVersion)")
        }
        guard file.bands.map({ Int($0.rawValue) }) == manifest.bands else {
            throw StoreSetError.blockMismatch(file: block.file, reason: "the bands differ from the manifest")
        }
        // The manifest says which build each block is from; a file of another size is another build, or a half-written one.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? -1
        guard size == block.bytes else {
            throw StoreSetError.blockMismatch(file: block.file, reason: "the file has \(size) bytes, the manifest says \(block.bytes)")
        }
        cache.store(file, for: key)
        return file
    }
}

/// The block files that are open, least recently used first out. It has a lock because a map can be built on several threads.
private final class BlockCache: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var files: [Int: FeatureStoreFile] = [:]
    private var order: [Int] = []

    init(limit: Int) { self.limit = limit }

    var count: Int { lock.lock(); defer { lock.unlock() }; return files.count }

    func file(for key: Int) -> FeatureStoreFile? {
        lock.lock(); defer { lock.unlock() }
        guard let file = files[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return file
    }

    func store(_ file: FeatureStoreFile, for key: Int) {
        lock.lock(); defer { lock.unlock() }
        if files.updateValue(file, forKey: key) == nil { order.append(key) } else { order.removeAll { $0 == key }; order.append(key) }
        while files.count > limit, let oldest = order.first {
            order.removeFirst()
            files[oldest] = nil
        }
    }
}
