import FeatureStore
import GeoCore

/// Joins the rings of an area feature that the cell clip cut apart.
///
/// Fill is even-odd, so the rings of a feature are only a set of closed outlines. The clip cut each ring at the cell
/// borders and marked the edges it created along a border as artificial. Dropping the artificial edges between two cells
/// that are both read leaves the real edges of the feature, which meet at the border points exactly (the same integer
/// on both sides). Chaining them end to start gives the rings of the whole feature. An artificial edge on the border of
/// the area that was read stays, because there the feature continues in a cell that is not read, and it closes the
/// chain.
enum LevelDissolve {
    /// - Parameters:
    ///   - rings: The rings of the pieces of one feature, with their cell.
    ///   - present: The source cells that exist in the area that was read.
    ///   - region: The area that was read, in source cells.
    /// - Returns: The closed rings, and the number of chains that did not close (they are closed with a straight line).
    static func rings(of rings: [LevelRing], present: Set<TileID>, region: LevelRegion) -> (rings: [[PackedPoint]], open: Int) {
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
        var open = 0
        // Start with the fragments that no other fragment leads into, so that a chain is followed from its beginning and an open
        // chain is counted once; what is left are closed loops of fragments.
        let ends = Set(fragments.map { $0[$0.count - 1] })
        let order = fragments.indices.filter { !ends.contains(fragments[$0][0]) } + fragments.indices.filter { ends.contains(fragments[$0][0]) }
        for index in order where !used[index] {
            used[index] = true
            var chain = fragments[index]
            while let last = chain.last, last != chain[0] {
                guard let next = starts[last]?.first(where: { !used[$0] }) else { break }
                used[next] = true
                chain.append(contentsOf: fragments[next].dropFirst())
            }
            if chain.last == chain[0] {
                closed.append(chain)
            } else if chain.count >= 3 {
                open += 1
                closed.append(chain + [chain[0]])
            }
        }
        return (closed, open)
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
