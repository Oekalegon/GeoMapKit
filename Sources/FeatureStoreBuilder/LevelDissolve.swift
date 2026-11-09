import FeatureStore
import Foundation
import GeoCore

/// What ``LevelDissolve`` made of the rings of one feature.
struct LevelDissolveResult {
    /// The closed rings.
    var rings: [[PackedPoint]] = []
    /// The chains that did not close, not closed (each has at least three points).
    var open: [[PackedPoint]] = []
    /// How many ends were joined to a start within a pixel of the top zoom of the level.
    var joinedBySnap = 0
    /// How many ends were joined to a start on the same line of a border (within a few cells or at any distance).
    var joinedAlongBorder = 0
}

/// Joins the rings of an area feature that the cell clip cut apart.
///
/// Fill is even-odd, so the rings of a feature are only a set of closed outlines. The clip cut each ring at the cell
/// borders and marked the edges it created along a border as artificial. Dropping the artificial edges between two cells
/// that both hold a piece of the feature leaves the real edges of the feature, which meet at the border points exactly (the same
/// integer on both sides). Chaining them end to start gives the rings of the whole feature. An artificial edge that faces a cell
/// without a piece of the feature (a cell outside the area that was read, outside the data, or a cell of a block that holds none of
/// the feature, as an open sea far from a coast) stays: there the feature ends, and the edge closes the chain.
///
/// Two source blocks are built apart, and each simplifies the outline of the sea (and of a big lake) on its own, so where the outline
/// crosses the border of two blocks the real edges of the two sides can end a few metres apart and not at the same integer, and
/// where a coastline runs almost along the border the two lines cross it kilometres apart. A chain that is still open after the exact
/// join is therefore joined, nearest first, to a chain that starts within a pixel of its end at the top zoom of the level; then to
/// one on the same line of a cell border within ``maximumBorderGapCells`` cells; then to one on the same line of a cell border at any
/// distance (the ring is cut at the block afterwards, so the join only has to close it, and along the edge of the data it is the
/// right edge). Each join is counted. What still does not close is returned as open chains; a feature with more than
/// ``maximumOpenChains`` of them is not joined at all.
enum LevelDissolve {
    /// How many cells of zoom 13 an open end may be from the start of another chain on the same line of a border to be joined to it
    /// in the second stage.
    static let maximumBorderGapCells = 16
    /// The most open chains of one feature that are joined; a feature with more is left as it is (the number of pairs grows with the
    /// square).
    static let maximumOpenChains = 1_000

    /// - Parameters:
    ///   - rings: The rings of the pieces of one feature, with their cell.
    ///   - region: The area that was read, in source cells.
    ///   - snapRadians: How far an open end may be from the start of another chain to be joined to it in the first stage, in
    ///     projected radians (a pixel of the top zoom of the level).
    /// - Returns: The closed rings, the chains that stayed open, and how many joins were made.
    static func rings(of rings: [LevelRing], region: LevelRegion, snapRadians: Double) -> LevelDissolveResult {
        var result = LevelDissolveResult()
        let holders = Set(rings.map(\.cell))
        var fragments: [[PackedPoint]] = []
        for ring in rings {
            let n = ring.points.count - 1
            guard n >= 3 else { continue }
            let rect = CellRect(tile: ring.cell)
            var keep = [Bool](repeating: true, count: n)
            for range in ring.artificialEdges {
                for edge in range where edge >= 0 && edge < n {
                    keep[edge] = !isInterior(from: ring.points[edge], to: ring.points[edge + 1], rect: rect, holders: holders, region: region)
                }
            }
            if !keep.contains(false) { result.rings.append(ring.points); continue }
            guard let start = (0..<n).first(where: { keep[$0] && !keep[($0 + n - 1) % n] }) else { continue }
            var current: [PackedPoint] = []
            for step in 0..<n {
                let edge = (start + step) % n
                if keep[edge] {
                    if current.isEmpty { current.append(ring.points[edge]) }
                    current.append(ring.points[edge + 1])
                } else if !current.isEmpty {
                    fragments.append(current)
                    current = []
                }
            }
            if !current.isEmpty { fragments.append(current) }
        }

        // The exact join: chains of fragments whose end is the start of the next.
        var starts: [PackedPoint: [Int]] = [:]
        for (index, fragment) in fragments.enumerated() { starts[fragment[0], default: []].append(index) }
        var used = [Bool](repeating: false, count: fragments.count)
        // Start with the fragments that no other fragment leads into, so that a chain is followed from its beginning and an open
        // chain is counted once; what is left are closed loops of fragments.
        let ends = Set(fragments.map { $0[$0.count - 1] })
        let order = fragments.indices.filter { !ends.contains(fragments[$0][0]) } + fragments.indices.filter { ends.contains(fragments[$0][0]) }
        var pending: [[PackedPoint]] = []
        for index in order where !used[index] {
            used[index] = true
            var chain = fragments[index]
            while let last = chain.last, last != chain[0] {
                guard let next = starts[last]?.first(where: { !used[$0] }) else { break }
                used[next] = true
                chain.append(contentsOf: fragments[next].dropFirst())
            }
            if chain.last == chain[0] { result.rings.append(chain) } else if chain.count >= 2 { pending.append(chain) }
        }

        // The joins of the ends that are left.
        if pending.count <= maximumOpenChains {
            join(&pending, into: &result, counter: \.joinedBySnap) { end, start, distance in
                distance <= snapUnits(snapRadians, atLatitude: end.latitude)
            }
            join(&pending, into: &result, counter: \.joinedAlongBorder) { end, start, distance in
                sameBorderLine(end, start) && distance <= Double(maximumBorderGapCells) * cellUnits(atLatitude: end.latitude)
            }
            join(&pending, into: &result, counter: \.joinedAlongBorder) { end, start, _ in sameBorderLine(end, start) }
        }
        result.open = pending.filter { $0.count >= 3 }
        return result
    }

