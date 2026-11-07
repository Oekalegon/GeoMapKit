import FeatureStore
import GeoCore

extension CellRect {
    /// The rectangle that a block of cells covers, so a line can be clipped to the whole block at once.
    ///
    /// The east and south borders are not treated as belonging to a neighbour (a block has no neighbour to leave a
    /// piece to), so a piece lying along them is kept.
    ///
    /// - Parameters:
    ///   - columns: The columns of the block.
    ///   - rows: The rows of the block.
    ///   - zoom: The storage zoom.
    /// - Returns: The rectangle, or `nil` if the north-west cell is not a valid tile.
    init?(columns: ClosedRange<Int>, rows: ClosedRange<Int>, zoom: Int) {
        guard let corner = TileID(zoom: zoom, x: columns.lowerBound, y: rows.lowerBound) else { return nil }
        tile = corner
        west = Self.longitude(column: columns.lowerBound, zoom: zoom)
        east = Self.longitude(column: columns.upperBound + 1, zoom: zoom)
        north = Self.latitude(row: rows.lowerBound, zoom: zoom)
        south = Self.latitude(row: rows.upperBound + 1, zoom: zoom)
        southY = Mercator.y(latitude: Double(south))
        northY = Mercator.y(latitude: Double(north))
        isLastColumn = true
        isLastRow = true
    }
}
