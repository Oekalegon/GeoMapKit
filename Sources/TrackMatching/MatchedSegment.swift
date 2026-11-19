/// One unbroken stretch of a recorded track (a ``TrackSegment``) after matching: matched and raw stretches in order.
public struct MatchedSegment: Sendable, Equatable {
    /// The stretches in order. They cover all the points of the segment.
    public let stretches: [MatchedStretch]

    /// Creates a matched segment.
    public init(stretches: [MatchedStretch]) { self.stretches = stretches }

    /// The recorded length of the segment, in metres.
    public var length: Double { stretches.reduce(0) { $0 + $1.length } }
    /// The length of the matched stretches, in metres.
    public var matchedLength: Double { stretches.filter(\.isMatched).reduce(0) { $0 + $1.length } }
}
