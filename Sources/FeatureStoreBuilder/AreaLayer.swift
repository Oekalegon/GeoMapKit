/// A set of polygons with a grid for the small ones, to ask whether a point lies in any of them.
struct AreaLayer {
    /// Polygons whose bounding box covers more grid cells than this are kept in a short list that every query tests, instead
    /// of in the grid: a wood of 20 km would otherwise take tens of thousands of cells.
    static let largestGridded = 400
    private static let cellSize = 100.0

    private(set) var polygons: [AreaPolygon] = []
    private var grid: [Int64: [Int]] = [:]
    private var large: [Int] = []

    /// Creates an empty layer.
    init() {}

    mutating func add(_ polygon: AreaPolygon) {
        let index = polygons.count
        polygons.append(polygon)
        let columns = Self.cell(polygon.minX)...Self.cell(polygon.maxX)
        let rows = Self.cell(polygon.minY)...Self.cell(polygon.maxY)
        if columns.count * rows.count > Self.largestGridded {
            large.append(index)
            return
        }
        for column in columns {
            for row in rows { grid[Self.key(column, row), default: []].append(index) }
        }
    }

    /// Whether a point, in metres, lies in any polygon of the layer.
    func contains(x: Double, y: Double) -> Bool {
        if (grid[Self.key(Self.cell(x), Self.cell(y))] ?? []).contains(where: { polygons[$0].contains(x: x, y: y) }) {
            return true
        }
        return large.contains { polygons[$0].contains(x: x, y: y) }
    }

    private static func cell(_ value: Double) -> Int { Int((value / cellSize).rounded(.down)) }
    private static func key(_ column: Int, _ row: Int) -> Int64 { (Int64(column) << 32) ^ (Int64(row) & 0xFFFF_FFFF) }
}
