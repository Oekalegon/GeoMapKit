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
/// - A group is **sea** if at least one block next to it has a border of cells that are all sea squares, and no block next to it has
///   a border that shows land (no sea in any of its cells) or a mixture.
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
        /// The part of those where the neighbours disagreed (some showed sea and some land, or a border was mixed).
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
    /// cannot be told from one without).
    ///
    /// - Parameters:
    ///   - manifest: The manifest; it is not changed here.
    ///   - folder: The folder of the manifest.
    ///   - covered: The blocks that a source file covers at least in part, with the source files each was built from. A block that is
    ///     not here (no data at all) is never changed.
    /// - Returns: The manifest with the new and rewritten blocks, and what was done. The files are already written.
    /// - Throws: `FeatureStoreError` for a block that cannot be read, and the file errors.
    public static func fill(
        manifest: StoreManifest, folder: URL, covered: [Position: [StoreManifest.Source]]
    ) throws -> (manifest: StoreManifest, report: Report) {
        var report = Report()
        guard manifest.profile == "full" else { return (manifest, report) }
        let blocks = Dictionary(uniqueKeysWithValues: manifest.blocks.map { (Position(x: $0.x, y: $0.y), $0) })

        // Which blocks are known: they have a coastline or sea of their own. The others that are covered are the candidates.
        var files: [Position: FeatureStoreFile] = [:]
        var candidates = Set<Position>()
        for position in covered.keys {
            try Task.checkCancellation()
            guard let block = blocks[position] else { candidates.insert(position); continue }
            let file = try FeatureStoreFile(contentsOf: folder.appendingPathComponent(block.file))
            files[position] = file
            let found = try scan(file)
            if !found.hasSea && !found.hasCoastline { candidates.insert(position) }
        }
        // Blocks outside the run that have sea or a coastline are evidence too.
        var known: [Position: FeatureStoreFile] = [:]
        for (position, block) in blocks where !candidates.contains(position) {
            if let file = files[position] { known[position] = file; continue }
            try Task.checkCancellation()
            let file = try FeatureStoreFile(contentsOf: folder.appendingPathComponent(block.file))
            let found = try scan(file)
            if found.hasSea || found.hasCoastline { known[position] = file }
        }

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
                for (dx, dy, side) in [(-1, 0, Side.east), (1, 0, .west), (0, -1, .south), (0, 1, .north)] {
                    let next = Position(x: position.x + dx, y: position.y + dy)
                    if candidates.contains(next) {
                        if seen.insert(next).inserted { queue.append(next) }
                    } else if let file = known[next] {
                        verdicts.insert(try border(of: file, side: side, position: next, blockZoom: manifest.blockZoom))
                    }
                }
            }
            if verdicts == [.sea] {
                sea.append(contentsOf: group)
            } else {
                report.left.append(contentsOf: group)
                if verdicts.contains(.sea) { report.conflicting.append(contentsOf: group) }
            }
        }
        report.left.sort()
        report.conflicting.sort()

        // Write the sea blocks.
        var result = manifest
        var byPosition = blocks
        let bands = manifest.bands.compactMap { ZoomBand(rawValue: UInt8($0)) }
        for position in sea.sorted() {
            try Task.checkCancellation()
            let block: StoreManifest.Block
            if let existing = blocks[position], let file = files[position] ?? (try? FeatureStoreFile(contentsOf: folder.appendingPathComponent(existing.file))) {
                let data = try rewrite(file, adding: position, manifest: manifest, bands: bands)
                block = try write(data, to: existing.file, folder: folder, replacing: existing)
                report.extended.append(position)
            } else {
                let name = "blocks/\(manifest.blockZoom)-\(position.x)-\(position.y).gmk"
                let data = try seaOnly(position, manifest: manifest, bands: bands)
                block = try write(
                    data, to: name, folder: folder,
                    replacing: StoreManifest.Block(x: position.x, y: position.y, file: name, bytes: 0, builtAt: Date(), sources: covered[position] ?? []))
                report.created.append(position)
            }
            byPosition[position] = block
        }
        result.blocks = byPosition.values.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        return (result, report)
    }

    // MARK: Looking at blocks

    private enum Side { case west, east, north, south }
    private enum Border { case sea, land, unclear }

    /// The cells of a block at the storage zoom.
    private static func cellRange(of position: Position, manifest zoom: (block: Int, storage: Int)) -> (columns: Range<Int>, rows: Range<Int>) {
        let shift = zoom.storage - zoom.block
        return ((position.x << shift)..<((position.x + 1) << shift), (position.y << shift)..<((position.y + 1) << shift))
    }

    private static let storageZoom = FeatureStoreBuilder.storageZoom

    private static func scan(_ file: FeatureStoreFile) throws -> (hasSea: Bool, hasCoastline: Bool) {
        let band: ZoomBand = file.bands.contains(.overview) ? .overview : (file.bands.first ?? .overview)
        let classes: Set<UInt8> = [FeatureClass.sea.rawValue, FeatureClass.coastline.rawValue]
        var hasSea = false, hasCoastline = false
        for cell in try file.cells() {
            for feature in try file.features(in: cell, band: band, classes: classes) {
                if feature.classID == FeatureClass.sea.rawValue { hasSea = true } else { hasCoastline = true }
            }
            if hasSea && hasCoastline { break }
        }
        return (hasSea, hasCoastline)
    }

    /// What the cells along one edge of a known block say: all sea squares, no sea at all, or neither.
    private static func border(of file: FeatureStoreFile, side: Side, position: Position, blockZoom: Int) throws -> Border {
        let range = cellRange(of: position, manifest: (blockZoom, storageZoom))
        let cells: [(Int, Int)]
        switch side {
        case .west: cells = range.rows.map { (range.columns.lowerBound, $0) }
        case .east: cells = range.rows.map { (range.columns.upperBound - 1, $0) }
        case .north: cells = range.columns.map { ($0, range.rows.lowerBound) }
        case .south: cells = range.columns.map { ($0, range.rows.upperBound - 1) }
        }
        let band: ZoomBand = file.bands.contains(.overview) ? .overview : (file.bands.first ?? .overview)
        var squares = 0, empty = 0
        for (x, y) in cells {
            guard let cell = TileID(zoom: storageZoom, x: x, y: y) else { return .unclear }
            let found = try file.features(in: cell, band: band, classes: [FeatureClass.sea.rawValue])
            if found.isEmpty { empty += 1 } else if isSquare(found, of: cell) { squares += 1 } else { return .unclear }
        }
        if squares == cells.count { return .sea }
        if empty == cells.count { return .land }
        return .unclear
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

    private static func write(_ data: Data, to name: String, folder: URL, replacing old: StoreManifest.Block) throws -> StoreManifest.Block {
        try FeatureStoreFile(data: data).verify()
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        var block = old
        block.bytes = Int64(data.count)
        block.builtAt = Date()
        return block
    }
}
