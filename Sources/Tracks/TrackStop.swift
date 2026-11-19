/// A place where the runner stood still: the points of the stop are one point of the cleaned track, and this says for how long.
public struct TrackStop: Sendable, Equatable {
    /// The index of the point in its ``TrackSegment``.
    public let pointIndex: Int
    /// How long it lasted, in seconds, from the first point of the cluster to the last.
    public let seconds: Double

    /// Creates a stop.
    public init(pointIndex: Int, seconds: Double) {
        self.pointIndex = pointIndex
        self.seconds = seconds
    }
}
