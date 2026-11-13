import FeatureStore
import Foundation
import GeoCore

extension OpenSea {
    /// The classes that only lie on land: a cell with one of them is land, whatever its neighbours are. Boundaries, names, piers, power
    /// lines and the like also lie over the sea, so they say nothing.
    static let landClasses: Set<UInt8> = [
        FeatureClass.path, .track, .roadMajor, .roadMinor, .railway, .waterLine, .waterArea, .forest, .landcover, .landuseUrban, .building,
        .peak, .piste, .tree, .barrier, .transportStop, .roadPoint, .address, .pavement, .cliff, .roadArea, .roadService, .militaryArea,
        .glacier, .bareGround, .wetland, .sand, .landUse,
    ].reduce(into: Set<UInt8>()) { $0.insert($1.rawValue) }

    /// Whether a cell holds a feature that lies only on land, in any band of the file.
    static func hasLandFeatures(_ file: FeatureStoreFile, cell: TileID) throws -> Bool {
        for band in file.bands where !(try file.features(in: cell, band: band, classes: landClasses).isEmpty) { return true }
        return false
    }

    /// Whether a block holds a feature of land anywhere; stops at the first.
    static func hasLandFeatures(in file: FeatureStoreFile) throws -> Bool {
        for cell in try file.cells() where try hasLandFeatures(file, cell: cell) { return true }
        return false
    }

    /// What is in a cell, as far as the sea is concerned.
    private enum CellKind { case square, empty, other }

