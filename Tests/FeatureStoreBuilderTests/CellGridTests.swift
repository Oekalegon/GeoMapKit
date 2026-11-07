import FeatureStore
import GeoCore
import Testing

@testable import FeatureStoreBuilder

@Suite("Cell borders")
struct CellGridTests {
    @Test("Borders match the tile corners, rounded to 1e-7 degrees")
    func bordersMatchTiles() {
        for tile in [TileID(zoom: 13, x: 4_312, y: 2_848)!, TileID(zoom: 13, x: 0, y: 0)!, TileID(zoom: 13, x: 4_096, y: 4_096)!] {
            let rect = CellRect(tile: tile)
            #expect(rect.west == Int32((tile.northWest.longitude * 1e7).rounded()))
            #expect(rect.north == Int32((tile.northWest.latitude * 1e7).rounded()))
            #expect(rect.east == Int32((tile.southEast.longitude * 1e7).rounded()))
            #expect(rect.south == Int32((tile.southEast.latitude * 1e7).rounded()))
        }
    }

    @Test("Neighbouring cells share their border integers exactly")
    func neighboursShareBorders() {
        let a = CellRect(tile: TileID(zoom: 13, x: 4_312, y: 2_848)!)
        let east = CellRect(tile: TileID(zoom: 13, x: 4_313, y: 2_848)!)
        let south = CellRect(tile: TileID(zoom: 13, x: 4_312, y: 2_849)!)
        #expect(a.east == east.west)
        #expect(a.south == south.north)
        #expect(a.northY > a.southY)
    }

    @Test("Candidate tiles include the tile of every point")
    func tilesCoverPoints() {
        let block = Block()
        var generator = SplitMix64(seed: 1)
        let points = (0..<50).map { _ in block.point(Double.random(in: 0..<3, using: &generator), Double.random(in: 0..<3, using: &generator)) }
        let tiles = Set(CellRect.tiles(covering: points, zoom: 13))
        for point in points {
            let tile = TileID.containing(Coordinate(latitude: Double(point.latitude) / 1e7, longitude: Double(point.longitude) / 1e7), zoom: 13)!
            #expect(tiles.contains(tile))
        }
        #expect(CellRect.tiles(covering: [], zoom: 13).isEmpty)
    }

    @Test("Band tolerances")
    func tolerances() {
        let overview = GeometrySimplifier.tolerance(for: .overview)!
        let mid = GeometrySimplifier.tolerance(for: .mid)!
        #expect(GeometrySimplifier.tolerance(for: .detail) == nil)
        // Metres at the equator: radians times the earth radius.
        #expect(abs(overview * 6_378_137 - 38.2) < 0.2)
        #expect(abs(mid * 6_378_137 - 4.78) < 0.05)
    }
}
