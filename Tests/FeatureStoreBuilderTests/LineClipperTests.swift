import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

@Suite("Line clipping")
struct LineClipperTests {
    let block = Block()

    private func pieces(_ line: [PackedPoint], in column: Int, _ row: Int) -> [ClippedLine] {
        LineClipper.clip(line, to: CellRect(tile: block.tile(column: column, row: row)))
    }

    @Test("A line inside one cell is one piece without flags")
    func inside() {
        let line = [block.point(1.2, 1.2), block.point(1.5, 1.4), block.point(1.8, 1.7)]
        let result = pieces(line, in: 1, 1)
        #expect(result.count == 1)
        #expect(result[0].points == line)
        #expect(result[0].flags == [] && result[0].offsetCentimetres == 0)
        for (column, row) in [(0, 1), (2, 1), (1, 0), (1, 2), (0, 0)] { #expect(pieces(line, in: column, row).isEmpty) }
    }

    @Test("A line across a border has two pieces that meet at one point with matching offsets")
    func acrossOneBorder() throws {
        let line = [block.point(1.6, 1.5), block.point(2.4, 1.5)]
        let west = try #require(pieces(line, in: 1, 1).first)
        let east = try #require(pieces(line, in: 2, 1).first)
        #expect(west.flags == [.continuesAfter] && east.flags == [.continuesBefore])
        #expect(west.points.first == line[0] && east.points.last == line[1])
        #expect(west.points.last == east.points.first)
        #expect(west.points.last?.longitude == CellRect(tile: block.tile(column: 1, row: 1)).east)
        #expect(abs(Double(east.offsetCentimetres) - length(west.points) * 100) < 5)
    }

    @Test("A line that leaves a cell and returns gives two pieces in it")
    func leavesAndReturns() {
        let line = [block.point(1.2, 1.5), block.point(1.5, 1.5), block.point(1.5, 0.5), block.point(1.8, 0.5), block.point(1.8, 1.5), block.point(1.9, 1.5)]
        let result = pieces(line, in: 1, 1)
        #expect(result.count == 2)
        #expect(result[0].flags == [.continuesAfter] && result[0].offsetCentimetres == 0)
        #expect(result[1].flags == [.continuesBefore] && result[1].offsetCentimetres > result[0].offsetCentimetres)
        // The part above the cell is in the cell to the north, as one piece with both flags.
        let north = pieces(line, in: 1, 0)
        #expect(north.count == 1 && north[0].flags == [.continuesBefore, .continuesAfter])
    }

    @Test("A line along a border belongs to the west or north cell only")
    func alongBorder() {
        let rect = CellRect(tile: block.tile(column: 1, row: 1))
        let south = rect.south
        let alongSouth = [PackedPoint(longitude: rect.west + 1_000, latitude: south), PackedPoint(longitude: rect.east - 1_000, latitude: south)]
        #expect(pieces(alongSouth, in: 1, 1).isEmpty)
        #expect(pieces(alongSouth, in: 1, 2).count == 1)
        let alongEast = [PackedPoint(longitude: rect.east, latitude: rect.south + 1_000), PackedPoint(longitude: rect.east, latitude: rect.north - 1_000)]
        #expect(pieces(alongEast, in: 1, 1).isEmpty)
        #expect(pieces(alongEast, in: 2, 1).count == 1)
    }

    @Test("A line that only touches a corner or a border from outside gives nothing")
    func touching() {
        let rect = CellRect(tile: block.tile(column: 1, row: 1))
        let corner = PackedPoint(longitude: rect.east, latitude: rect.south)
        let line = [PackedPoint(longitude: rect.east + 2_000, latitude: rect.south - 1_000), corner, PackedPoint(longitude: rect.east + 1_000, latitude: rect.south - 3_000)]
        #expect(pieces(line, in: 1, 1).isEmpty)
        let touchEdge = [PackedPoint(longitude: rect.east + 2_000, latitude: rect.south + 5_000), PackedPoint(longitude: rect.east, latitude: rect.south + 8_000), PackedPoint(longitude: rect.east + 2_000, latitude: rect.south + 11_000)]
        #expect(pieces(touchEdge, in: 1, 1).isEmpty)
    }

    @Test("Degenerate input gives nothing")
    func degenerate() {
        let p = block.point(1.5, 1.5)
        #expect(pieces([], in: 1, 1).isEmpty)
        #expect(pieces([p], in: 1, 1).isEmpty)
        #expect(pieces([p, p, p], in: 1, 1).isEmpty)
        #expect(pieces([p, p, block.point(1.6, 1.5)], in: 1, 1).first?.points.count == 2)
    }

    @Test("A line that starts and ends outside the cell but crosses it")
    func passesThrough() throws {
        let line = [block.point(0.5, 1.5), block.point(2.5, 1.5)]
        let middle = try #require(pieces(line, in: 1, 1).first)
        #expect(middle.flags == [.continuesBefore, .continuesAfter])
        #expect(middle.points.count == 2)
        #expect(abs(length(middle.points) - length(line) / 2) < length(line) * 0.02)
    }

    @Test("Random lines: pieces stay in their cell, keep their length, and chain across borders", arguments: Location.all)
    func randomLines(location: Location) throws {
        let block = Block(latitude: location.latitude, longitude: location.longitude)
        var generator = SplitMix64(seed: 42)
        for trial in 0..<300 {
            let count = Int.random(in: 2...25, using: &generator)
            let line = (0..<count).map { _ in block.point(Double.random(in: 0.05..<2.95, using: &generator), Double.random(in: 0.05..<2.95, using: &generator)) }
            let split = CellSplitter.split(line: line)
            var all: [ClippedLine] = []
            for (tile, piece) in split {
                let rect = CellRect(tile: tile)
                #expect(piece.points.allSatisfy(rect.contains), "trial \(trial): vertex outside its cell")
                all.append(piece)
            }
            // Total length is preserved.
            let total = all.reduce(0) { $0 + length($1.points) }
            #expect(abs(total - length(line)) <= max(1, length(line) * 1e-4), "trial \(trial): length")
            // Every original vertex is in some piece.
            let stored = Set(all.flatMap(\.points))
            for vertex in line { #expect(stored.contains(vertex), "trial \(trial): lost a vertex") }
            // In offset order the pieces chain: a piece that continues after meets the next piece that continues before.
            let ordered = all.sorted { $0.offsetCentimetres < $1.offsetCentimetres }
            for (piece, next) in zip(ordered, ordered.dropFirst()) where piece.continuesAfter {
                #expect(next.continuesBefore, "trial \(trial): broken chain")
                let a = try #require(piece.points.last), b = try #require(next.points.first)
                #expect(abs(Int(a.longitude) - Int(b.longitude)) <= 1 && abs(Int(a.latitude) - Int(b.latitude)) <= 1, "trial \(trial): seam")
                #expect(abs(Double(next.offsetCentimetres) - Double(piece.offsetCentimetres) - length(piece.points) * 100) <= 20, "trial \(trial): offset")
            }
            #expect(ordered.first?.continuesBefore == false && ordered.last?.continuesAfter == false)
        }
    }

    @Test("At the edge of the world a piece along the east or south border stays with its only cell")
    func worldEdge() {
        let last = CellRect(tile: TileID(zoom: 13, x: 8_191, y: 8_191)!)
        let alongEast = [PackedPoint(longitude: last.east, latitude: last.south + 1_000), PackedPoint(longitude: last.east, latitude: last.north - 1_000)]
        #expect(LineClipper.clip(alongEast, to: last).count == 1)
        let alongSouth = [PackedPoint(longitude: last.west + 1_000, latitude: last.south), PackedPoint(longitude: last.east - 1_000, latitude: last.south)]
        #expect(LineClipper.clip(alongSouth, to: last).count == 1)
    }
}
