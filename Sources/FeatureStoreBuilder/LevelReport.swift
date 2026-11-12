/// What building one level block read and wrote.
public struct LevelReport: Sendable, Equatable, CustomStringConvertible {
    /// Source cells that exist in the area that was read.
    public var cellsRead = 0
    /// Features read (pieces of the visible classes).
    public var featuresRead = 0
    /// Features written (a feature in more than one level cell counts once per cell).
    public var featuresWritten = 0
    /// Vertices written.
    public var verticesWritten = 0
    /// Level cells written.
    public var cellsWritten = 0
    /// Line chains and area rings dropped for being smaller than three pixels.
    public var droppedAsSmall = 0
    /// River courses whose water area was left out of the level, written as river lines.
    public var riverNamesAsLines = 0
    /// Area chains that did not close and were closed with a straight line; they are written as an incomplete feature (outline only).
    public var openAreaChains = 0
    /// Lines whose pieces were joined into one.
    public var linesJoined = 0
    /// Ends of area chains that were joined to a start within a pixel of the top zoom of the level.
    public var joinedBySnap = 0
    /// Ends of area chains that were joined to a start on the same line of a cell border.
    public var joinedAlongBorder = 0
    /// Area chains closed on themselves, because the gap between their two ends is small against the chain.
    public var closedBySmallGap = 0

    /// Creates an empty report.
    public init() {}

    public var description: String {
        "\(cellsRead) source cells, \(featuresRead) features read; \(featuresWritten) features, \(verticesWritten) vertices in \(cellsWritten) cells written; "
            + "\(linesJoined) lines joined, \(droppedAsSmall) dropped as small, \(joinedBySnap + joinedAlongBorder) area ends joined (\(joinedAlongBorder) along a border), \(closedBySmallGap) chains closed on a small gap, "
            + "\(openAreaChains) open area chains"
    }
}
