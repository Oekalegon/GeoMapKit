/// An area with its holes: rings in metres, filled by the even-odd rule.
struct AreaPolygon {
    var rings: [(xs: [Double], ys: [Double])]
    var minX: Double, maxX: Double, minY: Double, maxY: Double

    /// Creates a polygon from rings in metres; rings with fewer than four points are not areas and are left out.
    ///
    /// - Returns: `nil` if no ring is left.
    init?(rings projected: [[(x: Double, y: Double)]]) {
        let usable = projected.filter { $0.count >= 4 }
        guard !usable.isEmpty else { return nil }
        rings = usable.map { ring in (ring.map(\.x), ring.map(\.y)) }
        minX = usable.flatMap { $0.map(\.x) }.min() ?? 0
        maxX = usable.flatMap { $0.map(\.x) }.max() ?? 0
        minY = usable.flatMap { $0.map(\.y) }.min() ?? 0
        maxY = usable.flatMap { $0.map(\.y) }.max() ?? 0
    }

    /// Whether a point lies in the area: inside an odd number of its rings.
    func contains(x: Double, y: Double) -> Bool {
        guard x >= minX, x <= maxX, y >= minY, y <= maxY else { return false }
        var inside = false
        for ring in rings {
            var j = ring.xs.count - 1
            for i in 0..<ring.xs.count {
                if (ring.ys[i] > y) != (ring.ys[j] > y),
                    x < (ring.xs[j] - ring.xs[i]) * (y - ring.ys[i]) / (ring.ys[j] - ring.ys[i]) + ring.xs[i]
                {
                    inside.toggle()
                }
                j = i
            }
        }
        return inside
    }
}