    /// Gives the sea to the empty cells of the blocks that have a coast (question 62).
    ///
    /// A block with islands in open sea (the Røst archipelago off Lofoten) has coastlines, so ``fill(manifest:folder:covered:outside:now:persist:)``
    /// takes it for known and leaves it alone, but the cells between the islands hold no coastline and so get no sea: they stay
    /// background. A cell with no coastline, no sea and nothing that lies only on land, next to a cell that is a sea square (here, or across
    /// the border in the next block) is sea too: a coastline between them would have been cut into both. This spreads from the squares
    /// through such cells, and stops at any cell with a coast, a part of the sea, or a feature of land.
    ///
    /// Run it after ``fill(manifest:folder:covered:outside:now:persist:)``, so that the blocks of open sea next to a coast are sea squares
    /// that it can start from. It repeats until nothing changes, looking again only at the blocks next to the ones that changed.
    ///
    /// - Parameters:
    ///   - manifest: The manifest.
    ///   - folder: The folder of the manifest.
    ///   - now: The time recorded for the blocks that are written.
    ///   - persist: Called with the manifest after each block is written. The default does nothing.
    /// - Returns: The manifest, and for each block that was written the number of cells that got sea. The files are already written.
    /// - Throws: `FeatureStoreError` for a block that cannot be read, the errors of `persist` and the file errors.
    public static func fillEmptyCells(
        manifest: StoreManifest, folder: URL, now: Date = Date(), persist: (StoreManifest) throws -> Void = { _ in }
    ) throws -> (manifest: StoreManifest, cellsFilled: [Position: Int]) {
        var result = manifest
        var filled: [Position: Int] = [:]
        guard manifest.profile == "full" else { return (result, filled) }
        let bands = manifest.bands.compactMap { ZoomBand(rawValue: UInt8($0)) }
        var byPosition = Dictionary(uniqueKeysWithValues: manifest.blocks.map { (Position(x: $0.x, y: $0.y), $0) })
        var toLook = Set(byPosition.keys)
        var pass = 0
        while !toLook.isEmpty, pass < 20 {
            pass += 1
            var changed = Set<Position>()
            for position in toLook.sorted() {
                try Task.checkCancellation()
                guard let block = byPosition[position] else { continue }
                let file = try FeatureStoreFile(contentsOf: folder.appendingPathComponent(block.file))
                let seeds = try seedsFromNeighbours(of: position, blocks: byPosition, folder: folder, manifest: manifest)
                guard let cells = try emptyCellsToFill(in: file, position: position, manifest: manifest, extraSeeds: seeds), !cells.isEmpty else { continue }
                let data = try rewrite(file, adding: position, manifest: manifest, bands: bands, cells: { cells.contains($0) })
                let written = try write(data, to: block.file, folder: folder, replacing: block, now: now)
                byPosition[position] = written
                result.blocks = byPosition.values.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
                try persist(result)
                filled[position, default: 0] += cells.count
                changed.insert(position)
            }
            toLook = []
            for position in changed {
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let next = Position(x: position.x + dx, y: position.y + dy)
                    if byPosition[next] != nil { toLook.insert(next) }
                }
            }
        }
        return (result, filled)
    }

    /// The cells at the edge of a block that touch a sea square of the block next to it: places the sea can spread in from.
    private static func seedsFromNeighbours(
        of position: Position, blocks: [Position: StoreManifest.Block], folder: URL, manifest: StoreManifest
    ) throws -> Set<TileID> {
        var seeds = Set<TileID>()
        let own = cellRange(of: position, manifest: (manifest.blockZoom, manifest.storageZoom))
        for (dx, dy, side) in [(-1, 0, Side.east), (1, 0, .west), (0, -1, .south), (0, 1, .north)] {
            let next = Position(x: position.x + dx, y: position.y + dy)
            guard let block = blocks[next] else { continue }
            let file = try FeatureStoreFile(contentsOf: folder.appendingPathComponent(block.file))
            let range = cellRange(of: next, manifest: (manifest.blockZoom, file.storageZoom))
            let band = lookBand(of: file)
            // The cells of the neighbour along the shared edge, and the cell of this block each one touches.
            let pairs: [((Int, Int), (Int, Int))]
            switch side {
            case .east: pairs = range.rows.map { ((range.columns.upperBound - 1, $0), (own.columns.lowerBound, $0)) }
            case .west: pairs = range.rows.map { ((range.columns.lowerBound, $0), (own.columns.upperBound - 1, $0)) }
            case .south: pairs = range.columns.map { (($0, range.rows.upperBound - 1), ($0, own.rows.lowerBound)) }
            case .north: pairs = range.columns.map { (($0, range.rows.lowerBound), ($0, own.rows.upperBound - 1)) }
            }
            for (theirs, mine) in pairs {
                guard let theirCell = TileID(zoom: file.storageZoom, x: theirs.0, y: theirs.1),
                    let myCell = TileID(zoom: manifest.storageZoom, x: mine.0, y: mine.1)
                else { continue }
                let sea = try file.features(in: theirCell, band: band, classes: [FeatureClass.sea.rawValue])
                if isSquare(sea, of: theirCell) { seeds.insert(myCell) }
            }
        }
        return seeds
    }

    /// The empty cells of a block that the sea spreads to, or `nil` when the block has no coast (those are the business of the block rule).
    private static func emptyCellsToFill(
        in file: FeatureStoreFile, position: Position, manifest: StoreManifest, extraSeeds: Set<TileID>
    ) throws -> Set<TileID>? {
        let band = lookBand(of: file)
        let range = cellRange(of: position, manifest: (manifest.blockZoom, file.storageZoom))
        let withContent = Set(try file.cells())
        var kinds: [TileID: CellKind] = [:]
        var hasCoast = false
        for row in range.rows {
            for column in range.columns {
                guard let cell = TileID(zoom: file.storageZoom, x: column, y: row) else { continue }
                guard withContent.contains(cell) else { kinds[cell] = .empty; continue }
                let seaOrCoast = try file.features(in: cell, band: band, classes: [FeatureClass.sea.rawValue, FeatureClass.coastline.rawValue])
                if seaOrCoast.contains(where: { $0.classID == FeatureClass.coastline.rawValue }) { hasCoast = true }
                if !seaOrCoast.isEmpty {
                    let sea = seaOrCoast.filter { $0.classID == FeatureClass.sea.rawValue }
                    let onlySquare = seaOrCoast.count == sea.count && isSquare(sea, of: cell)
                    kinds[cell] = onlySquare ? .square : .other
                } else {
                    kinds[cell] = try hasLandFeatures(file, cell: cell) ? .other : .empty
                }
            }
        }
        guard hasCoast else { return nil }
        var queue = kinds.filter { $0.value == .square }.map(\.key)
        for cell in extraSeeds where kinds[cell] == .empty { queue.append(cell) }
        var fill = Set<TileID>()
        for cell in extraSeeds where kinds[cell] == .empty { fill.insert(cell) }
        while let cell = queue.popLast() {
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                guard let next = TileID(zoom: cell.zoom, x: cell.x + dx, y: cell.y + dy), kinds[next] == .empty, fill.insert(next).inserted
                else { continue }
                queue.append(next)
            }
        }
        return fill
    }
}
