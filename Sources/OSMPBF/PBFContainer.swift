import Foundation

/// Splits a PBF file into its blobs.
///
/// A PBF file is a sequence of `[4-byte big-endian header length][BlobHeader][Blob]`.
/// The BlobHeader names the blob type (`OSMHeader` or `OSMData`) and the size of
/// the following Blob. The sizes are limited by the format and checked here
/// before anything is allocated.
struct PBFContainer {
    /// The maximum size of a BlobHeader allowed by the format.
    static let maximumHeaderSize = 64 * 1024

    /// The maximum size of a Blob, compressed or uncompressed, allowed by the format.
    static let maximumBlobSize = 32 * 1024 * 1024

    private let data: Data

    init(_ data: Data) {
        self.data = data
    }

    /// Calls `body` for each blob with its type and decompressed payload.
    ///
    /// - Parameter body: Receives the blob type and payload. Return `false` to stop.
    /// - Throws: ``PBFError`` if the container is malformed, truncated or too large,
    ///   or whatever `body` throws.
    func forEachBlob(_ body: (_ type: String, _ payload: Data) throws -> Bool) throws {
        var offset = data.startIndex
        while offset < data.endIndex {
            guard data.endIndex - offset >= 4 else { throw PBFError.truncated }
            let headerLength = (0..<4).reduce(0) { $0 << 8 | Int(data[offset + $1]) }
            offset += 4
            guard headerLength > 0, headerLength <= Self.maximumHeaderSize else {
                throw PBFError.sizeLimitExceeded("BlobHeader of \(headerLength) bytes")
            }
            guard data.endIndex - offset >= headerLength else { throw PBFError.truncated }
            let (type, blobSize) = try Self.decodeBlobHeader(data[offset..<(offset + headerLength)])
            offset += headerLength

            guard blobSize <= Self.maximumBlobSize else {
                throw PBFError.sizeLimitExceeded("Blob of \(blobSize) bytes")
            }
            guard data.endIndex - offset >= blobSize else { throw PBFError.truncated }
            let payload = try Self.decodeBlob(data[offset..<(offset + blobSize)])
            offset += blobSize

            if try !body(type, payload) { return }
        }
    }

    private static func decodeBlobHeader(_ bytes: Data) throws -> (type: String, dataSize: Int) {
        var reader = ProtobufReader(bytes)
        var type: String?
        var dataSize: Int32?
        while let (number, wireType) = try reader.readFieldKey() {
            switch (number, wireType) {
            case (1, .lengthDelimited): type = try reader.readString()
            case (3, .varint): dataSize = try reader.readInt32()
            default: try reader.skip(wireType)
            }
        }
        guard let type else { throw PBFError.malformed("BlobHeader without type") }
        guard let dataSize, dataSize >= 0 else { throw PBFError.malformed("BlobHeader without a valid datasize") }
        return (type, Int(dataSize))
    }

    private static func decodeBlob(_ bytes: Data) throws -> Data {
        var reader = ProtobufReader(bytes)
        var raw: Data?
        var rawSize: Int32?
        var zlib: Data?
        var otherCompression: String?
        while let (number, wireType) = try reader.readFieldKey() {
            switch (number, wireType) {
            case (1, .lengthDelimited): raw = try reader.readBytes()
            case (2, .varint): rawSize = try reader.readInt32()
            case (3, .lengthDelimited): zlib = try reader.readBytes()
            case (4, .lengthDelimited): otherCompression = "lzma"; try skipBytes(&reader)
            case (5, .lengthDelimited): otherCompression = "bzip2"; try skipBytes(&reader)
            case (6, .lengthDelimited): otherCompression = "lz4"; try skipBytes(&reader)
            case (7, .lengthDelimited): otherCompression = "zstd"; try skipBytes(&reader)
            default: try reader.skip(wireType)
            }
        }
        if let raw { return raw }
        if let zlib {
            guard let rawSize, rawSize >= 0, Int(rawSize) <= maximumBlobSize else {
                throw PBFError.sizeLimitExceeded("raw_size missing or too large")
            }
            return try ZlibInflater.inflate(zlib, expectedSize: Int(rawSize))
        }
        if let otherCompression { throw PBFError.unsupportedCompression(otherCompression) }
        throw PBFError.malformed("Blob without data")
    }

    private static func skipBytes(_ reader: inout ProtobufReader) throws {
        _ = try reader.readBytes()
    }
}
