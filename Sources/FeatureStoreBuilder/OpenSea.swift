import FeatureStore
import Foundation
import GeoCore

/// Gives the blocks of open sea their sea (question 53).
///
/// ``FeatureStoreBuilder`` builds the sea from the coastlines in a block's own cut, so a block that no coastline comes near (open sea
/// far from any coast) gets no `sea` feature, and a block with nothing at all gets no file. The map then has rectangular holes in
/// the sea. Nothing in such a block says that it is sea, but its neighbours do: a connected group of blocks with no coastline and no
/// sea is all sea or all land (a coastline would have been in the cut of at least one of them, the margin of the cut reaches into
/// the next block), and the cells that the group shares a border with show which.
///
/// - A group is **sea** if at least one block next to it has a border with a cell that is a sea square (a cell with no coastline in
///   it that is wholly sea: the cell across the border can only be sea, since there is no coastline in the group), and no block next
///   to it has a border that shows land (a cell with no sea at all) or contradicts itself (sea squares and cells with no sea on the
///   same border). Cells that are only partly sea are neither: a coast near the border is normal, in an archipelago on every border,
///   and says nothing about the group.
/// - A group that touches only land, only blocks that are not covered by a source file, or nothing, is left as it is: the data
///   there is land without a coastline, or unknown, and unknown must stay empty.
///
/// A sea block is written as the cell square of class `sea` in every cell and every band of the manifest (the reader picks the band
/// from the manifest, not from the file, so a file with only the overview band would show nothing at a high zoom). A sparse block
/// that already has a file (borders, sea limits) is written again with the sea added.
public enum OpenSea {
    /// A block of the grid.
    public struct Position: Hashable, Sendable, Comparable {
        /// The column at the block zoom.
        public var x: Int
        /// The row at the block zoom.
        public var y: Int

        /// Creates a position.
        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }

