import Foundation

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

    /// The mean length of one degree of latitude, in kilometres (6371.0088 km mean radius).
    private static let kilometresPerDegree = 6371.0088 * .pi / 180

    /// The smallest box that contains a circle around a coordinate.
    ///
    /// Uses a local approximation: one degree of latitude is about 111.195 km (from the 6371.0088 km mean Earth radius), and the
    /// longitude extent is widened by `1 / cos(latitude)`. The box is square on the
    /// ground and slightly larger than the circle, never smaller.
    ///
    /// - Parameters:
    ///   - center: The centre of the circle.
    ///   - radiusKilometres: The radius in kilometres; must be positive and finite.
    /// - Returns: The box, or `nil` if the radius or centre is invalid, or the box
    ///   would reach a pole or cross the antimeridian (both unsupported).
    public static func around(_ center: Coordinate, radiusKilometres: Double) -> BoundingBox? {
        guard center.isValid, radiusKilometres.isFinite, radiusKilometres > 0 else { return nil }
        let latitudeExtent = radiusKilometres / kilometresPerDegree
        let cosine = cos(center.latitude * .pi / 180)
        guard cosine > 1e-6 else { return nil }
        let longitudeExtent = latitudeExtent / cosine
        let box = BoundingBox(
            south: center.latitude - latitudeExtent, west: center.longitude - longitudeExtent,
            north: center.latitude + latitudeExtent, east: center.longitude + longitudeExtent
        )
        return box.isValid ? box : nil
    }
}
