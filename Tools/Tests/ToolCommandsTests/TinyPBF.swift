import Foundation

/// A tiny uncompressed PBF file for end-to-end tests of the commands.
///
/// This duplicates a few lines of the encoder in the library's own tests on purpose:
/// the two packages do not share test code. It writes raw (uncompressed) blobs only.
enum TinyPBF {
    private static func varint(_ value: UInt64) -> [UInt8] {
        var bytes: [UInt8] = []
        var value = value
        while value >= 0x80 { bytes.append(UInt8(value & 0x7f) | 0x80); value >>= 7 }
        bytes.append(UInt8(value))
        return bytes
    }

    private static func zigZag(_ value: Int64) -> UInt64 { UInt64(bitPattern: (value << 1) ^ (value >> 63)) }
    private static func field(_ number: Int, varint value: UInt64) -> [UInt8] { varint(UInt64(number << 3)) + varint(value) }
    private static func field(_ number: Int, bytes: [UInt8]) -> [UInt8] { varint(UInt64(number << 3 | 2)) + varint(UInt64(bytes.count)) + bytes }
    private static func packed(_ values: [UInt64]) -> [UInt8] { values.flatMap(varint) }

    private static func delta(_ values: [Int64]) -> [Int64] {
        var previous: Int64 = 0
        return values.map { value in defer { previous = value }; return value - previous }
    }

    private static func blob(type: String, payload: [UInt8]) -> [UInt8] {
        let blobMessage = field(1, bytes: payload)                                       // raw
        let header = field(1, bytes: Array(type.utf8)) + field(3, varint: UInt64(blobMessage.count))
        let length = UInt32(header.count).bigEndian
        return withUnsafeBytes(of: length) { Array($0) } + header + blobMessage
    }

    /// Nodes 1 and 2 are inside the box 47...48 x 9...10; node 3 is far outside.
    /// Way 10 joins nodes 1, 2 and 3 and so crosses the box edge; way 11 is far away.
    static func make() -> Data {
        let header = field(4, bytes: Array("OsmSchema-V0.6".utf8)) + field(4, bytes: Array("DenseNodes".utf8))
        let ids: [Int64] = [1, 2, 3, 4, 5]
        let latitudes: [Int64] = [475_000_000, 476_000_000, 300_000_000, 100_000_000, 100_100_000]
        let longitudes: [Int64] = [95_000_000, 96_000_000, 50_000_000, 20_000_000, 20_100_000]
        let dense = field(1, bytes: packed(delta(ids).map(zigZag)))
            + field(8, bytes: packed(delta(latitudes).map(zigZag)))
            + field(9, bytes: packed(delta(longitudes).map(zigZag)))
        let table = field(1, bytes: [])                                                  // index 0 is the empty string
        let nodeBlock = field(1, bytes: table) + field(2, bytes: field(2, bytes: dense))

        func way(_ id: UInt64, _ nodes: [Int64]) -> [UInt8] {
            field(1, varint: id) + field(8, bytes: packed(delta(nodes).map(zigZag)))
        }
        let ways = field(3, bytes: way(10, [1, 2, 3])) + field(3, bytes: way(11, [4, 5]))
        let wayBlock = field(1, bytes: table) + field(2, bytes: ways)

        return Data(blob(type: "OSMHeader", payload: header) + blob(type: "OSMData", payload: nodeBlock)
            + blob(type: "OSMData", payload: wayBlock))
    }
}
