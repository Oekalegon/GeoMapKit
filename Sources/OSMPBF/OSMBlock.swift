/// The decoded contents of one PBF data block.
///
/// A block holds a few thousand objects at most, so it is decoded, handed to the
/// caller and released. This keeps memory bounded for files of any size.
public struct OSMBlock: Sendable {
    /// The nodes in the block, in file order.
    public internal(set) var nodes: [OSMNode]

    /// The ways in the block, in file order.
    public internal(set) var ways: [OSMWay]

    /// The relations in the block, in file order.
    public internal(set) var relations: [OSMRelation]

    /// Creates a block.
    ///
    /// - Parameters:
    ///   - nodes: The nodes.
    ///   - ways: The ways.
    ///   - relations: The relations.
    public init(nodes: [OSMNode] = [], ways: [OSMWay] = [], relations: [OSMRelation] = []) {
        self.nodes = nodes
        self.ways = ways
        self.relations = relations
    }
}
