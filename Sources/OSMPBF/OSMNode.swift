import GeoCore

/// An OSM node: a point with tags.
public struct OSMNode: Hashable, Sendable {
    /// The OSM node ID. OSM IDs exceed 32 bits, so this is always 64-bit.
    public let id: Int64

    /// The position in degrees.
    public let coordinate: Coordinate

    /// All tags of the node, with nothing dropped, ordered by the UTF-8 bytes of their keys.
    ///
    /// Identical keys, which OSM forbids, are all kept in file order. Keys that differ only in Unicode
    /// normalization stay separate (see `architecture.md`, question 46).
    public let orderedTags: [OSMTag]

    /// The tags as a dictionary.
    ///
    /// A convenience only: it is lossy, because a `[String: String]` treats keys that differ only in Unicode
    /// normalization as the same key, and a repeated key keeps its last value. Use ``orderedTags`` where
    /// nothing may be lost.
    public var tags: [String: String] { OSMTag.dictionary(orderedTags) }

    /// Creates a node.
    ///
    /// - Parameters:
    ///   - id: The OSM node ID.
    ///   - coordinate: The position in degrees.
    ///   - tags: The tags of the node.
    public init(id: Int64, coordinate: Coordinate, tags: [String: String]) {
        self.id = id
        self.coordinate = coordinate
        self.orderedTags = OSMTag.sortedByKeyBytes(tags.map { OSMTag(key: $0.key, value: $0.value) })
    }

    /// Creates a node with an ordered tag list. The tags are put in key byte order; nothing is merged.
    ///
    /// - Parameters:
    ///   - id: The OSM node ID.
    ///   - coordinate: The position in degrees.
    ///   - orderedTags: The tags.
    public init(id: Int64, coordinate: Coordinate, orderedTags: [OSMTag]) {
        self.id = id
        self.coordinate = coordinate
        self.orderedTags = OSMTag.sortedByKeyBytes(orderedTags)
    }
}
