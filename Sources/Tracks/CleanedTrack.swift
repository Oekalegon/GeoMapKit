/// A recorded track cut into unbroken stretches, with the places where it was cut (see ``TrackCleaner``).
public struct CleanedTrack: Sendable, Equatable {
    /// The stretches in order, each with at least two points.
    public let segments: [TrackSegment]
    /// The cuts, in order.
    public let breaks: [TrackBreak]
    /// How many points were merged into the point of a stop (all points of a cluster but the first).
    public let mergedPoints: Int
    /// How many stretches were left out because they had a single point left (a bad fix between two cuts, or the end of a recording that
    /// was resumed).
    public let droppedSegments: Int

    /// Creates a cleaned track.
    public init(segments: [TrackSegment], breaks: [TrackBreak], mergedPoints: Int, droppedSegments: Int) {
        self.segments = segments
        self.breaks = breaks
        self.mergedPoints = mergedPoints
        self.droppedSegments = droppedSegments
    }
}
