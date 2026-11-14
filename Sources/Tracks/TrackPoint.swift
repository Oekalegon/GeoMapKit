import Foundation
import GeoCore

/// One position of a track or route: where, and optionally how high and when.
public struct TrackPoint: Sendable, Equatable, Hashable {
    /// The position.
    public var coordinate: Coordinate
    /// The height in metres above the geoid as the file gives it, or `nil`. It is kept as data; the kit has no terrain model, so
    /// it computes no ascent from it.
    public var elevation: Double?
    /// When the position was recorded, or `nil` for a point with no time (a planned route has none).
    public var time: Date?

    /// Creates a point.
    ///
    /// - Parameters:
    ///   - coordinate: The position.
    ///   - elevation: The height in metres, if known.
    ///   - time: The time of the fix, if known.
    public init(coordinate: Coordinate, elevation: Double? = nil, time: Date? = nil) {
        self.coordinate = coordinate
        self.elevation = elevation
        self.time = time
    }

    /// Creates a point from latitude and longitude in degrees.
    public init(latitude: Double, longitude: Double, elevation: Double? = nil, time: Date? = nil) {
        self.init(coordinate: Coordinate(latitude: latitude, longitude: longitude), elevation: elevation, time: time)
    }
}
