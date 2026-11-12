import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

/// How the cut rings of an area are joined again, stage by stage.
@Suite("Level dissolve")
struct LevelDissolveTests {
    private let west = TileID(zoom: 13, x: 4_000, y: 2_400)!
    private let east = TileID(zoom: 13, x: 4_001, y: 2_400)!
    private let everything = LevelRegion(columns: 0...8_191, rows: 0...8_191)
    /// A pixel of the top zoom 8 of a level, in projected radians; the snap is twice that.
    private let snap = 2 * 0.5 * 2 * Double.pi / (256 * 256)

    private func pt(_ lon: Int32, _ lat: Int32) -> PackedPoint { PackedPoint(longitude: lon, latitude: lat) }

    /// The two halves of a rectangle across the border between two cells, the east half moved `shift` units north: the clip made the
    /// edges along the border, which the two halves therefore do not share.
    private func halves(shift: Int32, eastEastOffset: Int32 = 0) -> [LevelRing] {
        let rect = CellRect(tile: west)
        let border = rect.east, lat = rect.north / 2 + rect.south / 2
        let w: Int32 = 100_000, h: Int32 = 80_000
        let westRing = LevelRing(
            cell: west, points: [pt(border - w, lat + h), pt(border, lat + h), pt(border, lat - h), pt(border - w, lat - h), pt(border - w, lat + h)],
            artificialEdges: [1..<2])
        let eastRing = LevelRing(
            cell: east,
            points: [
                pt(border + eastEastOffset, lat + h + shift), pt(border + w, lat + h + shift), pt(border + w, lat - h + shift),
                pt(border + eastEastOffset, lat - h + shift), pt(border + eastEastOffset, lat + h + shift),
            ], artificialEdges: [3..<4])
        return [westRing, eastRing]
    }

    @Test func pieceThatMeetExactlyAreOneRing() {
        let result = LevelDissolve.rings(of: halves(shift: 0), region: everything, snapRadians: snap)
        #expect(result.rings.count == 1 && result.open.isEmpty && result.joinedBySnap == 0 && result.joinedAlongBorder == 0)
    }

    @Test func endsWithinAPixelAreJoinedFirst() {
        let result = LevelDissolve.rings(of: halves(shift: 20), region: everything, snapRadians: snap)
        #expect(result.rings.count == 1 && result.open.isEmpty)
        #expect(result.joinedBySnap == 2 && result.joinedAlongBorder == 0)
    }

    @Test func endsOnTheSameLineOfTheBorderAreJoinedWithinAFewCellsAndThenAtAnyDistance() {
        // The nearest pair first: here each half closes along the border, which fills the same area as one ring.
        let near = LevelDissolve.rings(of: halves(shift: 200_000), region: everything, snapRadians: snap)
        #expect(near.rings.count >= 1 && near.open.isEmpty && near.joinedBySnap == 0 && near.joinedAlongBorder == 2)
        // 5 degrees of latitude is far more than 16 cells: the last stage joins them.
        let far = LevelDissolve.rings(of: halves(shift: 5_000_000), region: everything, snapRadians: snap)
        #expect(far.rings.count >= 1 && far.open.isEmpty && far.joinedAlongBorder == 2)
    }

    @Test func aChainWhoseEndsAreOnDifferentLinesIsNotJoinedAndStaysOpen() {
        // A corner of a cell: its edges along the east and the south border face cells that hold other rings of the feature, so they
        // are dropped, and the chain runs from the south border to the east border: no longitude or latitude is shared.
        let rect = CellRect(tile: west)
        let a = rect.west + 1_000, b = rect.east, top = rect.north - 1_000, bottom = rect.south
        let corner = LevelRing(
            cell: west, points: [pt(a, top), pt(b, top), pt(b, bottom), pt(a, bottom), pt(a, top)], artificialEdges: [1..<3])
        func small(_ cell: TileID) -> LevelRing {
            let r = CellRect(tile: cell)
            let lon = r.west / 2 + r.east / 2, lat = r.north / 2 + r.south / 2
            return LevelRing(cell: cell, points: [pt(lon, lat), pt(lon + 100, lat), pt(lon + 100, lat + 100), pt(lon, lat + 100), pt(lon, lat)], artificialEdges: [])
        }
        let southCell = TileID(zoom: 13, x: west.x, y: west.y + 1)!
        let result = LevelDissolve.rings(of: [corner, small(east), small(southCell)], region: everything, snapRadians: snap)
        #expect(result.open.count == 1 && result.joinedBySnap == 0 && result.joinedAlongBorder == 0)
        #expect(result.closedBySmallGap == 0, "the gap is as big as the chain: not a seam, so the chain stays open")
        #expect(result.rings.count == 2, "the two small rings are closed")
    }

