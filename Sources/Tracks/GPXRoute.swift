/// An `rte` of a GPX file: a planned route. Its points have no times, so it is never an activity.
public struct GPXRoute: Sendable, Equatable {
    /// The name, if the file gives one.
    public var name: String?
    /// The points in order.
    public var points: [TrackPoint]

    /// Creates a route.
    public init(name: String? = nil, points: [TrackPoint]) {
        self.name = name
        self.points = points
    }

    /// The route as a ``Route``.
    ///
    /// - Throws: ``RouteError`` if there are no points, a point is not valid, or the route crosses the antimeridian.
    public func route() throws -> Route {
        try Route(name: name, points: points)
    }
}
