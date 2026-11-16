import Foundation

/// How far a `build-region` run has come: what a progress bar, in the terminal or in an app, shows.
///
/// Blocks that no source file covers are not counted. Blocks that are already up to date count as finished from the start.
public struct BlockProgress: Sendable, Equatable {
    /// The blocks of the run that have a file to build or keep.
    public var total: Int
    /// The blocks that are done: built, up to date or found empty.
    public var finished: Int
    /// The blocks being cut and built now.
    public var running: Int
    /// The parts of the running blocks that are done, added up (2.5 for four blocks that are on average 62 % done).
    public var partial: Double
    /// The blocks built in this run (not the ones that were up to date).
    public var built: Int
    /// The time since the first block was started.
    public var elapsed: Duration
    /// The time left, or `nil` until the work done in this run is about one block's worth.
    public var remaining: Duration?

    /// The part done, from 0 to 1; 1 for a run without blocks. The running blocks count by the part they have done.
    public var fraction: Double { total > 0 ? min((Double(finished) + partial) / Double(total), 1) : 1 }

    /// Creates a progress value.
    public init(
        total: Int, finished: Int, running: Int, built: Int, elapsed: Duration, remaining: Duration? = nil, partial: Double = 0
    ) {
        self.total = total
        self.finished = finished
        self.running = running
        self.partial = partial
        self.built = built
        self.elapsed = elapsed
        self.remaining = remaining
    }

    /// The time left, from the pace of the blocks built so far (wall-clock time per block, so blocks that run at once count).
    ///
    /// - Parameters:
    ///   - left: The blocks that are not finished.
    ///   - finishedInRun: The blocks finished so far in this run: built, or found to have nothing to store (blocks that were
    ///     already up to date are not counted, they cost no time).
    ///   - elapsed: The time since the first block was started.
    ///   - minimumBuilt: The fewest finished blocks that give an estimate; the first blocks of a run say little.
    /// - Returns: The estimate, or `nil` when fewer than `minimumBuilt` blocks are finished or nothing is left.
    public static func estimateRemaining(left: Int, finishedInRun: Int, elapsed: Duration, minimumBuilt: Int = 4) -> Duration? {
        guard left > 0, finishedInRun >= max(minimumBuilt, 1) else { return nil }
        return elapsed * left / finishedInRun
    }

    /// The time left, from the work done so far, counting the parts of the running blocks.
    ///
    /// - Parameters:
    ///   - left: The blocks that are not finished, less the parts of the running blocks that are done.
    ///   - doneInRun: The blocks finished in this run, with the parts of the running ones (blocks that were up to date cost no time and
    ///     are not counted).
    ///   - elapsed: The time since the first block was started.
    ///   - minimumDone: The least work, in blocks, that gives an estimate.
    /// - Returns: The estimate, or `nil` when less than `minimumDone` is done or nothing is left.
    public static func estimateRemaining(left: Double, doneInRun: Double, elapsed: Duration, minimumDone: Double = 1) -> Duration? {
        guard left > 0, doneInRun >= max(minimumDone, 0.01) else { return nil }
        return elapsed * (left / doneInRun)
    }
}
