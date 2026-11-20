import GeoCore

/// A line off the paths of the map with a count: a trace of the store, as the heat map draws it.
///
/// Where the ways of a map carry a count for each piece of 10 m, a trace (a stretch that was run across open ground) carries one count
/// for its whole length; the heat map draws it on the same scale (``HeatMapScale``).
public struct HeatMapTraceLine: Sendable, Equatable {
    /// The positions in order, at least two.
    public let coordinates: [Coordinate]
    /// How often it was used, by the measure of the heat map.
    public let count: Int

    /// Creates a trace line.
    public init(coordinates: [Coordinate], count: Int) {
        self.coordinates = coordinates
        self.count = count
    }
}
