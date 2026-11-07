/// An OSM relation: a group of objects with roles and tags.
///
/// Relations have no geometry of their own. Multipolygons are assembled into
/// areas later; the member list is always kept (see "Relations" in
/// `docs/design/architecture.md`).
public struct OSMRelation: Hashable, Sendable {
    /// The OSM relation ID.
    public let id: Int64

    /// The members, in file order.
    public let members: [OSMMember]

    /// All tags of the relation. Nothing is dropped, except that keys differing only in Unicode
    /// normalization collapse into one (see `architecture.md`, question 46).
    public let tags: [String: String]

    /// Creates a relation.
    ///
    /// - Parameters:
    ///   - id: The OSM relation ID.
    ///   - members: The members, in order.
    ///   - tags: The tags of the relation.
    public init(id: Int64, members: [OSMMember], tags: [String: String]) {
        self.id = id
        self.members = members
        self.tags = tags
    }
}
