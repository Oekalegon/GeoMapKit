import Foundation
import GeoCore

/// A stretch of a track that is on no line of the map: where the runner left the paths and ran across open ground, a place the map does
/// not have yet.
///
/// The line runs from the last point on a line before the stretch to the first point on a line after it, so that it is continuous with
/// the matched stretches on both sides. The traces of the store (``TraceBuilder``) are made from these.
public struct OffTrackLine: Sendable, Equatable {
    /// The positions in order, at least two.
    public let coordinates: [Coordinate]
    /// When the stretch began.
    public let start: Date
    /// The time the stretch took, in seconds.
    public let elapsed: TimeInterval
    /// The recorded length of the stretch itself, in metres (the joining lines at its ends are not in it).
    public let length: Double

    /// Creates a line; `nil` for fewer than two coordinates.
    public init?(coordinates: [Coordinate], start: Date, elapsed: TimeInterval, length: Double) {
        guard coordinates.count >= 2 else { return nil }
        self.coordinates = coordinates
        self.start = start
        self.elapsed = max(elapsed, 0)
        self.length = length
    }
}
