import OSMPBF

/// How long one stage of a cut took, and the memory in use when it started.
public struct PassTiming: Equatable, Sendable {
    /// The stage.
    public let pass: AreaCutter.Pass

    /// Time from the start of this stage to the start of the next (or the end).
    public let duration: Duration

    /// The peak heap footprint so far, in bytes, when the stage started.
    public let peakMemoryAtStart: Int64

    public init(pass: AreaCutter.Pass, duration: Duration, peakMemoryAtStart: Int64) {
        self.pass = pass
        self.duration = duration
        self.peakMemoryAtStart = peakMemoryAtStart
    }
}
