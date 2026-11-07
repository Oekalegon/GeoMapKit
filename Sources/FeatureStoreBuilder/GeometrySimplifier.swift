import FeatureStore
import Foundation

/// Douglas–Peucker simplification in Web Mercator.
///
/// Simplification is applied to a whole feature before it is clipped to cells, so
/// every cell sees the same simplified vertices. Neighbouring polygons are
/// simplified independently, so a shared border can open a small gap in the
/// simplified bands; no topology is preserved between features. A simplified ring
/// can in rare cases cross itself; the even-odd fill degrades mildly then.
enum GeometrySimplifier {
    /// The tolerance for a band in projected radians, or `nil` for the detail band, which is never simplified.
    ///
    /// It is half a pixel of a 256-pixel tile at the highest zoom of the band: about 38 m
    /// for the overview band (zoom 11) and about 4.8 m for the mid band (zoom 14) at the
    /// equator, and smaller on the ground at higher latitudes.
    static func tolerance(for band: ZoomBand) -> Double? {
        let zoom: Double
        switch band {
        case .overview: zoom = 11
        case .mid: zoom = 14
        case .detail: return nil
        }
        return 0.5 * 2 * .pi / (256 * pow(2, zoom))
    }

    /// Simplifies an open line. The first and last vertex are always kept.
    static func simplify(line: [PackedPoint], tolerance: Double) -> [PackedPoint] {
        guard line.count > 2 else { return line }
        let projected = line.map(project)
        var keep = [Bool](repeating: false, count: line.count)
        keep[0] = true
        keep[line.count - 1] = true
        reduce(projected, from: 0, to: line.count - 1, tolerance: tolerance, keep: &keep)
        return zip(line, keep).compactMap { $1 ? $0 : nil }
    }

    /// Simplifies a closed ring.
    ///
    /// - Returns: The closed simplified ring, or `nil` if fewer than three distinct vertices remain.
    static func simplify(ring: [PackedPoint], tolerance: Double) -> [PackedPoint]? {
        var points = ring
        if points.count > 1, points.first == points.last { points.removeLast() }
        guard points.count >= 3 else { return nil }
        let projected = points.map(project)
        // Split at the vertex farthest from the first, so the first vertex needs no special case.
        var farthest = 1
        var best = -1.0
        for index in 1..<points.count {
            let distance = hypot(projected[index].x - projected[0].x, projected[index].y - projected[0].y)
            if distance > best { best = distance; farthest = index }
        }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[farthest] = true
        reduce(projected, from: 0, to: farthest, tolerance: tolerance, keep: &keep)
        // Second half runs from `farthest` back around to vertex 0 (appended as a copy).
        let tail = Array(projected[farthest...]) + [projected[0]]
        var tailKeep = [Bool](repeating: false, count: tail.count)
        tailKeep[0] = true
        tailKeep[tail.count - 1] = true
        reduce(tail, from: 0, to: tail.count - 1, tolerance: tolerance, keep: &tailKeep)
        for (offset, flag) in tailKeep.enumerated() where flag && farthest + offset < points.count { keep[farthest + offset] = true }
        let result = zip(points, keep).compactMap { $1 ? $0 : nil }
        guard result.count >= 3 else { return nil }
        return result + [result[0]]
    }

    // MARK: Internals

    private struct Projected {
        var x: Double
        var y: Double
    }

    private static func project(_ point: PackedPoint) -> Projected {
        Projected(x: Mercator.radians(longitude: Double(point.longitude)), y: Mercator.y(latitude: Double(point.latitude)))
    }

    private static func reduce(_ points: [Projected], from first: Int, to last: Int, tolerance: Double, keep: inout [Bool]) {
        var stack = [(first, last)]
        while let (start, end) = stack.popLast() {
            guard end - start > 1 else { continue }
            var index = start
            var maximum = tolerance
            for candidate in (start + 1)..<end {
                let distance = distanceToSegment(points[candidate], points[start], points[end])
                if distance > maximum { maximum = distance; index = candidate }
            }
            if index != start {
                keep[index] = true
                stack.append((start, index))
                stack.append((index, end))
            }
        }
    }

    private static func distanceToSegment(_ p: Projected, _ a: Projected, _ b: Projected) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
