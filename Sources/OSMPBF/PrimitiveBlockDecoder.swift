import Foundation
import GeoCore

/// Decodes the `PrimitiveBlock` message: a string table plus groups of nodes,
/// ways and relations.
///
/// Coordinates are stored as integers: degrees = (offset + granularity × value) / 1e9.
/// With the default granularity of 100 this is OSM's native 1e-7 degree resolution.
struct PrimitiveBlockDecoder {
    let strings: [String]
    let granularity: Int64
    let latitudeOffset: Int64
    let longitudeOffset: Int64

    /// Decodes a data block.
    ///
    /// - Parameter data: The decompressed `OSMData` payload.
    /// - Returns: The block's nodes, ways and relations.
    /// - Throws: ``PBFError`` if the block is malformed or inconsistent.
    static func decode(_ data: Data) throws -> OSMBlock {
        var reader = ProtobufReader(data)
        var strings: [String] = []
        var groups: [Data] = []
        var granularity: Int64 = 100
        var latitudeOffset: Int64 = 0
        var longitudeOffset: Int64 = 0
        while let (number, wireType) = try reader.readFieldKey() {
            switch (number, wireType) {
            case (1, .lengthDelimited): strings = try decodeStringTable(reader.readBytes())
            case (2, .lengthDelimited): groups.append(try reader.readBytes())
            case (17, .varint): granularity = Int64(try reader.readInt32())
            case (19, .varint): latitudeOffset = try reader.readInt64()
            case (20, .varint): longitudeOffset = try reader.readInt64()
            default: try reader.skip(wireType)
            }
        }
        guard granularity > 0 else { throw PBFError.malformed("granularity \(granularity)") }

        let decoder = PrimitiveBlockDecoder(
            strings: strings, granularity: granularity,
            latitudeOffset: latitudeOffset, longitudeOffset: longitudeOffset
        )
        var block = OSMBlock()
        for group in groups {
            try decoder.decodeGroup(group, into: &block)
        }
        return block
    }

    private static func decodeStringTable(_ data: Data) throws -> [String] {
        var reader = ProtobufReader(data)
        var strings: [String] = []
        while let (number, wireType) = try reader.readFieldKey() {
            if number == 1, wireType == .lengthDelimited {
                strings.append(try reader.readString())
            } else {
                try reader.skip(wireType)
            }
        }
        return strings
    }

    private func decodeGroup(_ data: Data, into block: inout OSMBlock) throws {
        var reader = ProtobufReader(data)
        while let (number, wireType) = try reader.readFieldKey() {
            switch (number, wireType) {
            case (1, .lengthDelimited): block.nodes.append(try decodeNode(reader.readBytes()))
            case (2, .lengthDelimited): try decodeDenseNodes(reader.readBytes(), into: &block.nodes)
            case (3, .lengthDelimited): block.ways.append(try decodeWay(reader.readBytes()))
            case (4, .lengthDelimited): block.relations.append(try decodeRelation(reader.readBytes()))
            default: try reader.skip(wireType)
            }
        }
    }

    // MARK: Shared helpers

    func string(at index: Int) throws -> String {
        guard strings.indices.contains(index) else { throw PBFError.invalidStringIndex(index) }
        return strings[index]
    }

    func string(at index: UInt64) throws -> String {
        guard index < UInt64(strings.count) else { throw PBFError.invalidStringIndex(Int(truncatingIfNeeded: index)) }
        return strings[Int(index)]
    }

    /// Builds a tag dictionary from parallel key and value index arrays.
    func tags(keys: [UInt64], values: [UInt64]) throws -> [String: String] {
        guard keys.count == values.count else {
            throw PBFError.inconsistentBlock("\(keys.count) tag keys but \(values.count) values")
        }
        var tags: [String: String] = [:]
        tags.reserveCapacity(keys.count)
        for (key, value) in zip(keys, values) {
            tags[try string(at: key)] = try string(at: value)
        }
        return tags
    }

    /// Converts a stored integer to degrees. Integer arithmetic wraps instead of
    /// trapping, so a hostile file cannot crash the reader.
    func latitude(_ value: Int64) -> Double {
        Double(latitudeOffset &+ granularity &* value) / 1e9
    }

    func longitude(_ value: Int64) -> Double {
        Double(longitudeOffset &+ granularity &* value) / 1e9
    }
}
