import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

@Suite("Sea from coastlines")
struct SeaBuilderTests {
    private let block = Block()
    private var box: CellRect {
        CellRect(columns: block.centre.x - 1...block.centre.x + 1, rows: block.centre.y - 1...block.centre.y + 1, zoom: 13)!
    }

    /// A coastline through points given as block fractions (x east, y south, both 0 to 3).
    private func line(_ points: (Double, Double)...) -> [PackedPoint] { points.map { block.point($0.0, $0.1) } }

    private func sea(_ chains: [[PackedPoint]] = [], rings: [[PackedPoint]] = []) -> SeaBuilder.Result {
        SeaBuilder.build(rings: rings, chains: chains, box: box)
    }

    private func isWater(_ result: SeaBuilder.Result, _ x: Double, _ y: Double) -> Bool {
        SeaBuilder.contains(result.rings, block.point(x, y))
    }

    private var boxArea: Double { projectedArea(line((0, 0), (3, 0), (3, 3), (0, 3), (0, 0))) }

    @Test("Water is on the right of a coastline that runs west to east, so the south is sea")
    func eastward() {
        let result = sea([line((-0.3, 1.5), (1.5, 1.4), (3.3, 1.5))])
        #expect(result.openEnds == 0 && result.seaPolygons == 1 && result.islands == 0)
        #expect(isWater(result, 1.5, 2.5) && isWater(result, 0.2, 2.9) && isWater(result, 2.8, 1.9))
        #expect(!isWater(result, 1.5, 0.5) && !isWater(result, 0.2, 0.1))
        let ratio = projectedArea(result.rings[0]) / boxArea
        #expect(ratio > 0.45 && ratio < 0.55, "about half the box, was \(ratio)")
    }

    @Test("The same coastline run the other way round makes the north the sea")
    func westward() {
        let result = sea([line((3.3, 1.5), (1.5, 1.4), (-0.3, 1.5))])
        #expect(result.seaPolygons == 1)
        #expect(isWater(result, 1.5, 0.5) && !isWater(result, 1.5, 2.5))
    }

    @Test("A coastline that cuts a corner leaves the other three corners sea")
    func corner() {
        // From the north border to the east border, heading south-east: land is on the left, in the north-east corner.
        let result = sea([line((1.0, -0.2), (2.0, 0.5), (3.2, 1.0))])
        #expect(result.seaPolygons == 1 && result.openEnds == 0)
        #expect(!isWater(result, 2.8, 0.2))
        #expect(isWater(result, 0.2, 0.2) && isWater(result, 0.2, 2.8) && isWater(result, 2.8, 2.8))
    }

    @Test("Two coastlines with water between them make one sea")
    func strait() {
        let result = sea([line((-0.3, 0.8), (3.3, 0.8)), line((3.3, 2.2), (-0.3, 2.2))])
        #expect(result.seaPolygons == 1)
        #expect(isWater(result, 1.5, 1.5) && !isWater(result, 1.5, 0.3) && !isWater(result, 1.5, 2.7))
    }

    @Test("A peninsula that points into the sea is land, and the water goes around it")
    func peninsula() {
        let result = sea([line((-0.3, 0.5), (0.8, 0.5), (0.8, 1.2), (1.4, 1.2), (1.4, 0.5), (3.3, 0.5))])
        #expect(result.seaPolygons == 1)
        #expect(!isWater(result, 1.1, 0.9), "the peninsula is land")
        #expect(isWater(result, 1.1, 1.5) && isWater(result, 0.3, 0.9) && isWater(result, 1.7, 0.9))
        #expect(isWater(result, 0.3, 2.5) && !isWater(result, 0.3, 0.2))
    }

    @Test("A counter-clockwise island in open sea is a hole in the whole box")
    func islandInOpenSea() {
        // South-west, south-east, north-east, north-west: counter-clockwise, land inside.
        let island = line((1, 2), (2, 2), (2, 1), (1, 1), (1, 2))
        let result = sea(rings: [island])
        #expect(result.seaPolygons == 1 && result.islands == 1 && result.rings.count == 2)
        #expect(isWater(result, 0.3, 0.3) && !isWater(result, 1.5, 1.5))
    }

