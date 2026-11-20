/// How often a trace was run along in one month: what the traces of a time-lapse are made from.
public struct MonthlyTraceCount: Sendable, Equatable {
    /// The id of the trace (``StoredTrace/id``).
    public let traceID: Int64
    /// The month in which the activities started.
    public let month: TrackMonth
    /// The number of activities that ran along the trace in that month, each once.
    public let activities: Int
    /// The number of times it was run along in that month.
    public let passes: Int

    /// Creates a count.
    public init(traceID: Int64, month: TrackMonth, activities: Int, passes: Int) {
        self.traceID = traceID
        self.month = month
        self.activities = activities
        self.passes = passes
    }
}
