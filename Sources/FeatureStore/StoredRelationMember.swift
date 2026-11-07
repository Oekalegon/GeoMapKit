/// A member of a stored relation.
public struct StoredRelationMember: Hashable, Sendable {
    public var type: StoredObjectType
    public var id: Int64
    /// String ID of the role.
    public var role: UInt32

    public init(type: StoredObjectType, id: Int64, role: UInt32) {
        self.type = type
        self.id = id
        self.role = role
    }
}