    @Test("A clockwise ring is water inside, not an island")
    func clockwiseRing() {
        let lake = line((1, 1), (2, 1), (2, 2), (1, 2), (1, 1))
        let result = sea(rings: [lake])
        #expect(result.seaPolygons == 1 && result.islands == 0)
        #expect(isWater(result, 1.5, 1.5) && !isWater(result, 0.3, 0.3))
    }

    @Test("An island on land is not cut out of anything")
    func islandOnLand() {
        let coast = line((-0.3, 1.0), (3.3, 1.0))
        let island = line((1, 2.8), (2, 2.8), (2, 2.1), (1, 2.1), (1, 2.8))      // north of the coast? no, south: in the sea
        let onLand = line((1, 0.8), (2, 0.8), (2, 0.2), (1, 0.2), (1, 0.8))      // north of the coast: on land
        let result = sea([coast], rings: [island, onLand])
        #expect(result.islands == 1)
        #expect(!isWater(result, 1.5, 2.4), "the island in the sea is a hole")
        #expect(!isWater(result, 1.5, 0.5), "land stays land")
    }

    @Test("An island that crosses the border of the box is a bite out of the sea")
    func islandAcrossTheBorder() {
        let island = line((2.5, 2), (3.5, 2), (3.5, 1), (2.5, 1), (2.5, 2))
        let result = sea(rings: [island])
        #expect(result.openEnds == 0 && result.seaPolygons == 1)
        #expect(isWater(result, 1.0, 1.5) && isWater(result, 2.8, 0.3) && isWater(result, 2.8, 2.7))
        #expect(!isWater(result, 2.8, 1.5))
    }

    @Test("A coastline that ends inside the box builds no sea")
    func openEnd() {
        let result = sea([line((-0.3, 1.5), (1.5, 1.5))])
        #expect(result.openEnds == 1 && result.rings.isEmpty && result.seaPolygons == 0)
    }

    @Test("No coastline, no sea; a coastline that does not reach the box is ignored")
    func nothing() {
        #expect(sea().rings.isEmpty)
        #expect(sea([line((10, 10), (11, 10))]).rings.isEmpty)
    }
}

@Suite("Sea per cell")
struct SeaPerCellTests {
    private let block = Block()

    @Test("A cell inside an island holds no sea, and a coastal cell holds one polygon with no edge twice")
    func cells() {
        let box = CellRect(columns: block.centre.x - 1...block.centre.x + 1, rows: block.centre.y - 1...block.centre.y + 1, zoom: 13)!
        // An island that covers the middle cell and part of its neighbours (counter-clockwise: land inside).
        let island = [block.point(0.7, 2.3), block.point(2.3, 2.3), block.point(2.3, 0.7), block.point(0.7, 0.7), block.point(0.7, 2.3)]
        let lines = SeaBuilder.Lines(rings: [island], chains: [])
        let sea = SeaBuilder.build(lines: lines, box: box).rings
        func parts(_ column: Int, _ row: Int) -> [GeometryPart] {
            SeaBuilder.parts(in: CellRect(tile: block.tile(column: column, row: row)), lines: lines, sea: sea)
        }
        #expect(parts(1, 1).isEmpty, "inside the island: nothing, not a square and a hole that cancel")
        // The corner cell has the island in its corner: water in an L shape, not the whole square.
        #expect(parts(0, 0).count == 1 && parts(0, 0)[0].points.count == 7)
        // The west cell has the island along its east side: water in a strip.
        let coastal = parts(0, 1)
        #expect(coastal.count == 1 && coastal[0].points.count == 5)
        let cell = CellRect(tile: block.tile(column: 0, row: 1))
        #expect(coastal[0].points.allSatisfy { $0.longitude <= block.point(0.7, 1).longitude })
        #expect(coastal[0].points.contains { $0.longitude == cell.west })
        #expect(!coastal[0].artificialEdges.isEmpty, "the edges along the cell border are artificial")
        // Every edge of every part is either on the cell border (artificial) or a coast edge: no part has two coincident edges.
        for column in 0..<3 { for row in 0..<3 {
            for part in parts(column, row) {
                let edges = zip(part.points, part.points.dropFirst()).map { Set([$0.0, $0.1]) }
                #expect(Set(edges).count == edges.count, "cell \(column),\(row) has an edge twice")
            }
        } }
    }
}

