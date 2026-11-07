import Foundation
import GeoCore

/// Builds a feature store file in memory and writes it.
///
/// Usage: intern strings with ``intern(_:)`` and use the returned IDs in features
/// and relations, add features per cell and band with ``add(_:band:cell:)``, then
/// call ``data()`` or ``write(to:)``. At the end the strings are renumbered by how
/// often they are used (common strings get one-byte IDs), and all IDs are
/// remapped, so the IDs seen while building are provisional. The output is
/// deterministic: the same input in any order gives the same bytes.
///
/// Strings are compared byte for byte, never with Swift `String` equality, so two
/// strings that differ only in Unicode normalization stay separate.
///
/// The writer holds everything in memory. It is meant for the phone or Mac, with
/// one writer per block of cells.
public struct FeatureStoreWriter: Sendable {
    /// The zoom at which cells are stored; every cell passed to ``add(_:band:cell:)`` must have it.
    public let storageZoom: Int
    public let boundingBox: BoundingBox
    public let attribution: String
    public let sourceDate: Date?
    public let classifierVersion: UInt16

    private var stringIDs: [[UInt8]: UInt32] = [:]
    private var strings: [[UInt8]] = []
    private var cells: [CellKey: [ZoomBand: [StoredFeature]]] = [:]
    private var relations: [Int64: StoredRelation] = [:]

    private struct CellKey: Hashable, Comparable {
        let x: UInt32
        let y: UInt32
        static func < (lhs: CellKey, rhs: CellKey) -> Bool { (lhs.x, lhs.y) < (rhs.x, rhs.y) }
    }

    /// Creates a writer.
    ///
    /// - Parameters:
    ///   - storageZoom: The cell zoom, 13 for the feature store.
    ///   - boundingBox: The area the file covers.
    ///   - attribution: The data credit, for example "© OpenStreetMap contributors, ODbL".
    ///   - sourceDate: The date of the source data, if known.
    ///   - classifierVersion: The version of the class table that produced the class IDs.
    public init(
        storageZoom: Int = 13, boundingBox: BoundingBox, attribution: String, sourceDate: Date? = nil,
        classifierVersion: UInt16 = 0
    ) {
        self.storageZoom = storageZoom
        self.boundingBox = boundingBox
        self.attribution = attribution
        self.sourceDate = sourceDate
        self.classifierVersion = classifierVersion
    }

    /// The number of cells that have at least one feature.
    public var cellCount: Int { cells.count }

    /// Returns the provisional ID of a string, adding it if new. Compared byte for byte.
    public mutating func intern(_ bytes: [UInt8]) -> UInt32 {
        if let existing = stringIDs[bytes] { return existing }
        let id = UInt32(strings.count)
        strings.append(bytes)
        stringIDs[bytes] = id
        return id
    }

    /// Returns the provisional ID of a string's UTF-8 bytes.
    public mutating func intern(_ string: String) -> UInt32 { intern(Array(string.utf8)) }

    /// Adds one piece of a feature to a cell and band.
    ///
    /// - Throws: ``FeatureStoreError/invalidInput(_:)`` if the cell has the wrong zoom, a string ID was not
    ///   created by this writer, or a value does not fit the format.
    public mutating func add(_ feature: StoredFeature, band: ZoomBand, cell: TileID) throws {
        let key = try cellKey(cell)
        try validate(feature)
        cells[key, default: [:]][band, default: []].append(feature)
    }

    /// Adds a relation (tags and members), stored once per file.
    ///
    /// - Throws: ``FeatureStoreError/invalidInput(_:)`` for a duplicate ID or an unknown string ID.
    public mutating func add(_ relation: StoredRelation) throws {
        guard relations[relation.id] == nil else { throw FeatureStoreError.invalidInput("duplicate relation \(relation.id)") }
        for tag in relation.tags { try checkString(tag.key); try checkString(tag.value) }
        for member in relation.members { try checkString(member.role) }
        relations[relation.id] = relation
    }

