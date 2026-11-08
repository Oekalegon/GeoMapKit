/// The regions whose files are needed for an area.
public struct RegionSelection: Equatable, Sendable {
    /// The regions, the one that covers most of the area first. This is the order to give the files to `AreaCutter`: an object
    /// that several files hold is taken from the first.
    public let regions: [SourceRegion]
    /// The share of the area, from 0 to 1, that lies inside the outline of one of the regions. What is left is sea, or ground
    /// that the simplified outlines do not cover; a share well below 1 for an area on land is worth a look.
    public let coveredShare: Double

    /// Creates a selection.
    public init(regions: [SourceRegion], coveredShare: Double) {
        self.regions = regions
        self.coveredShare = coveredShare
    }
}
