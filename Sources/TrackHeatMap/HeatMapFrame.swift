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
}
