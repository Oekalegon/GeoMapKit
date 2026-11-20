/// What a run did.
public struct ImportReport: Sendable, Equatable {
    /// Activities that were not in the store.
    public var added = 0
    /// Activities that were in the store and were made again (another category, another map, other rules).
    public var replaced = 0
    /// Activities that were in the store already, in the same category, on the same map and with the same rules.
    public var skipped = 0
    /// Activities handled in each category (added, replaced or skipped).
    public var categories: [String: Int] = [:]
    /// What failed: a source that cannot be read, an activity that could not be matched or added.
    public var failures: [ImportFailure] = []
    /// What in a source is no activity (a planned route, a track with no times): not an error, but not imported.
    public var notActivities: [ImportFailure] = []
    /// Whether the run was stopped before all requests were done; what was done stays in the store.
    public var cancelled = false

    /// Creates an empty report.
    public init() {}

    /// All activities handled.
    public var handled: Int { added + replaced + skipped }
}
