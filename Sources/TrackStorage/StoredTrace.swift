import GeoCore

/// A trace as the store gives it: the line that several activities ran across open ground, with how often it was used.
public struct StoredTrace: Sendable, Equatable {
    /// The id of the trace. It is private to the store (not an OSM id); see ``TrackTrace/id``.
    public let id: Int64
    /// The line.
    public let coordinates: [Coordinate]
    /// The length of the line, in metres.
    public let length: Double
    /// The number of activities that ran along the trace, each once.
    public let activities: Int
    /// The number of times it was run along: every stretch that ran along it counts, so ten laps are ten.
    public let passes: Int

    /// Creates a trace.
    public init(id: Int64, coordinates: [Coordinate], length: Double, activities: Int, passes: Int) {
        self.id = id
        self.coordinates = coordinates
        self.length = length
        self.activities = activities
        self.passes = passes
    }
}
