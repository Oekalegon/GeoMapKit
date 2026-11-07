/// A relation stored losslessly: tags plus the ordered member list with roles.
public struct StoredRelation: Hashable, Sendable {
    public var id: Int64
    /// True if members were missing from the source data.
    public var isIncomplete: Bool
    public var tags: [StoredTag]
    public var members: [StoredRelationMember]

    public init(id: Int64, isIncomplete: Bool = false, tags: [StoredTag], members: [StoredRelationMember]) {
        self.id = id
        self.isIncomplete = isIncomplete
        self.tags = tags
        self.members = members
    }
}
