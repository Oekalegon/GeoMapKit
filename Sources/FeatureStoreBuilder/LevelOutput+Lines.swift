import FeatureStore
import GeoCore

extension LevelOutput {
    /// Joins the pieces of every line by their end points, drops the chain when it is small, cuts it at the border of the
    /// block, simplifies what lies in the block and cuts that into the cells of the level.
    ///
    /// A chain is small when the *network* it belongs to is small: the chains of one class that meet at an end point (the nodes that
    /// OSM ways share) are one network, and it is the extent of the network that is judged. A road is many ways, each a few hundred
    /// metres between two junctions, and judged one by one nearly all of them are under three pixels at a low zoom: the road
    /// comes out as dashes. Judged as a network the road stays whole, and only a stub that is not connected to anything is left out.
    ///
    /// Two pieces are one line where a piece that continues ends exactly where a piece that has a predecessor starts: the
    /// clip puts the same integer on the border of both cells. The cut at the block comes before the simplification, so
    /// that the point where a line crosses the border of the block is the same in both blocks (the end points of a
    /// simplified line are kept), whatever part of the line each block read.
    mutating func writeLines(_ collected: LevelCollection) throws {
        var allChains: [(key: LevelKey, attributes: LevelAttributes, line: [PackedPoint])] = []
        for key in collected.lines.keys.sorted() {
            guard let pieces = collected.lines[key], let attributes = collected.attributes[key] else { continue }
            // The outline of a water area that was left out (see `writeAreas`) goes with it.
            if key.classID == FeatureClass.waterEdge.rawValue, droppedWater.contains(LevelWaterKey(type: key.type, id: key.id)) {
                report.droppedAsSmall += 1
                continue
            }
            var starts: [PackedPoint: [Int]] = [:]
            for (index, piece) in pieces.enumerated() where piece.continuesBefore {
                starts[piece.points[0], default: []].append(index)
            }
            var next = [Int?](repeating: nil, count: pieces.count)
            var hasPredecessor = [Bool](repeating: false, count: pieces.count)
            for (index, piece) in pieces.enumerated() where piece.continuesAfter {
                guard let end = piece.points.last,
                    let candidate = starts[end]?.first(where: { $0 != index && !hasPredecessor[$0] })
                else { continue }
                next[index] = candidate
                hasPredecessor[candidate] = true
            }
            var visited = [Bool](repeating: false, count: pieces.count)
            func chain(from first: Int) -> [PackedPoint] {
                var points: [PackedPoint] = []
                var current: Int? = first
                while let index = current, !visited[index] {
                    visited[index] = true
                    points.append(contentsOf: points.isEmpty ? pieces[index].points[...] : pieces[index].points.dropFirst())
                    if next[index] != nil { report.linesJoined += 1 }
                    current = next[index]
                }
                return points
            }
            var chains: [[PackedPoint]] = []
            for index in pieces.indices where !hasPredecessor[index] && !visited[index] { chains.append(chain(from: index)) }
            for index in pieces.indices where !visited[index] { chains.append(chain(from: index)) }  // a closed loop of pieces
            // A river name is the course of a river in its own water area (which is drawn instead of a line). Where that area is kept at
            // this level the stretch stays a river name, and only if the level has the class; where the area was left out as too thin the
            // river is written as a line, so that it does not vanish.
            var tagged: [(key: LevelKey, line: [PackedPoint])] = chains.map { (key, $0) }
            if key.classID == FeatureClass.riverName.rawValue {
                let asLine = LevelKey(classID: FeatureClass.waterLine.rawValue, type: key.type, id: key.id)
                tagged = chains.compactMap { line in
                    if isInKeptWater(line[line.count / 2]) { return spec.classes.contains(key.classID) ? (key, line) : nil }
                    report.riverNamesAsLines += 1
                    return (asLine, line)
                }
            }
            for (key, line) in tagged where line.count >= 2 { allChains.append((key, attributes, line)) }
        }

        let networkExtent = LevelChainMerger.networkExtents(of: allChains.map { ($0.key.classID, $0.line) })
        var judged: [LevelChain] = []
        for (index, item) in allChains.enumerated() {
            guard networkExtent[index] >= spec.minimumExtent, extent(item.line) >= spec.minimumChainExtent else {
                report.droppedAsSmall += 1
                continue
            }
            judged.append(LevelChain(key: item.key, attributes: item.attributes, line: item.line))
        }
        let chainsBefore = judged.count
        let joined = LevelChainMerger.merge(judged, block: CellRect(tile: tile))
        report.linesJoined += chainsBefore - joined.count
        for chain in joined {
            let (key, attributes, line) = (chain.key, chain.attributes, chain.line)
            for (blockCell, inBlockPiece) in CellSplitter.split(line: line, zoom: tile.zoom) where blockCell == tile {
                let simplified = GeometrySimplifier.simplify(line: inBlockPiece.points, tolerance: spec.tolerance)
                for (cell, piece) in CellSplitter.split(line: simplified, zoom: spec.storageZoom) where inBlock(cell) {
                    var flags = piece.flags
                    // The ends of the piece in the block continue in the neighbouring block.
                    if inBlockPiece.continuesBefore && piece.points.first == simplified.first { flags.insert(.continuesBefore) }
                    if inBlockPiece.continuesAfter && piece.points.last == simplified.last { flags.insert(.continuesAfter) }
                    let offset = UInt32(clamping: UInt64(inBlockPiece.offsetCentimetres) + UInt64(piece.offsetCentimetres))
                    try add(key, attributes, kind: .line, flags: flags, offset: offset, parts: [GeometryPart(points: piece.points)], in: cell)
                }
            }
        }
    }
}
