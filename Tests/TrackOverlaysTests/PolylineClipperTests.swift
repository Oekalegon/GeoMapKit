import MapRender
import Testing

@testable import TrackOverlays

@Suite("Polyline clipper")
struct PolylineClipperTests {
    private let area = PolylineClipper.Rectangle(minX: 0, minY: 0, maxX: 100, maxY: 100)

    private func points(_ pairs: (Double, Double)...) -> [ScreenPoint] { pairs.map { ScreenPoint(x: $0.0, y: $0.1) } }

    @Test("A line inside is kept whole, and one outside is dropped")
    func insideAndOutside() {
        let inside = points((10, 10), (50, 50), (90, 20))
        #expect(PolylineClipper.clip(inside, to: area) == [inside])
        #expect(PolylineClipper.clip(points((-50, 10), (-10, 90)), to: area).isEmpty)
        #expect(PolylineClipper.clip(points((200, 0), (300, 100)), to: area).isEmpty)
        #expect(PolylineClipper.clip([], to: area).isEmpty && PolylineClipper.clip(points((5, 5)), to: area).isEmpty)
    }

    @Test("A step that leaves the area is cut at the edge")
    func cutAtTheEdge() {
        let result = PolylineClipper.clip(points((50, 50), (150, 50)), to: area)
        #expect(result == [points((50, 50), (100, 50))])
        let through = PolylineClipper.clip(points((-100, 50), (200, 50)), to: area)
        #expect(through == [points((0, 50), (100, 50))])
        let diagonal = PolylineClipper.clip(points((-50, -50), (150, 150)), to: area)
        #expect(diagonal == [points((0, 0), (100, 100))])
    }

    @Test("A line that leaves and comes back is two lines, and the steps inside are not joined across the gap")
    func leavesAndComesBack() {
        let line = points((10, 50), (50, 50), (150, 50), (150, 80), (50, 80), (10, 80))
        let result = PolylineClipper.clip(line, to: area)
        #expect(result.count == 2)
        #expect(result[0] == points((10, 50), (50, 50), (100, 50)))
        #expect(result[1] == points((100, 80), (50, 80), (10, 80)))
    }

    @Test("Steps along an edge are inside, and one that only touches a corner is no line")
    func edgesAndCorners() {
        #expect(PolylineClipper.clip(points((0, 0), (100, 0)), to: area) == [points((0, 0), (100, 0))])
        #expect(PolylineClipper.clip(points((-10, 10), (10, -10)), to: area).isEmpty == false, "it crosses the corner area")
        #expect(PolylineClipper.clip(points((-20, 0), (0, -20)), to: area).isEmpty, "this one misses the area")
    }
}
