import Foundation
import GeoCore
import MapRender
import MapStyle
import Testing
import Tracks

@testable import TrackOverlays

@Suite("Route overlay")
struct RouteOverlayTests {
    /// A view of 400 by 300 points at zoom 14 over Oslo, which is about 1,160 points for 0.1 degrees of longitude.
    private func viewport(zoom: Double = 14, center: Coordinate = Coordinate(latitude: 59.91, longitude: 10.75)) -> MapViewport {
        MapViewport(center: center, zoom: zoom, width: 400, height: 300)
    }

    private func lines(_ items: [OverlayItem]) -> [OverlayLine] {
        items.compactMap { if case .line(let line) = $0 { line } else { nil } }
    }

    private func markers(_ items: [OverlayItem]) -> [OverlayMarker] {
        items.compactMap { if case .marker(let marker) = $0 { marker } else { nil } }
    }

    private func route(_ pairs: [(Double, Double)], starts: [Int]? = nil, waypoints: [RouteWaypoint] = []) throws -> Route {
        try Route(points: pairs.map { TrackPoint(latitude: $0.0, longitude: $0.1) }, segmentStarts: starts, waypoints: waypoints)
    }

    @Test("A straight route is one line of two points with a start and an end marker; a corner is kept")
    func lineAndMarkers() throws {
        let straight = RouteOverlay(route: try route([(59.91, 10.745), (59.91, 10.75), (59.91, 10.755)]))
        let items = straight.items(for: viewport())
        #expect(lines(items).count == 1 && lines(items)[0].points.count == 2, "the point in the middle is on the line")
        #expect(lines(items)[0].style == RouteOverlayStyle.standard.line)
        let ends = markers(items)
        #expect(ends.count == 2 && ends[0].fill == RouteOverlayStyle.standard.end && ends[1].fill == RouteOverlayStyle.standard.start)
        // The start is on the left (west), the end on the right.
        #expect(ends[1].center.x < ends[0].center.x && abs(ends[0].center.y - 150) < 1)
        let bent = RouteOverlay(route: try route([(59.91, 10.745), (59.91, 10.75), (59.912, 10.75)]))
        #expect(lines(bent.items(for: viewport()))[0].points.count == 3)
    }

