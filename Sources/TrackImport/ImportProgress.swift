/// How far a run has come.
public struct ImportProgress: Sendable, Equatable {
    /// The requests that are done (read, and their activities added, skipped or failed).
    public let finished: Int
    /// All requests of the run.
    public let total: Int
    /// The request that was finished last.
    public let source: String
}