        /// Orders by row, then column.
        public static func < (lhs: Position, rhs: Position) -> Bool { (lhs.y, lhs.x) < (rhs.y, rhs.x) }
    }

    /// What the pass did.
    public struct Report: Sendable, Equatable {
        /// Blocks that had no file and were written as sea.
        public var created: [Position] = []
        /// Blocks that had a file without sea and were written again with the sea.
        public var extended: [Position] = []
        /// Blocks without a coastline and without sea that were not changed, because no neighbour showed that they are sea: land, or
        /// nothing known.
        public var left: [Position] = []
        /// The part of those that touch sea but whose neighbours also showed land or a mixed border (a coastline that was not joined,
        /// or one with no node in the cut). Groups that only touch land, or borders with no evidence, are in `left` only.
        public var conflicting: [Position] = []

        /// Creates a report.
        public init(created: [Position] = [], extended: [Position] = [], left: [Position] = [], conflicting: [Position] = []) {
            self.created = created
            self.extended = extended
            self.left = left
            self.conflicting = conflicting
        }

        /// Whether any block was changed.
        public var changed: Bool { !created.isEmpty || !extended.isEmpty }
    }

    /// Fills the open sea of a block set.
    ///
    /// Only a manifest of the `full` profile is looked at (the Watch profile has no coastline class, so a block with a coastline
    /// cannot be told from one without). Block files are opened one at a time and not kept, so the number of mappings stays small
    /// for a set of thousands of blocks.
    ///
    /// - Parameters:
    ///   - manifest: The manifest; it is not changed here.
    ///   - folder: The folder of the manifest.
    ///   - covered: The blocks that a source file covers at least in part, with the source files each was built from. A block that is
    ///     not here (no data at all) is never changed.
    ///   - now: The time recorded for the blocks that are written.
    ///   - persist: Called with the manifest after each block is written, so that the manifest on disk always matches the files (a
    ///     run that stops half way leaves a set that opens). The default does nothing.
    /// - Returns: The manifest with the new and rewritten blocks, and what was done. The files are already written.
    /// - Throws: `FeatureStoreError` for a block that cannot be read (a block that cannot be read is never replaced), the errors of
    ///   `persist` and the file errors.
    public static func fill(
        manifest: StoreManifest, folder: URL, covered: [Position: [StoreManifest.Source]], now: Date = Date(),
        persist: (StoreManifest) throws -> Void = { _ in }
    ) throws -> (manifest: StoreManifest, report: Report) {
        var report = Report()
        guard manifest.profile == "full" else { return (manifest, report) }
        let blocks = Dictionary(uniqueKeysWithValues: manifest.blocks.map { (Position(x: $0.x, y: $0.y), $0) })
        func open(_ block: StoreManifest.Block) throws -> FeatureStoreFile {
            try FeatureStoreFile(contentsOf: folder.appendingPathComponent(block.file))
        }

        // Which blocks are known: they have a coastline or sea of their own. The others that are covered are the candidates. Blocks
        // outside the run that have sea or a coastline are evidence too.
        var candidates = Set<Position>()
        var known = Set<Position>()
        for (position, block) in blocks.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            if try hasSeaOrCoastline(try open(block)) { known.insert(position) } else if covered[position] != nil { candidates.insert(position) }
        }
        for position in covered.keys where blocks[position] == nil { candidates.insert(position) }

        // Connected groups of candidates, and what their neighbours say.
        var seen = Set<Position>()
        var sea: [Position] = []
        for start in candidates.sorted() where !seen.contains(start) {
            var group: [Position] = []
            var queue = [start]
            seen.insert(start)
            var verdicts = Set<Border>()
            while let position = queue.popLast() {
                group.append(position)
                // The edge to look at is the one of the neighbour that faces this block: a neighbour to the west shows its east edge.
                for (dx, dy, side) in [(-1, 0, Side.east), (1, 0, .west), (0, -1, .south), (0, 1, .north)] {
                    let next = Position(x: position.x + dx, y: position.y + dy)
                    if candidates.contains(next) {
                        if seen.insert(next).inserted { queue.append(next) }
                    } else if known.contains(next), let block = blocks[next] {
                        verdicts.insert(try border(of: try open(block), side: side, position: next, blockZoom: manifest.blockZoom))
                    }
                }
            }
            if verdicts.contains(.sea), !verdicts.contains(.land), !verdicts.contains(.conflict) {
                sea.append(contentsOf: group)
            } else {
                report.left.append(contentsOf: group)
                if verdicts.contains(.sea) || verdicts.contains(.conflict) { report.conflicting.append(contentsOf: group) }
            }
        }
        report.left.sort()
        report.conflicting.sort()

        // Write the sea blocks, and the manifest after each.
        var result = manifest
        var byPosition = blocks
        let bands = manifest.bands.compactMap { ZoomBand(rawValue: UInt8($0)) }
        for position in sea.sorted() {
            try Task.checkCancellation()
            let block: StoreManifest.Block
            if let existing = blocks[position] {
                let data = try rewrite(try open(existing), adding: position, manifest: manifest, bands: bands)
                block = try write(data, to: existing.file, folder: folder, replacing: existing, now: now)
                report.extended.append(position)
            } else {
                let name = "blocks/\(manifest.blockZoom)-\(position.x)-\(position.y).gmk"
                let data = try seaOnly(position, manifest: manifest, bands: bands)
                block = try write(
                    data, to: name, folder: folder,
                    replacing: StoreManifest.Block(x: position.x, y: position.y, file: name, bytes: 0, builtAt: now, sources: covered[position] ?? []),
                    now: now)
                report.created.append(position)
            }
            byPosition[position] = block
            result.blocks = byPosition.values.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            try persist(result)
        }
        return (result, report)
    }

    // MARK: Looking at blocks

    private enum Side { case west, east, north, south }
    /// What the cells along a border say about the group: `sea` (a sea square, and no cell without sea), `land` (a cell without sea, and
    /// no sea square), `conflict` (both), or `none` (only cells that are partly sea).
    private enum Border { case sea, land, conflict, none }

    /// The cells of a block at the storage zoom.
    private static func cellRange(of position: Position, manifest zoom: (block: Int, storage: Int)) -> (columns: Range<Int>, rows: Range<Int>) {
        let shift = zoom.storage - zoom.block
        return ((position.x << shift)..<((position.x + 1) << shift), (position.y << shift)..<((position.y + 1) << shift))
    }

    /// The band to look at in a file: the overview band, or the lowest one it has.
    private static func lookBand(of file: FeatureStoreFile) -> ZoomBand {
        file.bands.contains(.overview) ? .overview : (file.bands.first ?? .overview)
    }

    /// Whether the file has a `sea` or a `coastline` feature anywhere; stops at the first.
    private static func hasSeaOrCoastline(_ file: FeatureStoreFile) throws -> Bool {
        let band = lookBand(of: file)
        let classes: Set<UInt8> = [FeatureClass.sea.rawValue, FeatureClass.coastline.rawValue]
        for cell in try file.cells() where !(try file.features(in: cell, band: band, classes: classes)).isEmpty { return true }
        return false
    }

    /// What the cells along one edge of a known block say about the block next to it.
    private static func border(of file: FeatureStoreFile, side: Side, position: Position, blockZoom: Int) throws -> Border {
        let range = cellRange(of: position, manifest: (blockZoom, file.storageZoom))
        let cells: [(Int, Int)]
        switch side {
        case .west: cells = range.rows.map { (range.columns.lowerBound, $0) }
        case .east: cells = range.rows.map { (range.columns.upperBound - 1, $0) }
        case .north: cells = range.columns.map { ($0, range.rows.lowerBound) }
        case .south: cells = range.columns.map { ($0, range.rows.upperBound - 1) }
        }
        let band = lookBand(of: file)
        var squares = 0, empty = 0
        for (x, y) in cells {
            guard let cell = TileID(zoom: file.storageZoom, x: x, y: y) else { return .conflict }
            let found = try file.features(in: cell, band: band, classes: [FeatureClass.sea.rawValue])
            if found.isEmpty { empty += 1 } else if isSquare(found, of: cell) { squares += 1 }
        }
        switch (squares > 0, empty > 0) {
        case (true, false): return .sea
        case (false, true): return .land
        case (true, true): return .conflict
        case (false, false): return .none
        }
    }

    /// Whether the sea of a cell is the cell square and nothing else.
    private static func isSquare(_ features: [StoredFeature], of cell: TileID) -> Bool {
        guard features.count == 1, features[0].parts.count == 1 else { return false }
        let rect = CellRect(tile: cell)
        var corners = Set<[Int32]>()
        for point in features[0].parts[0].points {
            guard point.longitude == rect.west || point.longitude == rect.east, point.latitude == rect.south || point.latitude == rect.north
            else { return false }
            corners.insert([point.longitude, point.latitude])
        }
        return corners.count == 4
    }

    // MARK: Writing

    private static func seaFeature(for cell: TileID) -> StoredFeature {
        StoredFeature(
            classID: FeatureClass.sea.rawValue, subclass: 0, kind: .area, objectType: .way, objectID: 0, flags: [], offsetAlongLine: 0,
            nameID: nil, tags: [], parts: [SeaBuilder.wholeCell(CellRect(tile: cell))])
    }

    private static func addSea(
        to writer: inout FeatureStoreWriter, position: Position, manifest: StoreManifest, bands: [ZoomBand]
    ) throws {
        let range = cellRange(of: position, manifest: (manifest.blockZoom, manifest.storageZoom))
        for row in range.rows {
            for column in range.columns {
                guard let cell = TileID(zoom: manifest.storageZoom, x: column, y: row) else { continue }
                let feature = seaFeature(for: cell)
                for band in bands { try writer.add(feature, band: band, cell: cell) }
            }
        }
    }

    private static func box(of position: Position, blockZoom: Int) throws -> BoundingBox {
        guard let tile = TileID(zoom: blockZoom, x: position.x, y: position.y) else { throw FeatureStoreError.invalidInput("block outside the grid") }
        return FeatureStoreBuilder.cellAlignedBox(
            covering: BoundingBox(
                south: tile.southEast.latitude, west: tile.northWest.longitude, north: tile.northWest.latitude, east: tile.southEast.longitude))
    }

    private static func seaOnly(_ position: Position, manifest: StoreManifest, bands: [ZoomBand]) throws -> Data {
        var writer = FeatureStoreWriter(
            storageZoom: manifest.storageZoom, boundingBox: try box(of: position, blockZoom: manifest.blockZoom),
            attribution: manifest.attribution, sourceDate: nil, classifierVersion: UInt16(manifest.classifierVersion))
        try addSea(to: &writer, position: position, manifest: manifest, bands: bands)
        return try writer.data()
    }

    /// The file written again with the sea of every cell added: features, names and relations are copied over to a new string table.
    private static func rewrite(_ file: FeatureStoreFile, adding position: Position, manifest: StoreManifest, bands: [ZoomBand]) throws -> Data {
        var writer = FeatureStoreWriter(
            storageZoom: file.storageZoom, boundingBox: file.boundingBox, attribution: file.attribution, sourceDate: file.sourceDate,
            classifierVersion: UInt16(file.classifierVersion))
        func string(_ id: UInt32) throws -> UInt32 {
            guard let bytes = file.stringBytes(at: id) else { throw FeatureStoreError.corrupt("string outside the table") }
            return writer.intern([UInt8](bytes))
        }
        for cell in try file.cells() {
            for band in file.bands {
                for var feature in try file.features(in: cell, band: band) {
                    feature.nameID = try feature.nameID.map(string)
                    feature.tags = try feature.tags.map { StoredTag(key: try string($0.key), value: try string($0.value)) }
                    try writer.add(feature, band: band, cell: cell)
                }
            }
        }
        for var relation in try file.relations() {
            relation.tags = try relation.tags.map { StoredTag(key: try string($0.key), value: try string($0.value)) }
            relation.members = try relation.members.map { StoredRelationMember(type: $0.type, id: $0.id, role: try string($0.role)) }
            try writer.add(relation)
        }
        try addSea(to: &writer, position: position, manifest: manifest, bands: bands)
        return try writer.data()
    }

    private static func write(_ data: Data, to name: String, folder: URL, replacing old: StoreManifest.Block, now: Date) throws -> StoreManifest.Block {
        try FeatureStoreFile(data: data).verify()
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        var block = old
        block.bytes = Int64(data.count)
        block.builtAt = now
        return block
    }
}
