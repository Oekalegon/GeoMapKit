/// What a heat map counts.
public enum HeatMapMeasure: Sendable, Equatable, CaseIterable {
    /// The number of activities that used a bucket, each once however often it passed.
    case activities
    /// The number of passes: every traversal, so ten laps are ten.
    case passes
}
