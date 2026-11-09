import FeatureStore
import GeoCore

extension LevelOutput {
    /// Dissolves the rings of every area feature, drops the small ones, cuts them at the border of the block, simplifies
    /// what lies in the block (the edges along the border of the block are kept as they are) and cuts that into level cells.
    /// The chains that stay open are written apart, as an incomplete feature.
    mutating func writeAreas(_ collected: LevelCollection, region: LevelRegion) throws {
        let blockRect = CellRect(tile: tile)

        /// The parts of the rings in the cells of the level: dropped when small, cut at the block, simplified, cut into cells.
        func parts(of rings: [[PackedPoint]]) -> [TileID: [GeometryPart]] {
            var partsByCell: [TileID: [GeometryPart]] = [:]
            for ring in rings {
                guard extent(ring) >= spec.minimumExtent else { report.droppedAsSmall += 1; continue }
                guard let clipped = RingClipper.clip(ring, to: blockRect) else { continue }
                guard let simplified = Self.simplified(clipped, tolerance: spec.tolerance) else {
                    report.droppedAsSmall += 1
                    continue
                }
                for (cell, piece) in CellSplitter.split(ring: simplified, zoom: spec.storageZoom) where inBlock(cell) {
                    var part = piece.part
                    // The clip at the block made these edges; the clip at the cell sees them as ordinary edges.
                    part.artificialEdges = Self.merged(part.artificialEdges + Self.edgesOnBorder(of: part.points, rect: blockRect))
                    partsByCell[cell, default: []].append(part)
                }
            }
            return partsByCell
        }

        for key in collected.rings.keys.sorted() {
            guard let rings = collected.rings[key], let attributes = collected.attributes[key] else { continue }
            let dissolved = LevelDissolve.rings(of: rings, region: region, snapRadians: 2 * spec.tolerance)
            report.joinedBySnap += dissolved.joinedBySnap
            report.joinedAlongBorder += dissolved.joinedAlongBorder
            report.openAreaChains += dissolved.open.count

            // A water area that is a ditch or a canal (thin) or a pond (small) is left out at this zoom, with its outline: a polder is
            // cut by thousands of them and they colour the land blue. A feature with an open chain is not judged, because what was
            // read of it is only a part.
            if key.classID == FeatureClass.waterArea.rawValue, dissolved.open.isEmpty {
                let size = widthAndArea(of: dissolved.rings)
                if size.width < spec.minimumWaterWidth || size.area < spec.minimumWaterArea {
                    droppedWater.insert(LevelWaterKey(type: key.type, id: key.id))
                    report.droppedAsSmall += 1
                    continue
                }
            }

            if key.classID == FeatureClass.waterArea.rawValue { keptWater.append(dissolved.rings) }

            // The rings that closed are filled; a chain that did not close is written on its own, closed with a straight line and
            // marked incomplete, so that it is drawn as an outline and the rest of the feature (the sea of the block) keeps its fill.
            let closed = parts(of: dissolved.rings)
            for cell in closed.keys.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
                guard let parts = FeatureEmitter.withoutCancellingSquares(closed[cell] ?? [], in: cell), !parts.isEmpty else { continue }
                try add(key, attributes, kind: .area, parts: parts, in: cell)
            }
            guard !dissolved.open.isEmpty else { continue }
            var incomplete = attributes
            incomplete.incomplete = true
            let open = parts(of: dissolved.open.compactMap { chain in chain.first.map { chain + [$0] } })
            for cell in open.keys.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
                guard let parts = open[cell], !parts.isEmpty else { continue }
                try add(key, incomplete, kind: .area, parts: parts, in: cell)
            }
        }
    }

    /// Simplifies a ring that was clipped to the block: the real runs of edges are simplified with their end points kept, the
    /// artificial runs (along the border of the block) are left as they are.
    ///
    /// - Returns: The closed ring, or `nil` if too little is left.
    static func simplified(_ ring: ClippedRing, tolerance: Double) -> [PackedPoint]? {
        let points = Array(ring.points.dropLast())
        let n = points.count
        guard n >= 3 else { return nil }
        var artificial = [Bool](repeating: false, count: n)
        for range in ring.artificialEdges { for edge in range where edge >= 0 && edge < n { artificial[edge] = true } }
        if !artificial.contains(true) { return GeometrySimplifier.simplify(ring: ring.points, tolerance: tolerance) }
        if !artificial.contains(false) { return ring.points }
        guard let start = (0..<n).first(where: { artificial[($0 + n - 1) % n] && !artificial[$0] }) else { return nil }
        var result: [PackedPoint] = []
        var run: [PackedPoint] = []
        var runIsArtificial = artificial[start]
        func close() {
            guard !run.isEmpty else { return }
            let part = runIsArtificial ? run : GeometrySimplifier.simplify(line: run, tolerance: tolerance)
            result.append(contentsOf: result.isEmpty ? part[...] : part.dropFirst())
        }
        for step in 0..<n {
            let edge = (start + step) % n
            if artificial[edge] != runIsArtificial { close(); run = []; runIsArtificial = artificial[edge] }
            if run.isEmpty { run = [points[edge]] }
            run.append(points[(edge + 1) % n])
        }
        close()
        return result.count >= 4 && result.first == result.last ? result : nil
    }

    /// The runs of edges that lie along the border of a rectangle.
    static func edgesOnBorder(of points: [PackedPoint], rect: CellRect) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        for edge in 0..<max(0, points.count - 1) {
            let a = points[edge], b = points[edge + 1]
            let onBorder = (a.longitude == rect.west && b.longitude == rect.west) || (a.longitude == rect.east && b.longitude == rect.east)
                || (a.latitude == rect.north && b.latitude == rect.north) || (a.latitude == rect.south && b.latitude == rect.south)
            if onBorder { runs.append(edge..<(edge + 1)) }
        }
        return runs
    }

    /// Sorted, joined runs of edges.
    static func merged(_ runs: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for run in runs.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, run.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, run.upperBound)
            } else {
                result.append(run)
            }
        }
        return result
    }
}
