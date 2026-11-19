import GeoCore

/// The nearest point of an edge of a ``LineNetwork`` to a position.
public struct EdgeProjection: Sendable, Equatable {
    /// The index of the edge in ``LineNetwork/edges``.
    public let edge: Int
    /// The point on the edge.
    public let coordinate: Coordinate
    /// How far along the edge the point lies, from 0 at ``LineNetwork/Edge/from`` to 1 at ``LineNetwork/Edge/to``.
    public let fraction: Double
    /// The distance from the position to the point, in metres.
    public let distance: Double

    /// Creates a projection.
    public init(edge: Int, coordinate: Coordinate, fraction: Double, distance: Double) {
        self.edge = edge
        self.coordinate = coordinate
        self.fraction = fraction
        self.distance = distance
    }
}
