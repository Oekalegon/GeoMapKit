import MapStyle

/// How an overlay line is drawn: a colour and a width in screen points, so it looks the same at every zoom.
public struct OverlayLineStyle: Sendable, Equatable {
    /// A wider line under the line, in another colour, that makes it stand out from the map (a route with a white edge).
    public struct Casing: Sendable, Equatable {
        /// The casing colour, with its own opacity.
        public var color: MapColor
        /// How much wider the casing is than the line on each side, in points.
        public var extraPoints: Double

        /// Creates a casing.
        public init(color: MapColor, extraPoints: Double) {
            self.color = color
            self.extraPoints = extraPoints
        }
    }

    /// The line colour; its alpha is the opacity of the line.
    public var color: MapColor
    /// The width in points.
    public var width: Double
    /// The dash pattern in points (on, off, on, off ...); empty for a solid line.
    public var dash: [Double]
    /// The casing, or `nil` for none.
    public var casing: Casing?

    /// Creates a line style. Ends and corners are round.
    public init(color: MapColor, width: Double, dash: [Double] = [], casing: Casing? = nil) {
        self.color = color
        self.width = width
        self.dash = dash
        self.casing = casing
    }
}
