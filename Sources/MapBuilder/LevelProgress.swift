/// How far a `build-levels` run has come: what a progress bar shows.
///
/// A level block is the unit; the parts of a block that is running are not known, so the bar moves when a block is done. Blocks that are
/// already up to date count as finished from the start.
public struct LevelProgress: Sendable, Equatable {
    /// The level blocks of the run, over all the levels.
    public var total: Int
    /// The level blocks that are done: built, up to date or found empty.
    public var finished: Int
    /// The level blocks being built now.
    public var running: Int
    /// The time since the first level block was started.
    public var elapsed: Duration
    /// The time left, or `nil` while too few blocks are done to say.
    public var remaining: Duration?

    /// The part done, from 0 to 1; 1 for a run without blocks.
    public var fraction: Double { total > 0 ? min(Double(finished) / Double(total), 1) : 1 }

    /// Creates a progress value.
    public init(total: Int, finished: Int, running: Int, elapsed: Duration, remaining: Duration? = nil) {
        self.total = total
        self.finished = finished
        self.running = running
        self.elapsed = elapsed
        self.remaining = remaining
    }
}
