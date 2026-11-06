import GeoCore

/// The objects selected from a PBF file for one area.
///
/// An extract is self-contained: every way's nodes are present (outside the box
/// as well as inside), and relations that touch the area are included with their
/// member ways and nodes. This is the input for building the feature store.
///
/// The objects are stored compactly, in columns, with tags referring to a shared
/// table of distinct strings (see ``InternedStrings``); an extract of a dense city
/// needs a quarter of the memory of the same objects as dictionaries. The
/// collections build ``OSMNode``, ``OSMWay`` and ``ExtractedRelation`` values on
/// demand, and offer accessors that read the columns without allocating.
public struct OSMExtract: Sendable {
    /// The header of the source file.
    public let header: OSMHeader

    /// The area that was cut.
    public let boundingBox: BoundingBox

    /// The nodes, sorted by ID: tagged nodes inside the area, plus every node that
    /// a kept way or relation refers to.
    public let nodes: ExtractedNodes

    /// The ways, sorted by ID: every way with a node in the area, plus the member
    /// ways of kept relations.
    public let ways: ExtractedWays

    /// The relations, sorted by ID, that touch the area.
    public let relations: ExtractedRelations

    /// The distinct strings that tags and roles refer to.
    public let strings: InternedStrings

    /// The number of nodes that kept ways or relations refer to but that were not
    /// in the file. Zero for a consistent file.
    public let missingNodeCount: Int

    init(
        header: OSMHeader, boundingBox: BoundingBox, nodes: ExtractedNodes, ways: ExtractedWays,
        relations: ExtractedRelations, strings: InternedStrings, missingNodeCount: Int
    ) {
        self.header = header
        self.boundingBox = boundingBox
        self.nodes = nodes
        self.ways = ways
        self.relations = relations
        self.strings = strings
        self.missingNodeCount = missingNodeCount
    }

    /// Looks up a node by ID.
    ///
    /// - Parameter id: The OSM node ID.
    /// - Returns: The node, or `nil` if it is not in the extract. O(log n).
    public func node(withID id: Int64) -> OSMNode? {
        nodes.index(ofID: id).map { nodes[$0] }
    }

    /// The approximate memory used by the extract's data, in bytes.
    public var memoryBytes: Int {
        nodes.memoryBytes + ways.memoryBytes + relations.memoryBytes + strings.memoryBytes
    }
}
