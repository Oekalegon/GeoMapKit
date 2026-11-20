/// Why legs could not be made.
public enum TrackLegsError: Error, Equatable, Sendable {
    /// The matched track and the cleaned track have a different number of segments, so they are not the same track.
    case segmentCountsDiffer(matched: Int, cleaned: Int)
}
