import Foundation
import GeoCore

/// One coarse level of a set of blocks, as a source of cells (question 50).
///
/// A level has the cells of its own storage zoom (`topZoom + 2`) and the overview band only; its blocks are opened when a cell in
/// them is first asked for, with a cache of their own. A level block is checked like a base block (size, storage zoom, format, rule
/// table, bands) and also against the blocks it was made from: when one of those has changed since, the level block is out of date
/// and is refused, with a pointer to `geomapkit build-levels`, and not drawn as if it matched.
///
/// A ``StoreSet`` hands out its levels with ``StoreSet/source(atZoom:)``.
public struct LevelSource: CellSource {
    /// The level.
    public let level: StoreManifest.Level

    private let manifest: StoreManifest
    private let directory: URL
    private let blocksByTile: [Int: StoreManifest.LevelBlock]
    private let staleTiles: Set<Int>
    private let cache: BlockCache

    init(level: StoreManifest.Level, manifest: StoreManifest, directory: URL, maximumOpenBlocks: Int) {
        self.level = level
        self.manifest = manifest
        self.directory = directory
        let side = 1 << level.blockZoom
        blocksByTile = Dictionary(uniqueKeysWithValues: level.blocks.map { ($0.y * side + $0.x, $0) })
        staleTiles = Set(manifest.staleLevelBlocks().filter { $0.topZoom == level.topZoom }.map { $0.y * side + $0.x })
        cache = BlockCache(limit: max(maximumOpenBlocks, 1))
    }

    // MARK: CellSource

    /// The zoom of the cells of the level, `topZoom + 2`.
    public var storageZoom: Int { level.storageZoom }
    /// The overview band: a level holds nothing else.
    public var bands: [ZoomBand] { [.overview] }
    /// The data credit of the set.
    public var attribution: String { manifest.attribution }

    /// The file that holds a cell of the level.
    ///
    /// - Parameter cell: A cell at the storage zoom of the level.
    /// - Returns: The file, or `nil` if no level block holds the cell (sea, or outside the area).
    /// - Throws: ``StoreSetError`` if the level block is missing, damaged, or made from blocks that have changed.
    public func file(containing cell: TileID) throws -> FeatureStoreFile? {
        guard cell.zoom == level.storageZoom else { return nil }
        let shift = level.storageZoom - level.blockZoom
        let side = 1 << level.blockZoom
        let key = (cell.y >> shift) * side + (cell.x >> shift)
        guard let block = blocksByTile[key] else { return nil }
        let file = try open(block, key: key)
        return try file.containsCell(cell) ? file : nil
    }

    /// The number of level block files that are open now (for tests and measurements).
    public var openBlockCount: Int { cache.count }

    private func open(_ block: StoreManifest.LevelBlock, key: Int) throws -> FeatureStoreFile {
        if let open = cache.file(for: key) { return open }
        guard !staleTiles.contains(key) else { throw StoreSetError.levelOutOfDate(file: block.file) }
        let file = try BlockOpening.open(
            file: block.file, bytes: block.bytes, in: directory, storageZoom: level.storageZoom, manifest: manifest,
            bands: [Int(ZoomBand.overview.rawValue)])
        cache.store(file, for: key)
        return file
    }
}
