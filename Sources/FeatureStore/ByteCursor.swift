import Foundation

/// A bounds-checked reader over a range of a `Data` whose indices start at zero.
///
/// Every read verifies that enough bytes remain, so corrupt or truncated files
/// throw ``FeatureStoreError`` and never read outside the range.
struct ByteCursor {
    private let data: Data
    private(set) var position: Int
    let end: Int

    init(_ data: Data, range: Range<Int>) {
        self.data = data
        self.position = range.lowerBound
        self.end = range.upperBound
    }

    var remaining: Int { end - position }
    var isAtEnd: Bool { position >= end }

    mutating func readUInt8() throws -> UInt8 {
        guard position < end else { throw FeatureStoreError.truncated }
        defer { position += 1 }
        return data[position]
    }

    mutating func readUInt16() throws -> UInt16 { UInt16(truncatingIfNeeded: try readFixed(width: 2)) }
    mutating func readUInt32() throws -> UInt32 { UInt32(truncatingIfNeeded: try readFixed(width: 4)) }
    mutating func readUInt64() throws -> UInt64 { try readFixed(width: 8) }
    mutating func readInt32() throws -> Int32 { Int32(bitPattern: try readUInt32()) }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let byte = try readUInt8()
            if shift == 63 && byte > 1 { throw FeatureStoreError.corrupt("varint too long") }
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
    }

    mutating func readZigzag() throws -> Int64 {
        let raw = try readVarint()
        return Int64(bitPattern: raw >> 1) ^ -Int64(bitPattern: raw & 1)
    }

    /// Reads a varint that must fit in `Int` and not exceed `limit`.
    mutating func readCount(limit: Int) throws -> Int {
        let value = try readVarint()
        guard limit >= 0, value <= UInt64(limit) else { throw FeatureStoreError.corrupt("count \(value) exceeds limit \(limit)") }
        return Int(value)
    }

    /// Returns a cursor over the next `length` bytes and skips them.
    mutating func skip(_ length: Int) throws -> Range<Int> {
        guard length >= 0, length <= remaining else { throw FeatureStoreError.truncated }
        defer { position += length }
        return position..<(position + length)
    }

    private mutating func readFixed(width: Int) throws -> UInt64 {
        guard width <= remaining else { throw FeatureStoreError.truncated }
        var value: UInt64 = 0
        for index in 0..<width { value |= UInt64(data[position + index]) << UInt64(index * 8) }
        position += width
        return value
    }
}
