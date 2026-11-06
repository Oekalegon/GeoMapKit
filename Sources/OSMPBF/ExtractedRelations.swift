/// The relations of an extract, stored in columns and sorted by ID.
public struct ExtractedRelations: RandomAccessCollection, Sendable {
    /// The relation IDs, sorted ascending.
    public let ids: [Int64]

    let memberOffsets: [UInt32]
    let memberTypes: [UInt8]
    let memberIDs: [Int64]
    let memberRoles: [UInt32]
    let complete: [Bool]
    let tagOffsets: [UInt32]
    let tagKeys: [UInt32]
    let tagValues: [UInt32]
    let strings: InternedStrings

    init(
        ids: [Int64], memberOffsets: [UInt32], memberTypes: [UInt8], memberIDs: [Int64], memberRoles: [UInt32],
        complete: [Bool], tagOffsets: [UInt32], tagKeys: [UInt32], tagValues: [UInt32], strings: InternedStrings
    ) {
        self.ids = ids
        self.memberOffsets = memberOffsets
        self.memberTypes = memberTypes
        self.memberIDs = memberIDs
        self.memberRoles = memberRoles
        self.complete = complete
        self.tagOffsets = tagOffsets
        self.tagKeys = tagKeys
        self.tagValues = tagValues
        self.strings = strings
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { ids.count }

    public subscript(position: Int) -> ExtractedRelation {
        let range = Int(memberOffsets[position])..<Int(memberOffsets[position + 1])
        let members = range.map { index in
            OSMMember(
                type: OSMMemberType(rawValue: Int(memberTypes[index])) ?? .node,
                id: memberIDs[index],
                role: strings.string(at: memberRoles[index]) ?? ""
            )
        }
        return ExtractedRelation(
            relation: OSMRelation(id: ids[position], members: members, tags: tags(at: position).dictionary),
            isComplete: complete[position]
        )
    }

    /// The tags of a relation.
    public func tags(at position: Int) -> TagList {
        TagList(
            keys: tagKeys[Int(tagOffsets[position])..<Int(tagOffsets[position + 1])],
            values: tagValues[Int(tagOffsets[position])..<Int(tagOffsets[position + 1])],
            strings: strings
        )
    }

    /// Whether every way and node member of a relation is in the extract.
    public func isComplete(at position: Int) -> Bool {
        complete[position]
    }

    /// The total number of members over all relations.
    public var memberCount: Int { memberIDs.count }

    /// The memory used by the columns, in bytes.
    public var memoryBytes: Int {
        ids.count * MemoryLayout<Int64>.stride + memberIDs.count * MemoryLayout<Int64>.stride + memberTypes.count
            + complete.count + (memberOffsets.count + memberRoles.count + tagOffsets.count + tagKeys.count + tagValues.count)
            * MemoryLayout<UInt32>.stride
    }
}
