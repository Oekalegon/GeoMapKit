/// The look of one feature class.
///
/// Which parts apply depends on the geometry: ``fill`` on areas, ``stroke`` on lines
/// and on area outlines, ``point`` on points, ``label`` on any feature with a name.
public struct ClassStyle: Sendable, Equatable {
    /// The area fill, if any.
    public var fill: FillStyle?
    /// The line (or outline) style, if any.
    public var stroke: StrokeStyle?
    /// The point symbol, if any.
    public var point: PointStyle?
    /// The label, if any.
    public var label: LabelStyle?
    /// The zoom range in which the class is drawn. Outside it the class is hidden.
    ///
    /// This is on top of the store's bands: a band decides which geometry exists,
    /// this range decides what the style shows.
    public var visibleZoom: ClosedRange<Double>
    /// The drawing order, lowest first.
    public var layer: Int

    /// Creates a class style.
    public init(
        fill: FillStyle? = nil, stroke: StrokeStyle? = nil, point: PointStyle? = nil, label: LabelStyle? = nil,
        visibleZoom: ClosedRange<Double> = 0...24, layer: Int
    ) {
        self.fill = fill
        self.stroke = stroke
        self.point = point
        self.label = label
        self.visibleZoom = visibleZoom
        self.layer = layer
    }
}
