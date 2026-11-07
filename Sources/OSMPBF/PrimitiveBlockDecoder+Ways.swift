import Foundation

extension PrimitiveBlockDecoder {
    /// Decodes a `Way` message. Node references are delta-coded.
    ///
    /// Optional per-node coordinates (`lat`/`lon`, the LocationsOnWays extension)
    /// are ignored; coordinates are resolved from the nodes.
    func decodeWay(_ data: Data) throws -> OSMWay {
        var reader = ProtobufReader(data)
        var id: Int64 = 0
        var keys: [UInt64] = []
        var values: [UInt64] = []
        var references: [Int64] = []
        while let (number, wireType) = try reader.readFieldKey() {
            switch (number, wireType) {
            case (1, .varint): id = try reader.readInt64()
            case (2, .lengthDelimited): keys = try ProtobufReader.packedVarints(reader.readBytes())
            case (3, .lengthDelimited): values = try ProtobufReader.packedVarints(reader.readBytes())
            case (8, .lengthDelimited): references = try ProtobufReader.packedSInt64(reader.readBytes())
            default: try reader.skip(wireType)
            }
        }
        var nodeID: Int64 = 0
        let nodeIDs = references.map { delta -> Int64 in
            nodeID = nodeID &+ delta
            return nodeID
        }
        return OSMWay(id: id, nodeIDs: nodeIDs, orderedTags: try tags(keys: keys, values: values))
    }
}