    @Test("The breaks of a recording are not drawn: two segments are two lines")
    func gaps() throws {
        let broken = RouteOverlay(route: try route(
            [(59.91, 10.740), (59.91, 10.745), (59.92, 10.750), (59.92, 10.755)], starts: [0, 2]))
        let found = lines(broken.items(for: viewport(zoom: 13)))
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.points.count == 2 })
    }

    @Test("A route outside the view draws nothing, and a route that crosses it is cut a little outside the view")
    func outsideAndAcross() throws {
        let far = RouteOverlay(route: try route([(10, 10), (10.1, 10.1)]))
        #expect(far.items(for: viewport()).isEmpty)
        // A route across the whole region: its ends are far outside the view, its line is cut near the view's edges.
        let long = RouteOverlay(route: try route([(59.91, 9.5), (59.91, 12.0)]))
        let items = lines(long.items(for: viewport()))
        #expect(items.count == 1)
        let points = items[0].points
        #expect(points.allSatisfy { $0.x >= -40 && $0.x <= 440 && abs($0.y - 150) < 1 }, "\(points)")
        #expect(markers(long.items(for: viewport())).isEmpty, "the markers are far outside the view")
    }

    @Test("Waypoints are circles, a required one with a wider ring, and one far from the view is left out")
    func waypoints() throws {
        let centre = Coordinate(latitude: 59.91, longitude: 10.75)
        let route = try route(
            [(59.91, 10.745), (59.91, 10.755)],
            waypoints: [
                RouteWaypoint(name: "A", coordinate: centre, distanceAlong: 280),
                RouteWaypoint(name: "B", coordinate: Coordinate(latitude: 59.9101, longitude: 10.7501), distanceAlong: 290, isRequired: true),
                RouteWaypoint(name: "Far", coordinate: Coordinate(latitude: 40, longitude: 10), distanceAlong: 300),
            ])
        let found = markers(RouteOverlay(route: route).items(for: viewport()))
        let style = RouteOverlayStyle.standard
        let circles = found.filter { $0.radius == style.waypointRadius }
        #expect(circles.count == 2 && found.count == 4)
        #expect(circles.map(\.outlineWidth).sorted() == [1, style.requiredRing].sorted())
    }

    @Test("A route of a single point is a marker and no line")
    func singlePoint() throws {
        let overlay = RouteOverlay(route: try route([(59.91, 10.75)]))
        let items = overlay.items(for: viewport())
        #expect(lines(items).isEmpty && markers(items).count == 2)
    }

    @Test("A long wandering route is simplified to the zoom, and no point of it is farther from the drawn line than a point")
    func simplification() throws {
        var pairs: [(Double, Double)] = []
        for index in 0..<4_000 {
            let along = Double(index)
            pairs.append((59.91 + 0.002 * sin(along / 120) + 0.00001 * sin(along * 1.7), 10.70 + along * 0.00002))
        }
        let overlay = RouteOverlay(route: try route(pairs))
        let wide = viewport(zoom: 9)
        let near = viewport(zoom: 16)
        let farLines = lines(overlay.items(for: wide))
        #expect(farLines.count == 1 && farLines[0].points.count < 30, "zoomed out: \(farLines.first?.points.count ?? 0)")
        let nearLines = lines(overlay.items(for: near))
        #expect(!nearLines.isEmpty && nearLines.map(\.points.count).reduce(0, +) > 60)
        // At an integer zoom the drawn line follows the route within the tolerance at that zoom.
        let view = viewport(zoom: 14)
        let drawn = lines(overlay.items(for: view)).flatMap(\.points)
        #expect(!drawn.isEmpty)
        let polyline = lines(overlay.items(for: view))
        for point in pairs.map({ view.screenPoint(for: Coordinate(latitude: $0.0, longitude: $0.1)) }) where point.x > 5 && point.x < 395 && point.y > 5 && point.y < 295 {
            var best = Double.infinity
            for line in polyline {
                for (a, b) in zip(line.points, line.points.dropFirst()) {
                    let dx = b.x - a.x, dy = b.y - a.y
                    let squared = dx * dx + dy * dy
                    let t = squared > 0 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / squared)) : 0
                    best = min(best, ((point.x - a.x - t * dx) * (point.x - a.x - t * dx) + (point.y - a.y - t * dy) * (point.y - a.y - t * dy)).squareRoot())
                }
            }
            #expect(best <= 0.5, "a point of the route is \(best) from the drawn line")
        }
    }

    @Test("The same view gives the same items (from the cache), and many tasks can ask at once")
    func cacheAndConcurrency() throws {
        var pairs: [(Double, Double)] = []
        for index in 0..<2_000 { pairs.append((59.91 + 0.001 * sin(Double(index) / 50), 10.70 + Double(index) * 0.00005)) }
        let overlay = RouteOverlay(route: try route(pairs))
        let first = overlay.items(for: viewport())
        #expect(overlay.items(for: viewport()) == first)
        DispatchQueue.concurrentPerform(iterations: 24) { index in
            let zoom = 8 + Double(index % 10)
            #expect(!overlay.items(for: viewport(zoom: zoom)).isEmpty)
        }
        #expect(overlay.items(for: viewport()) == first)
    }

    @Test("Every overlay has an id of its own, and the style is the standard one by default")
    func identity() throws {
        let line = try route([(59.91, 10.745), (59.91, 10.755)])
        let a = RouteOverlay(route: line), b = RouteOverlay(route: line)
        #expect(a.overlayID != b.overlayID && a.overlayID == a.overlayID)
        #expect(a.style == .standard && a.route == line)
    }

    @Test("Only the zoom levels used last are kept, and a level that was dropped is computed again to the same result")
    func boundedCache() throws {
        var pairs: [(Double, Double)] = []
        for index in 0..<3_000 { pairs.append((59.91 + 0.002 * sin(Double(index) / 100), 10.70 + Double(index) * 0.00003)) }
        let overlay = RouteOverlay(route: try route(pairs))
        let first = overlay.items(for: viewport(zoom: 12))
        for zoom in [13.0, 14, 15, 16, 17, 18] { _ = overlay.items(for: viewport(zoom: zoom)) }
        #expect(overlay.heldLevelCount == RouteOverlay.cachedLevels)
        #expect(overlay.items(for: viewport(zoom: 12)) == first, "level 12 was dropped and is computed again")
        #expect(overlay.heldLevelCount == RouteOverlay.cachedLevels)
    }
}
