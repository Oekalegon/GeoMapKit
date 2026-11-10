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
    /// The drawing order, lowest first. A style file allows 0 through 99: bridges are drawn 100 layers above their class
    /// and tunnels on layer 15, so the layers of the classes stay below 100.
    public var layer: Int
    /// The layer on which the stroke's casing is drawn, or `nil` to draw it directly under the stroke.
    ///
    /// Classes that cross at the same level (a motorway and a residential street) give their casing the
    /// same layer, below every one of their strokes. The renderer then draws all outlines first and all
    /// road fills on top, so at a crossing the fills run through each other's outlines and the outlines
    /// join into one shape instead of one road's outline cutting across the other.
    public var casingLayer: Int?
    /// How bridges of the class are drawn, or `nil` to draw them like the rest of the class (see ``BridgeStyle``).
    public var bridge: BridgeStyle?
    /// How tunnels of the class are drawn, or `nil` to draw them like the rest of the class (see ``TunnelStyle``).
    public var tunnel: TunnelStyle?
    /// Different looks for some of the features of the class, tried in order (see ``StyleVariant``). Empty for one look.
    public var variants: [StyleVariant] = []

    /// Creates a class style.
    public init(
        fill: FillStyle? = nil, stroke: StrokeStyle? = nil, point: PointStyle? = nil, label: LabelStyle? = nil,
        visibleZoom: ClosedRange<Double> = 0...24, layer: Int, casingLayer: Int? = nil, bridge: BridgeStyle? = nil,
        tunnel: TunnelStyle? = nil
    ) {
        self.bridge = bridge
        self.tunnel = tunnel
        self.fill = fill
        self.stroke = stroke
        self.point = point
        self.label = label
        self.visibleZoom = visibleZoom
        self.layer = layer
        self.casingLayer = casingLayer
    }
}
