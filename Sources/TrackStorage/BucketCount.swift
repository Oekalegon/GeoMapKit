import TrackMatching

/// How often a bucket of a way was used: the unit of the heat map.
public struct BucketCount: Sendable, Equatable {
    /// The length of a bucket along a way, in metres.
    public static let length = TrackLeg.bucketLength

    /// The OSM id of the way.
    public let wayID: Int64
    /// The bucket along the way: it covers `bucket * 10` to `(bucket + 1) * 10` metres from the start of the way.
    public let bucket: Int
    /// The number of activities that used the bucket, each once however often it passed.
    public let activities: Int
    /// The number of passes: every traversal counts, so ten laps are ten and a there-and-back is two.
    public let passes: Int

    /// Creates a count.
    public init(wayID: Int64, bucket: Int, activities: Int, passes: Int) {
        self.wayID = wayID
        self.bucket = bucket
        self.activities = activities
        self.passes = passes
    }

    /// The start of the bucket, in metres from the start of the way.
    public var startMetre: Double { Double(bucket) * Self.length }
}
