/// The ways of an extract, stored in columns and sorted by ID.
public struct ExtractedWays: RandomAccessCollection, Sendable {
    /// The way IDs, sorted ascending.
    public let ids: [Int64]

    let vertexOffsets: [UInt32]
    let vertices: [Int64]
    let tagOffsets: [UInt32]
    let tagKeys: [UInt32]
    let tagValues: [UInt32]
    let strings: InternedStrings

    init(
        ids: [Int64], vertexOffsets: [UInt32], vertices: [Int64],
        tagOffsets: [UInt32], tagKeys: [UInt32], tagValues: [UInt32], strings: InternedStrings
    ) {
        self.ids = ids
        self.vertexOffsets = vertexOffsets
        self.vertices = vertices
        self.tagOffsets = tagOffsets
        self.tagKeys = tagKeys
        self.tagValues = tagValues
        self.strings = strings
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { ids.count }

    public subscript(position: Int) -> OSMWay {
        OSMWay(id: ids[position], nodeIDs: Array(nodeIDs(at: position)), orderedTags: tags(at: position).orderedTags)
    }

    /// The node IDs along a way, in order.
    public func nodeIDs(at position: Int) -> ArraySlice<Int64> {
        vertices[Int(vertexOffsets[position])..<Int(vertexOffsets[position + 1])]
    }

    /// The tags of a way.
    public func tags(at position: Int) -> TagList {
        TagList(
            keys: tagKeys[Int(tagOffsets[position])..<Int(tagOffsets[position + 1])],
            values: tagValues[Int(tagOffsets[position])..<Int(tagOffsets[position + 1])],
            strings: strings
        )
    }

    /// The total number of node references over all ways.
    public var vertexCount: Int { vertices.count }

    /// The position of the way with the given ID, or `nil`. O(log n).
    public func index(ofID id: Int64) -> Int? {
        SortedIDs.index(of: id, in: ids)
    }

    /// The memory used by the columns, in bytes.
    public var memoryBytes: Int {
        (ids.count + vertices.count) * MemoryLayout<Int64>.stride
            + (vertexOffsets.count + tagOffsets.count + tagKeys.count + tagValues.count) * MemoryLayout<UInt32>.stride
    }
}
