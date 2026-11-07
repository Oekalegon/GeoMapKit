import FeatureStore
import GeoCore
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
    /// The box the user asked for. The cut (``cut``) used a larger box made of whole cells that contains it.
    public let requestedArea: BoundingBox
    /// The extent of the cells that were written, read back from the file header.
    public let storedExtent: BoundingBox
    /// Sizes and counts read back from the written file.
    public let statistics: FeatureStoreFile.Statistics
    /// What the builder stored, skipped and counted.
    public let report: BuildReport

    /// Creates a report from its parts.
    public init(
        profile: BuildProfile, outputName: String, cut: CutReport, buildTime: Duration, requestedArea: BoundingBox,
        storedExtent: BoundingBox,
        statistics: FeatureStoreFile.Statistics, report: BuildReport
    ) {
        self.profile = profile
        self.outputName = outputName
        self.cut = cut
        self.buildTime = buildTime
        self.requestedArea = requestedArea
        self.storedExtent = storedExtent
        self.statistics = statistics
        self.report = report
    }

    /// How far the file falls short of the box that was asked for.
    public var shortfall: ExtentShortfall { ExtentShortfall(requested: requestedArea, stored: storedExtent) }
}
