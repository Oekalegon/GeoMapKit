import GeoCore

/// An OSM node: a point with tags.
public struct OSMNode: Hashable, Sendable {
    /// The OSM node ID. OSM IDs exceed 32 bits, so this is always 64-bit.
    public let id: Int64

    /// The position in degrees.
    public let coordinate: Coordinate

    /// All tags of the node. Nothing is dropped.
    public let tags: [String: String]

    /// Creates a node.
    ///
    /// - Parameters:
    ///   - id: The OSM node ID.
    ///   - coordinate: The position in degrees.
    ///   - tags: The tags of the node.
    public init(id: Int64, coordinate: Coordinate, tags: [String: String]) {
        self.id = id
        self.coordinate = coordinate
        self.tags = tags
    }
}
