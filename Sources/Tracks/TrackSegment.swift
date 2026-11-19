/// One unbroken stretch of a cleaned track.
public struct TrackSegment: Sendable, Equatable {
    /// The points in order, at least two. A point where the runner stood still stands for all the points of that stop: its position is
    /// the mean of them and its time the time of the first.
    public let points: [TrackPoint]
    /// The stops in this stretch, in order.
    public let stops: [TrackStop]

    /// Creates a segment.
    public init(points: [TrackPoint], stops: [TrackStop] = []) {
        self.points = points
        self.stops = stops
    }
}
