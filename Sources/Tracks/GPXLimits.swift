/// How much of a GPX file is read before it is refused. A GPX file is untrusted input; the limits keep a hostile or broken file from
/// using all the memory.
public struct GPXLimits: Sendable, Equatable {
    /// The largest file in bytes.
    public var maximumBytes: Int
    /// The most points in all, over tracks, routes and waypoints.
    public var maximumPoints: Int

    /// Creates limits.
    public init(maximumBytes: Int = 50_000_000, maximumPoints: Int = 1_000_000) {
        self.maximumBytes = maximumBytes
        self.maximumPoints = maximumPoints
    }

    /// 50 MB and one million points: more than a day of one-second fixes, many times over.
    public static let standard = GPXLimits()
}
