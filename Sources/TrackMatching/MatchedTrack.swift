/// A recorded track after cleaning and matching to a ``LineNetwork``.
///
/// What the app needs for a category of the activity (road, trail, track: see the design note on categories) is in the terrain figures:
/// how much of the track lay on each class of line and how much on none.
public struct MatchedTrack: Sendable, Equatable {
    /// The matched segments, in the order of the cleaned track.
    public let segments: [MatchedSegment]

    /// Creates a matched track.
    public init(segments: [MatchedSegment]) { self.segments = segments }

    /// The recorded length, in metres.
    public var length: Double { segments.reduce(0) { $0 + $1.length } }

    /// The length on each feature class of the lines, in metres.
    public var lengthByClass: [UInt8: Double] {
        var total: [UInt8: Double] = [:]
        for stretch in segments.flatMap(\.stretches) { for (key, value) in stretch.lengthByClass { total[key, default: 0] += value } }
        return total
    }

    /// The length that is on no line (the raw stretches), in metres.
    public var unmatchedLength: Double {
        segments.flatMap(\.stretches).filter { !$0.isMatched }.reduce(0) { $0 + $1.length }
    }
}
