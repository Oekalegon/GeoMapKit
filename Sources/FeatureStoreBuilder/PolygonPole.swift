import FeatureStore
import Foundation

/// The point inside an area that is farthest from its edges (the pole of inaccessibility): where a marker and a name sit best.
///
/// The centre of the bounding box is a poor place: for a bent building or a park around a pond it lies outside. This finds the middle
/// of the largest circle that fits inside the rings (even-odd, so a hole is outside) by looking at squares and keeping only those that
/// can still hold a larger circle than the best so far (Mapbox's polylabel). The `MapRender` module has the same idea for the names of
/// lakes, in screen points; this one works on the stored coordinates, for the point that the builder stores with an area.
enum PolygonPole {
    /// How many squares are looked at at most.
    static let maximumSquares = 600
    /// How many edge measurements are made at most; a polygon with tens of thousands of vertices gets the best point found so far.
    static let edgeBudget = 4_000_000

    private struct Square {
        let x: Double
        let y: Double
        /// Half the side.
        let half: Double
        /// The distance from the middle to the nearest edge, negative outside.
        let distance: Double
        var potential: Double { distance + half * 2.0.squareRoot() }
    }

    /// The pole of an area.
    ///
    /// - Parameter rings: The rings of the area (outer rings and holes, even-odd), closed or not; rings of fewer than three points are
    ///   ignored. The pieces of a multipolygon may all be given when they do not overlap.
    /// - Returns: The point, or `nil` if the rings enclose no area.
    static func find(in rings: [[PackedPoint]]) -> PackedPoint? {
        let rings = rings.filter { $0.count >= 3 }
        guard !rings.isEmpty else { return nil }
        // Longitude degrees are shorter than latitude degrees away from the equator: x is scaled so that distances are the same in both.
        let latitudes = rings.joined().map { Double($0.latitude) }
        let meanLatitude = latitudes.reduce(0, +) / Double(latitudes.count)
        let scale = max(cos(meanLatitude / 1e7 * .pi / 180), 0.01)
        let xs = rings.map { $0.map { Double($0.longitude) * scale } }
        let ys = rings.map { $0.map { Double($0.latitude) } }
        guard let minX = xs.joined().min(), let maxX = xs.joined().max(), let minY = ys.joined().min(), let maxY = ys.joined().max()
        else { return nil }
        let side = min(maxX - minX, maxY - minY)
        guard side > 0 else { return nil }
        let precision = max(1, side / 100)
        let segments = max(1, rings.reduce(0) { $0 + $1.count })

        var work = 0
        func make(_ x: Double, _ y: Double, _ half: Double) -> Square {
            work += segments
            return Square(x: x, y: y, half: half, distance: signedDistance(x, y, xs, ys))
        }
        var best = make((minX + maxX) / 2, (minY + maxY) / 2, 0)
        var squares: [Square] = []
        var half = side / 2
        var x = minX
        while x < maxX {
            var y = minY
            while y < maxY {
                squares.append(make(x + half, y + half, half))
                if squares.count >= maximumSquares { break }
                y += side
            }
            if squares.count >= maximumSquares { break }
            x += side
        }
        for square in squares where square.distance > best.distance { best = square }
        var examined = 0
        while !squares.isEmpty, examined < maximumSquares * 4, work < edgeBudget {
            // The square that could still hold the largest circle.
            var index = 0
            for candidate in squares.indices where squares[candidate].potential > squares[index].potential { index = candidate }
            let square = squares.remove(at: index)
            examined += 1
            if square.distance > best.distance { best = square }
            if square.potential - best.distance <= precision { continue }
            half = square.half / 2
            for (dx, dy) in [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)] {
                squares.append(make(square.x + dx * half, square.y + dy * half, half))
            }
        }
        guard best.distance >= 0 else { return nil }
        return PackedPoint(longitude: Int32((best.x / scale).rounded()), latitude: Int32(best.y.rounded()))
    }

    /// The distance from a point to the nearest edge of the rings: positive inside (even-odd), negative outside.
    private static func signedDistance(_ px: Double, _ py: Double, _ xs: [[Double]], _ ys: [[Double]]) -> Double {
        var inside = false
        var nearest = Double.infinity
        for ring in xs.indices {
            let rx = xs[ring], ry = ys[ring]
            var previous = rx.count - 1
            for index in rx.indices {
                let ax = rx[index], ay = ry[index], bx = rx[previous], by = ry[previous]
                if (ay > py) != (by > py), px < (bx - ax) * (py - ay) / (by - ay) + ax { inside.toggle() }
                nearest = min(nearest, segmentDistanceSquared(px, py, ax, ay, bx, by))
                previous = index
            }
        }
        let distance = nearest.squareRoot()
        return inside ? distance : -distance
    }

    private static func segmentDistanceSquared(_ px: Double, _ py: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        var x = ax, y = ay
        let dx = bx - ax, dy = by - ay
        if dx != 0 || dy != 0 {
            let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
            x += dx * t
            y += dy * t
        }
        return (px - x) * (px - x) + (py - y) * (py - y)
    }
}
