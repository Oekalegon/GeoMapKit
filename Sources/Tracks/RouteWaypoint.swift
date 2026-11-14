import GeoCore

/// A place on a ``Route``: a named point with its distance along the route.
public struct RouteWaypoint: Sendable, Equatable {
    /// The name, if any.
    public var name: String?
    /// The position of the waypoint itself, which can be a little off the route line.
    public var coordinate: Coordinate
    /// The distance along the route to the nearest point of the line, in metres from the start.
    public var distanceAlong: Double
    /// Whether the runner must pass it. A route follower will not skip past a required waypoint when it rejoins the route. Nothing is
    /// required by default: a waypoint of a GPX file is a point of interest until the caller says otherwise.
    public var isRequired: Bool

    /// Creates a waypoint.
    public init(name: String? = nil, coordinate: Coordinate, distanceAlong: Double, isRequired: Bool = false) {
        self.name = name
        self.coordinate = coordinate
        self.distanceAlong = distanceAlong
        self.isRequired = isRequired
    }
}
