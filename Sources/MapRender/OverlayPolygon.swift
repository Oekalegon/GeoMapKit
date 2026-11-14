import MapStyle

/// An area of an overlay, in screen points.
public struct OverlayPolygon: Sendable, Equatable {
    /// The rings (the outer ring and any holes), filled by the even-odd rule. Each has at least three vertices; a ring is closed by
    /// the renderer.
    public var rings: [[ScreenPoint]]
    /// The fill colour, with its own opacity, or `nil` for no fill.
    public var fill: MapColor?
    /// The outline, or `nil` for none.
    public var outline: OverlayLineStyle?

    /// Creates a polygon.
    public init(rings: [[ScreenPoint]], fill: MapColor?, outline: OverlayLineStyle? = nil) {
        self.rings = rings
        self.fill = fill
        self.outline = outline
    }
}
