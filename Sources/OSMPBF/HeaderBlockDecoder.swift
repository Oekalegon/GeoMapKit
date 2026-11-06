import Foundation
import GeoCore

/// Decodes the `HeaderBlock` message of a PBF file.
enum HeaderBlockDecoder {
    /// The required features this reader supports. A file that requires anything
    /// else must be rejected, because its data may not be interpreted correctly.
    static let supportedRequiredFeatures: Set<String> = [
        "OsmSchema-V0.6",
        "DenseNodes",
        "HistoricalInformation",
    ]

    /// Decodes a header block.
    ///
    /// - Parameter data: The decompressed `OSMHeader` payload.
    /// - Returns: The header.
    /// - Throws: ``PBFError/unsupportedRequiredFeature(_:)`` if the file needs a
    ///   feature this reader lacks, or another ``PBFError`` if the data is malformed.
    static func decode(_ data: Data) throws -> OSMHeader {
        var reader = ProtobufReader(data)
        var boundingBox: BoundingBox?
        var required: [String] = []
        var optional: [String] = []
        var program: String?
        var source: String?
        while let (number, wireType) = try reader.readFieldKey() {
            switch (number, wireType) {
            case (1, .lengthDelimited): boundingBox = try decodeBoundingBox(reader.readBytes())
            case (4, .lengthDelimited): required.append(try reader.readString())
            case (5, .lengthDelimited): optional.append(try reader.readString())
            case (16, .lengthDelimited): program = try reader.readString()
            case (17, .lengthDelimited): source = try reader.readString()
            default: try reader.skip(wireType)
            }
        }
        if let unsupported = required.first(where: { !supportedRequiredFeatures.contains($0) }) {
            throw PBFError.unsupportedRequiredFeature(unsupported)
        }
        return OSMHeader(
            boundingBox: boundingBox, requiredFeatures: required, optionalFeatures: optional,
            writingProgram: program, source: source
        )
    }

    /// Bounding box edges are `sint64` values in nanodegrees.
    private static func decodeBoundingBox(_ data: Data) throws -> BoundingBox {
        var reader = ProtobufReader(data)
        var left: Int64?, right: Int64?, top: Int64?, bottom: Int64?
        while let (number, wireType) = try reader.readFieldKey() {
            switch (number, wireType) {
            case (1, .varint): left = ProtobufReader.zigZagDecode(try reader.readVarint())
            case (2, .varint): right = ProtobufReader.zigZagDecode(try reader.readVarint())
            case (3, .varint): top = ProtobufReader.zigZagDecode(try reader.readVarint())
            case (4, .varint): bottom = ProtobufReader.zigZagDecode(try reader.readVarint())
            default: try reader.skip(wireType)
            }
        }
        guard let left, let right, let top, let bottom else {
            throw PBFError.malformed("HeaderBBox is missing an edge")
        }
        return BoundingBox(
            south: Double(bottom) / 1e9, west: Double(left) / 1e9,
            north: Double(top) / 1e9, east: Double(right) / 1e9
        )
    }
}
