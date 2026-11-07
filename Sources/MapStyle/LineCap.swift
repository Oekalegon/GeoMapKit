/// How a stroked line ends.
public enum LineCap: String, Sendable, Equatable {
    /// The line stops at the end point.
    case butt
    /// A half circle past the end point.
    case round
    /// A half square past the end point.
    case square
}
