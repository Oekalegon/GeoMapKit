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
    /// The zoom range in which this label is shown. It can be narrower than the class's own `visibleZoom`, so a
    /// name appears later than its shape.
    public var visibleZoom: ClosedRange<Double>
    /// For the name of a line: on the line, or beside it. Names of points and areas ignore it.
    public var placement: LabelPlacement
    /// The smallest area, in square points on the screen, that an area must cover to get this label: a pond is not named, a lake is.
    /// It only applies to areas; 0 names every area.
    public var minimumArea: Double

    /// Creates a label style.
    public init(
        size: ZoomValue<Double>, color: MapColor, haloColor: MapColor = .white, haloWidth: Double = 2,
        priority: Int = 0,
        visibleZoom: ClosedRange<Double> = 0...24,
        placement: LabelPlacement = .onLine,
        minimumArea: Double = 0
    ) {
        self.size = size
        self.color = color
        self.haloColor = haloColor
        self.haloWidth = haloWidth
        self.priority = priority
        self.visibleZoom = visibleZoom
        self.placement = placement
        self.minimumArea = minimumArea
    }
}
