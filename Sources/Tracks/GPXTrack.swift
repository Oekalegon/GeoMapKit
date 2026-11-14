/// A `trk` of a GPX file: a recorded track, in segments (a new segment starts where the recording was paused or lost).
public struct GPXTrack: Sendable, Equatable {
    /// The name, if the file gives one.
    public var name: String?
    /// The type of activity the file says (`type`, for example `running`), if any.
    public var type: String?
    /// The segments, each a list of points in order. Empty segments are not kept.
    public var segments: [[TrackPoint]]

    /// Creates a track.
    public init(name: String? = nil, type: String? = nil, segments: [[TrackPoint]]) {
        self.name = name
        self.type = type
        self.segments = segments
    }

    /// All points of all segments, in order.
    public var points: [TrackPoint] { segments.flatMap { $0 } }

    /// The track as a ``Route``: the segments are joined in one polyline, and ``Route/segmentStarts`` says where each began.
    ///
    /// - Throws: ``RouteError`` if there are no points, a point is not valid, or the track crosses the antimeridian.
    public func route() throws -> Route {
        var starts: [Int] = []
        var count = 0
        for segment in segments where !segment.isEmpty {
            starts.append(count)
            count += segment.count
        }
        return try Route(name: name, points: points, segmentStarts: starts)
    }

    /// The track as an activity, if it is one.
    ///
    /// - Parameters:
    ///   - id: The id of the activity; by default one made from the start time, the number of points and the first position, so the same
    ///     activity read twice (or from two files) gets the same id.
    ///   - rules: What makes a track an activity.
    /// - Throws: ``NotAnActivity`` with the reason.
    public func activity(id: String? = nil, rules: ActivityRules = .standard) throws -> ActivityTrack {
        try ActivityTrack(id: id, name: name, kind: type, points: points, rules: rules)
    }
}
