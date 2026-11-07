import Foundation
import GeoCore
import FeatureStore

/// The part of the world on screen: a centre, a zoom level and a size in points.
///
/// The projection is Web Mercator with 256-point tiles, so at zoom `z` the world is
/// `256 × 2^z` points wide. Zoom is fractional. North is up; rotation is not supported
/// (see "Renderer scope" in the architecture document).
///
/// Screen positions are computed relative to the centre in `Double`, so there is no
/// precision loss at high zoom levels where absolute world coordinates are large.
public struct MapViewport: Sendable, Equatable {
    /// The size, in points, of a tile at an integer zoom level.
    public static let tileSize = 256.0

    /// The coordinate in the middle of the view.
    public let center: Coordinate
    /// The (fractional) zoom level, 0 for a 256-point world.
    public let zoom: Double
    /// The width of the view in points.
    public let width: Double
    /// The height of the view in points.
    public let height: Double

    /// Creates a viewport.
    ///
    /// The latitude is clamped to the Web Mercator range, the longitude is wrapped into -180...180, the zoom is
    /// limited to 0 through ``TileID/maximumZoom``, and sizes below 0 become 0. Non-finite values fall back to
    /// 0° N, 0° E, zoom 0 and size 0.
    ///
    /// - Parameters:
    ///   - center: The coordinate in the middle of the view, in degrees.
    ///   - zoom: The fractional zoom level.
    ///   - width: The view width in points.
    ///   - height: The view height in points.
    public init(center: Coordinate, zoom: Double, width: Double, height: Double) {
        let latitude = center.latitude.isFinite ? min(max(center.latitude, -TileID.maximumLatitude), TileID.maximumLatitude) : 0
        var longitude = center.longitude.isFinite ? (center.longitude + 180).truncatingRemainder(dividingBy: 360) : 180
        if longitude < 0 { longitude += 360 }
        self.center = Coordinate(latitude: latitude, longitude: longitude - 180)
        self.zoom = zoom.isFinite ? min(max(zoom, 0), Double(TileID.maximumZoom)) : 0
        self.width = width.isFinite ? max(width, 0) : 0
        self.height = height.isFinite ? max(height, 0) : 0
        let world = Self.tileSize * exp2(self.zoom)
        centerX = Self.worldX(longitude: self.center.longitude, world: world)
        centerY = Self.worldY(latitude: self.center.latitude, world: world)
    }

    private let centerX: Double
    private let centerY: Double

    /// The width of the whole world in points at this zoom.
    public var worldSize: Double { Self.tileSize * exp2(zoom) }

    /// The ground distance covered by one point at the centre latitude, in metres.
    ///
    /// Use it with ``LineWidth/resolved(atZoom:metresPerPoint:lanes:)`` for real road widths. It is the scale at the
    /// centre; across a view the scale changes with latitude (a few percent over 10 km at Norwegian latitudes).
    public var metresPerPoint: Double {
        cos(center.latitude * .pi / 180) * 2 * .pi * 6_378_137 / worldSize
    }

    /// The screen position of a coordinate in degrees.
    public func screenPoint(for coordinate: Coordinate) -> ScreenPoint {
        let latitude = min(max(coordinate.latitude, -TileID.maximumLatitude), TileID.maximumLatitude)
        return screenPoint(longitude: coordinate.longitude, latitude: latitude)
    }

    /// The screen position of a stored point (1e-7 degrees).
    public func screenPoint(for point: PackedPoint) -> ScreenPoint {
        screenPoint(longitude: Double(point.longitude) * 1e-7, latitude: Double(point.latitude) * 1e-7)
    }

    /// The coordinate at a screen position. The inverse of ``screenPoint(for:)-(Coordinate)``.
    public func coordinate(at point: ScreenPoint) -> Coordinate {
        let world = worldSize
        let x = centerX + (point.x - width / 2)
        let y = centerY + (point.y - height / 2)
        let longitude = x / world * 360 - 180
        let latitude = atan(sinh(.pi * (1 - 2 * y / world))) * 180 / .pi
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    /// The storage cells that touch the view, with a margin, in row-major order.
    ///
    /// The view is assumed not to cross the antimeridian: columns outside the world are dropped, not wrapped.
    ///
    /// - Parameters:
    ///   - storageZoom: The zoom of the store's cells (13 in the current format).
    ///   - margin: Extra points around the view, so wide strokes and labels from a neighbouring cell are still drawn.
    public func cells(storageZoom: Int, margin: Double = 0) -> [TileID] {
        guard (0...TileID.maximumZoom).contains(storageZoom) else { return [] }
        let world = worldSize
        let count = 1 << storageZoom
        let margin = margin.isFinite ? max(margin, 0) : 0
        func index(_ worldPoint: Double) -> Int { Int((worldPoint / world * Double(count)).rounded(.down)) }
        let minX = max(index(centerX - width / 2 - margin), 0)
        let maxX = min(index(centerX + width / 2 + margin), count - 1)
        let minY = max(index(centerY - height / 2 - margin), 0)
        let maxY = min(index(centerY + height / 2 + margin), count - 1)
        guard minX <= maxX, minY <= maxY else { return [] }
        var result: [TileID] = []
        for y in minY...maxY {
            for x in minX...maxX {
                if let tile = TileID(zoom: storageZoom, x: x, y: y) { result.append(tile) }
            }
        }
        return result
    }

    private func screenPoint(longitude: Double, latitude: Double) -> ScreenPoint {
        let world = worldSize
        return ScreenPoint(
            x: Self.worldX(longitude: longitude, world: world) - centerX + width / 2,
            y: Self.worldY(latitude: latitude, world: world) - centerY + height / 2)
    }

    private static func worldX(longitude: Double, world: Double) -> Double { (longitude + 180) / 360 * world }

    private static func worldY(latitude: Double, world: Double) -> Double {
        (1 - asinh(tan(latitude * .pi / 180)) / .pi) / 2 * world
    }
}
