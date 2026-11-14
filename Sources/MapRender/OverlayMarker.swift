import MapStyle

/// A round marker of an overlay: a dot or a ring at a screen position. Its size is in points, so it looks the same at every zoom.
public struct OverlayMarker: Sendable, Equatable {
    /// The centre.
    public var center: ScreenPoint
    /// The radius of the fill in points.
    public var radius: Double
    /// The fill colour.
    public var fill: MapColor
    /// The outline colour, or `nil` for none.
    public var outline: MapColor?
    /// The outline width in points, drawn outside the radius.
    public var outlineWidth: Double

    /// Creates a marker.
    public init(center: ScreenPoint, radius: Double, fill: MapColor, outline: MapColor? = nil, outlineWidth: Double = 0) {
        self.center = center
        self.radius = radius
        self.fill = fill
        self.outline = outline
        self.outlineWidth = outlineWidth
    }
}