    /// Encodes the file.
    public func data() throws -> Data {
        // Renumber strings by use count, most used first, ties by first use.
        var uses = [Int](repeating: 0, count: strings.count)
        func count(_ id: UInt32) { uses[Int(id)] += 1 }
        for bands in cells.values {
            for features in bands.values {
                for feature in features {
                    if let name = feature.nameID { count(name) }
                    for tag in feature.tags { count(tag.key); count(tag.value) }
                }
            }
        }
        for relation in relations.values {
            for tag in relation.tags { count(tag.key); count(tag.value) }
            for member in relation.members { count(member.role) }
        }
        let order = (0..<strings.count).sorted { uses[$0] != uses[$1] ? uses[$0] > uses[$1] : $0 < $1 }
        var remap = [UInt32](repeating: 0, count: strings.count)
        for (newID, oldID) in order.enumerated() { remap[oldID] = UInt32(newID) }

        var file = ByteWriter()
        file.bytes.append(contentsOf: [UInt8](repeating: 0, count: FileHeader.size))

        // Cells.
        var index = ByteWriter()
        var blocks: [(key: CellKey, bytes: [UInt8])] = []
        for key in cells.keys.sorted() {
            let tile = try tileID(for: key)
            let origin = Self.origin(of: tile)
            var bands: [ZoomBand: [StoredFeature]] = [:]
            for (band, features) in cells[key] ?? [:] { bands[band] = features.map { remapped($0, remap) } }
            blocks.append((key, try CellCodec.encode(originLongitude: origin.longitude, originLatitude: origin.latitude, bands: bands, stringCount: strings.count)))
        }
        let indexStart = file.count
        let cellsStartOffset = indexStart + blocks.count * 24
        var offset = cellsStartOffset
        for block in blocks {
            // Blocks are padded to 8 bytes; the stored length is the unpadded length.
            index.writeUInt32(block.key.x)
            index.writeUInt32(block.key.y)
            index.writeUInt64(UInt64(offset))
            guard let length = UInt32(exactly: block.bytes.count) else { throw FeatureStoreError.invalidInput("cell too large") }
            index.writeUInt32(length)
            index.writeUInt32(0)
            offset += (block.bytes.count + 7) & ~7
        }
        file.writeBytes(index.bytes)
        for block in blocks {
            file.writeBytes(block.bytes)
            file.align(to: 8)
        }
        let cellsEnd = file.count

        // Strings.
        let stringOffsetsStart = file.count
        var stringBytes = ByteWriter()
        file.writeUInt32(0)
        for oldID in order {
            stringBytes.writeBytes(strings[oldID])
            guard let end = UInt32(exactly: stringBytes.count) else { throw FeatureStoreError.invalidInput("string table too large") }
            file.writeUInt32(end)
        }
        let stringOffsetsEnd = file.count
        file.align(to: 8)
        let stringBytesStart = file.count
        file.writeBytes(stringBytes.bytes)
        let stringBytesEnd = file.count
        file.align(to: 8)

        // Relations.
        let relationsStart = file.count
        let sortedRelations = relations.keys.sorted()
        var records = ByteWriter()
        var entries = ByteWriter()
        let recordsBase = 8 + sortedRelations.count * 16
        for id in sortedRelations {
            guard let relation = relations[id] else { continue }
            entries.writeUInt64(UInt64(bitPattern: id))
            entries.writeUInt64(UInt64(recordsBase + records.count))
            records.writeUInt8(relation.isIncomplete ? 1 : 0)
            records.writeVarint(UInt64(relation.tags.count))
            for tag in relation.tags {
                records.writeVarint(UInt64(remap[Int(tag.key)]))
                records.writeVarint(UInt64(remap[Int(tag.value)]))
            }
            records.writeVarint(UInt64(relation.members.count))
            for member in relation.members {
                records.writeUInt8(member.type.rawValue)
                records.writeZigzag(member.id)
                records.writeVarint(UInt64(remap[Int(member.role)]))
            }
        }
        file.writeUInt32(UInt32(sortedRelations.count))
        file.writeUInt32(0)
        file.writeBytes(entries.bytes)
        file.writeBytes(records.bytes)
        let relationsEnd = file.count
        file.align(to: 8)

        // Attribution.
        let attributionStart = file.count
        file.writeBytes(Array(attribution.utf8))
        let attributionEnd = file.count
        file.align(to: 8)

        let totalLength = file.count + FileHeader.trailerSize
        let sections: [Range<UInt64>] = [
            UInt64(indexStart)..<UInt64(indexStart + blocks.count * 24),
            UInt64(cellsStartOffset)..<UInt64(cellsEnd),
            UInt64(stringOffsetsStart)..<UInt64(stringOffsetsEnd),
            UInt64(stringBytesStart)..<UInt64(stringBytesEnd),
            UInt64(relationsStart)..<UInt64(relationsEnd),
            UInt64(attributionStart)..<UInt64(attributionEnd),
        ]
        guard let cellCount = UInt32(exactly: blocks.count) else { throw FeatureStoreError.invalidInput("too many cells") }
        let header = FileHeader(
            classifierVersion: classifierVersion, storageZoom: UInt8(storageZoom),
            bandMask: Self.bandMask(of: cells), cellCount: cellCount,
            west: Self.packed(boundingBox.west), south: Self.packed(boundingBox.south),
            east: Self.packed(boundingBox.east), north: Self.packed(boundingBox.north),
            sourceDate: Int64(sourceDate?.timeIntervalSince1970 ?? 0), fileLength: UInt64(totalLength),
            sections: sections)
        file.bytes.replaceSubrange(0..<FileHeader.size, with: header.encoded())
        file.writeUInt32(CRC32.checksum(file.bytes))
        return Data(file.bytes)
    }

