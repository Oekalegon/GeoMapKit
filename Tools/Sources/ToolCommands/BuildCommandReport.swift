import FeatureStore
import FeatureStoreBuilder

/// The result of cutting an area and building a feature store file from it.
public struct BuildCommandReport: Sendable {
    /// The copy that was built.
    public let profile: BuildProfile
    /// The name of the written file.
    public let outputName: String
    /// The cut that came first.
    public let cut: CutReport
    /// How long the build took, not counting the cut or the write.
    public let buildTime: Duration
    /// Sizes and counts read back from the written file.
    public let statistics: FeatureStoreFile.Statistics
    /// What the builder stored, skipped and counted.
    public let report: BuildReport

    /// Creates a report from its parts.
    public init(
        profile: BuildProfile, outputName: String, cut: CutReport, buildTime: Duration,
        statistics: FeatureStoreFile.Statistics, report: BuildReport
    ) {
        self.profile = profile
        self.outputName = outputName
        self.cut = cut
        self.buildTime = buildTime
        self.statistics = statistics
        self.report = report
    }
}
