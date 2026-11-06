import Foundation

/// A bounds-checked reader for the protobuf wire format.
///
/// Every read verifies that enough bytes remain, so malformed or truncated
/// input throws ``PBFError`` and never reads outside the data.
struct ProtobufReader {
    private let data: Data
    private var position: Int
    private let end: Int

    init(_ data: Data) {
        self.data = data
        self.position = data.startIndex
        self.end = data.endIndex
    }

    var isAtEnd: Bool { position >= end }

    /// Reads a variable-length integer (up to 64 bits).
    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard position < end else { throw PBFError.truncated }
            let byte = data[position]
            position += 1
            // The tenth byte may only carry the top bit.
            if shift == 63 && byte > 1 { throw PBFError.invalidVarint }
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
    }

    /// Reads the next field key, or returns `nil` at the end of the data.
    mutating func readFieldKey() throws -> (number: Int, wireType: WireType)? {
        guard !isAtEnd else { return nil }
        let key = try readVarint()
        guard let wireType = WireType(rawValue: UInt8(key & 7)) else {
            throw PBFError.malformed("unknown wire type \(key & 7)")
        }
        let number = key >> 3
        guard number > 0, number < (1 << 29) else {
            throw PBFError.malformed("invalid field number \(number)")
        }
        return (Int(number), wireType)
    }

    /// Reads a length-delimited value, checking the length against the remaining bytes.
    mutating func readBytes() throws -> Data {
        let length = try readVarint()
        guard length <= UInt64(end - position) else { throw PBFError.truncated }
        let count = Int(length)
        let slice = data[position..<(position + count)]
        position += count
        return slice
    }

    /// Reads a length-delimited value as UTF-8. Invalid sequences become U+FFFD.
    mutating func readString() throws -> String {
        String(decoding: try readBytes(), as: UTF8.self)
    }

    /// Reads a varint as a signed 64-bit integer (protobuf `int64`).
    mutating func readInt64() throws -> Int64 {
        Int64(bitPattern: try readVarint())
    }

    /// Reads a varint as a signed 32-bit integer (protobuf `int32`).
    mutating func readInt32() throws -> Int32 {
        Int32(truncatingIfNeeded: try readVarint())
    }

    /// Skips a value of the given wire type.
    mutating func skip(_ wireType: WireType) throws {
        switch wireType {
        case .varint:
            _ = try readVarint()
        case .fixed64:
            try advance(8)
        case .fixed32:
            try advance(4)
        case .lengthDelimited:
            _ = try readBytes()
        case .startGroup, .endGroup:
            throw PBFError.malformed("groups are not supported")
        }
    }

    private mutating func advance(_ count: Int) throws {
        guard count <= end - position else { throw PBFError.truncated }
        position += count
    }

    /// Decodes a zigzag-encoded signed integer (protobuf `sint64`).
    static func zigZagDecode(_ value: UInt64) -> Int64 {
        Int64(bitPattern: value >> 1) ^ -Int64(bitPattern: value & 1)
    }

    /// Decodes a packed repeated varint field.
    static func packedVarints(_ data: Data) throws -> [UInt64] {
        var reader = ProtobufReader(data)
        var values: [UInt64] = []
        while !reader.isAtEnd {
            values.append(try reader.readVarint())
        }
        return values
    }

    /// Decodes a packed repeated `sint64` field.
    static func packedSInt64(_ data: Data) throws -> [Int64] {
        try packedVarints(data).map(zigZagDecode)
    }

    /// Decodes a packed repeated `int32` field.
    static func packedInt32(_ data: Data) throws -> [Int32] {
        try packedVarints(data).map { Int32(truncatingIfNeeded: $0) }
    }
}
