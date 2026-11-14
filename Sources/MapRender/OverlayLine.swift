/// A line of an overlay, in screen points.
public struct OverlayLine: Sendable, Equatable {
    /// The vertices in order, at least two.
    public var points: [ScreenPoint]
    /// How it is drawn.
    public var style: OverlayLineStyle

    /// Creates a line.
    public init(points: [ScreenPoint], style: OverlayLineStyle) {
        self.points = points
        self.style = style
    }
}
