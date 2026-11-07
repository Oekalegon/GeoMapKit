/// An OSM way: an ordered list of node IDs with tags.
///
/// A way is closed when its first and last node IDs are equal. The coordinates
/// are not stored here; they are resolved from the nodes (see the two-pass
/// loading described in `docs/design/architecture.md`).
public struct OSMWay: Hashable, Sendable {
    /// The OSM way ID.
    public let id: Int64

    /// The node IDs along the way, in order.
    public let nodeIDs: [Int64]

    /// All tags of the way, with nothing dropped, ordered by the UTF-8 bytes of their keys.
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

    /// Creates a way.
    ///
    /// - Parameters:
    ///   - id: The OSM way ID.
    ///   - nodeIDs: The node IDs along the way, in order.
    ///   - tags: The tags of the way.
    public init(id: Int64, nodeIDs: [Int64], tags: [String: String]) {
        self.id = id
        self.nodeIDs = nodeIDs
        self.orderedTags = OSMTag.sortedByKeyBytes(tags.map { OSMTag(key: $0.key, value: $0.value) })
    }

    /// Creates a way with an ordered tag list. The tags are put in key byte order; nothing is merged.
    ///
    /// - Parameters:
    ///   - id: The OSM way ID.
    ///   - nodeIDs: The node IDs along the way, in order.
    ///   - orderedTags: The tags.
    public init(id: Int64, nodeIDs: [Int64], orderedTags: [OSMTag]) {
        self.id = id
        self.nodeIDs = nodeIDs
        self.orderedTags = OSMTag.sortedByKeyBytes(orderedTags)
    }

    /// Whether the first and last node are the same (a ring).
    public var isClosed: Bool {
        nodeIDs.count > 1 && nodeIDs.first == nodeIDs.last
    }
}
