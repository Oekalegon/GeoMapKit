import Foundation
import Testing
@testable import GeoCore

@Suite("WebMercator fit and BoundingBox relations")
struct WebMercatorTests {
    private let width = 400.0
    private let height = 400.0

    @Test("the middle of an area is its middle on the map, and the Mercator maths round-trips")
    func centre() {
        let box = BoundingBox(south: 47.0, west: 9.0, north: 48.0, east: 10.0)
        let centre = WebMercator.center(of: box)
        #expect(abs(centre.longitude - 9.5) < 1e-9)
        // On a Mercator map the middle is a little north of the middle in degrees.
        #expect(centre.latitude > 47.5 && centre.latitude < 47.51)
        for latitude in [-60.0, 0, 47.5, 80] {
            #expect(abs(WebMercator.latitude(y: WebMercator.y(latitude: latitude)) - latitude) < 1e-9)
        }
        #expect(WebMercator.y(latitude: 90) == WebMercator.y(latitude: TileID.maximumLatitude))
        #expect(abs(WebMercator.y(latitude: 0) - 0.5) < 1e-12)
    }

    @Test("a bigger area zooms out, the area fits with room round it, and the zoom stays in the range")
    func zoom() {
        let small = BoundingBox(south: 47.10, west: 9.50, north: 47.11, east: 9.51)
        let big = BoundingBox(south: 40, west: 0, north: 50, east: 20)
        let zoomSmall = WebMercator.zoom(fitting: small, width: width, height: height)
        let zoomBig = WebMercator.zoom(fitting: big, width: width, height: height)
        #expect(zoomSmall > zoomBig)
        // At that zoom the area's width is within the view, less the padding.
        let pixels = 256 * pow(2, zoomSmall) * (small.east - small.west) / 360
        #expect(pixels <= width * 0.7 + 1e-6)
        let world = BoundingBox(south: -80, west: -179, north: 80, east: 179)
        #expect(WebMercator.zoom(fitting: world, width: width, height: height) == 2)
        let tiny = BoundingBox(south: 47.1, west: 9.5, north: 47.1001, east: 9.5001)
        #expect(WebMercator.zoom(fitting: tiny, width: width, height: height) == 17)
        let point = BoundingBox(south: 47.1, west: 9.5, north: 47.1, east: 9.5)
        #expect(WebMercator.zoom(fitting: point, width: width, height: height) == 15)
        #expect(WebMercator.zoom(fitting: point, width: width, height: height, range: 2...12) == 12)
        // The range and the padding are honoured, and a silly padding is limited.
        #expect(WebMercator.zoom(fitting: big, width: width, height: height, range: 5...6) == 5)
        #expect(WebMercator.zoom(fitting: small, width: width, height: height, padding: 0) > zoomSmall)
        #expect(WebMercator.zoom(fitting: small, width: width, height: height, padding: 3).isFinite)
    }

    @Test("a tall area is limited by its height and a wide one by its width")
    func orientation() {
        let tall = BoundingBox(south: 40, west: 9.0, north: 50, east: 9.1)
        let wide = BoundingBox(south: 47.0, west: 0, north: 47.1, east: 10)
        #expect(WebMercator.zoom(fitting: tall, width: width, height: height)
            < WebMercator.zoom(fitting: BoundingBox(south: 40, west: 9.0, north: 41, east: 9.1), width: width, height: height))
        #expect(WebMercator.zoom(fitting: wide, width: width, height: height)
            < WebMercator.zoom(fitting: BoundingBox(south: 47.0, west: 0, north: 47.1, east: 1), width: width, height: height))
        // The same area in a taller view can be zoomed in further when it is tall.
        #expect(WebMercator.zoom(fitting: tall, width: width, height: 800) > WebMercator.zoom(fitting: tall, width: width, height: height))
    }

    @Test("a box encloses another when it holds all of it, and boxes intersect when they overlap or touch")
    func relations() {
        let a = BoundingBox(south: 0, west: 0, north: 1, east: 1)
        #expect(a.encloses(BoundingBox(south: 0.2, west: 0.2, north: 0.8, east: 0.8)))
        #expect(a.encloses(a))
        #expect(!a.encloses(BoundingBox(south: 0.5, west: 0.5, north: 2, east: 2)))
        #expect(!a.encloses(BoundingBox(south: -0.1, west: 0.2, north: 0.8, east: 0.8)))
        #expect(a.intersects(BoundingBox(south: 0.5, west: 0.5, north: 2, east: 2)))
        #expect(a.intersects(BoundingBox(south: 1, west: 1, north: 2, east: 2)))
        #expect(!a.intersects(BoundingBox(south: 1.1, west: 0, north: 2, east: 1)))
        #expect(!a.intersects(BoundingBox(south: 0, west: 1.1, north: 1, east: 2)))
    }
}
