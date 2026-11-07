import FeatureStore

/// One piece of a ring inside one cell.
struct ClippedRing: Equatable {
    /// The vertices, closed (the first vertex is repeated at the end).
    var points: [PackedPoint]
    /// Runs of edges created by the clip along the cell border. Edge `i` runs from `points[i]` to `points[i + 1]`.
    var artificialEdges: [Range<Int>]

    /// The ring as geometry for the file format.
    var part: GeometryPart { GeometryPart(points: points, artificialEdges: artificialEdges) }
}
