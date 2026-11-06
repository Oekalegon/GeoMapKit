/// A geographic position in degrees on the WGS 84 ellipsoid.
///
/// Latitude is the first component, longitude the second, matching the usual
/// geographic convention. This is the opposite of the `(x, y)` order used for
/// projected coordinates, so convert deliberately.
public struct Coordinate: Hashable, Sendable, Codable {
    /// Latitude in degrees, positive north. Valid range is -90 to 90.
    public var latitude: Double

    /// Longitude in degrees, positive east. Valid range is -180 to 180.
    public var longitude: Double

    /// Creates a coordinate.
    ///
    /// - Parameters:
    ///   - latitude: Latitude in degrees, positive north.
    ///   - longitude: Longitude in degrees, positive east.
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