@Suite("Sea by cell buckets")
struct SeaBucketTests {
    private let block = Block()

    private func line(_ points: (Double, Double)...) -> [PackedPoint] { points.map { block.point($0.0, $0.1) } }

    /// The sea of every cell the slow way (every cell clips every coastline) and the fast way (segments sorted into cells).
    private func compare(rings: [[PackedPoint]], chains: [[PackedPoint]], _ name: String) throws {
        let columns = block.centre.x - 1...block.centre.x + 1, rows = block.centre.y - 1...block.centre.y + 1
        let box = try #require(CellRect(columns: columns, rows: rows, zoom: 13))
        let lines = SeaBuilder.Lines(rings: rings, chains: chains)
        let sea = SeaBuilder.build(lines: lines, box: box).rings
        let fast = SeaBuilder.parts(lines: lines, sea: sea, columns: columns, rows: rows, zoom: 13)
        for row in rows {
            for column in columns {
                let cell = CellRect(tile: try #require(TileID(zoom: 13, x: column, y: row)))
                let slow = SeaBuilder.parts(in: cell, lines: lines, sea: sea)
                let got = fast[(row - rows.lowerBound) * columns.count + (column - columns.lowerBound)] ?? []
                // The same parts, up to extra vertices where a coastline lies exactly along a cell border: compare the areas.
                let area = { (parts: [GeometryPart]) in parts.map { projectedArea($0.points) }.sorted() }
                let same = slow.count == got.count && zip(area(slow), area(got)).allSatisfy { abs($0 - $1) <= 1e-9 * max($0, $1, 1e-12) }
                #expect(same, "\(name): cell \(column - columns.lowerBound),\(row - rows.lowerBound): \(area(slow)) against \(area(got))")
            }
        }
    }

    @Test("The fast way agrees with the slow way on random islands and coasts")
    func randomScenes() throws {
        var random = SplitMix64(seed: 20_261_108)
        func unit() -> Double { Double(random.next() % 10_000) / 10_000 }
        for scene in 0..<300 {
            // Up to four islands: counter-clockwise polygons of 4 to 9 points around a random centre, of random size.
            var rings: [[PackedPoint]] = []
            for _ in 0..<Int(random.next() % 4) {
                let cx = unit() * 3, cy = unit() * 3, radius = 0.05 + unit() * 1.1
                let count = 4 + Int(random.next() % 6)
                var points: [(Double, Double)] = []
                for k in 0..<count {
                    let angle = Double(k) / Double(count) * 2 * Double.pi
                    let r = radius * (0.6 + 0.4 * unit())
                    points.append((cx + r * cos(angle), cy - r * sin(angle)))   // y grows south: counter-clockwise on the map
                }
                points.append(points[0])
                rings.append(points.map { block.point($0.0, $0.1) })
            }
            // Sometimes a coast across the block, as a few long segments.
            var chains: [[PackedPoint]] = []
            if random.next() % 2 == 0 {
                let y0 = unit() * 3, y1 = unit() * 3
                chains.append([block.point(-0.4, y0), block.point(1.0 + unit(), (y0 + y1) / 2 + unit() - 0.5), block.point(3.4, y1)])
            }
            try compare(rings: rings, chains: chains, "scene \(scene)")
        }
    }

    @Test("The fast way gives the same sea in every cell as the slow way")
    func sameAsTheSlowWay() throws {
        // A coast across the block, running through three cells.
        try compare(rings: [], chains: [line((-0.3, 1.5), (1.5, 1.4), (3.3, 1.5))], "coast")
        // The same coast the other way round.
        try compare(rings: [], chains: [line((3.3, 1.5), (1.5, 1.4), (-0.3, 1.5))], "coast, reversed")
        // A coast that cuts a corner, and a strait between two coasts.
        try compare(rings: [], chains: [line((1.0, -0.2), (2.0, 0.5), (3.2, 1.0))], "corner")
        try compare(rings: [], chains: [line((-0.3, 0.8), (3.3, 0.8)), line((3.3, 2.2), (-0.3, 2.2))], "strait")
        // Islands: one covering the middle cell (cells inside it are land), one small in a cell, one across a border.
        let big = line((0.7, 2.3), (2.3, 2.3), (2.3, 0.7), (0.7, 0.7), (0.7, 2.3))
        let small = line((0.1, 0.45), (0.3, 0.45), (0.3, 0.2), (0.1, 0.2), (0.1, 0.45))
        let across = line((2.5, 2), (3.5, 2), (3.5, 1), (2.5, 1), (2.5, 2))
        try compare(rings: [big, small, across], chains: [], "islands in open sea")
        // A clockwise ring (water inside) and an island on land beside a coast.
        let lake = line((1, 1), (2, 1), (2, 2), (1, 2), (1, 1))
        try compare(rings: [lake], chains: [], "lake")
        try compare(rings: [line((1, 2.8), (2, 2.8), (2, 2.1), (1, 2.1), (1, 2.8))], chains: [line((-0.3, 1.0), (3.3, 1.0))], "island and coast")
        // A coast that runs exactly along a cell border: the cells on both sides must agree with the slow way.
        let border = CellRect(tile: try #require(TileID(zoom: 13, x: block.centre.x, y: block.centre.y))).north
        let along = [PackedPoint(longitude: block.point(-0.3, 1).longitude, latitude: border), PackedPoint(longitude: block.point(3.3, 1).longitude, latitude: border)]
        try compare(rings: [], chains: [along], "along a border")
        // A ring that starts inside a cell and is cut by the border (the wrap case) and one that starts on a border.
        let wrap = line((1.2, 1.2), (1.8, 1.2), (1.8, 1.8), (1.2, 1.8), (1.2, 1.2))
        let wrapAcross = line((0.8, 1.5), (1.5, 1.2), (2.2, 1.5), (1.5, 1.8), (0.8, 1.5))
        try compare(rings: [wrap, wrapAcross], chains: [], "rings that start inside a cell")
        // Nothing at all.
        try compare(rings: [], chains: [], "nothing")
    }
}

@Suite("Cancelling squares")
struct CancellingSquareTests {
    private let block = Block()

    @Test("A cell inside an island holds nothing of the sea: the outer ring and the hole cancel")
    func cancels() {
        let rect = block.rect
        let square = GeometryPart(points: [
            PackedPoint(longitude: rect.west, latitude: rect.north), PackedPoint(longitude: rect.east, latitude: rect.north),
            PackedPoint(longitude: rect.east, latitude: rect.south), PackedPoint(longitude: rect.west, latitude: rect.south),
            PackedPoint(longitude: rect.west, latitude: rect.north),
        ])
        let other = GeometryPart(points: [block.point(1.2, 1.2), block.point(1.8, 1.2), block.point(1.5, 1.8), block.point(1.2, 1.2)])
        #expect(FeatureEmitter.withoutCancellingSquares([square, square], in: block.centre) == [])
        #expect(FeatureEmitter.withoutCancellingSquares([square, other, square], in: block.centre) == [other])
        #expect(FeatureEmitter.withoutCancellingSquares([square], in: block.centre) == [square])
        #expect(FeatureEmitter.withoutCancellingSquares([square, square, square], in: block.centre) == [square])
        #expect(FeatureEmitter.withoutCancellingSquares([other], in: block.centre) == [other])
    }
}
