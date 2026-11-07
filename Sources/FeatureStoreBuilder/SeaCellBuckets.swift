import FeatureStore
import GeoCore

/// Sorts the segments of the coastlines into the cells they pass through, in one pass.
///
/// Building the sea cell by cell would otherwise clip every coastline vertex against every cell, which takes time in
/// proportion to cells times vertices. Here each segment is put in the lists of the few cells its bounding box touches
/// (a cell border belongs to both cells), and a cell then sees only its own segments.
struct SeaCellBuckets {
    private let columns: ClosedRange<Int>
    private let rows: ClosedRange<Int>
    private var inputs: [Int: SeaBuilder.CellInput] = [:]

    /// - Parameters:
    ///   - lines: The coastlines.
    ///   - columns: The columns of the block of cells.
    ///   - rows: The rows of the block of cells.
    ///   - zoom: The storage zoom.
    init(lines: SeaBuilder.Lines, columns: ClosedRange<Int>, rows: ClosedRange<Int>, zoom: Int) {
        self.columns = columns
        self.rows = rows
        // For each cell, the segments (line index, segment index) in coastline order.
        var segments: [Int: [(line: Int, segment: Int)]] = [:]
        let allLines: [(points: [PackedPoint], isRing: Bool)] =
            lines.chains.map { ($0.points, false) } + lines.rings.map { ($0.line.points, true) }
        for (index, line) in allLines.enumerated() where line.points.count >= 2 {
            if line.isRing, let ring = lines.rings[safe: index - lines.chains.count],
                let owner = Self.tile(of: PackedPoint(longitude: ring.west, latitude: ring.north), zoom: zoom),
                Self.contains(CellRect(tile: owner), ring)
            {
                // A ring wholly inside one cell is an island of that cell and needs no segments.
                if let key = key(of: owner) { inputs[key, default: .init()].wholeRings.append((ring.line.points, ring.area)) }
                continue
            }
            for segment in 0..<(line.points.count - 1) {
                let a = line.points[segment], b = line.points[segment + 1]
                // One unit of margin makes a segment that touches a border count for both cells.
                guard let low = Self.tile(of: PackedPoint(longitude: Self.step(min(a.longitude, b.longitude), -1), latitude: Self.step(max(a.latitude, b.latitude), 1)), zoom: zoom),
                    let high = Self.tile(of: PackedPoint(longitude: Self.step(max(a.longitude, b.longitude), 1), latitude: Self.step(min(a.latitude, b.latitude), -1)), zoom: zoom)
                else { continue }
                let firstColumn = max(low.x, columns.lowerBound), lastColumn = min(high.x, columns.upperBound)
                let firstRow = max(low.y, rows.lowerBound), lastRow = min(high.y, rows.upperBound)
                guard firstColumn <= lastColumn, firstRow <= lastRow else { continue }
                for row in firstRow...lastRow {
                    for column in firstColumn...lastColumn {
                        segments[(row - rows.lowerBound) * columns.count + (column - columns.lowerBound), default: []].append((index, segment))
                    }
                }
            }
        }
        for (key, list) in segments {
            var input = inputs[key] ?? .init()
            input.runs = Self.runs(from: list, lines: allLines)
            inputs[key] = input
        }
    }

    /// What was found for a cell, or `nil` if no coastline comes near it.
    func input(forColumn column: Int, row: Int) -> SeaBuilder.CellInput? {
        inputs[(row - rows.lowerBound) * columns.count + (column - columns.lowerBound)]
    }

    private func key(of tile: TileID) -> Int? {
        guard columns.contains(tile.x), rows.contains(tile.y) else { return nil }
        return (tile.y - rows.lowerBound) * columns.count + (tile.x - columns.lowerBound)
    }

    private static func tile(of point: PackedPoint, zoom: Int) -> TileID? { CellRect.tile(owning: point, zoom: zoom) }

    /// Whether a ring lies wholly inside a cell (a border counts as inside).
    private static func contains(_ cell: CellRect, _ ring: SeaBuilder.Lines.Ring) -> Bool {
        ring.west >= cell.west && ring.east <= cell.east && ring.south >= cell.south && ring.north <= cell.north
    }

    private static func step(_ value: Int32, _ delta: Int32) -> Int32 {
        value.addingReportingOverflow(delta).overflow ? value : value + delta
    }

    /// Joins the consecutive segments of one coastline into runs of points. A ring's last run and first run are one run when
    /// the ring starts inside the cell.
    private static func runs(from list: [(line: Int, segment: Int)], lines: [(points: [PackedPoint], isRing: Bool)]) -> [[PackedPoint]] {
        var runs: [(line: Int, first: Int, last: Int)] = []
        for entry in list {
            if let last = runs.last, last.line == entry.line, last.last + 1 == entry.segment {
                runs[runs.count - 1].last = entry.segment
            } else {
                runs.append((entry.line, entry.segment, entry.segment))
            }
        }
        var result: [[PackedPoint]] = []
        var merged = Set<Int>()
        for (index, run) in runs.enumerated() where !merged.contains(index) {
            let points = lines[run.line].points
            var path = Array(points[run.first...(run.last + 1)])
            // The ring's first run starts at segment 0 and its last run ends at the last segment: they are one run.
            if lines[run.line].isRing, run.first == 0,
                let other = runs.indices.last(where: { $0 != index && runs[$0].line == run.line && runs[$0].last == points.count - 2 })
            {
                path = Array(points[runs[other].first...(runs[other].last + 1)]) + path.dropFirst()
                merged.insert(other)
            }
            result.append(path)
        }
        return result
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
