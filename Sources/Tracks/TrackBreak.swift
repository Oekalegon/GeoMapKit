/// A place where a track was cut: the points on the two sides are not one line.
public struct TrackBreak: Sendable, Equatable {
    /// Why the track was cut.
    public enum Reason: Sendable, Equatable {
        /// The recording stopped for longer than the rules allow and went on somewhere else: the seconds and the metres between the points.
        case gap(seconds: Double, metres: Double)
        /// The step is faster than the rules allow: the speed in metres per second and the metres. Also a step in no time.
        case speed(metresPerSecond: Double, metres: Double)
        /// Points with no time are further apart than the rules allow: the metres.
        case jump(metres: Double)
    }

    /// The index, in the points that were given, of the last point before the cut.
    public let afterIndex: Int
    /// Why.
    public let reason: Reason

    /// Creates a break.
    public init(afterIndex: Int, reason: Reason) {
        self.afterIndex = afterIndex
        self.reason = reason
    }
}
