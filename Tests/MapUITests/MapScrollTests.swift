import GeoCore
import MapRender
import Testing

@testable import MapUI

@Suite("MapScroll")
struct MapScrollTests {
    private let viewport = MapViewport(center: Coordinate(latitude: 60, longitude: 10), zoom: 12, width: 800, height: 600)
    private let range = 2.0...20.0

    @Test("Zooming in keeps the coordinate under the pointer where it was")
    func pointerStays() {
        let pointer = ScreenPoint(x: 600, y: 150)
        let before = viewport.coordinate(at: pointer)
        let result = MapScroll.zoomed(viewport, at: pointer, delta: 5, in: range)
        #expect(result.zoom == 12.5)
        let after = MapViewport(center: result.center, zoom: result.zoom, width: 800, height: 600).coordinate(at: pointer)
        #expect(abs(after.latitude - before.latitude) < 1e-9 && abs(after.longitude - before.longitude) < 1e-9)
    }

    @Test("Zooming about the middle of the view leaves the centre")
    func middle() {
        let result = MapScroll.zoomed(viewport, at: ScreenPoint(x: 400, y: 300), delta: -10, in: range)
        #expect(result.zoom == 11)
        #expect(abs(result.center.latitude - 60) < 1e-9 && abs(result.center.longitude - 10) < 1e-9)
    }

    @Test("The zoom stays in its range and the centre does not move at the limit")
    func limits() {
        let high = MapViewport(center: viewport.center, zoom: 20, width: 800, height: 600)
        let result = MapScroll.zoomed(high, at: ScreenPoint(x: 10, y: 10), delta: 50, in: range)
        #expect(result.zoom == 20 && result.center == high.center)
        #expect(MapScroll.zoomed(viewport, at: ScreenPoint(x: 400, y: 300), delta: -1000, in: range).zoom == 2)
    }

    @Test("A scroll moves the map with the fingers")
    func pans() {
        let center = MapScroll.panned(viewport, dx: 0, dy: 100)
        #expect(center.latitude > 60, "content down means the view looks further north")
        let east = MapScroll.panned(viewport, dx: -100, dy: 0)
        #expect(east.longitude > 10, "content left means the view looks further east")
    }
}
