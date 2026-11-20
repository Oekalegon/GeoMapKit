/// How often a bucket of a way was used, as the heat map takes it: a number of the measure the app chose (the activities, or the
/// passes, of the track store).
public struct HeatMapBucket: Sendable, Equatable {
    /// The OSM id of the way.
    public let wayID: Int64
    /// The bucket along the way: it covers `bucket * bucketLength` to `(bucket + 1) * bucketLength` metres from the start of the way.
    public let bucket: Int
    /// The count; 0 or less is not drawn.
    public let count: Int

    /// Creates a bucket.
    public init(wayID: Int64, bucket: Int, count: Int) {
        self.wayID = wayID
        self.bucket = bucket
        self.count = count
    }

    /// The length of a bucket along a way, in metres. It is the length that the track store counts in.
    public static let bucketLength = 10.0
}
