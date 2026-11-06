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

    /// All tags of the way. Nothing is dropped.
    public let tags: [String: String]

    /// Creates a way.
    ///
    /// - Parameters:
    ///   - id: The OSM way ID.
    ///   - nodeIDs: The node IDs along the way, in order.
    ///   - tags: The tags of the way.
    public init(id: Int64, nodeIDs: [Int64], tags: [String: String]) {
        self.id = id
        self.nodeIDs = nodeIDs
        self.tags = tags
    }

    /// Whether the first and last node are the same (a ring).
    public var isClosed: Bool {
        nodeIDs.count > 1 && nodeIDs.first == nodeIDs.last
    }
}
