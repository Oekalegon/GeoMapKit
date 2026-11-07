/// Appends little-endian integers and varints to a byte array.
struct ByteWriter {
    var bytes: [UInt8] = []

    var count: Int { bytes.count }

    mutating func writeUInt8(_ value: UInt8) { bytes.append(value) }

    mutating func writeUInt16(_ value: UInt16) { writeFixed(UInt64(value), width: 2) }
    mutating func writeUInt32(_ value: UInt32) { writeFixed(UInt64(value), width: 4) }
    mutating func writeUInt64(_ value: UInt64) { writeFixed(value, width: 8) }
    mutating func writeInt32(_ value: Int32) { writeFixed(UInt64(UInt32(bitPattern: value)), width: 4) }

    mutating func writeBytes(_ other: some Sequence<UInt8>) { bytes.append(contentsOf: other) }

    mutating func writeVarint(_ value: UInt64) {
        var rest = value
        while rest >= 0x80 {
            bytes.append(UInt8(rest & 0x7f) | 0x80)
            rest >>= 7
        }
        bytes.append(UInt8(rest))
    }

    mutating func writeZigzag(_ value: Int64) {
        writeVarint(UInt64(bitPattern: (value << 1) ^ (value >> 63)))
    }

    /// Pads with zero bytes to a multiple of `alignment`.
    mutating func align(to alignment: Int) {
        while bytes.count % alignment != 0 { bytes.append(0) }
    }

    private mutating func writeFixed(_ value: UInt64, width: Int) {
        for shift in 0..<width { bytes.append(UInt8((value >> UInt64(shift * 8)) & 0xff)) }
    }
}
