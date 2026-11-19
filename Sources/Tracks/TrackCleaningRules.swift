/// What counts as a break, a jump or a stop when a recorded track is cleaned (see ``TrackCleaner``).
///
/// The numbers are for any sport. A sport that is fast or slow (a descent on a bike, a walk) can choose its own; the package does not know
/// the sport, so the app does.
public struct TrackCleaningRules: Sendable, Equatable {
    /// The time between two points, in seconds, above which the recording is taken as having stopped. A gap of this length with a move of
    /// more than ``gapDistance`` is a break (the route between is not known); one with less is a stop.
    public var maximumGap: Double
    /// The distance, in metres, that a point may move during a gap of more than ``maximumGap`` and still be the same stretch (a pause).
    public var gapDistance: Double
    /// The speed between two points, in metres per second, above which the second is a jump (a bad fix, or a recording that was resumed
    /// somewhere else). Only steps of more than ``jumpDistance`` count, so a short step in a short time is not a jump.
    public var maximumSpeed: Double
    /// The shortest step, in metres, that can be a jump by speed (a short step in a short time is not a jump, however fast it looks).
    public var jumpDistance: Double
    /// The step, in metres, between two points with no time above which the second is a jump.
    public var jumpDistanceUntimed: Double
    /// The distance, in metres, from the first point of a cluster within which later points are the same place (the runner stands still,
    /// and the fix wanders).
    public var stationaryRadius: Double
    /// The shortest time, in seconds, that a cluster must last to be reported as a stop.
    public var minimumStop: Double

    /// Creates rules; negative values are made 0.
    public init(
        maximumGap: Double = 120, gapDistance: Double = 100, maximumSpeed: Double = 30, jumpDistance: Double = 50, jumpDistanceUntimed: Double = 1_000, stationaryRadius: Double = 4,
        minimumStop: Double = 10
    ) {
        self.maximumGap = max(maximumGap, 0)
        self.gapDistance = max(gapDistance, 0)
        self.maximumSpeed = max(maximumSpeed, 0)
        self.jumpDistance = max(jumpDistance, 0)
        self.jumpDistanceUntimed = max(jumpDistanceUntimed, 0)
        self.stationaryRadius = max(stationaryRadius, 0)
        self.minimumStop = max(minimumStop, 0)
    }

    /// A gap of 2 minutes with a move of 100 m, a speed of 30 m/s (108 km/h) over steps of 50 m, a step of 1,000 m between points with no time, a stationary
    /// radius of 4 m, and a stop of 10 s.
    public static let standard = TrackCleaningRules()
}
