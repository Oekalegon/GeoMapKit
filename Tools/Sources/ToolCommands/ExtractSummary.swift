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
    /// The memory used by the extract's data, in bytes.
    public let memoryBytes: Int

    public init(
        nodes: Int, taggedNodes: Int, nodesOutsideBox: Int, ways: Int, wayVertices: Int,
        relations: Int, incompleteRelations: Int, missingNodes: Int, memoryBytes: Int
    ) {
        self.nodes = nodes
        self.taggedNodes = taggedNodes
        self.nodesOutsideBox = nodesOutsideBox
        self.ways = ways
        self.wayVertices = wayVertices
        self.relations = relations
        self.incompleteRelations = incompleteRelations
        self.missingNodes = missingNodes
        self.memoryBytes = memoryBytes
    }

    /// Summarizes an extract, reading the columns without building any object.
    public init(_ extract: OSMExtract) {
        let nodes = extract.nodes
        self.init(
            nodes: nodes.count,
            taggedNodes: nodes.indices.filter { nodes.hasTags(at: $0) }.count,
            nodesOutsideBox: nodes.indices.filter { !extract.boundingBox.contains(nodes.coordinate(at: $0)) }.count,
            ways: extract.ways.count,
            wayVertices: extract.ways.vertexCount,
            relations: extract.relations.count,
            incompleteRelations: extract.relations.indices.filter { !extract.relations.isComplete(at: $0) }.count,
            missingNodes: extract.missingNodeCount,
            memoryBytes: extract.memoryBytes
        )
    }
}
