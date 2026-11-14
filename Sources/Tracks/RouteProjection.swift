import GeoCore

/// The nearest point of a ``Route`` to a position, with the progress along the route there.
public struct RouteProjection: Sendable, Equatable {
    /// The point on the route line.
    public let coordinate: Coordinate
    /// The distance along the route to that point, in metres from the start.
    public let distanceAlong: Double
    /// The distance from the position that was projected to that point, in metres.
    public let distance: Double
    /// The index of the point at the start of the step of the route that the projection lies on.
    public let stepIndex: Int

    /// Creates a projection.
    public init(coordinate: Coordinate, distanceAlong: Double, distance: Double, stepIndex: Int) {
        self.coordinate = coordinate
        self.distanceAlong = distanceAlong
        self.distance = distance
        self.stepIndex = stepIndex
    }
}
