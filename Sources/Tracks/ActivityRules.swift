/// What makes a recorded track an activity, one that can go into a heat map: its points have times, in order.
public struct ActivityRules: Sendable, Equatable {
    /// The smallest share of the points that must have a time, from 0 to 1.
    public var minimumTimedFraction: Double
    /// The fewest points with a time.
    public var minimumPoints: Int
    /// How far a time may go back, in seconds, before the track is refused. A smaller step back is set to the time before it.
    public var timeTolerance: Double

    /// Creates rules.
    public init(minimumTimedFraction: Double = 0.9, minimumPoints: Int = 2, timeTolerance: Double = 2) {
        self.minimumTimedFraction = minimumTimedFraction
        self.minimumPoints = minimumPoints
        self.timeTolerance = timeTolerance
    }

    /// 90 % of the points with a time, at least 2 points, and a step back of up to 2 seconds forgiven.
    public static let standard = ActivityRules()
}
