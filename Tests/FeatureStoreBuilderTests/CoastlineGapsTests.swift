import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

@Suite("Coastline gaps")
struct CoastlineGapsTests {
    private let block = Block()
    private var box: CellRect {
        CellRect(columns: block.centre.x - 1...block.centre.x + 1, rows: block.centre.y - 1...block.centre.y + 1, zoom: 13)!
    }

    private func line(_ points: (Double, Double)...) -> [PackedPoint] { points.map { block.point($0.0, $0.1) } }

    private func isWater(_ result: SeaBuilder.Result, _ x: Double, _ y: Double) -> Bool {
        SeaBuilder.contains(result.rings, block.point(x, y))
    }

    @Test("A coastline whose ends are both inside is closed on itself: land inside is an island")
    func islandFromAnOpenCoast() {
        // South, east, north: land on the left, so the land is inside the U.
        let closed = CoastlineGaps.close(chains: [line((1.0, 0.5), (1.0, 2.0), (2.0, 2.0), (2.0, 0.5))], rings: [], block: box)
        #expect(closed.chains.isEmpty && closed.rings.count == 1 && closed.gaps.count == 1)
        #expect(closed.rings[0].first == closed.rings[0].last)
        let sea = SeaBuilder.build(rings: closed.rings, chains: closed.chains, box: box)
        #expect(sea.openEnds == 0 && sea.islands == 1 && sea.seaPolygons == 1)
        #expect(isWater(sea, 0.3, 0.3) && !isWater(sea, 1.5, 1.2))
    }

    @Test("A coastline with the water inside is closed into a lake of water")
    func fjordHead() {
        let closed = CoastlineGaps.close(chains: [line((2.0, 0.5), (2.0, 2.0), (1.0, 2.0), (1.0, 0.5))], rings: [], block: box)
        #expect(closed.rings.count == 1)
        let sea = SeaBuilder.build(rings: closed.rings, chains: closed.chains, box: box)
        #expect(sea.openEnds == 0)
        #expect(isWater(sea, 1.5, 1.2) && !isWater(sea, 0.3, 0.3))
    }

    @Test("The end of one coastline is joined to the start of the next, and the gap is counted in metres")
    func joinsTwoCoastlines() {
        let closed = CoastlineGaps.close(
            chains: [line((-0.3, 1.0), (1.4, 1.0)), line((1.6, 1.0), (3.3, 1.0))], rings: [], block: box)
        #expect(closed.chains.count == 1 && closed.rings.isEmpty)
        #expect(closed.chains[0].count == 4)
        let gap = try? #require(closed.gaps.first)
        #expect(gap.map { $0 > 500 && $0 < 800 } == true, "about 0.2 cells, 660 m")
    }

    @Test("A gap is not closed across another coastline, nor when it is too long")
    func refusals() {
        let a = line((-0.3, 1.0), (1.4, 1.0)), b = line((1.6, 1.0), (3.3, 1.0))
        let across = line((1.5, -0.3), (1.5, 3.3))
        let blocked = CoastlineGaps.close(chains: [a, b, across], rings: [], block: box)
        #expect(blocked.gaps.isEmpty && blocked.chains.count == 3, "a coastline crosses the line")
        let far = CoastlineGaps.close(chains: [a, b], rings: [], block: box, maximumGap: 100)
        #expect(far.gaps.isEmpty && far.chains.count == 2, "0.2 cells is more than 100 m")
    }

    @Test("A dangling stub, which would close into a sliver, is left alone")
    func stub() {
        let closed = CoastlineGaps.close(chains: [line((0.5, 1.5), (1.5, 1.4))], rings: [], block: box)
        #expect(closed.gaps.isEmpty && closed.rings.isEmpty && closed.chains.count == 1)
    }

    @Test("A loose end at a country border is carried on to beyond the edge; one far from a border is not")
    func borders() throws {
        let coast = line((-0.3, 1.5), (0.8, 1.45), (1.5, 1.4))
        let border = line((1.5, 1.38), (1.5, 1.9))                       // 66 m from the end
        let carried = CoastlineGaps.close(chains: [coast], rings: [], block: box, borders: [border])
        #expect(carried.extended == 1 && carried.chains.count == 1)
        let last = try #require(carried.chains[0].last)
        #expect(!box.contains(last), "the extension leaves the block")
        #expect(last.longitude > block.point(3, 1.4).longitude, "straight on, to the east")
        let far = CoastlineGaps.close(chains: [coast], rings: [], block: box, borders: [line((2.5, 1.0), (2.5, 2.0))])
        #expect(far.extended == 0 && far.chains[0] == coast, "a border 3 km away is not this coastline's border")
        // The start of a coastline that comes in from the border is carried back.
        let incoming = line((1.5, 1.4), (2.2, 1.45), (3.3, 1.5))
        let back = CoastlineGaps.close(chains: [incoming], rings: [], block: box, borders: [border])
        let first = try #require(back.chains[0].first)
        #expect(back.extended == 1 && !box.contains(first))
        // And the sea can then be built.
        let sea = SeaBuilder.build(rings: [], chains: carried.chains, box: box)
        #expect(sea.openEnds == 0 && sea.seaPolygons == 1)
    }
}
