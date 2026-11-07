import Foundation
import GeoCore

extension FeatureStoreBuilder {
    /// The smallest box made of whole cells that contains a box.
    ///
    /// The builder writes only cells that lie completely inside the area it is given, so a box whose edges cut through
    /// cells silently loses those cells. Cut this box instead of the one the user asked for and the file covers all of
    /// it. Each edge moves outward by less than one cell; an edge that already lies on a cell border stays where it is.
    /// Latitudes beyond the Web Mercator limit (about 85.05°) and longitudes beyond ±180° stop at the edge of the world.
    ///
    /// - Parameter box: The area that must be covered.
    /// - Returns: A box whose edges are cell borders at the storage zoom (13).
    public static func cellAlignedBox(covering box: BoundingBox) -> BoundingBox {
        let n = 1 << zoom
        let count = Double(n)
        // An edge on a cell border only up to rounding (coordinates are stored in 1e-7 degrees) must not grow by a
        // whole cell. A ten-thousandth of a cell is about half a metre.
        func settled(_ value: Double) -> Double {
            let nearest = value.rounded()
            return abs(value - nearest) < 1e-4 ? nearest : value
        }
        func column(_ longitude: Double) -> Double { settled((longitude + 180) / 360 * count) }
        func row(_ latitude: Double) -> Double {
            let limit = TileID.maximumLatitude
            let clamped = min(max(latitude, -limit), limit)
            return settled((1 - Mercator.y(latitude: clamped * 1e7) / .pi) / 2 * count)
        }
        func clamp(_ value: Double, _ upper: Int) -> Int { Int(min(max(value, 0), Double(upper))) }
        let westColumn = clamp(column(box.west).rounded(.down), n - 1)
        let eastEdge = max(clamp(column(box.east).rounded(.up), n), westColumn + 1)
        let northRow = clamp(row(box.north).rounded(.down), n - 1)
        let southEdge = max(clamp(row(box.south).rounded(.up), n), northRow + 1)
        return BoundingBox(
            south: Double(CellRect.latitude(row: southEdge, zoom: zoom)) / 1e7,
            west: Double(CellRect.longitude(column: westColumn, zoom: zoom)) / 1e7,
            north: Double(CellRect.latitude(row: northRow, zoom: zoom)) / 1e7,
            east: Double(CellRect.longitude(column: eastEdge, zoom: zoom)) / 1e7)
    }
}
