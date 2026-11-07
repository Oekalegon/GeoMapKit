import Foundation

/// CRC-32 (IEEE 802.3), used to check a whole file after a transfer.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1 }
        return value
    }

    static func checksum(_ data: Data, range: Range<Int>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for index in range { crc = table[Int((crc ^ UInt32(buffer[index])) & 0xff)] ^ (crc >> 8) }
        }
        return ~crc
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return ~crc
    }
}
