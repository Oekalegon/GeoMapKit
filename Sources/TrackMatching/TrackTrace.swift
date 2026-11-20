import GeoCore

/// A line that several activities ran across open ground, made from their off-track stretches.
public struct TrackTrace: Sendable, Equatable {
    /// The id. It is private to the store (not an OSM id) and is made from the stretch that started the trace, so it stays the same
    /// while that stretch is in the store.
    public let id: Int64
    /// The line, in the order of the first stretch that made it, with the vertices moved to the average of the stretches that joined it.
    public let coordinates: [Coordinate]
    /// The length of the line, in metres.
    public let length: Double
    /// The stretches that made or joined the trace: the `source` that was given for each, once for each time it ran along the trace.
    public let sources: [Int64]

    /// Creates a trace.
    public init(id: Int64, coordinates: [Coordinate], length: Double, sources: [Int64]) {
        self.id = id
        self.coordinates = coordinates
        self.length = length
        self.sources = sources
    }
}
