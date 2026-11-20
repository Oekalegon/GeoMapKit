import TrackOverlays
import TrackStorage

/// One picture of a heat map: the overlay, and what it shows.
public struct HeatMapFrame: Sendable {
    /// The overlay to give to the map.
    public let overlay: HeatMapOverlay
    /// The months that are counted in it, or `nil` when the store has no activity to name a month by.
    public let months: ClosedRange<TrackMonth>?
    /// The number of buckets (10 m pieces of ways) with a count.
    public let bucketCount: Int
    /// The highest count of a bucket, 0 for an empty frame.
    public let maximumCount: Int
    /// The number of ways of the map in the area. When it is 0 the area has no lines (it is outside the map, or a place with no paths);
    /// when it is not 0 and the frame is empty, the counts of the store are somewhere else.
    public let waysInArea: Int
}
