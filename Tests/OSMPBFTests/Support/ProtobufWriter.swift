import Foundation

/// A minimal protobuf encoder for building test files.
///
/// This is written independently of the reader's decoding code, so a mistake in
/// one is unlikely to be mirrored in the other. It is still written from the
/// published PBF format, so it needs checking against a real OSM file too.
struct ProtobufWriter {
    private(set) var bytes: [UInt8] = []

    var data: Data { Data(bytes) }

    mutating func varint(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            bytes.append(UInt8(value & 0x7f) | 0x80)
            value >>= 7
        }
        bytes.append(UInt8(value))
    }

    static func zigZag(_ value: Int64) -> UInt64 {
        UInt64(bitPattern: (value << 1) ^ (value >> 63))
    }

    mutating func key(_ field: Int, wire: UInt8) {
        varint(UInt64(field << 3) | UInt64(wire))
    }

    mutating func uint(_ field: Int, _ value: UInt64) {
        key(field, wire: 0)
        varint(value)
    }

    mutating func int(_ field: Int, _ value: Int64) {
        uint(field, UInt64(bitPattern: value))
    }

    mutating func sint(_ field: Int, _ value: Int64) {
        uint(field, Self.zigZag(value))
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        key(field, wire: 2)
        varint(UInt64(value.count))
        bytes.append(contentsOf: value)
    }

    mutating func string(_ field: Int, _ value: String) {
        bytes(field, Data(value.utf8))
    }

    mutating func packed(_ field: Int, _ values: [UInt64]) {
        var inner = ProtobufWriter()
        values.forEach { inner.varint($0) }
        bytes(field, inner.data)
    }

    mutating func packedSInt(_ field: Int, _ values: [Int64]) {
        packed(field, values.map(Self.zigZag))
    }

    mutating func packedInt32(_ field: Int, _ values: [Int32]) {
        packed(field, values.map { UInt64(bitPattern: Int64($0)) })
    }

    static func delta(_ values: [Int64]) -> [Int64] {
        var previous: Int64 = 0
        return values.map { value in
            defer { previous = value }
            return value - previous
        }
    }
}
