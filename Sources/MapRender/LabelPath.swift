import Foundation

/// A polyline with the distance along it known at every vertex, for laying text along a line.
struct LabelPath {
    let points: [ScreenPoint]
    /// The distance from the start to each vertex.
    private let distances: [Double]

    var length: Double { distances.last ?? 0 }

    init?(_ points: [ScreenPoint]) {
        guard points.count >= 2 else { return nil }
        var distances = [0.0]
        distances.reserveCapacity(points.count)
        for (a, b) in zip(points, points.dropFirst()) {
            distances.append(distances[distances.count - 1] + hypot(b.x - a.x, b.y - a.y))
        }
        guard let total = distances.last, total > 1e-9 else { return nil }
        self.points = points
        self.distances = distances
    }

    /// The parts of a polyline that lie in the bounds, cut at the edge of the bounds. Parts outside are left out, so a long
    /// road is not walked metre by metre and its labels are placed where it can be seen.
    static func runs(of points: [ScreenPoint], in bounds: ScreenBounds) -> [LabelPath] {
        var result: [LabelPath] = []
        var current: [ScreenPoint] = []
        func finish() {
            if let path = LabelPath(current) { result.append(path) }
            current = []
        }
        for (a, b) in zip(points, points.dropFirst()) {
            guard let (from, to) = clip(a, b, to: bounds) else {
                finish()
                continue
            }
            // A segment that starts where the last one ended continues the run; one that enters the bounds starts a new run.
            if from != a { finish() }
            if current.isEmpty { current.append(from) }
            current.append(to)
            if to != b { finish() }
        }
        finish()
        return result
    }

    /// The part of the segment inside the bounds (Liang–Barsky), or `nil`.
    private static func clip(_ a: ScreenPoint, _ b: ScreenPoint, to bounds: ScreenBounds) -> (ScreenPoint, ScreenPoint)? {
        let dx = b.x - a.x, dy = b.y - a.y
        var t0 = 0.0, t1 = 1.0
        for (p, q) in [(-dx, a.x - bounds.minX), (dx, bounds.maxX - a.x), (-dy, a.y - bounds.minY), (dy, bounds.maxY - a.y)] {
            if p == 0 {
                if q < 0 { return nil }
            } else {
                let t = q / p
                if p < 0 {
                    if t > t1 { return nil }
                    t0 = max(t0, t)
                } else {
                    if t < t0 { return nil }
                    t1 = min(t1, t)
                }
            }
        }
        let from = t0 == 0 ? a : ScreenPoint(x: a.x + dx * t0, y: a.y + dy * t0)
        let to = t1 == 1 ? b : ScreenPoint(x: a.x + dx * t1, y: a.y + dy * t1)
        return (from, to)
    }

    /// The index of the segment that holds a distance.
    private func segment(at distance: Double) -> Int {
        var low = 0, high = distances.count - 2
        while low < high {
            let middle = (low + high + 1) / 2
            if distances[middle] <= distance { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// The point at a distance from the start, clamped to the line.
    func position(at distance: Double) -> ScreenPoint {
        let s = min(max(distance, 0), length)
        let index = segment(at: s)
        let a = points[index], b = points[index + 1]
        let span = distances[index + 1] - distances[index]
        let t = span > 1e-12 ? (s - distances[index]) / span : 0
        return ScreenPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Whether the stretch between two distances is straight enough for text: no segment of it turns away from the chord
    /// by more than `maximumTurn` radians.
    func isGentle(from start: Double, to end: Double, maximumTurn: Double) -> Bool {
        let a = position(at: start), b = position(at: end)
        let chord = atan2(b.y - a.y, b.x - a.x)
        let first = segment(at: min(max(start, 0), length))
        let last = segment(at: min(max(end, 0), length))
        for index in first...last {
            let p = points[index], q = points[index + 1]
            guard hypot(q.x - p.x, q.y - p.y) > 1e-9 else { continue }
            var turn = atan2(q.y - p.y, q.x - p.x) - chord
            while turn > .pi { turn -= 2 * .pi }
            while turn < -.pi { turn += 2 * .pi }
            if abs(turn) > maximumTurn { return false }
        }
        return true
    }
}
