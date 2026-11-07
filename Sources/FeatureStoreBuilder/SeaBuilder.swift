import FeatureStore

/// Builds the sea, as polygons, from coastlines and the box the store covers.
///
/// OSM has no sea polygon, only coastlines with land on the left and water on the right. Inside a box the coastlines
/// that cross it divide it into land and sea. Each crossing piece enters the box at one point and leaves it at another;
/// walking the box border clockwise from a leaving point to the next entering point stays in the water, so the pieces and
/// the border stretches between them form the sea polygons. An island is a closed coastline inside the box that runs
/// counter-clockwise (land inside); it is a hole in the sea. A box that no coastline crosses and that has islands in
/// it is open sea; one with no coastline at all is land, which is the default.
///
/// A coastline that starts or ends inside the box (the extract stops there, or the line is broken) cannot be closed
/// without guessing which side is water, so then no sea is built at all (``Result/openEnds`` counts them, and the pieces that do not close into a polygon). Only the
/// coastline pieces the extract holds are used: a coastline way with no vertex inside the cut area is not in the
/// extract (see the cutter's known limitation), and a box crossed only by such a way is then taken for land.
enum SeaBuilder {
    struct Result: Equatable {
        /// Rings to fill with the even-odd rule: the sea polygons, and the islands as holes in them. Closed.
        var rings: [[PackedPoint]] = []
        /// The number of sea polygons.
        var seaPolygons = 0
        /// The number of islands cut out of them.
        var islands = 0
        /// Coastline pieces that start or end inside the box, or that do not close into a polygon; when there are any, no sea is built.
        var openEnds = 0
    }

    /// - Parameters:
    ///   - rings: Closed coastlines (first point repeated at the end).
    ///   - chains: Coastlines that are not closed.
    ///   - box: The block of cells the store covers.
    static func build(rings: [[PackedPoint]], chains: [[PackedPoint]], box: CellRect) -> Result {
        var result = Result()
        var pieces: [[PackedPoint]] = []
        var islands: [[PackedPoint]] = []
        var seaRings: [[PackedPoint]] = []

        for chain in chains { pieces.append(contentsOf: clipped(chain, to: box)) }
        for ring in rings {
            if ring.allSatisfy(box.contains) {
                if signedArea(ring) > 0 { islands.append(ring) } else if signedArea(ring) < 0 { seaRings.append(ring) }
            } else {
                var parts = clipped(ring, to: box)
                // A ring that starts inside the box is cut in two at its start: the last part continues into the first.
                if parts.count > 1, let first = parts.first, let last = parts.last, !onBorder(first[0], box) {
                    parts[0] = last + first.dropFirst()
                    parts.removeLast()
                }
                pieces.append(contentsOf: parts)
            }
        }

        result.openEnds = pieces.filter { piece in
            guard let first = piece.first, let last = piece.last else { return true }
            return !onBorder(first, box) || !onBorder(last, box)
        }.count
        if result.openEnds > 0 { return result }

        let walked = join(pieces, in: box)
        // Pieces that did not close into a polygon (their sides do not alternate, so the data is inconsistent) count as
        // open ends: a partial sea would be worse than none.
        if walked.unclosed > 0 {
            result.openEnds = walked.unclosed
            return result
        }
        seaRings.append(contentsOf: walked.polygons)
        if seaRings.isEmpty && pieces.isEmpty && !islands.isEmpty { seaRings = [boxRing(box)] }
        guard !seaRings.isEmpty else { return result }
        result.seaPolygons = seaRings.count

        // An island is a hole only if it lies in water; one on land (a coastline drawn inside a land area) is left alone.
        let water = seaRings
        for island in islands where contains(water, island[0]) {
            seaRings.append(island)
            result.islands += 1
        }
        result.rings = seaRings
        return result
    }

    // MARK: Pieces

    /// The parts of a polyline inside the box.
    private static func clipped(_ line: [PackedPoint], to box: CellRect) -> [[PackedPoint]] {
        LineClipper.clip(line, to: box).map(\.points)
    }

    private static func onBorder(_ point: PackedPoint, _ box: CellRect) -> Bool {
        point.longitude == box.west || point.longitude == box.east || point.latitude == box.south || point.latitude == box.north
    }

    // MARK: Walking the border

