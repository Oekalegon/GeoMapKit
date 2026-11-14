import MapRender

/// Cuts a polyline to a rectangle (Liang-Barsky on each step), so a route that runs far outside the view costs only what is in it.
enum PolylineClipper {
    struct Rectangle {
        var minX: Double, minY: Double, maxX: Double, maxY: Double
    }

    /// The parts of a polyline that lie in the rectangle, each at least two points. Where a step leaves the rectangle and a later one
    /// comes back, the parts are separate polylines.
    static func clip(_ points: [ScreenPoint], to rectangle: Rectangle) -> [[ScreenPoint]] {
        guard points.count >= 2 else { return [] }
        var result: [[ScreenPoint]] = []
        var current: [ScreenPoint] = []
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            guard let (start, end) = clip(a, b, to: rectangle) else {
                if current.count >= 2 { result.append(current) }
                current = []
                continue
            }
            if current.last == start {
                current.append(end)
            } else {
                if current.count >= 2 { result.append(current) }
                current = [start, end]
            }
        }
        if current.count >= 2 { result.append(current) }
        return result
    }

    /// The part of the step from `a` to `b` inside the rectangle, or `nil`.
    private static func clip(_ a: ScreenPoint, _ b: ScreenPoint, to r: Rectangle) -> (ScreenPoint, ScreenPoint)? {
        var t0 = 0.0, t1 = 1.0
        let dx = b.x - a.x, dy = b.y - a.y
        for (p, q) in [(-dx, a.x - r.minX), (dx, r.maxX - a.x), (-dy, a.y - r.minY), (dy, r.maxY - a.y)] {
            if p == 0 {
                if q < 0 { return nil }
            } else {
                let t = q / p
                if p < 0 { if t > t1 { return nil }; t0 = max(t0, t) } else { if t < t0 { return nil }; t1 = min(t1, t) }
            }
        }
        // A step that only touches a corner is no line.
        guard t1 >= t0 else { return nil }
        let start = t0 == 0 ? a : ScreenPoint(x: a.x + t0 * dx, y: a.y + t0 * dy)
        let end = t1 == 1 ? b : ScreenPoint(x: a.x + t1 * dx, y: a.y + t1 * dy)
        return (start, end)
    }
}
