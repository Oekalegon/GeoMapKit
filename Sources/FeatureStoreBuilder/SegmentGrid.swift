import FeatureStore
import Foundation

/// Line segments in a grid, for asking whether a point lies on one.
///
/// The outline of a river that runs out into the sea is drawn by the coastline, so the builder asks whether a stretch of an
/// outline lies on a coastline.
struct SegmentGrid {
    private static let cellSize = 25.0

    private struct Segment { var x0, y0, x1, y1: Double }

    private var grid: [Int64: [Segment]] = [:]

    /// Creates an empty grid.
    init() {}

    /// Adds the segments of a line in metres.
    mutating func add(points: [(x: Double, y: Double)]) {
        guard points.count >= 2 else { return }
        for index in 0..<(points.count - 1) { add(points[index], points[index + 1]) }
    }

    /// Whether a point, in metres, lies within `tolerance` metres of a segment.
    ///
    /// - Parameter tolerance: At most 25 metres.
    func isNear(x: Double, y: Double, tolerance: Double) -> Bool {
        let column = Self.cell(x), row = Self.cell(y)
        for c in (column - 1)...(column + 1) {
            for r in (row - 1)...(row + 1) {
                for segment in grid[Self.key(c, r)] ?? [] {
                    let sx = segment.x1 - segment.x0, sy = segment.y1 - segment.y0
                    let squared = sx * sx + sy * sy
                    guard squared > 0 else { continue }
                    let t = min(max(((x - segment.x0) * sx + (y - segment.y0) * sy) / squared, 0), 1)
                    let px = segment.x0 + t * sx - x, py = segment.y0 + t * sy - y
                    if px * px + py * py <= tolerance * tolerance { return true }
                }
            }
        }
        return false
    }

    private static func key(_ column: Int, _ row: Int) -> Int64 { (Int64(column) << 32) ^ (Int64(row) & 0xFFFF_FFFF) }
    private static func cell(_ value: Double) -> Int { Int((value / cellSize).rounded(.down)) }

    private mutating func add(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) {
        let segment = Segment(x0: a.x, y0: a.y, x1: b.x, y1: b.y)
        for column in Self.cell(min(a.x, b.x))...Self.cell(max(a.x, b.x)) {
            for row in Self.cell(min(a.y, b.y))...Self.cell(max(a.y, b.y)) { grid[Self.key(column, row), default: []].append(segment) }
        }
    }
}