    /// Joins ends to starts, nearest pair first, for the pairs that `accepts`: a chain that is joined to a chain that leads back to
    /// it, or to itself, becomes a closed ring; the others become longer chains.
    private static func join(
        _ pending: inout [[PackedPoint]], into result: inout LevelDissolveResult, counter: WritableKeyPath<LevelDissolveResult, Int>,
        accepts: (PackedPoint, PackedPoint, Double) -> Bool
    ) {
        guard !pending.isEmpty else { return }
        var pairs: [(distance: Double, from: Int, to: Int)] = []
        for from in pending.indices {
            let end = pending[from][pending[from].count - 1]
            for to in pending.indices {
                let start = pending[to][0]
                let d = distance(end, start)
                if accepts(end, start, d) { pairs.append((d, from, to)) }
            }
        }
        guard !pairs.isEmpty else { return }
        pairs.sort { $0.distance < $1.distance }
        var next = [Int?](repeating: nil, count: pending.count)
        var previous = [Int?](repeating: nil, count: pending.count)
        for pair in pairs where next[pair.from] == nil && previous[pair.to] == nil {
            next[pair.from] = pair.to
            previous[pair.to] = pair.from
            result[keyPath: counter] += 1
        }
        var done = [Bool](repeating: false, count: pending.count)
        var rebuilt: [[PackedPoint]] = []
        // Paths, from their first chain.
        for head in pending.indices where previous[head] == nil {
            var chain: [PackedPoint] = []
            var current: Int? = head
            while let index = current, !done[index] {
                done[index] = true
                chain += pending[index]
                current = next[index]
            }
            rebuilt.append(chain)
        }
        // What is left are cycles: closed rings.
        for index in pending.indices where !done[index] {
            var ring: [PackedPoint] = []
            var current: Int? = index
            while let at = current, !done[at] {
                done[at] = true
                ring += pending[at]
                current = next[at]
            }
            if let first = ring.first { result.rings.append(ring + [first]) }
        }
        pending = rebuilt
    }

    // MARK: Geometry

    /// The distance of two points in units of 1e-7 degree of latitude (a degree of longitude is shorter by the cosine of the latitude).
    private static func distance(_ a: PackedPoint, _ b: PackedPoint) -> Double {
        let cosine = cos(Double(a.latitude) * 1e-7 * .pi / 180)
        return hypot(Double(Int64(a.longitude) - Int64(b.longitude)) * cosine, Double(Int64(a.latitude) - Int64(b.latitude)))
    }

    /// The height of a cell of zoom 13 in units of 1e-7 degree of latitude at a latitude (the width of a cell scaled by the cosine).
    private static func cellUnits(atLatitude latitude: Int32) -> Double {
        360.0 / 8192 * 1e7 * cos(Double(latitude) * 1e-7 * .pi / 180)
    }

    /// A length in projected radians as units of 1e-7 degree of latitude at a latitude: a projected radian is longer on the ground
    /// than a radian of latitude by 1 / cosine of the latitude.
    private static func snapUnits(_ radians: Double, atLatitude latitude: Int32) -> Double {
        radians * cos(Double(latitude) * 1e-7 * .pi / 180) * 180 / .pi * 1e7
    }

    /// Whether two points lie on the same line of a cell border: the same longitude that is the border of a column of cells of zoom 13,
    /// or the same latitude that is the border of a row.
    static func sameBorderLine(_ a: PackedPoint, _ b: PackedPoint) -> Bool {
        (a.longitude == b.longitude && isBorderLongitude(a.longitude)) || (a.latitude == b.latitude && isBorderLatitude(a.latitude))
    }

    private static func isBorderLongitude(_ longitude: Int32) -> Bool {
        let column = Int(((Double(longitude) / 1e7 + 180) / 360 * 8192).rounded())
        return (0...8192).contains(column) && CellRect.longitude(column: column, zoom: 13) == longitude
    }

    private static func isBorderLatitude(_ latitude: Int32) -> Bool {
        let y = Mercator.y(latitude: Double(latitude))
        let row = Int(((1 - y / .pi) / 2 * 8192).rounded())
        return (max(row - 1, 0)...min(row + 1, 8192)).contains { CellRect.latitude(row: $0, zoom: 13) == latitude }
    }

    /// Whether an artificial edge lies between two cells that both hold a piece of the feature, so that the other cell has its twin.
    private static func isInterior(from a: PackedPoint, to b: PackedPoint, rect: CellRect, holders: Set<TileID>, region: LevelRegion) -> Bool {
        let x = rect.tile.x, y = rect.tile.y
        let neighbour: (Int, Int)?
        if a.longitude == rect.west && b.longitude == rect.west { neighbour = (x - 1, y) }
        else if a.longitude == rect.east && b.longitude == rect.east { neighbour = (x + 1, y) }
        else if a.latitude == rect.north && b.latitude == rect.north { neighbour = (x, y - 1) }
        else if a.latitude == rect.south && b.latitude == rect.south { neighbour = (x, y + 1) }
        else { neighbour = nil }
        guard let (nx, ny) = neighbour, region.contains(x: nx, y: ny), let tile = TileID(zoom: rect.tile.zoom, x: nx, y: ny) else { return false }
        return holders.contains(tile)
    }
}
