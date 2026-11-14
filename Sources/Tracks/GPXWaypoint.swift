/// A `wpt` of a GPX file: a named place, not part of any track.
public struct GPXWaypoint: Sendable, Equatable {
    /// The name, if the file gives one.
    public var name: String?
    /// The description (`desc`), if any.
    public var details: String?
    /// The position, with the height and time if the file has them.
    public var point: TrackPoint

    /// Creates a waypoint.
    public init(name: String? = nil, details: String? = nil, point: TrackPoint) {
        self.name = name
        self.details = details
        self.point = point
    }
}
