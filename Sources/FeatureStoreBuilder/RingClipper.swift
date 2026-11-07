import FeatureStore
import Foundation

/// Clips a polygon ring to a cell (Sutherland–Hodgman), tracking which edges the clip created.
///
/// Work is done in Web Mercator in `Double`; only the final vertices are rounded to
/// 1e-7 degrees, and a vertex created on a border gets that border's integer exactly,
/// so neighbouring cells agree on it (apart from a rare rounding tie of one unit).
/// An edge created along the border, joining a point where the ring leaves the cell to
/// the next point where it returns, is marked artificial; pieces of real edges stay real.
///
/// A ring that covers the whole cell becomes the cell's square with all edges
/// artificial, and a ring that only touches the cell, or has zero area inside it,
/// gives `nil`. Fill rings with the even-odd rule: a hole that covers the cell then
/// cancels the outer ring.
enum RingClipper {
    private struct Vertex {
        var x: Double  // longitude, 1e-7 degrees
        var y: Double  // projected latitude, radians
        var exactLongitude: Int32?
        var exactLatitude: Int32?
        /// The edge from this vertex to the next one is artificial.
        var artificial: Bool
    }

    private enum Boundary { case west, east, south, north }

    /// A ring without consecutive duplicates or a repeated closing vertex, with the projected y of every vertex,
    /// computed once so that clipping it to many cells does not repeat the projection.
    struct PreparedRing {
        let points: [PackedPoint]
        let projectedY: [Double]

        init(_ ring: [PackedPoint]) {
            var points: [PackedPoint] = []
            points.reserveCapacity(ring.count)
            for point in ring where point != points.last { points.append(point) }
            if points.count > 1, points.first == points.last { points.removeLast() }
            self.points = points
            self.projectedY = points.map { Mercator.y(latitude: Double($0.latitude)) }
        }
    }

    /// Clips a closed ring to a cell.
    ///
    /// - Parameters:
    ///   - ring: The vertices; a repeated first vertex at the end is optional.
    ///   - rect: The cell.
    /// - Returns: The clipped ring, closed, or `nil` if nothing with an area is left.
    static func clip(_ ring: [PackedPoint], to rect: CellRect) -> ClippedRing? {
        clip(PreparedRing(ring), to: rect)
    }

    /// Clips a prepared ring to a cell; see ``clip(_:to:)``.
    static func clip(_ prepared: PreparedRing, to rect: CellRect) -> ClippedRing? {
        guard prepared.points.count >= 3 else { return nil }
        var vertices = prepared.points.indices.map { index in
            let point = prepared.points[index]
            return Vertex(
                x: Double(point.longitude), y: prepared.projectedY[index],
                exactLongitude: point.longitude, exactLatitude: point.latitude, artificial: false)
        }

        for boundary in [Boundary.west, .east, .south, .north] {
            vertices = clip(vertices, to: boundary, rect: rect)
            if vertices.count < 3 { return nil }
        }
        return finish(vertices, rect: rect)
    }

    // MARK: One boundary

    private static func clip(_ input: [Vertex], to boundary: Boundary, rect: CellRect) -> [Vertex] {
        var output: [Vertex] = []
        for index in input.indices {
            let current = input[index]
            let next = input[(index + 1) % input.count]
            let currentInside = isInside(current, boundary, rect), nextInside = isInside(next, boundary, rect)
            switch (currentInside, nextInside) {
            case (true, true):
                output.append(current)
            case (true, false):
                output.append(current)
                var exit = intersection(current, next, boundary, rect)
                exit.artificial = true
                output.append(exit)
            case (false, true):
                var entry = intersection(current, next, boundary, rect)
                entry.artificial = current.artificial
                output.append(entry)
            case (false, false):
                break
            }
        }
        // Merge consecutive equal vertices; the later one carries the outgoing edge.
        var merged: [Vertex] = []
        for vertex in output {
            if let last = merged.last, last.x == vertex.x, last.y == vertex.y { merged[merged.count - 1] = vertex } else { merged.append(vertex) }
        }
        if merged.count > 1, let first = merged.first, let last = merged.last, first.x == last.x, first.y == last.y {
            merged[0].artificial = last.artificial
            merged.removeLast()
        }
        return merged
    }

