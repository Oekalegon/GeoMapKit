import FeatureStore
import Foundation

/// Closes the gaps in the coastlines of an extract with straight lines.
///
/// An extract stops at a country border, and so do its coastlines: the shore on the other side is not in the file. A
/// coastline that ends inside the area the store covers cannot say where the water goes next, so no sea can be built from
/// it. Here the loose ends are joined: the end of a coastline to the nearest start of one (its own included) with a straight
/// line, as long as the line is short, crosses no coastline, and does not close a sliver. The sea then runs up to the line,
/// which stands for the border, and the map ends there. A coastline way that is broken in the middle (a missing node) is
/// repaired the same way.
///
/// A loose end that finds no partner, but lies at a country border (within ``borderTolerance`` of a border way of the
/// extract: the extract is cut along a polygon that follows the border to within a kilometre or so), is the place where the
/// coastline leaves the extract: it is extended straight on, in the direction of its last
/// stretch, to beyond the edge of the area, so the sea runs on up to the edge. A loose end that is not at a border stays
/// loose: the coastline is broken there, and no sea is built.
enum CoastlineGaps {
    /// The longest gap that is closed, in metres.
    static let defaultMaximumGap = 20_000.0
    /// How near a loose end must be to a country border, in metres, to be taken for a coastline that leaves the extract.
    static let borderTolerance = 1_500.0
    /// How far back from a loose end the direction of the coastline is taken, in metres.
    private static let directionReach = 50.0
    /// How far beyond the loose end an extension runs, in metres: well past the edge of any block.
    private static let extensionLength = 40_000.0
    /// A coastline closed on itself must enclose at least this share of the square of the gap, or it is a dangling stub.
    private static let minimumAreaShare = 0.05

    struct Result {
        /// The coastlines, with the closed gaps joined into them.
        var chains: [[PackedPoint]]
        /// The closed coastlines, including those the gaps closed.
        var rings: [[PackedPoint]]
        /// The length in metres of each gap that was closed.
        var gaps: [Double]
        /// The number of loose ends at a country border that were extended to the edge of the area.
        var extended = 0
    }

    /// - Parameters:
    ///   - chains: The coastlines that are not closed.
    ///   - rings: The closed coastlines.
    ///   - block: The block of cells the store covers. A loose end is one that lies inside it.
    ///   - maximumGap: The longest gap to close, in metres.
    ///   - borders: The country borders of the extract, as polylines; a loose end near one is extended to the edge.
    static func close(
        chains: [[PackedPoint]], rings: [[PackedPoint]], block: CellRect, borders: [[PackedPoint]] = [],
        maximumGap: Double = defaultMaximumGap
    ) -> Result {
        func inside(_ point: PackedPoint) -> Bool {
            point.longitude > block.west && point.longitude < block.east && point.latitude > block.south && point.latitude < block.north
        }
        let ends = chains.indices.filter { chains[$0].last.map(inside) == true }
        let starts = chains.indices.filter { chains[$0].first.map(inside) == true }
        guard !ends.isEmpty || !starts.isEmpty else { return Result(chains: chains, rings: rings, gaps: []) }

        // Every pair of a loose end and a loose start that is near enough, nearest first.
        var candidates: [(end: Int, start: Int, distance: Double)] = []
        for end in ends {
            for start in starts {
                guard let last = chains[end].last, let first = chains[start].first else { continue }
                let distance = Geodesy.distance(last, first)
                if distance <= maximumGap { candidates.append((end, start, distance)) }
            }
        }
        candidates.sort { ($0.distance, $0.end, $0.start) < ($1.distance, $1.end, $1.start) }

        let projection = LocalMetres(referenceLatitude: (Double(block.south) + Double(block.north)) / 2e7)
        var next: [Int: Int] = [:]
        var taken = Set<Int>()
        var gaps: [Double] = []
        for candidate in candidates where next[candidate.end] == nil && !taken.contains(candidate.start) {
            guard let from = chains[candidate.end].last, let to = chains[candidate.start].first,
                !crossesACoastline(from, to, chains: chains, rings: rings)
            else { continue }
            if candidate.end == candidate.start {
                // A coastline closed on itself must enclose something: a stub that doubles back is no coast.
                let ring = chains[candidate.end].map { projection.project($0) }
                guard shoelace(ring) >= minimumAreaShare * candidate.distance * candidate.distance else { continue }
            }
            next[candidate.end] = candidate.start
            taken.insert(candidate.start)
            gaps.append(candidate.distance)
        }
        // Loose ends that found no partner and lie on a border leave the extract: carry them straight on.
        var chains = chains
        var extended = 0
        for end in ends where next[end] == nil {
            guard let last = chains[end].last, isAtBorder(last, borders, projection),
                let far = farPoint(beyond: chains[end], atEnd: true, projection),
                !crossesACoastline(last, far, chains: chains, rings: rings)
            else { continue }
            chains[end].append(far)
            extended += 1
        }
        for start in starts where !taken.contains(start) {
            guard let first = chains[start].first, isAtBorder(first, borders, projection),
                let far = farPoint(beyond: chains[start], atEnd: false, projection),
                !crossesACoastline(first, far, chains: chains, rings: rings)
            else { continue }
            chains[start].insert(far, at: 0)
            extended += 1
        }
        guard !next.isEmpty || extended > 0 else { return Result(chains: chains, rings: rings, gaps: []) }

        var outChains: [[PackedPoint]] = [], outRings = rings
        var used = Set<Int>()
        for index in chains.indices where !taken.contains(index) {
            var path = chains[index]
            used.insert(index)
            var current = index
            while let following = next[current] {
                path += chains[following]
                used.insert(following)
                current = following
            }
            outChains.append(path)
        }
        // What is left lies on cycles: a coastline closed on itself, or several closed into a ring.
        for index in chains.indices where !used.contains(index) {
            var path = chains[index]
            used.insert(index)
            var current = index
            while let following = next[current], following != index {
                path += chains[following]
                used.insert(following)
                current = following
            }
            if let first = path.first { path.append(first) }
            outRings.append(path)
        }
        return Result(chains: outChains, rings: outRings, gaps: gaps, extended: extended)
    }

