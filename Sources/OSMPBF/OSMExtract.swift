import GeoCore

/// The objects selected from a PBF file for one area.
///
/// An extract is self-contained: every way's nodes are present (outside the box
/// as well as inside), and relations that touch the area are included with their
/// member ways and nodes. This is the input for building the feature store.
public struct OSMExtract: Sendable {
    /// The header of the source file.
    public let header: OSMHeader

    /// The area that was cut.
    public let boundingBox: BoundingBox

    /// The nodes, sorted by ID: tagged nodes inside the area, plus every node that
    /// a kept way or relation refers to.
    public let nodes: [OSMNode]

    /// The ways, sorted by ID: every way with a node in the area, plus the member
    /// ways of kept relations.
    public let ways: [OSMWay]

    /// The relations, sorted by ID, that touch the area.
    public let relations: [ExtractedRelation]

    /// The number of nodes that kept ways or relations refer to but that were not
    /// in the file. Zero for a consistent file.
    public let missingNodeCount: Int

    /// Creates an extract.
    ///
    /// - Parameters:
    ///   - header: The header of the source file.
    ///   - boundingBox: The area that was cut.
    ///   - nodes: The nodes, sorted by ID.
    ///   - ways: The ways, sorted by ID.
    ///   - relations: The relations, sorted by ID.
    ///   - missingNodeCount: The number of referenced nodes absent from the file.
    public init(
        header: OSMHeader, boundingBox: BoundingBox, nodes: [OSMNode], ways: [OSMWay],
        relations: [ExtractedRelation], missingNodeCount: Int
    ) {
        self.header = header
        self.boundingBox = boundingBox
        self.nodes = nodes
        self.ways = ways
        self.relations = relations
        self.missingNodeCount = missingNodeCount
    }

    /// Looks up a node by ID.
    ///
    /// - Parameter id: The OSM node ID.
    /// - Returns: The node, or `nil` if it is not in the extract. O(log n).
    public func node(withID id: Int64) -> OSMNode? {
        var low = 0
        var high = nodes.count
        while low < high {
            let middle = low + (high - low) / 2
            if nodes[middle].id < id { low = middle + 1 } else { high = middle }
        }
        return low < nodes.count && nodes[low].id == id ? nodes[low] : nil
    }
}
