/// What a heat map counts, for a bucket of a way and for a trace (a line off the paths) alike.
public enum HeatMapMeasure: Sendable, Equatable, CaseIterable {
    /// The number of activities that used a bucket, each once however often it passed.
    case activities
    /// The number of passes: every traversal, so ten laps are ten.
    case passes
}
