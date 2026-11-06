/// The kind of object a relation member refers to.
public enum OSMMemberType: Int, Hashable, Sendable {
    /// A node (a point).
    case node = 0

    /// A way (a line or ring of nodes).
    case way = 1

    /// Another relation.
    case relation = 2
}
