import Foundation

/// The address of a tile in the standard Web Mercator tile grid.
///
/// At zoom `z` the world is divided into `2^z` columns and rows. Column `x`
/// grows eastwards from the antimeridian and row `y` grows **southwards** from
/// the northern edge of the map. The map covers latitudes of about ±85.0511°.
///
/// The feature store uses this grid at one fixed storage zoom (z13), see
/// `docs/design/architecture.md`.
public struct TileID: Hashable, Sendable, Codable {
    /// The largest latitude, in degrees, that Web Mercator can represent.
    public static let maximumLatitude = 85.0511287798066

    /// The highest zoom level supported, chosen so `2^zoom` fits comfortably in `Int`.
    public static let maximumZoom = 30

    /// The zoom level, 0 for the whole world in one tile.
    public let zoom: Int

    /// The column, from 0 at the antimeridian eastwards.
    public let x: Int

    /// The row, from 0 at the northern edge southwards.
    public let y: Int

    private enum CodingKeys: String, CodingKey {
        case zoom, x, y
    }

    /// Decodes a tile address and rejects values outside the grid.
    ///
    /// Tile addresses arrive from manifests and from the Watch's area requests,
    /// so they are treated as untrusted input.
    ///
    /// - Throws: `DecodingError.dataCorrupted` if the address lies outside the grid.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let zoom = try container.decode(Int.self, forKey: .zoom)
        let x = try container.decode(Int.self, forKey: .x)
        let y = try container.decode(Int.self, forKey: .y)
        guard let tile = TileID(zoom: zoom, x: x, y: y) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Tile \(zoom)/\(x)/\(y) is outside the grid"
            ))
        }
        self = tile
    }

    /// Creates a tile address, or returns `nil` if it lies outside the grid.
    ///
    /// - Parameters:
    ///   - zoom: The zoom level, from 0 to ``maximumZoom``.
    ///   - x: The column, from 0 to `2^zoom - 1`.
    ///   - y: The row, from 0 to `2^zoom - 1`.
    public init?(zoom: Int, x: Int, y: Int) {
        guard (0...Self.maximumZoom).contains(zoom) else { return nil }
        let count = 1 << zoom
        guard (0..<count).contains(x), (0..<count).contains(y) else { return nil }
        self.zoom = zoom
        self.x = x
        self.y = y
    }

    /// Returns the tile that contains a coordinate.
    ///
    /// Latitudes beyond ``maximumLatitude`` are clamped to the edge of the map,
    /// and longitudes are wrapped into -180 to 180. Longitude +180 is treated
    /// as -180 and falls in column 0, so a bounding box that ends at +180 is not
    /// supported.
    ///
    /// A coordinate on a tile border is assigned to one of the two adjacent
    /// tiles. Which one is subject to floating-point rounding, so do not use a
    /// computed tile corner (``northWest``, ``southEast``) to identify a tile;
    /// use a point inside it. Only exactly representable borders, such as the
    /// equator and the prime meridian, are assigned to the east and south tile.
    ///
    /// - Parameters:
    ///   - coordinate: The position in degrees.
    ///   - zoom: The zoom level, from 0 to ``maximumZoom``.
    /// - Returns: The containing tile, or `nil` if `zoom` is out of range or the
    ///   coordinate is not finite.
    public static func containing(_ coordinate: Coordinate, zoom: Int) -> TileID? {
        guard (0...maximumZoom).contains(zoom),
              coordinate.latitude.isFinite, coordinate.longitude.isFinite else { return nil }

        let count = Double(1 << zoom)
        let latitude = min(max(coordinate.latitude, -maximumLatitude), maximumLatitude)
        var longitude = (coordinate.longitude + 180).truncatingRemainder(dividingBy: 360)
        if longitude < 0 { longitude += 360 }

        let fractionX = longitude / 360
        let fractionY = (1 - asinh(tan(latitude * .pi / 180)) / .pi) / 2

        let x = min(Int(fractionX * count), Int(count) - 1)
        let y = min(max(Int(fractionY * count), 0), Int(count) - 1)
        return TileID(zoom: zoom, x: x, y: y)
    }

    /// The north-west corner of the tile.
    ///
    /// Passing this back to ``containing(_:zoom:)`` may return a neighbouring
    /// tile because of floating-point rounding.
    public var northWest: Coordinate {
        Coordinate(
            latitude: Self.latitude(forRow: Double(y), zoom: zoom),
            longitude: Double(x) / Double(1 << zoom) * 360 - 180
        )
    }

    /// The south-east corner of the tile.
    public var southEast: Coordinate {
        Coordinate(
            latitude: Self.latitude(forRow: Double(y + 1), zoom: zoom),
            longitude: Double(x + 1) / Double(1 << zoom) * 360 - 180
        )
    }

    private static func latitude(forRow row: Double, zoom: Int) -> Double {
        let n = Double.pi * (1 - 2 * row / Double(1 << zoom))
        return atan(sinh(n)) * 180 / .pi
    }
}
