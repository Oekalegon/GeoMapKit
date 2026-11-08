import Foundation
import GeoCore
import FeatureStore

/// The part of the world on screen: a centre, a zoom level, a size in points and a bearing.
///
/// The projection is Web Mercator with 256-point tiles, so at zoom `z` the world is
/// `256 × 2^z` points wide. Zoom is fractional. The map can be turned: the bearing is the compass direction that points up
/// the screen, in degrees clockwise from north, so 0 is north up and 90 has east at the top. The turn is part of the
/// projection, so everything built on screen points (clipping, label placement, which keeps text upright) works unchanged.
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
    /// The compass direction at the top of the view, in degrees clockwise from north, 0 up to (not including) 360.
    public let bearing: Double

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
    ///   - bearing: The compass direction at the top of the view in degrees clockwise from north. Any finite value is
    ///     wrapped into 0..<360; a non-finite one becomes 0 (north up).
    public init(center: Coordinate, zoom: Double, width: Double, height: Double, bearing: Double = 0) {
        let latitude = center.latitude.isFinite ? min(max(center.latitude, -TileID.maximumLatitude), TileID.maximumLatitude) : 0
        var longitude = center.longitude.isFinite ? (center.longitude + 180).truncatingRemainder(dividingBy: 360) : 180
        if longitude < 0 { longitude += 360 }
        self.center = Coordinate(latitude: latitude, longitude: longitude - 180)
        self.zoom = zoom.isFinite ? min(max(zoom, 0), Double(TileID.maximumZoom)) : 0
        self.width = width.isFinite ? max(width, 0) : 0
        self.height = height.isFinite ? max(height, 0) : 0
        var turn = bearing.isFinite ? bearing.truncatingRemainder(dividingBy: 360) : 0
        if turn < 0 { turn += 360 }
        // A value that rounds to 360 is north again.
        self.bearing = turn >= 360 ? 0 : turn
        let radians = self.bearing * .pi / 180
        cosBearing = cos(radians)
        sinBearing = sin(radians)
        let world = Self.tileSize * exp2(self.zoom)
        centerX = Self.worldX(longitude: self.center.longitude, world: world)
        centerY = Self.worldY(latitude: self.center.latitude, world: world)
    }

    private let centerX: Double
    private let centerY: Double
    private let cosBearing: Double
    private let sinBearing: Double

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
        // Undo the turn: from the screen offset to the offset along the (north up) map axes.
        let ux = point.x - width / 2, uy = point.y - height / 2
        let x = centerX + ux * cosBearing - uy * sinBearing
        let y = centerY + ux * sinBearing + uy * cosBearing
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
        // The cells that touch the turned view: its bounding box along the map axes.
        let halfWidth = abs(width / 2 * cosBearing) + abs(height / 2 * sinBearing)
        let halfHeight = abs(width / 2 * sinBearing) + abs(height / 2 * cosBearing)
        let minX = max(index(centerX - halfWidth - margin), 0)
        let maxX = min(index(centerX + halfWidth + margin), count - 1)
        let minY = max(index(centerY - halfHeight - margin), 0)
        let maxY = min(index(centerY + halfHeight + margin), count - 1)
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
        let dx = Self.worldX(longitude: longitude, world: world) - centerX
        let dy = Self.worldY(latitude: latitude, world: world) - centerY
        return ScreenPoint(x: dx * cosBearing + dy * sinBearing + width / 2, y: -dx * sinBearing + dy * cosBearing + height / 2)
    }

    private static func worldX(longitude: Double, world: Double) -> Double { (longitude + 180) / 360 * world }

    private static func worldY(latitude: Double, world: Double) -> Double {
        (1 - asinh(tan(latitude * .pi / 180)) / .pi) / 2 * world
    }
}
