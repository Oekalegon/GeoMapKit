import OSMPBF
import GeoCore

/// Counts describing an extract.
public struct ExtractSummary: Equatable, Sendable {
    public let nodes: Int
    public let taggedNodes: Int
    public let nodesOutsideBox: Int
    public let ways: Int
    public let wayVertices: Int
    public let relations: Int
    public let incompleteRelations: Int
    public let missingNodes: Int

    public init(
        nodes: Int, taggedNodes: Int, nodesOutsideBox: Int, ways: Int, wayVertices: Int,
        relations: Int, incompleteRelations: Int, missingNodes: Int
    ) {
        self.nodes = nodes
        self.taggedNodes = taggedNodes
        self.nodesOutsideBox = nodesOutsideBox
        self.ways = ways
        self.wayVertices = wayVertices
        self.relations = relations
        self.incompleteRelations = incompleteRelations
        self.missingNodes = missingNodes
    }

    /// Summarizes an extract.
    public init(_ extract: OSMExtract) {
        self.init(
            nodes: extract.nodes.count,
            taggedNodes: extract.nodes.filter { !$0.tags.isEmpty }.count,
            nodesOutsideBox: extract.nodes.filter { !extract.boundingBox.contains($0.coordinate) }.count,
            ways: extract.ways.count,
            wayVertices: extract.ways.reduce(0) { $0 + $1.nodeIDs.count },
            relations: extract.relations.count,
            incompleteRelations: extract.relations.filter { !$0.isComplete }.count,
            missingNodes: extract.missingNodeCount
        )
    }
}
