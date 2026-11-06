/// A geographic position in degrees on the WGS 84 ellipsoid.
///
/// Latitude is the first component, longitude the second, matching the usual
/// geographic convention. This is the opposite of the `(x, y)` order used for
/// projected coordinates, so convert deliberately.
///
/// The initializer does **not** validate its input, and decoding does not
/// either: NaN and out-of-range values are accepted so that a single bad
/// coordinate does not make every call site handle an error. Consumers must cope
/// with them. ``TileID/containing(_:zoom:)`` returns `nil` for non-finite input,
/// clamps latitude and wraps longitude. Use ``isValid`` where a strictly valid
/// position is required, for example when reading untrusted files.
public struct Coordinate: Hashable, Sendable, Codable {
    /// Latitude in degrees, positive north. Valid range is -90 to 90.
    public let latitude: Double

    /// Longitude in degrees, positive east. Valid range is -180 to 180.
    public let longitude: Double

    /// Creates a coordinate without validating it.
    ///
    /// - Parameters:
    ///   - latitude: Latitude in degrees, positive north.
    ///   - longitude: Longitude in degrees, positive east.
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Whether both components are finite and within their valid ranges
    /// (latitude -90 to 90, longitude -180 to 180).
    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}
