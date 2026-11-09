import FeatureStore
import GeoCore

extension LevelOutput {
    /// Joins the pieces of every line by their end points, simplifies the chain, drops it when it is small, and cuts it.
    ///
    /// Two pieces are one line where a piece that continues ends exactly where a piece that has a predecessor starts: the
    /// clip puts the same integer on the border of both cells.
    mutating func writeLines(_ collected: LevelCollection) throws {
        for key in collected.lines.keys.sorted() {
            guard let pieces = collected.lines[key], let attributes = collected.attributes[key] else { continue }
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
            for line in chains where line.count >= 2 {
                guard extent(line) >= spec.minimumExtent else { report.droppedAsSmall += 1; continue }
                let simplified = GeometrySimplifier.simplify(line: line, tolerance: spec.tolerance)
                for (cell, piece) in CellSplitter.split(line: simplified, zoom: spec.storageZoom) where inBlock(cell) {
                    try add(
                        key, attributes, kind: .line, flags: piece.flags, offset: piece.offsetCentimetres,
                        parts: [GeometryPart(points: piece.points)], in: cell)
                }
            }
        }
    }
}
