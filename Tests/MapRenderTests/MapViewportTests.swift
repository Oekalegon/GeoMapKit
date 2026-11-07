import FeatureStore
import GeoCore
import Testing

@testable import MapRender

@Suite("MapViewport")
struct MapViewportTests {
    private let center = Coordinate(latitude: 47.14, longitude: 9.52)

    @Test func centerProjectsToTheMiddleOfTheView() {
        let viewport = MapViewport(center: center, zoom: 15, width: 400, height: 300)
        let point = viewport.screenPoint(for: center)
        #expect(abs(point.x - 200) < 1e-6 && abs(point.y - 150) < 1e-6)
    }

    @Test func northIsUpAndEastIsRight() {
        let viewport = MapViewport(center: center, zoom: 15, width: 400, height: 300)
        let north = viewport.screenPoint(for: Coordinate(latitude: 47.141, longitude: 9.52))
        let east = viewport.screenPoint(for: Coordinate(latitude: 47.14, longitude: 9.521))
        #expect(north.y < 150 && abs(north.x - 200) < 1e-6)
        #expect(east.x > 200 && abs(east.y - 150) < 1e-6)
    }

    @Test func screenAndCoordinateRoundTrip() {
        let viewport = MapViewport(center: center, zoom: 17.3, width: 400, height: 300)
        let coordinate = Coordinate(latitude: 47.1412, longitude: 9.5231)
        let back = viewport.coordinate(at: viewport.screenPoint(for: coordinate))
        #expect(abs(back.latitude - coordinate.latitude) < 1e-9 && abs(back.longitude - coordinate.longitude) < 1e-9)
    }

    @Test func packedPointsMatchCoordinates() {
        let viewport = MapViewport(center: center, zoom: 16, width: 400, height: 300)
        let a = viewport.screenPoint(for: PackedPoint(longitude: 95_100_000, latitude: 471_400_000))
        let b = viewport.screenPoint(for: Coordinate(latitude: 47.14, longitude: 9.51))
        #expect(abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6)
    }

    @Test func worldSizeDoublesWithEachZoomLevel() {
        let a = MapViewport(center: center, zoom: 10, width: 10, height: 10)
        let b = MapViewport(center: center, zoom: 11, width: 10, height: 10)
        #expect(a.worldSize == 256 * 1024 && b.worldSize == 2 * a.worldSize)
    }

    @Test func metresPerPointMatchesTheKnownEquatorValue() {
        let viewport = MapViewport(center: Coordinate(latitude: 0, longitude: 0), zoom: 0, width: 10, height: 10)
        #expect(abs(viewport.metresPerPoint - 156_543.03392) < 0.01)
    }

    @Test func metresPerPointShrinksWithLatitude() {
        let equator = MapViewport(center: Coordinate(latitude: 0, longitude: 0), zoom: 10, width: 10, height: 10)
        let norway = MapViewport(center: Coordinate(latitude: 60, longitude: 0), zoom: 10, width: 10, height: 10)
        #expect(abs(norway.metresPerPoint / equator.metresPerPoint - 0.5) < 1e-9)
    }

    @Test func invalidInputIsClamped() {
        let viewport = MapViewport(center: Coordinate(latitude: 95, longitude: 190), zoom: .nan, width: -5, height: .infinity)
        #expect(viewport.center.latitude == TileID.maximumLatitude)
        #expect(abs(viewport.center.longitude - (-170)) < 1e-9)
        #expect(viewport.zoom == 0 && viewport.width == 0 && viewport.height == 0)
        #expect(MapViewport(center: center, zoom: 99, width: 1, height: 1).zoom == Double(TileID.maximumZoom))
    }

    @Test func cellsCoverTheView() throws {
        let viewport = MapViewport(center: center, zoom: 13, width: 512, height: 512)
        let cells = viewport.cells(storageZoom: 13)
        let middle = try #require(TileID.containing(center, zoom: 13))
        #expect(cells.contains(middle))
        // At zoom 13 a cell is 256 points, so 512 points span two or three cells per axis.
        #expect((4...9).contains(cells.count))
        for cell in cells { #expect(abs(cell.x - middle.x) <= 1 && abs(cell.y - middle.y) <= 1) }
    }

    @Test func marginAddsNeighbouringCells() {
        let viewport = MapViewport(center: center, zoom: 13, width: 100, height: 100)
        #expect(viewport.cells(storageZoom: 13, margin: 300).count > viewport.cells(storageZoom: 13).count)
    }

    @Test func cellsAtTheWorldEdgeAreClamped() {
        let viewport = MapViewport(center: Coordinate(latitude: 85, longitude: 0), zoom: 3, width: 4000, height: 4000)
        let cells = viewport.cells(storageZoom: 3)
        #expect(cells.count == 64)
        #expect(cells.allSatisfy { (0..<8).contains($0.x) && (0..<8).contains($0.y) })
    }

    @Test func invalidStorageZoomGivesNoCells() {
        #expect(MapViewport(center: center, zoom: 13, width: 100, height: 100).cells(storageZoom: 99).isEmpty)
    }
}
