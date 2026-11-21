import TrackOverlays
import TrackStorage

/// One picture of a heat map: the overlay, and what it shows.
public struct HeatMapFrame: Sendable {
    /// The overlay to give to the map.
    public let overlay: HeatMapOverlay
    /// The months that are counted in it, or `nil` when the store has no activity to name a month by.
    public let months: ClosedRange<TrackMonth>?
    /// The number of buckets (10 m pieces of ways) with a count, not counting the traces.
    public let bucketCount: Int
    /// The number of lines off the paths (traces of the store) with a count: where activities left the lines of the map.
    public let traceCount: Int
    /// The highest count of a bucket or a trace, 0 for an empty frame.
    public let maximumCount: Int
    /// The number of ways of the map in the area; 0 means the area has no lines (outside the map, or a place with no paths).
    public let waysInArea: Int
    /// Whether the frame counts only some categories or months. A frame of a time-lapse always does (it shows a month or a window of
    /// months), so an empty one need not mean that the counts are elsewhere: see ``emptiness(databaseCountedPieces:)``.
    public let isFiltered: Bool
}
