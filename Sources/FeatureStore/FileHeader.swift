import Foundation

/// The fixed-size header at the start of a feature store file.
///
/// All integers are little-endian. Layout (144 bytes):
/// magic `GMKM` (4), format version (2), flags (2, zero), classifier version (2),
/// storage zoom (1), band mask (1), cell count (4), bounding box west, south, east,
/// north as Int32 in 1e-7 degrees (16), source date in Unix seconds (8, 0 if
/// unknown), file length (8), then six sections as (offset, length) pairs of
/// UInt64. The last four bytes of the file are a CRC-32 of everything before them.
struct FileHeader: Equatable {
    static let magic: [UInt8] = Array("GMKM".utf8)
    static let formatVersion: UInt16 = 1
    static let size = 144
    static let trailerSize = 4

    enum Section: Int, CaseIterable {
        case cellIndex, cells, stringOffsets, stringBytes, relations, attribution
    }

    var classifierVersion: UInt16
    var storageZoom: UInt8
    var bandMask: UInt8
    var cellCount: UInt32
    var west: Int32
    var south: Int32
    var east: Int32
    var north: Int32
    var sourceDate: Int64
    var fileLength: UInt64
    var sections: [Range<UInt64>]

    func encoded() -> [UInt8] {
        var writer = ByteWriter()
        writer.writeBytes(Self.magic)
        writer.writeUInt16(Self.formatVersion)
        writer.writeUInt16(0)
        writer.writeUInt16(classifierVersion)
        writer.writeUInt8(storageZoom)
        writer.writeUInt8(bandMask)
        writer.writeUInt32(cellCount)
        for value in [west, south, east, north] { writer.writeInt32(value) }
        writer.writeUInt64(UInt64(bitPattern: sourceDate))
        writer.writeUInt64(fileLength)
        for section in sections {
            writer.writeUInt64(section.lowerBound)
            writer.writeUInt64(section.upperBound - section.lowerBound)
        }
        return writer.bytes
    }

    /// Parses and validates the header of `data`.
    static func parse(_ data: Data) throws -> FileHeader {
        guard data.count >= size + trailerSize else {
            // Distinguish "not our file" from "our file, cut short".
            if data.count >= magic.count, Array(data.prefix(magic.count)) != magic { throw FeatureStoreError.badMagic }
            throw FeatureStoreError.truncated
        }
        var cursor = ByteCursor(data, range: 0..<size)
        guard Array(data.prefix(4)) == magic else { throw FeatureStoreError.badMagic }
        _ = try cursor.skip(4)
        let version = try cursor.readUInt16()
        guard version == formatVersion else { throw FeatureStoreError.unsupportedVersion(Int(version)) }
        guard try cursor.readUInt16() == 0 else { throw FeatureStoreError.corrupt("unknown header flags") }
        let classifierVersion = try cursor.readUInt16()
        let zoom = try cursor.readUInt8()
        guard zoom <= 30 else { throw FeatureStoreError.corrupt("storage zoom \(zoom)") }
        let bandMask = try cursor.readUInt8()
        guard bandMask & ~0b111 == 0 else { throw FeatureStoreError.corrupt("band mask") }
        let cellCount = try cursor.readUInt32()
        let west = try cursor.readInt32(), south = try cursor.readInt32()
        let east = try cursor.readInt32(), north = try cursor.readInt32()
        let sourceDate = Int64(bitPattern: try cursor.readUInt64())
        let fileLength = try cursor.readUInt64()
        guard fileLength == UInt64(data.count) else {
            throw fileLength > UInt64(data.count) ? FeatureStoreError.truncated : .corrupt("file longer than its header says")
        }
        var sections: [Range<UInt64>] = []
        let limit = fileLength - UInt64(trailerSize)
        for _ in Section.allCases {
            let offset = try cursor.readUInt64(), length = try cursor.readUInt64()
            let (end, overflow) = offset.addingReportingOverflow(length)
            guard !overflow, offset >= UInt64(size), end <= limit, offset % 8 == 0 else {
                throw FeatureStoreError.corrupt("section out of range")
            }
            sections.append(offset..<end)
        }
        return FileHeader(
            classifierVersion: classifierVersion, storageZoom: zoom, bandMask: bandMask, cellCount: cellCount,
            west: west, south: south, east: east, north: north, sourceDate: sourceDate,
            fileLength: fileLength, sections: sections)
    }

    func range(of section: Section) -> Range<Int> {
        let range = sections[section.rawValue]
        return Int(range.lowerBound)..<Int(range.upperBound)
    }
}
