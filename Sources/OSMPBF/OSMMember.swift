/// A member of an OSM relation: a reference to another object with a role.
public struct OSMMember: Hashable, Sendable {
    /// The kind of object referred to.
    public let type: OSMMemberType

    /// The ID of the referred object.
    public let id: Int64

    /// The role of the member in the relation, such as `outer` or `inner`. May be empty.
    public let role: String

    /// Creates a relation member.
    ///
    /// - Parameters:
    ///   - type: The kind of object referred to.
    ///   - id: The ID of the referred object.
    ///   - role: The role of the member; empty if none.
    public init(type: OSMMemberType, id: Int64, role: String) {
        self.type = type
        self.id = id
        self.role = role
    }
}
