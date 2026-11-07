/// A position in OSM's native unit: degrees times 10^7, as 32-bit integers.
public struct PackedPoint: Hashable, Sendable {
    /// Longitude in 1e-7 degrees.
    public var longitude: Int32
    /// Latitude in 1e-7 degrees.
    public var latitude: Int32

    public init(longitude: Int32, latitude: Int32) {
        self.longitude = longitude
        self.latitude = latitude
    }
}
