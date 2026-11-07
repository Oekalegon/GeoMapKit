/// How the `name` of a feature is labelled.
public struct LabelStyle: Sendable, Equatable {
    /// The font size in points.
    public var size: ZoomValue<Double>
    /// The text colour.
    public var color: MapColor
    /// The colour of the outline that keeps the text legible on any background.
    public var haloColor: MapColor
    /// The halo width in points, 0 for none.
    public var haloWidth: Double
    /// Higher priority labels are placed first and win a collision.
    public var priority: Int

    /// Creates a label style.
    public init(
        size: ZoomValue<Double>, color: MapColor, haloColor: MapColor = .white, haloWidth: Double = 2,
        priority: Int = 0
    ) {
        self.size = size
        self.color = color
        self.haloColor = haloColor
        self.haloWidth = haloWidth
        self.priority = priority
    }
}
