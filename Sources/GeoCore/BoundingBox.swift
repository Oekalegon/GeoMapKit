/// A rectangle in latitude and longitude, in degrees.
///
/// The box does not cross the antimeridian: `west` must not exceed `east`
/// (see the geometry conventions in `docs/design/architecture.md`). Like
/// ``Coordinate`` the initializer does not validate; use ``isValid``.
public struct BoundingBox: Hashable, Sendable, Codable {
    /// The southern edge, in degrees latitude.
    public let south: Double

    /// The western edge, in degrees longitude.
    public let west: Double

    /// The northern edge, in degrees latitude.
    public let north: Double

    /// The eastern edge, in degrees longitude.
    public let east: Double

    /// Creates a bounding box without validating it.
    ///
    /// - Parameters:
    ///   - south: The southern edge, in degrees latitude.
    ///   - west: The western edge, in degrees longitude.
    ///   - north: The northern edge, in degrees latitude.
    ///   - east: The eastern edge, in degrees longitude.
    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    /// Whether all edges are finite and in range, `south <= north` and `west <= east`.
    public var isValid: Bool {
        guard [south, west, north, east].allSatisfy(\.isFinite) else { return false }
        return (-90...90).contains(south) && (-90...90).contains(north)
            && (-180...180).contains(west) && (-180...180).contains(east)
            && south <= north && west <= east
    }

    /// Whether a coordinate lies inside the box. The edges are inclusive.
    ///
    /// - Parameter coordinate: The position to test.
    /// - Returns: `true` if the coordinate is within the box. Always `false` for a
    ///   non-finite coordinate.
    public func contains(_ coordinate: Coordinate) -> Bool {
        (south...north).contains(coordinate.latitude) && (west...east).contains(coordinate.longitude)
    }
}
