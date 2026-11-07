import FeatureStore
import GeoCore

extension SeaBuilder {
    /// The sea in every cell of a block, from the coastlines (simplified for one band) and the sea of the whole block.
    ///
    /// The coastline segments are sorted into the cells once (``SeaCellBuckets``), so the work grows with the number of
    /// vertices and the number of cells, not with their product. A cell with no coastline near it is sea or land as a whole,
    /// and so is every such cell next to it; one test per connected group of them says which.
    ///
    /// - Parameters:
    ///   - lines: The coastlines.
    ///   - sea: The sea of the whole block (``build(lines:box:)``), used to tell sea from land where no coastline is near.
    ///   - columns: The columns of the block.
    ///   - rows: The rows of the block.
    ///   - zoom: The storage zoom.
    /// - Returns: The parts of each cell, row by row (index `(row - first row) * columns + (column - first column)`); `nil`
    ///   or empty for a cell with no sea.
    static func parts(
        lines: Lines, sea: [[PackedPoint]], columns: ClosedRange<Int>, rows: ClosedRange<Int>, zoom: Int
    ) -> [[GeometryPart]?] {
        let buckets = SeaCellBuckets(lines: lines, columns: columns, rows: rows, zoom: zoom)
        let width = columns.count, height = rows.count
        var parts = [[GeometryPart]?](repeating: nil, count: width * height)
        var untouched = [Bool](repeating: false, count: width * height)     // no coastline near the cell at all
        for row in rows {
            for column in columns {
                let slot = (row - rows.lowerBound) * width + (column - columns.lowerBound)
                guard let cell = TileID(zoom: zoom, x: column, y: row) else { continue }
                guard let input = buckets.input(forColumn: column, row: row) else {
                    untouched[slot] = true
                    continue
                }
                let rect = CellRect(tile: cell)
                if let found = SeaBuilder.parts(in: rect, input: input) {
                    parts[slot] = found
                } else if SeaBuilder.contains(sea, SeaBuilder.centre(of: rect)) {
                    // Coastline touches the cell without cutting it: the cell is sea or land as a whole.
                    parts[slot] = [SeaBuilder.wholeCell(rect)]
                }
            }
        }
        // A cell with no coastline near it is all sea or all land, and so is every such cell next to it (a coastline
        // between two cells would be near both). One test per connected group of them finds out which.
        var visited = [Bool](repeating: false, count: width * height)
        for start in 0..<(width * height) where untouched[start] && !visited[start] {
            var queue = [start]
            visited[start] = true
            var members: [Int] = []
            var next = 0
            while next < queue.count {
                let slot = queue[next]
                next += 1
                members.append(slot)
                let column = slot % width, row = slot / width
                for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let c = column + dc, r = row + dr
                    guard c >= 0, c < width, r >= 0, r < height else { continue }
                    let neighbour = r * width + c
                    if untouched[neighbour] && !visited[neighbour] {
                        visited[neighbour] = true
                        queue.append(neighbour)
                    }
                }
            }
            guard let first = TileID(zoom: zoom, x: columns.lowerBound + start % width, y: rows.lowerBound + start / width) else { continue }
            let isSea = SeaBuilder.contains(sea, SeaBuilder.centre(of: CellRect(tile: first)))
            if isSea {
                for slot in members {
                    guard let cell = TileID(zoom: zoom, x: columns.lowerBound + slot % width, y: rows.lowerBound + slot / width) else { continue }
                    parts[slot] = [SeaBuilder.wholeCell(CellRect(tile: cell))]
                }
            }
        }
        return parts
    }
}
