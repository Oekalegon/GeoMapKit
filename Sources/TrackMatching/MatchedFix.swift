/// A recorded fix that the matcher laid on a line, with the place in the edges of its stretch.
///
/// The fixes of a stretch are the ones the matcher used (not closer than ``MatchingRules/minimumSpacing`` to the one before), and they
/// are what gives the edges of a stretch their times: between two fixes the track went along the edges from one to the other.
public struct MatchedFix: Sendable, Equatable {
    /// The index of the point in the points of the segment.
    public let point: Int
    /// The place in ``MatchedStretch/edges`` of the edge that the fix lies on. The edges from the edge of one fix to the edge of the next
    /// are the route between them. Two fixes can have the same place (both on one edge).
    public let edgeIndex: Int
    /// How far along the edge the fix lies, from 0 at ``LineNetwork/Edge/from`` to 1 at ``LineNetwork/Edge/to``.
    public let fraction: Double

    /// Creates a fix.
    public init(point: Int, edgeIndex: Int, fraction: Double) {
        self.point = point
        self.edgeIndex = edgeIndex
        self.fraction = fraction
    }
}
