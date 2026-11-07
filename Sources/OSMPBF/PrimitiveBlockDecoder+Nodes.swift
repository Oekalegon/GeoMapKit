import Foundation
import GeoCore

extension PrimitiveBlockDecoder {
    /// Decodes a plain `Node` message.
    func decodeNode(_ data: Data) throws -> OSMNode {
        var reader = ProtobufReader(data)
        var id: Int64 = 0
        var keys: [UInt64] = []
        var values: [UInt64] = []
        var latitudeValue: Int64 = 0
        var longitudeValue: Int64 = 0
        while let (number, wireType) = try reader.readFieldKey() {
            switch (number, wireType) {
            case (1, .varint): id = ProtobufReader.zigZagDecode(try reader.readVarint())
            case (2, .lengthDelimited): keys = try ProtobufReader.packedVarints(reader.readBytes())
            case (3, .lengthDelimited): values = try ProtobufReader.packedVarints(reader.readBytes())
            case (8, .varint): latitudeValue = ProtobufReader.zigZagDecode(try reader.readVarint())
            case (9, .varint): longitudeValue = ProtobufReader.zigZagDecode(try reader.readVarint())
            default: try reader.skip(wireType)
            }
        }
        return OSMNode(
            id: id,
            coordinate: Coordinate(latitude: latitude(latitudeValue), longitude: longitude(longitudeValue)),
            orderedTags: try tags(keys: keys, values: values)
        )
    }

    /// Decodes a `DenseNodes` message: delta-coded IDs and coordinates, and a
    /// flat key/value array where each node's tags end with a 0 key.
    func decodeDenseNodes(_ data: Data, into nodes: inout [OSMNode]) throws {
        var reader = ProtobufReader(data)
        var ids: [Int64] = []
        var latitudes: [Int64] = []
        var longitudes: [Int64] = []
        var keysValues: [Int32] = []
        while let (number, wireType) = try reader.readFieldKey() {
            switch (number, wireType) {
            case (1, .lengthDelimited): ids = try ProtobufReader.packedSInt64(reader.readBytes())
            case (8, .lengthDelimited): latitudes = try ProtobufReader.packedSInt64(reader.readBytes())
            case (9, .lengthDelimited): longitudes = try ProtobufReader.packedSInt64(reader.readBytes())
            case (10, .lengthDelimited): keysValues = try ProtobufReader.packedInt32(reader.readBytes())
            default: try reader.skip(wireType)
            }
        }
        let count = ids.count
        guard latitudes.count == count, longitudes.count == count else {
            throw PBFError.inconsistentBlock("dense nodes: \(count) ids, \(latitudes.count) latitudes, \(longitudes.count) longitudes")
        }
        nodes.reserveCapacity(nodes.count + count)

        var id: Int64 = 0
        var latitudeValue: Int64 = 0
        var longitudeValue: Int64 = 0
        var cursor = 0
        for index in 0..<count {
            id = id &+ ids[index]
            latitudeValue = latitudeValue &+ latitudes[index]
            longitudeValue = longitudeValue &+ longitudes[index]

            var tags: [OSMTag] = []
            if !keysValues.isEmpty {
                while true {
                    guard cursor < keysValues.count else {
                        throw PBFError.inconsistentBlock("dense nodes: key/value list ended early")
                    }
                    let key = keysValues[cursor]
                    cursor += 1
                    if key == 0 { break }
                    guard cursor < keysValues.count else {
                        throw PBFError.inconsistentBlock("dense nodes: key without a value")
                    }
                    let value = keysValues[cursor]
                    cursor += 1
                    tags.append(OSMTag(key: try string(at: Int(key)), value: try string(at: Int(value))))
                }
            }
            nodes.append(OSMNode(
                id: id,
                coordinate: Coordinate(latitude: latitude(latitudeValue), longitude: longitude(longitudeValue)),
                orderedTags: tags
            ))
        }
        guard keysValues.isEmpty || cursor == keysValues.count else {
            throw PBFError.inconsistentBlock("dense nodes: leftover key/value entries")
        }
    }
}
