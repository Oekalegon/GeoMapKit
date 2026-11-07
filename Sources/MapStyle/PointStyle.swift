/// How a point feature is drawn: a filled circle with an optional outline.
public struct PointStyle: Sendable, Equatable {
    /// The circle radius in points.
    public var radius: ZoomValue<Double>
    /// The fill colour.
    public var color: ZoomValue<MapColor>
    /// The outline colour.
    public var outlineColor: MapColor
    /// The outline width in points, 0 for none.
    public var outlineWidth: Double

    /// Creates a point style.
    public init(
        radius: ZoomValue<Double>, color: ZoomValue<MapColor>, outlineColor: MapColor = .white,
        outlineWidth: Double = 1
    ) {
        self.radius = radius
        self.color = color
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
    }
}
