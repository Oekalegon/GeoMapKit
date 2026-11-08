/// The segments of the one-way roads of a scene in a grid, to find those near a point.
struct CarriagewayGrid {
    /// One segment of a road, in screen points, with the index of its line.
    struct Segment {
        var line: Int
        var ax, ay, bx, by: Double
    }

    private let cellSize: Double
    private var cells: [Int64: [Segment]] = [:]

    /// Creates the grid.
    ///
    /// - Parameters:
    ///   - lines: The lines of the scene.
    ///   - indices: The lines to put in the grid.
    ///   - cellSize: The size of a cell, in points; a search finds every segment within one cell size of a point.
    init(lines: [SceneLine], indices: [Int], cellSize: Double) {
        self.cellSize = cellSize
        for index in indices {
            let points = lines[index].points
            for position in 0..<(points.count - 1) {
                let a = points[position], b = points[position + 1]
                guard a != b else { continue }
                let segment = Segment(line: index, ax: a.x, ay: a.y, bx: b.x, by: b.y)
                for column in cell(min(a.x, b.x))...cell(max(a.x, b.x)) {
                    for row in cell(min(a.y, b.y))...cell(max(a.y, b.y)) { cells[Self.key(column, row), default: []].append(segment) }
                }
            }
        }
    }

    /// The segments in the cell of a point and the cells around it.
    func segments(near point: ScreenPoint) -> [Segment] {
        let column = cell(point.x), row = cell(point.y)
        var found: [Segment] = []
        for c in (column - 1)...(column + 1) {
            for r in (row - 1)...(row + 1) { found += cells[Self.key(c, r)] ?? [] }
        }
        return found
    }

    private func cell(_ value: Double) -> Int { Int((value / cellSize).rounded(.down)) }
    private static func key(_ column: Int, _ row: Int) -> Int64 { (Int64(column) << 32) ^ (Int64(row) & 0xFFFF_FFFF) }
}
