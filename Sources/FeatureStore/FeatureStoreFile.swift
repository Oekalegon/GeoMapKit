import Foundation
import GeoCore

/// A read-only feature store file.
///
/// The file is memory-mapped. Opening checks only the header and the section
/// ranges, so it is cheap; lookups then touch just the pages they need. All reads
/// are bounds-checked and the file is treated as untrusted: damage produces a
/// ``FeatureStoreError``, never a crash. ``verify()`` checks the whole file (the
/// checksum and all structure) and is meant to run once after a transfer.
public struct FeatureStoreFile: Sendable {
    private let data: Data
    private let header: FileHeader
    private let stringCount: Int

    /// The format version of the file.
    public var formatVersion: Int { Int(FileHeader.formatVersion) }
    /// The version of the class table that produced the class IDs.
    public var classifierVersion: Int { Int(header.classifierVersion) }
    /// The zoom of the cells.
    public var storageZoom: Int { Int(header.storageZoom) }
    /// The number of cells in the file.
    public var cellCount: Int { Int(header.cellCount) }
    /// The area the file covers.
    public var boundingBox: BoundingBox {
        BoundingBox(
            south: Double(header.south) / 1e7, west: Double(header.west) / 1e7,
            north: Double(header.north) / 1e7, east: Double(header.east) / 1e7)
    }
    /// The date of the source data, if the writer recorded it.
    public var sourceDate: Date? { header.sourceDate == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(header.sourceDate)) }
    /// The bands that hold at least one feature.
    public var bands: [ZoomBand] { ZoomBand.allCases.filter { header.bandMask & (1 << $0.rawValue) != 0 } }
    /// The OSM attribution recorded in the file.
    public var attribution: String {
        String(decoding: data[header.range(of: .attribution)], as: UTF8.self)
    }
    /// The number of strings in the string table.
    public var stringTableCount: Int { stringCount }

    /// Opens a file by memory-mapping it.
    public init(contentsOf url: URL) throws {
        try self.init(data: try Data(contentsOf: url, options: .alwaysMapped))
    }

    /// Opens a file held in memory.
    public init(data: Data) throws {
        // Slices of other data keep their original indices; copy so ours start at zero.
        let normalized = data.startIndex == 0 ? data : Data(data)
        self.header = try FileHeader.parse(normalized)
        self.data = normalized
        let index = header.range(of: .cellIndex)
        guard index.count == Int(header.cellCount) * 24 else {
            throw FeatureStoreError.corrupt("cell index size")
        }
        let offsets = header.range(of: .stringOffsets)
        guard offsets.count % 4 == 0 else { throw FeatureStoreError.corrupt("string offsets size") }
        self.stringCount = max(offsets.count / 4 - 1, 0)
        let relations = header.range(of: .relations)
        guard relations.count >= 8 else { throw FeatureStoreError.corrupt("relation table size") }
    }

    // MARK: Cells

    /// Reads the features of one cell and band.
    ///
    /// - Parameters:
    ///   - cell: A cell at the file's storage zoom.
    ///   - band: The band to read; other bands are not decoded.
    ///   - classes: Only these classes are decoded; the others are skipped by length. `nil` reads all.
    /// - Returns: The features, or an empty array if the file has no such cell or band.
    public func features(in cell: TileID, band: ZoomBand, classes: Set<UInt8>? = nil) throws -> [StoredFeature] {
        guard cell.zoom == storageZoom, let block = try blockRange(of: cell) else { return [] }
        let layout = try CellCodec.layout(of: data, block: block)
        return try CellCodec.decodeBand(data: data, layout: layout, band: band, classes: classes, stringCount: stringCount)
    }

    /// Whether the file holds the cell.
    public func containsCell(_ cell: TileID) throws -> Bool {
        guard cell.zoom == storageZoom else { return false }
        return try blockRange(of: cell) != nil
    }

    /// All cells in the file, in index order. Reads the whole index.
    public func cells() throws -> [TileID] {
        try (0..<cellCount).map { position in
            let entry = try indexEntry(at: position)
            guard let tile = TileID(zoom: storageZoom, x: Int(entry.x), y: Int(entry.y)) else {
                throw FeatureStoreError.corrupt("cell outside the grid")
            }
            return tile
        }
    }

    // MARK: Strings

    /// The bytes of a string, or `nil` if the ID is out of range or the table is damaged.
    public func stringBytes(at id: UInt32) -> Data? {
        guard Int(id) < stringCount else { return nil }
        let offsets = header.range(of: .stringOffsets)
        let bytes = header.range(of: .stringBytes)
        var cursor = ByteCursor(data, range: (offsets.lowerBound + Int(id) * 4)..<offsets.upperBound)
        guard let start = try? cursor.readUInt32(), let end = try? cursor.readUInt32(),
            start <= end, Int(end) <= bytes.count
        else { return nil }
        return data[(bytes.lowerBound + Int(start))..<(bytes.lowerBound + Int(end))]
    }

    /// A string decoded as UTF-8 (invalid bytes become U+FFFD; use ``stringBytes(at:)`` for the exact bytes).
    public func string(at id: UInt32) -> String? {
        stringBytes(at: id).map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: Relations

    /// Looks up a relation by ID. O(log n).
    public func relation(withID id: Int64) throws -> StoredRelation? {
        let section = header.range(of: .relations)
        var head = ByteCursor(data, range: section)
        let count = Int(try head.readUInt32())
        _ = try head.readUInt32()
        guard count <= (section.count - 8) / 16 else { throw FeatureStoreError.corrupt("relation count") }
        var low = 0, high = count
        while low < high {
            let middle = (low + high) / 2
            let entry = try relationEntry(section: section, position: middle)
            if entry.id == id { return try decodeRelation(id: id, section: section, offset: entry.offset) }
            if entry.id < id { low = middle + 1 } else { high = middle }
        }
        return nil
    }

    // MARK: Verification

    /// Checks the checksum and the whole structure: index order and ranges, every cell and band, the string table and the relations.
    public func verify() throws {
        let body = 0..<(data.count - FileHeader.trailerSize)
        var trailer = ByteCursor(data, range: body.upperBound..<data.count)
        guard CRC32.checksum(data, range: body) == (try trailer.readUInt32()) else { throw FeatureStoreError.checksumMismatch }

        let cellsSection = header.range(of: .cells)
        var previous: (UInt32, UInt32)?
        var previousEnd = cellsSection.lowerBound
        for position in 0..<cellCount {
            let entry = try indexEntry(at: position)
            if let previous { guard previous < (entry.x, entry.y) else { throw FeatureStoreError.corrupt("cell index not sorted") } }
            previous = (entry.x, entry.y)
            let block = try checkedBlock(entry)
            guard block.lowerBound >= previousEnd else { throw FeatureStoreError.corrupt("cell blocks overlap") }
            previousEnd = block.upperBound
            let layout = try CellCodec.layout(of: data, block: block)
            for band in ZoomBand.allCases {
                _ = try CellCodec.decodeBand(data: data, layout: layout, band: band, classes: nil, stringCount: stringCount)
            }
        }

        let offsets = header.range(of: .stringOffsets)
        let bytesLength = header.range(of: .stringBytes).count
        var cursor = ByteCursor(data, range: offsets)
        var last: UInt32 = 0
        for _ in 0..<(offsets.count / 4) {
            let value = try cursor.readUInt32()
            guard value >= last, Int(value) <= bytesLength else { throw FeatureStoreError.corrupt("string offsets") }
            last = value
        }

        let section = header.range(of: .relations)
        var head = ByteCursor(data, range: section)
        let relationCount = Int(try head.readUInt32())
        _ = try head.readUInt32()
        guard relationCount <= (section.count - 8) / 16 else { throw FeatureStoreError.corrupt("relation count") }
        var previousID: Int64?
        for position in 0..<relationCount {
            let entry = try relationEntry(section: section, position: position)
            if let previousID { guard previousID < entry.id else { throw FeatureStoreError.corrupt("relations not sorted") } }
            previousID = entry.id
            _ = try decodeRelation(id: entry.id, section: section, offset: entry.offset)
        }
    }

    // MARK: Private

    private struct IndexEntry {
        let x: UInt32
        let y: UInt32
        let offset: UInt64
        let length: UInt32
    }

    private func indexEntry(at position: Int) throws -> IndexEntry {
        let index = header.range(of: .cellIndex)
        guard position >= 0, position < cellCount, (position + 1) * 24 <= index.count else {
            throw FeatureStoreError.corrupt("cell index entry")
        }
        var cursor = ByteCursor(data, range: (index.lowerBound + position * 24)..<index.upperBound)
        let x = try cursor.readUInt32(), y = try cursor.readUInt32()
        let offset = try cursor.readUInt64(), length = try cursor.readUInt32()
        return IndexEntry(x: x, y: y, offset: offset, length: length)
    }

    private func checkedBlock(_ entry: IndexEntry) throws -> Range<Int> {
        let section = header.range(of: .cells)
        let (end, overflow) = entry.offset.addingReportingOverflow(UInt64(entry.length))
        guard !overflow, entry.offset >= UInt64(section.lowerBound), end <= UInt64(section.upperBound) else {
            throw FeatureStoreError.corrupt("cell block out of range")
        }
        return Int(entry.offset)..<Int(end)
    }

    private func blockRange(of cell: TileID) throws -> Range<Int>? {
        let target = (UInt32(truncatingIfNeeded: cell.x), UInt32(truncatingIfNeeded: cell.y))
        var low = 0, high = cellCount
        while low < high {
            let middle = (low + high) / 2
            let entry = try indexEntry(at: middle)
            let key = (entry.x, entry.y)
            if key == target { return try checkedBlock(entry) }
            if key < target { low = middle + 1 } else { high = middle }
        }
        return nil
    }

    private func relationEntry(section: Range<Int>, position: Int) throws -> (id: Int64, offset: Int) {
        var cursor = ByteCursor(data, range: (section.lowerBound + 8 + position * 16)..<section.upperBound)
        let id = Int64(bitPattern: try cursor.readUInt64())
        let offset = try cursor.readUInt64()
        guard offset >= 8, offset < UInt64(section.count) else {
            throw FeatureStoreError.corrupt("relation offset")
        }
        return (id, Int(offset))
    }

    private func decodeRelation(id: Int64, section: Range<Int>, offset: Int) throws -> StoredRelation {
        var cursor = ByteCursor(data, range: (section.lowerBound + offset)..<section.upperBound)
        let flags = try cursor.readUInt8()
        guard flags & ~1 == 0 else { throw FeatureStoreError.corrupt("relation flags") }
        let tagCount = try cursor.readCount(limit: cursor.remaining / 2)
        var tags: [StoredTag] = []
        for _ in 0..<tagCount {
            let key = try cursor.readCount(limit: stringCount - 1), value = try cursor.readCount(limit: stringCount - 1)
            tags.append(StoredTag(key: UInt32(key), value: UInt32(value)))
        }
        let memberCount = try cursor.readCount(limit: cursor.remaining / 3)
        var members: [StoredRelationMember] = []
        for _ in 0..<memberCount {
            guard let type = StoredObjectType(rawValue: try cursor.readUInt8()) else { throw FeatureStoreError.corrupt("member type") }
            let memberID = try cursor.readZigzag()
            let role = try cursor.readCount(limit: stringCount - 1)
            members.append(StoredRelationMember(type: type, id: memberID, role: UInt32(role)))
        }
        return StoredRelation(id: id, isIncomplete: flags & 1 == 1, tags: tags, members: members)
    }
}
