/// One line or ring of a feature.
public struct GeometryPart: Hashable, Sendable {
    /// The vertices, in absolute 1e-7 degree coordinates. A ring repeats its first
    /// vertex at the end, as OSM closed ways do.
    public var points: [PackedPoint]

    /// Runs of edges that the cell clip created along a cell border. Edge `i` runs
    /// from `points[i]` to `points[i + 1]`. The renderer fills these edges but does
    /// not stroke them.
    public var artificialEdges: [Range<Int>]

    public init(points: [PackedPoint], artificialEdges: [Range<Int>] = []) {
        self.points = points
        self.artificialEdges = artificialEdges
    }
}
