/// When a map shows its scale ruler.
///
/// There is no timer in the map for this: the view moves from "moving" to "idle" with the gestures and asks ``isShown(moving:idleFor:)``
/// once the delay is over.
public enum ScaleRulerVisibility: Sendable, Equatable {
    /// The ruler is never shown.
    case hidden
    /// The ruler is always shown.
    case always
    /// The ruler shows while the map is panned, zoomed or turned, and goes away `delay` after the last change.
    case afterMoving(delay: Duration = .seconds(2))

    /// Whether the ruler is shown.
    ///
    /// - Parameters:
    ///   - moving: Whether the map is being panned, zoomed or turned now.
    ///   - idleFor: How long ago the last change was; it counts only when `moving` is `false`.
    public func isShown(moving: Bool, idleFor: Duration) -> Bool {
        switch self {
        case .hidden: false
        case .always: true
        case .afterMoving(let delay): moving || idleFor < delay
        }
    }

    /// The time after which a ruler that shows after moving goes away, or `nil` for the other cases.
    public var delay: Duration? {
        if case .afterMoving(let delay) = self { delay } else { nil }
    }
}
