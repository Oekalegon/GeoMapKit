/// A relation in an extract, with whether all of its members are present.
public struct ExtractedRelation: Hashable, Sendable {
    /// The relation as read from the file; its member list is complete even if
    /// some members are missing from the extract.
    public let relation: OSMRelation

    /// Whether every way member and every node member is present in the extract.
    ///
    /// Members that are relations are ignored: they are kept when they touch the
    /// area, and a parent relation does not need them to be drawn.
    public let isComplete: Bool

    /// Creates an extracted relation.
    ///
    /// - Parameters:
    ///   - relation: The relation.
    ///   - isComplete: Whether all way and node members are in the extract.
    public init(relation: OSMRelation, isComplete: Bool) {
        self.relation = relation
        self.isComplete = isComplete
    }
}