    @Test func aLongChainWhoseEndsAreACellApartOnDifferentLinesIsClosedOnItself() {
        // The coast of a bay along the border of two blocks: a ring that runs 100 cells out and back, and whose two ends, one on the
        // east border and one on the south border, are about a cell apart (two blocks simplified the coast apart). The gap is small
        // against the chain, so it closes on itself and is filled; without that the whole sea of the block is only outlined.
        let rect = CellRect(tile: west)
        let b = rect.east, south = rect.south
        let cellWidth = rect.east - rect.west, cellHeight = rect.north - rect.south
        let top = south + cellHeight
        let ring = LevelRing(
            cell: west,
            points: [
                pt(b, south), pt(b, top), pt(b - 100 * cellWidth, top), pt(b - 100 * cellWidth, south), pt(b - cellWidth, south),
                pt(b, south),
            ], artificialEdges: [0..<1, 4..<5])
        func small(_ cell: TileID) -> LevelRing {
            let r = CellRect(tile: cell)
            let lon = r.west / 2 + r.east / 2, lat = r.north / 2 + r.south / 2
            return LevelRing(cell: cell, points: [pt(lon, lat), pt(lon + 100, lat), pt(lon + 100, lat + 100), pt(lon, lat + 100), pt(lon, lat)], artificialEdges: [])
        }
        let southCell = TileID(zoom: 13, x: west.x, y: west.y + 1)!
        let result = LevelDissolve.rings(of: [ring, small(east), small(southCell)], region: everything, snapRadians: snap)
        #expect(result.open.isEmpty && result.closedBySmallGap == 1)
        #expect(result.joinedBySnap == 0 && result.joinedAlongBorder == 0)
        #expect(result.rings.count == 3, "the two small rings and the long one")
    }

    @Test func aNeighbourThatHoldsNothingOfTheFeatureDoesNotHideTheEdgeFacingIt() {
        // Only the west half: the east cell holds none of this feature (an open sea far from a coast has no sea piece), so the edge
        // down the border stays and the ring closes by itself.
        let result = LevelDissolve.rings(of: [halves(shift: 0)[0]], region: everything, snapRadians: snap)
        #expect(result.rings.count == 1 && result.open.isEmpty && result.joinedBySnap + result.joinedAlongBorder == 0)
    }

    @Test func aFeatureWithMoreOpenChainsThanTheLimitIsNotJoined() {
        // 700 pairs of halves far apart from each other: 1,400 chains, each pair would be joined by the first stage.
        var rings: [LevelRing] = []
        for index in 0..<700 {
            let column = 100 + 3 * index
            let a = TileID(zoom: 13, x: column, y: 2_400)!, b = TileID(zoom: 13, x: column + 1, y: 2_400)!
            let rect = CellRect(tile: a)
            let border = rect.east, lat = rect.north / 2 + rect.south / 2
            rings.append(LevelRing(
                cell: a, points: [pt(border - 1_000, lat + 1_000), pt(border, lat + 1_000), pt(border, lat - 1_000), pt(border - 1_000, lat - 1_000), pt(border - 1_000, lat + 1_000)],
                artificialEdges: [1..<2]))
            rings.append(LevelRing(
                cell: b, points: [pt(border, lat + 1_010), pt(border + 1_000, lat + 1_010), pt(border + 1_000, lat - 990), pt(border, lat - 990), pt(border, lat + 1_010)],
                artificialEdges: [3..<4]))
        }
        let result = LevelDissolve.rings(of: rings, region: everything, snapRadians: snap)
        #expect(result.joinedBySnap == 0 && result.joinedAlongBorder == 0 && result.rings.isEmpty)
        #expect(result.open.count == 1_400, "left as they are, and counted")
    }

    @Test func aBorderLineIsALongitudeOrLatitudeThatIsTheBorderOfACell() {
        let rect = CellRect(tile: west)
        #expect(LevelDissolve.sameBorderLine(pt(rect.east, 100), pt(rect.east, 900_000)))
        #expect(LevelDissolve.sameBorderLine(pt(5, rect.north), pt(900_000, rect.north)))
        #expect(!LevelDissolve.sameBorderLine(pt(rect.east + 1, 100), pt(rect.east + 1, 900_000)), "a longitude that is not a border")
        #expect(!LevelDissolve.sameBorderLine(pt(rect.east, 100), pt(rect.east + 1, 100)))
    }
}
