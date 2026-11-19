import GeoCore

/// A part of a track that is either laid on the lines of the network or left as it was recorded.
///
/// A stretch can be very short: one wobble away from the lines, or a change between two ways that share no vertex, leaves a raw stretch of
/// a fix or two between two matched ones. An app that counts stretches should ignore those below a length it chooses.
public struct MatchedStretch: Sendable, Equatable {
    /// The points of the track segment that this stretch covers, as indexes into its points. The stretches of a segment follow each
    /// other and cover all its points.
    public let pointRange: Range<Int>
    /// Whether the stretch is on the lines of the network. A stretch that is not is the raw line (open ground, ice, a beach, or a place
    /// the map does not have).
    public let isMatched: Bool
    /// How sure the match is, from 0 to 1, and 0 for a raw stretch. This is a first measure, from how near the fixes are to the lines
    /// and how well the route agrees with the steps; it is checked against real tracks before anything is built on it.
    public let confidence: Double
    /// The line to draw: the fixes laid on the network and the nodes of the route between them for a matched stretch, the raw points for
    /// a raw one.
    public let coordinates: [Coordinate]
    /// The edges of the network that the stretch follows, in order (indexes into ``LineNetwork/edges``); empty for a raw stretch.
    public let edges: [Int]
    /// The length that was recorded in this stretch, in metres, as the sum of the straight steps between its points.
    public let length: Double
    /// For a matched stretch, the part of ``length`` on each feature class of the lines (the step to a point counts for the class of the
    /// line that point was laid on); empty for a raw stretch.
    public let lengthByClass: [UInt8: Double]

    /// Creates a stretch.
    public init(
        pointRange: Range<Int>, isMatched: Bool, confidence: Double, coordinates: [Coordinate], edges: [Int], length: Double,
        lengthByClass: [UInt8: Double]
    ) {
        self.pointRange = pointRange
        self.isMatched = isMatched
        self.confidence = confidence
        self.coordinates = coordinates
        self.edges = edges
        self.length = length
        self.lengthByClass = lengthByClass
    }
}
