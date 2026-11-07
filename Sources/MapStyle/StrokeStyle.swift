/// How a line, or the outline of an area, is drawn.
public struct StrokeStyle: Sendable, Equatable {
    /// A darker band under the line that makes it stand out from the fills (a road casing).
    public struct Casing: Sendable, Equatable {
        /// The casing colour.
        public var color: ZoomValue<MapColor>
        /// The extra width on each side of the line, in points.
        public var extraPoints: Double

        /// Creates a casing.
        public init(color: ZoomValue<MapColor>, extraPoints: Double) {
            self.color = color
            self.extraPoints = extraPoints
        }
    }

    /// The line colour.
    public var color: ZoomValue<MapColor>
    /// The line width.
    public var width: LineWidth
    /// The dash pattern in points (on, off, on, off ...), empty for a solid line.
    public var dash: [Double]
    /// The line ends.
    public var cap: LineCap
    /// The corners.
    public var join: LineJoin
    /// The casing, if any.
    public var casing: Casing?

    /// Creates a stroke style.
    public init(
        color: ZoomValue<MapColor>, width: LineWidth, dash: [Double] = [], cap: LineCap = .round,
        join: LineJoin = .round, casing: Casing? = nil
    ) {
        self.color = color
        self.width = width
        self.dash = dash
        self.cap = cap
        self.join = join
        self.casing = casing
    }
}
