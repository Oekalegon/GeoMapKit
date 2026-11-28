import Foundation

/// Web Mercator maths for placing a map over an area: where the middle of a box is on the map, and how far to zoom so that it fits a view.
///
/// Zoom levels are fractional and measured in 256-point tiles, as in ``TileID`` and the map view.
public enum WebMercator {
    /// The size of a tile in points.
    public static let tileSize = 256.0

    /// The place of a latitude on the map, from 0 at the north edge of the world to 1 at the south edge.
    ///
    /// - Parameter latitude: In degrees; limited to the Web Mercator range (``TileID/maximumLatitude``).
    public static func y(latitude: Double) -> Double {
        let limit = TileID.maximumLatitude
        let radians = min(max(latitude, -limit), limit) * .pi / 180
        return (1 - asinh(tan(radians)) / .pi) / 2
    }

    /// The latitude in degrees of a place on the map, the inverse of ``y(latitude:)``.
    ///
    /// - Parameter y: From 0 (north edge) to 1 (south edge).
    public static func latitude(y: Double) -> Double {
        atan(sinh(.pi * (1 - 2 * y))) * 180 / .pi
    }

    /// The middle of a box as it appears on the map: the longitude halfway and the latitude where the map's own vertical middle is, which
    /// is a little north of the middle in degrees.
    ///
    /// - Parameter box: The area.
    public static func center(of box: BoundingBox) -> Coordinate {
        let middle = (y(latitude: box.south) + y(latitude: box.north)) / 2
        return Coordinate(latitude: latitude(y: middle), longitude: (box.west + box.east) / 2)
    }

    /// The zoom at which a box fills a view, with room round it.
    ///
    /// - Parameters:
    ///   - box: The area to show.
    ///   - width: The width of the view in points.
    ///   - height: The height of the view in points.
    ///   - padding: The share of each side of the view left empty round the box, 0 to under 0.5.
    ///   - range: The lowest and highest zoom to return; a box with no size gives the highest zoom that is at most 15.
    /// - Returns: The fractional zoom, inside `range`.
    public static func zoom(
        fitting box: BoundingBox, width: Double, height: Double, padding: Double = 0.15, range: ClosedRange<Double> = 2...17
    ) -> Double {
        let padding = min(max(padding, 0), 0.49)
        let usableWidth = max(width, 1) * (1 - 2 * padding)
        let usableHeight = max(height, 1) * (1 - 2 * padding)
        let longitudeShare = (box.east - box.west) / 360
        let latitudeShare = abs(y(latitude: box.south) - y(latitude: box.north))
        guard longitudeShare > 1e-9 || latitudeShare > 1e-9 else { return min(max(15, range.lowerBound), range.upperBound) }
        let byWidth = longitudeShare > 1e-9 ? log2(usableWidth / (tileSize * longitudeShare)) : .infinity
        let byHeight = latitudeShare > 1e-9 ? log2(usableHeight / (tileSize * latitudeShare)) : .infinity
        return min(max(min(byWidth, byHeight), range.lowerBound), range.upperBound)
    }
}
