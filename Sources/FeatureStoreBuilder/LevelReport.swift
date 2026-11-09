/// What building one level block read and wrote.
public struct LevelReport: Sendable, Equatable {
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
    /// Area chains that did not close and were closed with a straight line; their feature is marked incomplete.
    public var openAreaChains = 0
    /// Lines whose pieces were joined into one.
    public var linesJoined = 0

    /// Creates an empty report.
    public init() {}
}