    /// Encodes the file and writes it to `url`, replacing an existing file atomically.
    public func write(to url: URL) throws {
        try data().write(to: url, options: .atomic)
    }

    // MARK: Helpers

    private func remapped(_ feature: StoredFeature, _ remap: [UInt32]) -> StoredFeature {
        var copy = feature
        copy.nameID = feature.nameID.map { remap[Int($0)] }
        copy.tags = feature.tags.map { StoredTag(key: remap[Int($0.key)], value: remap[Int($0.value)]) }
        return copy
    }

    private func validate(_ feature: StoredFeature) throws {
        if let name = feature.nameID { try checkString(name) }
        for tag in feature.tags { try checkString(tag.key); try checkString(tag.value) }
    }

    private func checkString(_ id: UInt32) throws {
        guard Int(id) < strings.count else { throw FeatureStoreError.invalidInput("unknown string ID \(id)") }
    }

    private func cellKey(_ cell: TileID) throws -> CellKey {
        guard cell.zoom == storageZoom else { throw FeatureStoreError.invalidInput("cell zoom \(cell.zoom) is not \(storageZoom)") }
        return CellKey(x: UInt32(cell.x), y: UInt32(cell.y))
    }

    private func tileID(for key: CellKey) throws -> TileID {
        guard let tile = TileID(zoom: storageZoom, x: Int(key.x), y: Int(key.y)) else {
            throw FeatureStoreError.invalidInput("cell outside the grid")
        }
        return tile
    }

    private static func origin(of tile: TileID) -> PackedPoint {
        let corner = tile.northWest
        return PackedPoint(longitude: packed(corner.longitude), latitude: packed(corner.latitude))
    }

    private static func packed(_ degrees: Double) -> Int32 {
        guard degrees.isFinite else { return 0 }
        return Int32(max(-1_800_000_000, min(1_800_000_000, (degrees * 1e7).rounded())))
    }

    private static func bandMask(of cells: [CellKey: [ZoomBand: [StoredFeature]]]) -> UInt8 {
        var mask: UInt8 = 0
        for bands in cells.values { for (band, features) in bands where !features.isEmpty { mask |= 1 << band.rawValue } }
        return mask
    }
}
