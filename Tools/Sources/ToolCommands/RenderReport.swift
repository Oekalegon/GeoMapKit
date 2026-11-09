import FeatureStore

/// What the `render` command did, for a store file or for the manifest of a set of blocks.
public struct RenderReport: Equatable, Sendable {
    /// The PNG file name.
    public let outputName: String
    /// The image size in pixels.
    public let pixelWidth: Int
    /// The image height in pixels.
    public let pixelHeight: Int
    /// The PNG size in bytes.
    public let pngBytes: Int
    /// The band that was read.
    public let band: ZoomBand
    /// The number of store cells read.
    public let cellCount: Int
    /// The number of draw steps with features.
    public let stepCount: Int
    /// The number of features in the scene.
    public let featureCount: Int
    /// The time to build the scene (decode, join, project).
    public let sceneTime: Duration
    /// The time to draw and encode.
    public let drawTime: Duration
    /// The rule table version the store was built with, if it is older than the one this tool builds with; otherwise `nil`.
    public let outdatedRuleTable: Int?
    /// The rule table version this tool builds with, set when ``outdatedRuleTable`` is.
    public let currentRuleTable: Int?

    /// Creates a report.
    public init(
        outputName: String, pixelWidth: Int, pixelHeight: Int, pngBytes: Int, band: ZoomBand, cellCount: Int, stepCount: Int,
        featureCount: Int, sceneTime: Duration, drawTime: Duration, outdatedRuleTable: Int? = nil, currentRuleTable: Int? = nil
    ) {
        self.outdatedRuleTable = outdatedRuleTable
        self.currentRuleTable = currentRuleTable
        self.outputName = outputName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pngBytes = pngBytes
        self.band = band
        self.cellCount = cellCount
        self.stepCount = stepCount
        self.featureCount = featureCount
        self.sceneTime = sceneTime
        self.drawTime = drawTime
    }
}