    /// Whether a point lies within ``borderTolerance`` of a border.
    private static func isAtBorder(_ point: PackedPoint, _ borders: [[PackedPoint]], _ projection: LocalMetres) -> Bool {
        let p = projection.project(point)
        for border in borders {
            for index in 0..<max(border.count - 1, 0) {
                let a = projection.project(border[index]), b = projection.project(border[index + 1])
                let dx = b.x - a.x, dy = b.y - a.y
                let squared = dx * dx + dy * dy
                let t = squared > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / squared, 0), 1) : 0
                let px = a.x + t * dx - p.x, py = a.y + t * dy - p.y
                if px * px + py * py <= borderTolerance * borderTolerance { return true }
            }
        }
        return false
    }

    /// A point far beyond one end of a coastline, on the line through that end and the coastline `directionReach` metres back.
    private static func farPoint(beyond chain: [PackedPoint], atEnd: Bool, _ projection: LocalMetres) -> PackedPoint? {
        let points = atEnd ? Array(chain.reversed()) : chain      // the end in question first
        guard let origin = points.first else { return nil }
        let o = projection.project(origin)
        var back: (x: Double, y: Double)?
        for point in points.dropFirst() {
            let p = projection.project(point)
            if ((p.x - o.x) * (p.x - o.x) + (p.y - o.y) * (p.y - o.y)).squareRoot() >= directionReach { back = p; break }
        }
        guard let back else { return nil }
        let dx = o.x - back.x, dy = o.y - back.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return nil }
        // Back from metres to 1e-7 degrees at the latitude of the end.
        let metresPerUnit = Geodesy.earthRadius * Double.pi / 180 / 1e7
        let latitude = Double(origin.latitude) / 1e7 * Double.pi / 180
        let longitude = Double(origin.longitude) + dx / length * extensionLength / (metresPerUnit * cos(latitude))
        let northing = Double(origin.latitude) + dy / length * extensionLength / metresPerUnit
        guard abs(longitude) < 1_800_000_000, abs(northing) < 850_000_000 else { return nil }
        return PackedPoint(longitude: Int32(longitude.rounded()), latitude: Int32(northing.rounded()))
    }

    private static func shoelace(_ points: [(x: Double, y: Double)]) -> Double {
        var sum = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Whether the segment between two points properly crosses a segment of any coastline (touching at its ends is no crossing).
    private static func crossesACoastline(
        _ from: PackedPoint, _ to: PackedPoint, chains: [[PackedPoint]], rings: [[PackedPoint]]
    ) -> Bool {
        func side(_ a: PackedPoint, _ b: PackedPoint, _ c: PackedPoint) -> Double {
            (Double(b.longitude) - Double(a.longitude)) * (Double(c.latitude) - Double(a.latitude))
                - (Double(b.latitude) - Double(a.latitude)) * (Double(c.longitude) - Double(a.longitude))
        }
        for line in chains + rings {
            for index in 0..<max(line.count - 1, 0) {
                let a = line[index], b = line[index + 1]
                if a == from || a == to || b == from || b == to { continue }
                let d1 = side(from, to, a), d2 = side(from, to, b), d3 = side(a, b, from), d4 = side(a, b, to)
                if d1 * d2 < 0 && d3 * d4 < 0 { return true }
            }
        }
        return false
    }
}
