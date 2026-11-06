import Foundation

extension PrimitiveBlockDecoder {
    /// Decodes a `Relation` message. Member IDs are delta-coded.
    func decodeRelation(_ data: Data) throws -> OSMRelation {
        var reader = ProtobufReader(data)
        var id: Int64 = 0
        var keys: [UInt64] = []
        var values: [UInt64] = []
        var roles: [Int32] = []
        var memberIDs: [Int64] = []
        var types: [UInt64] = []
        while let (number, wireType) = try reader.readFieldKey() {
            switch (number, wireType) {
            case (1, .varint): id = try reader.readInt64()
            case (2, .lengthDelimited): keys = try ProtobufReader.packedVarints(reader.readBytes())
            case (3, .lengthDelimited): values = try ProtobufReader.packedVarints(reader.readBytes())
            case (8, .lengthDelimited): roles = try ProtobufReader.packedInt32(reader.readBytes())
            case (9, .lengthDelimited): memberIDs = try ProtobufReader.packedSInt64(reader.readBytes())
            case (10, .lengthDelimited): types = try ProtobufReader.packedVarints(reader.readBytes())
            default: try reader.skip(wireType)
            }
        }
        guard roles.count == memberIDs.count, memberIDs.count == types.count else {
            throw PBFError.inconsistentBlock(
                "relation \(id): \(roles.count) roles, \(memberIDs.count) members, \(types.count) types"
            )
        }
        var memberID: Int64 = 0
        var members: [OSMMember] = []
        members.reserveCapacity(memberIDs.count)
        for index in memberIDs.indices {
            memberID = memberID &+ memberIDs[index]
            guard let type = OSMMemberType(rawValue: Int(truncatingIfNeeded: types[index])), types[index] <= 2 else {
                throw PBFError.malformed("relation \(id): unknown member type \(types[index])")
            }
            members.append(OSMMember(type: type, id: memberID, role: try string(at: Int(roles[index]))))
        }
        return OSMRelation(id: id, members: members, tags: try tags(keys: keys, values: values))
    }
}
