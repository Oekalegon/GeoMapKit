import FeatureStore
import GeoCore

/// Splits a line or ring into the pieces of every cell it touches.
enum CellSplitter {
    /// The pieces of a line, ordered by cell row then column, and within a cell in line order.
    static func split(line: [PackedPoint], zoom: Int = 13) -> [(cell: TileID, piece: ClippedLine)] {
        var result: [(TileID, ClippedLine)] = []
        for tile in CellRect.tiles(covering: line, zoom: zoom) {
            for piece in LineClipper.clip(line, to: CellRect(tile: tile)) { result.append((tile, piece)) }
        }
        return result
    }

    /// The pieces of a ring, ordered by cell row then column.
    static func split(ring: [PackedPoint], zoom: Int = 13) -> [(cell: TileID, piece: ClippedRing)] {
        var result: [(TileID, ClippedRing)] = []
        for tile in CellRect.tiles(covering: ring, zoom: zoom) {
            if let piece = RingClipper.clip(ring, to: CellRect(tile: tile)) { result.append((tile, piece)) }
        }
        return result
    }
}
