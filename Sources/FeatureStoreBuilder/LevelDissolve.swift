import FeatureStore
import Foundation
import GeoCore

/// Joins the rings of an area feature that the cell clip cut apart.
///
/// Fill is even-odd, so the rings of a feature are only a set of closed outlines. The clip cut each ring at the cell
/// borders and marked the edges it created along a border as artificial. Dropping the artificial edges between two cells
/// that are both read leaves the real edges of the feature, which meet at the border points exactly (the same integer
/// on both sides). Chaining them end to start gives the rings of the whole feature. An artificial edge on the border of
/// the area that was read stays, because there the feature continues in a cell that is not read, and it closes the
/// chain.
///
/// Two source blocks are built apart, and each simplifies the outline of the sea (and of a big lake) on its own, so where the outline
/// crosses the border of two blocks the real edges of the two sides can end a few metres apart and not at the same integer. A chain
/// that is still open after the exact join is joined to the nearest chain that starts within a pixel of its end at the top zoom of the
/// level (``rings(of:present:region:snapRadians:)``), which at that zoom cannot be seen. A coastline that runs almost along the border
/// of two blocks crosses it at points that can differ by kilometres for a difference of a few metres in the line, so an end is also
/// joined to a start on the same line of the border, up to ``maximumBorderGapCells`` cells away: the sliver between them is as thin as
/// the difference of the two simplified lines. What is left is joined along a line of a border at any distance. What still does not
/// close is reported.
enum LevelDissolve {
    /// How many cells of zoom 13 an open end may be from the start of another chain on the same line of a border to be joined to it.
    static let maximumBorderGapCells = 16

    /// - Parameters:
    ///   - rings: The rings of the pieces of one feature, with their cell.
    ///   - present: The source cells that exist in the area that was read.
    ///   - region: The area that was read, in source cells.
    ///   - snapRadians: How far an open end may be from the start of another chain to be joined to it, in projected radians (a pixel
    ///     of the top zoom of the level).
    /// - Returns: The closed rings, and the number of chains that did not close (they are closed with a straight line).
    static func rings(of rings: [LevelRing], present: Set<TileID>, region: LevelRegion, snapRadians: Double) -> (rings: [[PackedPoint]], open: Int) {
        var closed: [[PackedPoint]] = []
        var fragments: [[PackedPoint]] = []
        for ring in rings {
            let n = ring.points.count - 1
            guard n >= 3 else { continue }
            let rect = CellRect(tile: ring.cell)
            var keep = [Bool](repeating: true, count: n)
            for range in ring.artificialEdges {
                for edge in range where edge >= 0 && edge < n {
                    keep[edge] = !isInterior(from: ring.points[edge], to: ring.points[edge + 1], rect: rect, present: present, region: region)
                }
            }
            if !keep.contains(false) { closed.append(ring.points); continue }
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
            if chain.last == chain[0] { closed.append(chain) } else if chain.count >= 2 { pending.append(chain) }
        }

        // Join an open end to the nearest start within a pixel or on the same line of a border within a few cells, or close a chain
        // whose end is that near its own start. What is left is joined along a line of a border at any distance: there is nothing
        // else it can be, and the ring is cut at the block afterwards.
        for anyDistanceOnBorder in [false, true] {
        var joined = true
        while joined {
            joined = false
            search: for i in pending.indices {
                let end = pending[i][pending[i].count - 1]
                var best: (index: Int, distance: Double)?
                for j in pending.indices {
                    let start = pending[j][0]
                    let distance = Self.distance(end, start)
                    let onBorderLine = end.longitude == start.longitude || end.latitude == start.latitude
                    let limit = onBorderLine
                        ? (anyDistanceOnBorder ? .infinity : Double(Self.maximumBorderGapCells) * Self.cellUnits(atLatitude: end.latitude))
                        : Self.snapUnits(snapRadians, atLatitude: end.latitude)
                    if distance <= limit, best == nil || distance < best!.distance { best = (j, distance) }
                }
                guard let target = best?.index else { continue }
                if target == i {
                    closed.append(pending[i] + [pending[i][0]])
                    pending.remove(at: i)
                } else {
                    let merged = pending[i] + pending[target]
                    for index in [i, target].sorted(by: >) { pending.remove(at: index) }
                    pending.append(merged)
                }
                joined = true
                break search
            }
        }
        }
        var open = 0
        for chain in pending where chain.count >= 3 {
            open += 1
            closed.append(chain + [chain[0]])
        }
        return (closed, open)
    }

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

    /// Whether an artificial edge lies between two cells that are both read, so that the other cell holds its twin.
    private static func isInterior(from a: PackedPoint, to b: PackedPoint, rect: CellRect, present: Set<TileID>, region: LevelRegion) -> Bool {
        let x = rect.tile.x, y = rect.tile.y
        let neighbour: (Int, Int)?
        if a.longitude == rect.west && b.longitude == rect.west { neighbour = (x - 1, y) }
        else if a.longitude == rect.east && b.longitude == rect.east { neighbour = (x + 1, y) }
        else if a.latitude == rect.north && b.latitude == rect.north { neighbour = (x, y - 1) }
        else if a.latitude == rect.south && b.latitude == rect.south { neighbour = (x, y + 1) }
        else { neighbour = nil }
        guard let (nx, ny) = neighbour, region.contains(x: nx, y: ny), let tile = TileID(zoom: rect.tile.zoom, x: nx, y: ny) else { return false }
        return present.contains(tile)
    }
}
