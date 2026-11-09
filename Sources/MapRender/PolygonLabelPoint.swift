import Foundation

/// The point inside a polygon that is farthest from its edges (the "pole of inaccessibility"): where a name fits best.
///
/// The centre of the bounding box is a poor place for a name: for a bent lake it lies on land. This finds the middle of the
/// largest circle that fits inside the rings (even-odd, so a hole is outside), to a precision of a point, by looking at
/// squares and keeping only those that can still hold a larger circle than the best one so far (Mapbox's polylabel).
enum PolygonLabelPoint {
    /// How many squares are looked at at most; a polygon with a hundred thousand vertices must not stall a frame.
    static let maximumSquares = 600

    private struct Square {
        let x: Double
        let y: Double
        /// Half the side.
        let half: Double
        /// The distance from the middle to the nearest edge, negative outside.
        let distance: Double
        /// The largest distance any point of the square can have.
        var potential: Double { distance + half * 2.0.squareRoot() }
    }

    /// - Parameters:
    ///   - rings: The rings of the polygon in screen points, which decide what is inside (even-odd); fewer than three points are ignored.
    ///     The pieces that a polygon was cut into may all be given: they do not overlap.
    ///   - edges: The lines that the distance is measured to, if they are not the rings: the real edges of the pieces, so that the
    ///     border between two cells, which is no shore, does not count.
    ///   - domain: Where the point may be, for example the part of a big lake that is in view; the bounding box of the rings if `nil`.
    ///   - precision: How close to the best point the answer is, in points.
    /// - Returns: The point and its distance to the nearest edge, or `nil` if there is no area.
    static func find(
        in rings: [[ScreenPoint]], edges: [[ScreenPoint]]? = nil, domain: ScreenBounds? = nil, precision: Double = 1
    ) -> (point: ScreenPoint, distance: Double)? {
        let rings = rings.filter { $0.count >= 3 }
        let lines = edges ?? rings
        guard var bounds = ScreenBounds(of: rings.joined()) else { return nil }
        if let domain {
            bounds = ScreenBounds(
                minX: max(bounds.minX, domain.minX), minY: max(bounds.minY, domain.minY),
                maxX: min(bounds.maxX, domain.maxX), maxY: min(bounds.maxY, domain.maxY))
        }
        guard bounds.maxX > bounds.minX, bounds.maxY > bounds.minY else { return nil }
        let width = bounds.maxX - bounds.minX, height = bounds.maxY - bounds.minY
        let side = min(width, height)
        guard side > 0 else { return nil }

        var squares: [Square] = []
        func make(_ x: Double, _ y: Double, _ half: Double) -> Square {
            Square(x: x, y: y, half: half, distance: signedDistance(x, y, rings, lines))
        }
        var half = side / 2
        var x = bounds.minX
        while x < bounds.maxX {
            var y = bounds.minY
            while y < bounds.maxY {
                squares.append(make(x + half, y + half, half))
                y += side
            }
            x += side
        }
        // The middle of the bounding box is the first guess.
        var best = make((bounds.minX + bounds.maxX) / 2, (bounds.minY + bounds.maxY) / 2, 0)
        var looked = squares.count
        while !squares.isEmpty, looked < maximumSquares {
            // The square with the largest potential next.
            guard let index = squares.indices.max(by: { squares[$0].potential < squares[$1].potential }) else { break }
            let square = squares.remove(at: index)
            if square.distance > best.distance { best = square }
            if square.potential - best.distance <= precision { continue }
            half = square.half / 2
            for (dx, dy) in [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)] {
                squares.append(make(square.x + dx * half, square.y + dy * half, half))
            }
            looked += 4
        }
        guard best.distance > 0 else { return nil }
        return (ScreenPoint(x: best.x, y: best.y), best.distance)
    }

    /// The distance from a point to the nearest edge of the rings, positive when the point is inside (even-odd) and negative outside.
    private static func signedDistance(_ px: Double, _ py: Double, _ rings: [[ScreenPoint]], _ lines: [[ScreenPoint]]) -> Double {
        var inside = false
        for ring in rings {
            var j = ring.count - 1
            for i in 0..<ring.count {
                let a = ring[i], b = ring[j]
                if (a.y > py) != (b.y > py), px < (b.x - a.x) * (py - a.y) / (b.y - a.y) + a.x { inside.toggle() }
                j = i
            }
        }
        var nearest = Double.infinity
        for line in lines where line.count >= 2 {
            for i in 1..<line.count { nearest = min(nearest, squaredDistance(px, py, line[i - 1], line[i])) }
        }
        let distance = nearest.isFinite ? nearest.squareRoot() : 1e6
        return inside ? distance : -distance
    }

    private static func squaredDistance(_ px: Double, _ py: Double, _ a: ScreenPoint, _ b: ScreenPoint) -> Double {
        var x = a.x, y = a.y
        var dx = b.x - x, dy = b.y - y
        if dx != 0 || dy != 0 {
            let t = ((px - x) * dx + (py - y) * dy) / (dx * dx + dy * dy)
            if t > 1 {
                x = b.x
                y = b.y
            } else if t > 0 {
                x += dx * t
                y += dy * t
            }
        }
        dx = px - x
        dy = py - y
        return dx * dx + dy * dy
    }
}
