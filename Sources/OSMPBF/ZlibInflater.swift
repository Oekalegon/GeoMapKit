import Foundation
#if canImport(Compression)
import Compression
#endif

/// Decompresses the zlib data found in PBF blobs.
///
/// A PBF `zlib_data` field is a zlib stream: a 2-byte header, raw deflate data,
/// and a 4-byte big-endian Adler-32 checksum. Apple's Compression framework
/// decodes raw deflate, so the header is validated and stripped, and the
/// checksum is verified here.
///
/// On platforms without the Compression framework (for example Linux) this
/// throws ``PBFError/decompressionFailed``; a different implementation is needed
/// there (see the open question on decompression in `docs/design/architecture.md`).
enum ZlibInflater {
    /// Decompresses a zlib stream to exactly `expectedSize` bytes.
    ///
    /// - Parameters:
    ///   - zlib: The zlib stream.
    ///   - expectedSize: The uncompressed size declared by the blob (`raw_size`).
    /// - Returns: The decompressed data.
    /// - Throws: ``PBFError/decompressionFailed`` if the header is invalid, the
    ///   output size differs from `expectedSize` or the checksum does not match.
    static func inflate(_ zlib: Data, expectedSize: Int) throws -> Data {
        #if canImport(Compression)
        guard zlib.count >= 7, expectedSize >= 0 else { throw PBFError.decompressionFailed }
        let start = zlib.startIndex
        let cmf = zlib[start]
        let flg = zlib[start + 1]
        guard cmf & 0x0f == 8, (Int(cmf) << 8 | Int(flg)) % 31 == 0, flg & 0x20 == 0 else {
            throw PBFError.decompressionFailed
        }
        let deflate = zlib[(start + 2)..<(zlib.endIndex - 4)]
        let trailer = zlib[(zlib.endIndex - 4)...]
        let expectedChecksum = trailer.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }

        // One spare byte detects output that is larger than declared: the framework
        // truncates silently when the buffer is too small.
        var output = [UInt8](repeating: 0, count: expectedSize + 1)
        let outputCapacity = output.count
        let written: Int = deflate.withUnsafeBytes { source in
            guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return output.withUnsafeMutableBufferPointer { destination in
                guard let destinationBase = destination.baseAddress else { return -1 }
                return compression_decode_buffer(
                    destinationBase, outputCapacity, sourceBase, source.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw PBFError.decompressionFailed }
        output.removeLast()
        guard Self.adler32(output) == expectedChecksum else { throw PBFError.decompressionFailed }
        return Data(output)
        #else
        throw PBFError.decompressionFailed
        #endif
    }

    /// The Adler-32 checksum of a byte sequence.
    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        // 5552 is the largest block for which the sums cannot overflow before the modulo.
        var index = 0
        while index < bytes.count {
            let blockEnd = min(index + 5552, bytes.count)
            while index < blockEnd {
                a &+= UInt32(bytes[index])
                b &+= a
                index += 1
            }
            a %= 65521
            b %= 65521
        }
        return b << 16 | a
    }
}
