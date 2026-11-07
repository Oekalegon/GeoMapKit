import GeoCore
import Testing

@testable import FeatureStoreBuilder

@Suite("Cell aligned box")
struct CellAlignedBoxTests {
    /// One cell of longitude at the storage zoom, in degrees.
    private let cell = 360.0 / 8_192

    private func padded(_ box: BoundingBox) -> BoundingBox { FeatureStoreBuilder.cellAlignedBox(covering: box) }

    @Test func theResultContainsTheBoxAndGrowsByLessThanOneCellPerSide() {
        let box = BoundingBox(south: 47.03, west: 9.45, north: 47.29, east: 9.66)
        let result = padded(box)
        #expect(result.west <= box.west && result.east >= box.east && result.south <= box.south && result.north >= box.north)
        #expect(box.west - result.west < cell && result.east - box.east < cell)
        #expect(box.south - result.south < cell && result.north - box.north < cell)
    }

    @Test func everyCellOfThePaddedBoxIsWrittenSoTheFileCoversTheBox() throws {
        let box = BoundingBox(south: 47.03, west: 9.45, north: 47.29, east: 9.66)
        let result = padded(box)
        let range = try #require(FeatureStoreBuilder.writtenCells(in: result))
        // The written cells tile exactly the padded box: nothing is dropped any more.
        let columns = Double(range.columns.count) * cell
        #expect(abs((result.east - result.west) - columns) < 1e-6)
        // The box that was asked for falls inside the written cells.
        let unpadded = FeatureStoreBuilder.writtenCells(in: box)
        #expect(range.columns.count > (unpadded?.columns.count ?? 0))
    }

    @Test func aBoxMadeOfWholeCellsDoesNotGrow() {
        let aligned = padded(BoundingBox(south: 47.03, west: 9.45, north: 47.29, east: 9.66))
        #expect(padded(aligned) == aligned, "padding twice changes nothing")
    }

    @Test func aTinyBoxBecomesOneCell() throws {
        let result = padded(BoundingBox(south: 47.0850, west: 9.5000, north: 47.0851, east: 9.5001))
        let range = try #require(FeatureStoreBuilder.writtenCells(in: result))
        #expect(range.columns.count == 1 && range.rows.count == 1)
    }

    @Test func aDegenerateBoxOnACellBorderStillGetsACell() throws {
        let aligned = padded(BoundingBox(south: 47.03, west: 9.45, north: 47.29, east: 9.66))
        let line = BoundingBox(south: aligned.south, west: aligned.west, north: aligned.south, east: aligned.west)
        let result = padded(line)
        #expect(FeatureStoreBuilder.writtenCells(in: result) != nil)
    }

    @Test func theEdgeOfTheWorldIsNotPassed() {
        let result = padded(BoundingBox(south: -89, west: -180, north: 89, east: 180))
        #expect(result.west == -180 && result.east == 180)
        #expect(result.north <= TileID.maximumLatitude + 1e-6 && result.south >= -TileID.maximumLatitude - 1e-6)
    }
}
