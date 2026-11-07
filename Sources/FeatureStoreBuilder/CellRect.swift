import FeatureStore
import Foundation
import GeoCore

/// The borders of one cell as integers in 1e-7 degrees, shared exactly with its neighbours.
///
/// Every border is rounded once by one function, so the east border of a cell and
/// the west border of the next cell are the same integer. A cell is closed: a
/// vertex exactly on a border belongs to both cells.
struct CellRect {
    let tile: TileID
    let west: Int32
    let east: Int32
    let south: Int32
    let north: Int32
    /// Projected y of the south and north borders, computed from the integers.
    let southY: Double
    let northY: Double
    /// True at the edge of the world, where no neighbour owns a piece lying on the border.
    let isLastColumn: Bool
    let isLastRow: Bool

    /// - Precondition: `tile` is a valid tile (every `TileID` is).
    init(tile: TileID) {
        self.tile = tile
        west = Self.longitude(column: tile.x, zoom: tile.zoom)
        east = Self.longitude(column: tile.x + 1, zoom: tile.zoom)
        north = Self.latitude(row: tile.y, zoom: tile.zoom)
        south = Self.latitude(row: tile.y + 1, zoom: tile.zoom)
        southY = Mercator.y(latitude: Double(south))
        northY = Mercator.y(latitude: Double(north))
        isLastColumn = tile.x == (1 << tile.zoom) - 1
        isLastRow = tile.y == (1 << tile.zoom) - 1
    }

    /// The longitude of the west border of a column, in 1e-7 degrees. Column `2^zoom` is the east edge of the world.
    static func longitude(column: Int, zoom: Int) -> Int32 {
        let degrees = Double(column) / Double(1 << zoom) * 360 - 180
        return Int32((degrees * 1e7).rounded())
    }

    /// The latitude of the north border of a row, in 1e-7 degrees. Row `2^zoom` is the south edge of the map.
    static func latitude(row: Int, zoom: Int) -> Int32 {
        let n = Double.pi * (1 - 2 * Double(row) / Double(1 << zoom))
        return Int32((atan(sinh(n)) * 180 / .pi * 1e7).rounded())
    }

    /// Whether a point lies inside the closed cell.
    func contains(_ point: PackedPoint) -> Bool {
        point.longitude >= west && point.longitude <= east && point.latitude >= south && point.latitude <= north
    }

    /// The cells at `zoom` that may overlap the bounding box of `points`, with one cell of margin.
    ///
    /// Cells that only touch the geometry yield no pieces when clipped.
    static func tiles(covering points: [PackedPoint], zoom: Int) -> [TileID] {
        guard let first = points.first else { return [] }
        var minLon = first.longitude, maxLon = first.longitude, minLat = first.latitude, maxLat = first.latitude
        for point in points {
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
        }
        let n = 1 << zoom
        func column(_ longitude: Int32) -> Int {
            let value = (Double(longitude) / 1e7 + 180) / 360 * Double(n)
            return max(0, min(n - 1, Int(value.rounded(.down))))
        }
        func row(_ latitude: Int32) -> Int {
            let y = Mercator.y(latitude: Double(latitude))
            let value = (1 - y / .pi) / 2 * Double(n)
            return max(0, min(n - 1, Int(value.rounded(.down))))
        }
        let columns = max(0, column(minLon) - 1)...min(n - 1, column(maxLon) + 1)
        let rows = max(0, row(maxLat) - 1)...min(n - 1, row(minLat) + 1)
        var result: [TileID] = []
        for y in rows { for x in columns { if let tile = TileID(zoom: zoom, x: x, y: y) { result.append(tile) } } }
        return result
    }
}