    private static func isInside(_ vertex: Vertex, _ boundary: Boundary, _ rect: CellRect) -> Bool {
        switch boundary {
        case .west: vertex.x >= Double(rect.west)
        case .east: vertex.x <= Double(rect.east)
        case .south: vertex.y >= rect.southY
        case .north: vertex.y <= rect.northY
        }
    }

    /// The point where the segment between two vertices meets a border, computed with the endpoints in a fixed order.
    private static func intersection(_ a: Vertex, _ b: Vertex, _ boundary: Boundary, _ rect: CellRect) -> Vertex {
        let swap = (b.x, b.y) < (a.x, a.y)
        let p = swap ? b : a, q = swap ? a : b
        switch boundary {
        case .west, .east:
            let border = boundary == .west ? rect.west : rect.east
            let t = (Double(border) - p.x) / (q.x - p.x)
            return Vertex(
                x: Double(border), y: p.y + t * (q.y - p.y), exactLongitude: border, exactLatitude: nil, artificial: false)
        case .south, .north:
            let border = boundary == .south ? rect.south : rect.north
            let borderY = boundary == .south ? rect.southY : rect.northY
            let t = (borderY - p.y) / (q.y - p.y)
            return Vertex(
                x: p.x + t * (q.x - p.x), y: borderY, exactLongitude: nil, exactLatitude: border, artificial: false)
        }
    }

    // MARK: Result

    private static func finish(_ vertices: [Vertex], rect: CellRect) -> ClippedRing? {
        var points: [PackedPoint] = []
        var artificial: [Bool] = []
        for vertex in vertices {
            let longitude = vertex.exactLongitude ?? clamp(vertex.x.rounded(), rect.west, rect.east)
            let latitude = vertex.exactLatitude ?? clamp(Mercator.latitude(y: vertex.y).rounded(), rect.south, rect.north)
            let point = PackedPoint(longitude: longitude, latitude: latitude)
            if points.last == point {
                artificial[artificial.count - 1] = vertex.artificial
            } else {
                points.append(point)
                artificial.append(vertex.artificial)
            }
        }
        if points.count > 1, points.first == points.last {
            artificial[0] = artificial[artificial.count - 1]
            points.removeLast()
            artificial.removeLast()
        }
        guard points.count >= 3, twiceArea(points) != 0 else { return nil }

        var runs: [Range<Int>] = []
        var start: Int?
        for (index, flag) in artificial.enumerated() {
            if flag, start == nil { start = index }
            if !flag, let begin = start {
                runs.append(begin..<index)
                start = nil
            }
        }
        if let begin = start { runs.append(begin..<artificial.count) }
        // The closing edge is edge `count - 1`; a run ending at it stays one run.
        points.append(points[0])
        return ClippedRing(points: points, artificialEdges: runs)
    }

    /// Twice the signed area in integer units, relative to the first vertex so the sums stay small.
    private static func twiceArea(_ points: [PackedPoint]) -> Int64 {
        let origin = points[0]
        var sum: Int64 = 0
        for index in 1..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            let ax = Int64(a.longitude) - Int64(origin.longitude), ay = Int64(a.latitude) - Int64(origin.latitude)
            let bx = Int64(b.longitude) - Int64(origin.longitude), by = Int64(b.latitude) - Int64(origin.latitude)
            sum += ax * by - bx * ay
        }
        return sum
    }

    private static func clamp(_ value: Double, _ low: Int32, _ high: Int32) -> Int32 {
        Int32(max(Double(low), min(Double(high), value)))
    }
}
