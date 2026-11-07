import MapStyle

/// A name that wants a place on the map, before collision handling.
public struct LabelCandidate: Sendable, Equatable {
    /// The OSM ID, to draw one label per feature.
    public var objectID: Int64
    /// The text.
    public var text: String
    /// The point the label belongs to: the position of a point feature, or the centre of an area.
    public var anchor: ScreenPoint
    /// The radius in points of the point symbol next to the label, 0 for an area.
    public var symbolRadius: Double
    /// The font size in points at the current zoom.
    public var fontSize: Double
    /// The label style (colours, halo, priority).
    public var style: LabelStyle
    /// The size of the area the label belongs to in square points, used to pick the largest piece of an area.
    public var extent: Double

    /// Creates a candidate.
    public init(
        objectID: Int64, text: String, anchor: ScreenPoint, symbolRadius: Double, fontSize: Double, style: LabelStyle,
        extent: Double = 0
    ) {
        self.objectID = objectID
        self.text = text
        self.anchor = anchor
        self.symbolRadius = symbolRadius
        self.fontSize = fontSize
        self.style = style
        self.extent = extent
    }
}
