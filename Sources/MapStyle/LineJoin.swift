/// How two segments of a stroked line meet.
public enum LineJoin: Sendable, Equatable {
    /// A sharp corner (limited by the renderer's miter limit).
    case miter
    /// A rounded corner.
    case round
    /// A flattened corner.
    case bevel
}