    /// Joins pieces into sea polygons by walking the border clockwise from each end to the next start.
    private static func join(_ pieces: [[PackedPoint]], in box: CellRect) -> (polygons: [[PackedPoint]], unclosed: Int) {
        guard !pieces.isEmpty else { return ([], 0) }
        let width = Int64(box.east) - Int64(box.west), height = Int64(box.north) - Int64(box.south)
        let perimeter = 2 * (width + height)

        /// The distance clockwise from the north-west corner.
        func position(_ point: PackedPoint) -> Int64 {
            if point.latitude == box.north { return Int64(point.longitude) - Int64(box.west) }
            if point.longitude == box.east { return width + Int64(box.north) - Int64(point.latitude) }
            if point.latitude == box.south { return width + height + Int64(box.east) - Int64(point.longitude) }
            return 2 * width + height + Int64(point.latitude) - Int64(box.south)
        }
        func ahead(_ from: Int64, _ to: Int64) -> Int64 { ((to - from) % perimeter + perimeter) % perimeter }

        let corners: [(position: Int64, point: PackedPoint)] = [
            (width, PackedPoint(longitude: box.east, latitude: box.north)),
            (width + height, PackedPoint(longitude: box.east, latitude: box.south)),
            (2 * width + height, PackedPoint(longitude: box.west, latitude: box.south)),
            (0, PackedPoint(longitude: box.west, latitude: box.north)),
        ]

        var used = [Bool](repeating: false, count: pieces.count)
        var polygons: [[PackedPoint]] = []
        var unclosed = 0
        for start in pieces.indices where !used[start] {
            used[start] = true
            var ring = pieces[start]
            var current = start
            var closed = false
            while true {
                let leaving = position(ring[ring.count - 1])
                var best: (index: Int, distance: Int64)?
                for index in pieces.indices where !used[index] || index == start {
                    let distance = ahead(leaving, position(pieces[index][0]))
                    if let known = best, known.distance <= distance { continue }
                    best = (index, distance)
                }
                guard let next = best else { break }
                for corner in corners.map({ ($0, ahead(leaving, $0.position)) }).sorted(by: { $0.1 < $1.1 })
                where corner.1 > 0 && corner.1 < next.distance {
                    ring.append(corner.0.point)
                }
                if next.index == start { closed = true; break }
                used[next.index] = true
                current = next.index
                ring.append(contentsOf: pieces[current])
            }
            if closed, ring.count >= 3 {
                if ring.first != ring.last { ring.append(ring[0]) }
                polygons.append(ring)
            } else {
                unclosed += 1
            }
        }
        return (polygons, unclosed)
    }

    private static func boxRing(_ box: CellRect) -> [PackedPoint] {
        let northWest = PackedPoint(longitude: box.west, latitude: box.north)
        return [
            northWest, PackedPoint(longitude: box.east, latitude: box.north), PackedPoint(longitude: box.east, latitude: box.south),
            PackedPoint(longitude: box.west, latitude: box.south), northWest,
        ]
    }

    // MARK: Geometry

    /// Twice the signed area in longitude and latitude (east and north as positive): positive for a counter-clockwise ring.
    private static func signedArea(_ ring: [PackedPoint]) -> Int64 {
        guard let origin = ring.first, ring.count >= 4 else { return 0 }
        var sum: Int64 = 0
        for index in 1..<(ring.count - 1) {
            let a = ring[index], b = ring[index + 1]
            let ax = Int64(a.longitude) - Int64(origin.longitude), ay = Int64(a.latitude) - Int64(origin.latitude)
            let bx = Int64(b.longitude) - Int64(origin.longitude), by = Int64(b.latitude) - Int64(origin.latitude)
            sum += ax * by - bx * ay
        }
        return sum
    }

    /// Whether a point is inside the rings, by the even-odd rule.
    static func contains(_ rings: [[PackedPoint]], _ point: PackedPoint) -> Bool {
        var inside = false
        let x = Double(point.longitude), y = Double(point.latitude)
        for ring in rings {
            for index in 0..<(ring.count - 1) {
                let a = ring[index], b = ring[index + 1]
                let ay = Double(a.latitude), by = Double(b.latitude)
                guard (ay > y) != (by > y) else { continue }
                let crossing = Double(a.longitude) + (y - ay) / (by - ay) * (Double(b.longitude) - Double(a.longitude))
                if x < crossing { inside.toggle() }
            }
        }
        return inside
    }
}
