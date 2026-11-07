/// A position on the map view, in points, with the origin at the top-left corner and y growing downwards.
public struct ScreenPoint: Hashable, Sendable {
    /// Distance from the left edge, in points.
    public var x: Double
    /// Distance from the top edge, in points.
    public var y: Double

    /// Creates a screen point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
