import Compression
import Foundation

/// Builds small PBF files for tests.
public struct PBFFileBuilder {
    public init() {}

    public enum Compression { case raw, zlib }

    public private(set) var file = Data()

    /// Appends one blob: `[4-byte header length][BlobHeader][Blob]`.
    public mutating func appendBlob(
        type: String, payload: Data, compression: Compression = .zlib,
        declaredRawSize: Int? = nil, extraBlobField: (field: Int, value: Data)? = nil
    ) {
        var blob = ProtobufWriter()
        switch compression {
        case .raw:
            blob.bytes(1, payload)
        case .zlib:
            blob.int(2, Int64(declaredRawSize ?? payload.count))
            blob.bytes(3, Self.zlib(payload))
        }
        if let extraBlobField { blob.bytes(extraBlobField.field, extraBlobField.value) }
        appendRaw(type: type, blob: blob.data)
    }

    /// Appends a blob whose Blob message the caller has built.
    public mutating func appendRaw(type: String, blob: Data, declaredDataSize: Int? = nil) {
        var header = ProtobufWriter()
        header.string(1, type)
        header.int(3, Int64(declaredDataSize ?? blob.count))
        var length = UInt32(header.data.count).bigEndian
        file.append(Data(bytes: &length, count: 4))
        file.append(header.data)
        file.append(blob)
    }

    /// A zlib stream: header, raw deflate, big-endian Adler-32.
    public static func zlib(_ payload: Data) -> Data {
        let source = [UInt8](payload)
        var destination = [UInt8](repeating: 0, count: source.count + 1024)
        let written = compression_encode_buffer(
            &destination, destination.count, source, source.count, nil, COMPRESSION_ZLIB
        )
        precondition(written > 0 || source.isEmpty, "compression failed")
        var out: [UInt8] = [0x78, 0x9c]
        out.append(contentsOf: destination.prefix(written))
        let checksum = adler32(source)
        out.append(contentsOf: [UInt8(checksum >> 24), UInt8(checksum >> 16 & 0xff), UInt8(checksum >> 8 & 0xff), UInt8(checksum & 0xff)])
        return Data(out)
    }

    public static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }

    // MARK: Messages

    /// An `OSMHeader` payload.
    public static func headerPayload(
        required: [String] = ["OsmSchema-V0.6", "DenseNodes"], optional: [String] = [],
        bbox: (left: Int64, right: Int64, top: Int64, bottom: Int64)? = nil,
        program: String? = "GeoMapKitTests"
    ) -> Data {
        var header = ProtobufWriter()
        if let bbox {
            var box = ProtobufWriter()
            box.sint(1, bbox.left)
            box.sint(2, bbox.right)
            box.sint(3, bbox.top)
            box.sint(4, bbox.bottom)
            header.bytes(1, box.data)
        }
        required.forEach { header.string(4, $0) }
        optional.forEach { header.string(5, $0) }
        if let program { header.string(16, program) }
        return header.data
    }

    /// A string table message.
    public static func stringTable(_ strings: [String]) -> Data {
        var table = ProtobufWriter()
        strings.forEach { table.string(1, $0) }
        return table.data
    }

    /// A `DenseNodes` message. `tags[i]` are string-table index pairs for node `i`.
    public static func denseNodes(
        ids: [Int64], latitudes: [Int64], longitudes: [Int64], tags: [[(key: Int32, value: Int32)]]? = nil
    ) -> Data {
        var dense = ProtobufWriter()
        dense.packedSInt(1, ProtobufWriter.delta(ids))
        dense.packedSInt(8, ProtobufWriter.delta(latitudes))
        dense.packedSInt(9, ProtobufWriter.delta(longitudes))
        if let tags {
            var flat: [Int32] = []
            for nodeTags in tags {
                for tag in nodeTags { flat.append(tag.key); flat.append(tag.value) }
                flat.append(0)
            }
            dense.packedInt32(10, flat)
        }
        return dense.data
    }

    public static func way(id: Int64, nodeIDs: [Int64], tags: [(key: UInt64, value: UInt64)]) -> Data {
        var way = ProtobufWriter()
        way.int(1, id)
        way.packed(2, tags.map(\.key))
        way.packed(3, tags.map(\.value))
        way.packedSInt(8, ProtobufWriter.delta(nodeIDs))
        return way.data
    }

    public static func relation(
        id: Int64, members: [(id: Int64, role: Int32, type: UInt64)], tags: [(key: UInt64, value: UInt64)]
    ) -> Data {
        var relation = ProtobufWriter()
        relation.int(1, id)
        relation.packed(2, tags.map(\.key))
        relation.packed(3, tags.map(\.value))
        relation.packedInt32(8, members.map(\.role))
        relation.packedSInt(9, ProtobufWriter.delta(members.map(\.id)))
        relation.packed(10, members.map(\.type))
        return relation.data
    }

    /// A `PrimitiveBlock` with one group.
    public static func primitiveBlock(
        strings: [String], dense: Data? = nil, ways: [Data] = [], relations: [Data] = [],
        granularity: Int32? = nil, latitudeOffset: Int64? = nil, longitudeOffset: Int64? = nil
    ) -> Data {
        var group = ProtobufWriter()
        if let dense { group.bytes(2, dense) }
        ways.forEach { group.bytes(3, $0) }
        relations.forEach { group.bytes(4, $0) }
        var block = ProtobufWriter()
        block.bytes(1, stringTable(strings))
        block.bytes(2, group.data)
        if let granularity { block.int(17, Int64(granularity)) }
        if let latitudeOffset { block.int(19, latitudeOffset) }
        if let longitudeOffset { block.int(20, longitudeOffset) }
        return block.data
    }
}
