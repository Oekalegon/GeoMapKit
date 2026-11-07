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

    /// All tags of the relation, with nothing dropped, ordered by the UTF-8 bytes of their keys.
    ///
    /// Identical keys, which OSM forbids, are all kept in file order. Keys that differ only in Unicode
    /// normalization stay separate (see `architecture.md`, question 46).
    public let orderedTags: [OSMTag]

    /// The tags as a dictionary.
    ///
    /// A convenience only: it is lossy, because a `[String: String]` treats keys that differ only in Unicode
    /// normalization as the same key, and a repeated key keeps its last value. Use ``orderedTags`` where
    /// nothing may be lost.
    public var tags: [String: String] { OSMTag.dictionary(orderedTags) }

    /// Creates a relation.
    ///
    /// - Parameters:
    ///   - id: The OSM relation ID.
    ///   - members: The members, in order.
    ///   - tags: The tags of the relation.
    public init(id: Int64, members: [OSMMember], tags: [String: String]) {
        self.id = id
        self.members = members
        self.orderedTags = OSMTag.sortedByKeyBytes(tags.map { OSMTag(key: $0.key, value: $0.value) })
    }

    /// Creates a relation with an ordered tag list. The tags are put in key byte order; nothing is merged.
    ///
    /// - Parameters:
    ///   - id: The OSM relation ID.
    ///   - members: The members, in order.
    ///   - orderedTags: The tags.
    public init(id: Int64, members: [OSMMember], orderedTags: [OSMTag]) {
        self.id = id
        self.members = members
        self.orderedTags = OSMTag.sortedByKeyBytes(orderedTags)
    }
}
