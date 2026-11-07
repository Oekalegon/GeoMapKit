import GeoCore

/// The nodes of an extract, stored in columns and sorted by ID.
///
/// Iterating yields ``OSMNode`` values built on demand. For scans over many nodes
/// use the columns (``ids``) and the accessors, which do not allocate.
///
/// Coordinates are stored as 32-bit integers in 1e-7 degrees, OSM's own precision,
/// and come out as the same `Double` the PBF reader produced.
public struct ExtractedNodes: RandomAccessCollection, Sendable {
    /// The node IDs, sorted ascending.
    public let ids: [Int64]

    let latitudes: [Int32]
    let longitudes: [Int32]
    let tagOffsets: [UInt32]
    let tagKeys: [UInt32]
    let tagValues: [UInt32]
    let strings: InternedStrings

    init(
        ids: [Int64], latitudes: [Int32], longitudes: [Int32],
        tagOffsets: [UInt32], tagKeys: [UInt32], tagValues: [UInt32], strings: InternedStrings
    ) {
        self.ids = ids
        self.latitudes = latitudes
        self.longitudes = longitudes
        self.tagOffsets = tagOffsets
        self.tagKeys = tagKeys
        self.tagValues = tagValues
        self.strings = strings
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { ids.count }

    public subscript(position: Int) -> OSMNode {
        OSMNode(id: ids[position], coordinate: coordinate(at: position), orderedTags: tags(at: position).orderedTags)
    }

    /// The position of the coordinate of a node.
    public func coordinate(at position: Int) -> Coordinate {
        Coordinate(latitude: Double(latitudes[position]) / 1e7, longitude: Double(longitudes[position]) / 1e7)
    }

    /// The tags of a node.
    public func tags(at position: Int) -> TagList {
        TagList(
            keys: tagKeys[Int(tagOffsets[position])..<Int(tagOffsets[position + 1])],
            values: tagValues[Int(tagOffsets[position])..<Int(tagOffsets[position + 1])],
            strings: strings
        )
    }

    /// Whether a node has at least one tag.
    public func hasTags(at position: Int) -> Bool {
        tagOffsets[position + 1] > tagOffsets[position]
    }

    /// The position of the node with the given ID, or `nil`. O(log n).
    public func index(ofID id: Int64) -> Int? {
        SortedIDs.index(of: id, in: ids)
    }

    /// The memory used by the columns, in bytes.
    public var memoryBytes: Int {
        ids.count * MemoryLayout<Int64>.stride + (latitudes.count + longitudes.count) * MemoryLayout<Int32>.stride
            + (tagOffsets.count + tagKeys.count + tagValues.count) * MemoryLayout<UInt32>.stride
    }
}
