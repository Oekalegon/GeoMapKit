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

    /// The matched stretches that are sure enough and long enough to count in statistics of the lines.
    ///
    /// - Parameters:
    ///   - minimumConfidence: The least confidence, from 0 to 1 (see ``MatchedStretch/confidence``).
    ///   - minimumLength: The least recorded length of a stretch, in metres.
    public func countedStretches(minimumConfidence: Double = 0.5, minimumLength: Double = 100) -> [MatchedStretch] {
        stretches.filter { $0.isMatched && $0.confidence >= minimumConfidence && $0.length >= minimumLength }
    }
}
