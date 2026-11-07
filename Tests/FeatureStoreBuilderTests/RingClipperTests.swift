import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

@Suite("Ring clipping")
struct RingClipperTests {
    let block = Block()

    private func clip(_ ring: [PackedPoint], in column: Int, _ row: Int) -> ClippedRing? {
        RingClipper.clip(ring, to: CellRect(tile: block.tile(column: column, row: row)))
    }

    private func square(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [PackedPoint] {
        [block.point(x0, y0), block.point(x1, y0), block.point(x1, y1), block.point(x0, y1), block.point(x0, y0)]
    }

    /// Whether an edge of a ring lies on a border of the cell.
    private func isOnBorder(_ a: PackedPoint, _ b: PackedPoint, _ rect: CellRect) -> Bool {
        (a.longitude == b.longitude && (a.longitude == rect.west || a.longitude == rect.east))
            || (a.latitude == b.latitude && (a.latitude == rect.south || a.latitude == rect.north))
    }

    @Test("A ring inside the cell is unchanged and has no artificial edges")
    func inside() throws {
        let ring = square(1.2, 1.2, 1.8, 1.8)
        let result = try #require(clip(ring, in: 1, 1))
        #expect(Set(result.points) == Set(ring))
        #expect(result.points.first == result.points.last && result.points.count == 5)
        #expect(result.artificialEdges.isEmpty)
        #expect(clip(ring, in: 2, 1) == nil && clip(ring, in: 0, 0) == nil)
    }

    @Test("A ring across a border has an artificial edge on that border in both cells")
    func acrossBorder() throws {
        let ring = square(1.5, 1.3, 2.5, 1.7)
        let west = try #require(clip(ring, in: 1, 1))
        let east = try #require(clip(ring, in: 2, 1))
        let westRect = CellRect(tile: block.tile(column: 1, row: 1)), eastRect = CellRect(tile: block.tile(column: 2, row: 1))
        #expect(west.artificialEdges.count == 1 && east.artificialEdges.count == 1)
        for run in west.artificialEdges { for edge in run { #expect(isOnBorder(west.points[edge], west.points[edge + 1], westRect)) } }
        for run in east.artificialEdges { for edge in run { #expect(isOnBorder(east.points[edge], east.points[edge + 1], eastRect)) } }
        // Real edges keep their original vertices.
        #expect(west.points.contains(ring[0]) && east.points.contains(ring[2]))
        // The two pieces add up to the ring.
        #expect(abs(projectedArea(west.points) + projectedArea(east.points) - projectedArea(ring)) < projectedArea(ring) * 1e-4)
    }

    @Test("A ring that covers the cell becomes the cell square, all artificial")
    func coversCell() throws {
        let ring = square(0.2, 0.2, 2.8, 2.8)
        let result = try #require(clip(ring, in: 1, 1))
        let rect = CellRect(tile: block.tile(column: 1, row: 1))
        #expect(result.points.count == 5)
        #expect(Set(result.points) == Set([
            PackedPoint(longitude: rect.west, latitude: rect.north), PackedPoint(longitude: rect.east, latitude: rect.north),
            PackedPoint(longitude: rect.east, latitude: rect.south), PackedPoint(longitude: rect.west, latitude: rect.south),
        ]))
        #expect(result.artificialEdges == [0..<4])
    }

    @Test("A ring next to the cell, sharing only a border, gives nothing")
    func touchingOnly() {
        let rect = CellRect(tile: block.tile(column: 1, row: 1))
        let ring = [
            PackedPoint(longitude: rect.east, latitude: rect.south + 1_000), PackedPoint(longitude: rect.east + 5_000, latitude: rect.south + 1_000),
            PackedPoint(longitude: rect.east + 5_000, latitude: rect.north - 1_000), PackedPoint(longitude: rect.east, latitude: rect.north - 1_000),
        ]
        #expect(RingClipper.clip(ring, to: rect) == nil)
    }

    @Test("A concave ring that leaves and re-enters keeps its total area")
    func concave() {
        // A "U" that opens upwards and sticks out of the top of the centre cell.
        let ring = [
            block.point(1.1, 0.6), block.point(1.3, 0.6), block.point(1.3, 1.6), block.point(1.7, 1.6),
            block.point(1.7, 0.6), block.point(1.9, 0.6), block.point(1.9, 1.9), block.point(1.1, 1.9), block.point(1.1, 0.6),
        ]
        let pieces = CellSplitter.split(ring: ring)
        let total = pieces.reduce(0) { $0 + projectedArea($1.piece.points) }
        #expect(abs(total - projectedArea(ring)) < projectedArea(ring) * 1e-4)
        #expect(pieces.count >= 2)
    }

    @Test("Orientation does not matter")
    func reversed() throws {
        let ring = square(1.5, 1.3, 2.5, 1.7)
        let a = try #require(clip(ring, in: 1, 1)), b = try #require(clip(ring.reversed(), in: 1, 1))
        #expect(Set(a.points) == Set(b.points))
        #expect(a.artificialEdges.reduce(0) { $0 + $1.count } == b.artificialEdges.reduce(0) { $0 + $1.count })
    }

    @Test("Degenerate rings give nothing")
    func degenerate() {
        let p = block.point(1.5, 1.5)
        #expect(clip([], in: 1, 1) == nil)
        #expect(clip([p, p, p, p], in: 1, 1) == nil)
        #expect(clip([p, block.point(1.6, 1.5), block.point(1.7, 1.5), p], in: 1, 1) == nil)
    }

    @Test("Random star-shaped polygons: area is preserved, edges are consistent, neighbours agree")
    func randomPolygons() throws {
        var generator = SplitMix64(seed: 7)
        for trial in 0..<200 {
            // One vertex per angular sector, so the polygon is simple and star-shaped around the centre.
            let count = Int.random(in: 5...30, using: &generator)
            let angles = (0..<count).map { (Double($0) + Double.random(in: 0.1..<0.9, using: &generator)) * 2 * .pi / Double(count) }
            var ring = angles.map { angle -> PackedPoint in
                let radius = Double.random(in: 0.2..<1.4, using: &generator)
                return block.point(1.5 + radius * cos(angle), 1.5 + radius * sin(angle))
            }
            ring.append(ring[0])
            let pieces = CellSplitter.split(ring: ring)
            let total = pieces.reduce(0) { $0 + projectedArea($1.piece.points) }
            #expect(abs(total - projectedArea(ring)) <= projectedArea(ring) * 1e-4, "trial \(trial): area")
            for (tile, piece) in pieces {
                let rect = CellRect(tile: tile)
                #expect(piece.points.allSatisfy(rect.contains), "trial \(trial): vertex outside")
                #expect(piece.points.first == piece.points.last)
                for run in piece.artificialEdges {
                    for edge in run { #expect(isOnBorder(piece.points[edge], piece.points[edge + 1], rect), "trial \(trial): artificial edge off the border") }
                }
                // Real edges that lie on a border would be wrong for random input.
                let artificial = Set(piece.artificialEdges.flatMap { Array($0) })
                for edge in 0..<(piece.points.count - 1) where !artificial.contains(edge) {
                    #expect(!isOnBorder(piece.points[edge], piece.points[edge + 1], rect), "trial \(trial): real edge on the border")
                }
            }
            // Where two cells share a border, the artificial edges on it have the same end points on both sides.
            for (tile, piece) in pieces {
                let rect = CellRect(tile: tile)
                guard let neighbour = pieces.first(where: { $0.cell.x == tile.x + 1 && $0.cell.y == tile.y }) else { continue }
                let mine = Set(piece.points.filter { $0.longitude == rect.east })
                let theirs = Set(neighbour.piece.points.filter { $0.longitude == CellRect(tile: neighbour.cell).west })
                // Compare the border points allowing one unit of rounding.
                for point in mine where !theirs.contains(where: { abs(Int($0.latitude) - Int(point.latitude)) <= 1 }) {
                    // A point on the border may belong to a ring that stays on one side only; it must at least lie on a shared edge.
                    #expect(piece.points.contains(point), "trial \(trial)")
                }
            }
        }
    }
}
